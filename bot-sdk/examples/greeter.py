#!/usr/bin/env python3
"""A working Privio bot: /start, /help, and an introduction in a group.

Run it:

    export PRIVIO_BOT_TOKEN=...        # from @botcreator, shown once
    export PRIVIO_BASE_URL=https://your-server.example
    python3 examples/greeter.py

It does three things and nothing it cannot do:

* answers ``/start`` and ``/help`` in a private chat;
* offers two buttons on ``/menu`` and does something different for each,
  which is a real button rather than a decoration;
* asks a question on ``/poll`` and says back what it heard, so an answer
  visibly reaches the bot — including a changed or withdrawn one;
* introduces itself in a group when somebody sends it ``/start`` there, and
  says plainly what it does and does not receive;
* answers anything else with a nudge towards ``/help``.

What it deliberately does **not** do: pretend to moderate. Deleting other
people's messages is not something a bot can do in Privio at all — a group's
messages are encrypted per device and only their author can withdraw them —
see docs/bots.md. A button that did nothing would be worse than no button.
"""

from __future__ import annotations

import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from privio_bot import Bot, Update  # noqa: E402

HELP = """I can do these:

/start — say hello
/help — this list
/menu — two buttons, to show that buttons work
/poll — a question with three answers

In a group I only receive messages addressed to me: a command, a mention of
@{username}, or a reply to something I said. I hold no key for the group, so
that is not a setting I could be talked out of — the members' own devices
decide what reaches me."""

GROUP_INTRO = """Hello — I am a bot, run by somebody outside this group.

What reaches me here: commands, mentions of me, and replies to my messages.
Nothing else, and nothing sent before I was added.

Whoever runs me can read what reaches me. Type /help for what I can do."""


#: The answers of each poll this process sent, to say back which one was
#: picked. In memory: a poll from before a restart is answered by number, which
#: is enough for an example and honest about what it remembers.
POLL_OPTIONS: dict[int, tuple[str, ...]] = {}


def handle(bot: Bot, update: Update) -> None:
    # An answer to a poll: the person's whole answer as it now stands. Every
    # change arrives, and only changes — the same answer twice is not delivered
    # twice, so there is nothing here to de-duplicate.
    if update.vote:
        if update.vote.retracted:
            bot.reply(update, "You took your answer back. Pick again whenever you like.")
            return
        labels = POLL_OPTIONS.get(update.vote.poll_id)
        picked = ", ".join(
            labels[i] if labels and i < len(labels) else f"answer {i + 1}"
            for i in update.vote.options
        )
        bot.reply(update, f"Noted: {picked}. You can change it until the poll closes.")
        return

    # A press, not something somebody typed. It arrives once — pressing the same
    # button again is refused server-side — so this needs no state of its own to
    # avoid acting twice.
    if update.button:
        if update.button.id == "weather":
            bot.reply(update, "Grey, probably. I have no weather data; this is an example.")
        elif update.button.id == "time":
            bot.reply(update, f"It is {time.strftime('%H:%M')} where I run.")
        else:
            # A button id this version does not know. It came from a message an
            # older version of this bot sent, which is the ordinary case after a
            # deploy, not an attack.
            bot.reply(update, "That button is from an older version of me. Try /menu.")
        return

    command = update.command

    # A command in a group may name another bot. The server parsed it; this is
    # only the check that it was meant for us.
    if command and command.addressed_to and command.addressed_to != USERNAME:
        return

    if command and command.name == "start":
        bot.reply(update, GROUP_INTRO if update.in_group else "Hello. Type /help.")
        return

    if command and command.name == "help":
        bot.reply(update, HELP.format(username=USERNAME))
        return

    if command and command.name == "menu":
        # The buttons belong to this message. Pressing one sends back its id —
        # not its label, which is why the id is what the code below matches on.
        bot.reply(
            update,
            "Pick one:",
            buttons=[("weather", "The weather"), ("time", "The time")],
        )
        return

    if command and command.name == "poll":
        # show_results: the person sees the tally once they have answered. Off
        # by default in the API, and switched on here knowingly — with only a
        # handful of people, a tally can give away how somebody else answered.
        options = ("Tea", "Coffee", "Neither")
        sent = bot.send_poll(
            update.account_id,
            "Tea or coffee?",
            list(options),
            show_results=True,
            group_id=update.scope_id if update.in_group else None,
        )
        POLL_OPTIONS[sent.poll_id] = options
        return

    if command:
        bot.reply(update, f"I do not know /{command.name}. Type /help.")
        return

    # Not a command. In a group this is a mention or a reply, because nothing
    # else reaches us.
    bot.reply(update, "Type /help to see what I can do.")


def main() -> int:
    token = os.environ.get("PRIVIO_BOT_TOKEN")
    base = os.environ.get("PRIVIO_BASE_URL")
    if not token or not base:
        print("Set PRIVIO_BOT_TOKEN and PRIVIO_BASE_URL.", file=sys.stderr)
        return 2

    bot = Bot(token, base)
    me = bot.me()

    global USERNAME
    USERNAME = me.get("username", "bot")
    print(f"running as @{USERNAME}")

    # Publish the menu, so the app can offer the commands rather than making
    # people remember them.
    bot.set_commands(
        [
            ("start", "Say hello"),
            ("help", "What I can do"),
            ("menu", "Two buttons"),
            ("poll", "A question to answer"),
        ]
    )

    bot.run(handle)
    return 0


USERNAME = "bot"

if __name__ == "__main__":
    raise SystemExit(main())
