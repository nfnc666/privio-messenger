#!/usr/bin/env python3
"""A working Privio bot: /start, /help, and an introduction in a group.

Run it:

    export PRIVIO_BOT_TOKEN=...        # from @botcreator, shown once
    export PRIVIO_BASE_URL=https://your-server.example
    python3 examples/greeter.py

It does three things and nothing it cannot do:

* answers ``/start`` and ``/help`` in a private chat;
* introduces itself in a group when somebody sends it ``/start`` there, and
  says plainly what it does and does not receive;
* answers anything else with a nudge towards ``/help``.

What it deliberately does **not** do: pretend to moderate. The moderation
rights exist and are enforced, but the API routes a bot would call to use them
are not written yet — see docs/bots.md. A button that did nothing would be
worse than no button.
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from privio_bot import Bot, Update  # noqa: E402

HELP = """I can do these:

/start — say hello
/help — this list

In a group I only receive messages addressed to me: a command, a mention of
@{username}, or a reply to something I said. I hold no key for the group, so
that is not a setting I could be talked out of — the members' own devices
decide what reaches me."""

GROUP_INTRO = """Hello — I am a bot, run by somebody outside this group.

What reaches me here: commands, mentions of me, and replies to my messages.
Nothing else, and nothing sent before I was added.

Whoever runs me can read what reaches me. Type /help for what I can do."""


def handle(bot: Bot, update: Update) -> None:
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
    bot.set_commands([("start", "Say hello"), ("help", "What I can do")])

    bot.run(handle)
    return 0


USERNAME = "bot"

if __name__ == "__main__":
    raise SystemExit(main())
