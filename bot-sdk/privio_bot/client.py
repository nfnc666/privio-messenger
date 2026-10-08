"""The HTTP client and the polling loop."""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Callable, Iterator


#: The largest picture or file a bot may upload. Matches `BOT_LIMITS` on the
#: server; a bigger one is refused here so the reason is a sentence rather than
#: a dropped connection.
MAX_ATTACHMENT_BYTES = 8 * 1024 * 1024

#: The most answers one poll may offer. Matches `BOT_LIMITS.maxPollOptions`.
MAX_POLL_OPTIONS = 10


def _iso(value: datetime | str) -> str:
    """A timestamp the server accepts: ISO 8601 with an offset.

    A naive ``datetime`` is refused rather than guessed at — whether it meant
    UTC or the machine's local time is exactly the thing that makes a poll
    close an hour early.
    """
    if isinstance(value, str):
        return value
    if value.tzinfo is None:
        raise ValueError("closes_at needs a timezone; use datetime.now(timezone.utc) + …")
    return value.astimezone(timezone.utc).isoformat()


class BotError(RuntimeError):
    """The server refused something.

    Carries the machine-readable code as well as the sentence, because a bot
    that wants to react to `not_contacted` should not have to match on
    English.
    """

    def __init__(self, status: int, code: str, message: str) -> None:
        super().__init__(f"{status} {code}: {message}")
        self.status = status
        self.code = code
        self.message = message


def _error_from(error: urllib.error.HTTPError) -> BotError:
    """The server's refusal, as a `BotError` carrying its code.

    One place rather than two: the upload path and the JSON path both need it,
    and a second copy is a second chance for one of them to lose the code and
    leave a bot matching on English.
    """
    try:
        parsed = json.loads(error.read())
    except ValueError:
        parsed = {}
    return BotError(
        error.code,
        str(parsed.get("error", "http_error")),
        str(parsed.get("message", error.reason)),
    )


@dataclass(frozen=True)
class Command:
    """A parsed `/command`, as the server parsed it.

    Parsed server-side so that every bot agrees with the app about what
    `/help@name` means in a group holding several bots.
    """

    name: str
    args: str
    addressed_to: str | None = None


@dataclass(frozen=True)
class Press:
    """Somebody pressed a button under one of the bot's messages.

    ``message_id`` is the message the button was under, so a bot that sent the
    same buttons twice can tell which of the two was pressed. A press arrives
    once: pressing again is refused server-side, so no state of yours has to
    make that true.
    """

    id: str
    message_id: int


@dataclass(frozen=True)
class Vote:
    """Somebody answered one of the bot's polls, changed or took back an answer.

    ``options`` is their **whole** answer as it now stands — indices into the
    poll's options, in order — not the difference from the last one. A bot that
    missed an update still ends up right by keeping the latest per person. An
    empty tuple means they took their vote back.

    The same answer twice is not delivered twice: the server only tells you
    about a change.
    """

    poll_id: int
    options: tuple[int, ...]

    @property
    def retracted(self) -> bool:
        return not self.options


@dataclass(frozen=True)
class PollResults:
    """One poll and its tally, as the bot sees it.

    The bot sees every count whatever ``show_results`` says: that switch is
    about what the *people answering* see.
    """

    id: int
    question: str
    options: tuple[str, ...]
    max_choices: int
    show_results: bool
    closes_at: str | None
    closed: bool
    #: One count per option, zeros included.
    counts: tuple[int, ...]
    #: People who answered. Not ``sum(counts)`` when several picks are allowed.
    voters: int

    @classmethod
    def from_json(cls, raw: dict[str, Any]) -> "PollResults":
        return cls(
            id=int(raw["id"]),
            question=str(raw["question"]),
            options=tuple(str(o) for o in raw.get("options", [])),
            max_choices=int(raw.get("maxChoices", 1)),
            show_results=bool(raw.get("showResults", False)),
            closes_at=raw.get("closesAt"),
            closed=bool(raw.get("closed", False)),
            counts=tuple(int(n) for n in raw.get("counts", [])),
            voters=int(raw.get("voters", 0)),
        )


@dataclass(frozen=True)
class SentPoll:
    """What sending a poll gives back: the message, and the poll to reuse."""

    message_id: int
    poll_id: int


@dataclass(frozen=True)
class Update:
    """One thing that happened."""

    update_id: int
    account_id: str
    username: str
    text: str
    at: str
    #: ``"direct"`` or ``"group"``.
    scope: str = "direct"
    #: The group it happened in, when ``scope`` is ``"group"``.
    scope_id: str | None = None
    command: Command | None = None
    #: Set when this update *is* a button press. ``text`` is then empty.
    button: Press | None = None
    #: Set when this update *is* an answer to a poll. ``text`` is then empty.
    vote: Vote | None = None

    @property
    def in_group(self) -> bool:
        return self.scope == "group" and self.scope_id is not None

    @classmethod
    def from_json(cls, raw: dict[str, Any]) -> "Update":
        chat = raw.get("chat") or {}
        command_raw = raw.get("command")
        button_raw = raw.get("button")
        vote_raw = raw.get("vote")
        return cls(
            update_id=int(raw["updateId"]),
            account_id=str(chat.get("accountId", "")),
            username=str(chat.get("username", "")),
            text=str(raw.get("text", "")),
            at=str(raw.get("at", "")),
            scope=str(raw.get("scope", "direct")),
            scope_id=raw.get("scopeId"),
            command=(
                Command(
                    name=str(command_raw["name"]),
                    args=str(command_raw.get("args", "")),
                    addressed_to=command_raw.get("addressedTo"),
                )
                if command_raw
                else None
            ),
            button=(
                Press(id=str(button_raw["id"]), message_id=int(button_raw["messageId"]))
                if button_raw
                else None
            ),
            vote=(
                Vote(
                    poll_id=int(vote_raw["pollId"]),
                    options=tuple(int(i) for i in vote_raw.get("options", [])),
                )
                if vote_raw
                else None
            ),
        )


class Bot:
    """A bot, talking to one Privio server.

    The token goes in a header and never in a URL. It is not logged here, and
    nothing in this client prints it — a token in a log file is a token in a
    backup.
    """

    def __init__(self, token: str, base_url: str, *, timeout: float = 35.0) -> None:
        if not token:
            raise ValueError("a bot token is required")
        self._token = token
        self._base = base_url.rstrip("/")
        self._timeout = timeout

    # -- plumbing ----------------------------------------------------------

    def _request(self, method: str, path: str, body: dict[str, Any] | None = None) -> Any:
        data = None if body is None else json.dumps(body).encode("utf-8")
        headers = {
            "authorization": f"Bearer {self._token}",
            "accept": "application/json",
        }
        # Only when there is one. A JSON content-type with an empty body is
        # refused by the server — correctly, since it says a body is coming and
        # then none does. `DELETE /v1/bot/webhook` takes no body at all.
        if data is not None:
            headers["content-type"] = "application/json"
        request = urllib.request.Request(
            f"{self._base}{path}",
            data=data,
            method=method,
            headers=headers,
        )
        try:
            with urllib.request.urlopen(request, timeout=self._timeout) as response:
                payload = response.read()
        except urllib.error.HTTPError as error:
            raise _error_from(error) from None
        return json.loads(payload) if payload else {}

    # -- the API -----------------------------------------------------------

    def me(self) -> dict[str, Any]:
        """Who this token belongs to, and the command menu it publishes."""
        return self._request("GET", "/v1/bot/me")

    def get_updates(self, *, timeout: int = 25, limit: int = 100) -> list[Update]:
        """Waits for updates, or answers empty at the deadline.

        An update is handed out **once**. There is no acknowledgement to send:
        receiving it is what consumes it, so a crash between receiving and
        acting loses that update. A bot that must not lose one should write it
        down before acting on it.
        """
        raw = self._request("GET", f"/v1/bot/updates?timeout={timeout}&limit={limit}")
        return [Update.from_json(item) for item in raw.get("updates", [])]

    def send(
        self,
        to: str,
        text: str,
        *,
        group_id: str | None = None,
        buttons: list[tuple[str, str]] | None = None,
    ) -> int:
        """Answers somebody.

        A bot may not open a conversation: this fails with ``not_contacted``
        until the person has written to it. In a group it also needs the
        *Send messages* right, which an admin grants separately.

        ``buttons`` is ``[(id, label), …]``, at most eight, with distinct ids.
        The id comes back on a press and is yours; the label is what the person
        reads. They belong to this message and cannot be changed afterwards —
        a button whose label changed under somebody about to press it is a
        button that did something other than what it said.
        """
        body: dict[str, Any] = {"to": to, "text": text}
        if group_id:
            body["groupId"] = group_id
        if buttons:
            body["buttons"] = [{"id": key, "label": label} for key, label in buttons]
        return int(self._request("POST", "/v1/bot/send", body)["messageId"])

    def reply(
        self,
        update: Update,
        text: str,
        *,
        buttons: list[tuple[str, str]] | None = None,
    ) -> int:
        """Answers where the update came from, in the group if it was in one."""
        return self.send(
            update.account_id,
            text,
            group_id=update.scope_id if update.in_group else None,
            buttons=buttons,
        )

    def _upload(self, data: bytes, *, kind: str, name: str | None) -> str:
        """Puts bytes on the server and returns the media id.

        Raw bytes, not multipart: the server stores what arrives and the send
        then points at it. **Not encrypted** — everything on the bot path is
        plaintext the server can read, and a file is no different.
        """
        # Checked here rather than left to the server, because the server does
        # not get to answer: Fastify's body limit closes the connection on a
        # payload this size, so the author saw a bare `URLError` and no reason.
        # Found by sending nine megabytes at a real server.
        if len(data) > MAX_ATTACHMENT_BYTES:
            raise BotError(
                413,
                "attachment_too_large",
                f"A bot attachment must be at most {MAX_ATTACHMENT_BYTES // (1024 * 1024)} MB; "
                f"this one is {len(data) / (1024 * 1024):.1f} MB.",
            )
        query = f"?kind={urllib.parse.quote(kind)}"
        if name:
            query += f"&name={urllib.parse.quote(name)}"
        request = urllib.request.Request(
            f"{self._base}/v1/bot/media{query}",
            data=data,
            method="POST",
            headers={
                "authorization": f"Bearer {self._token}",
                "accept": "application/json",
                "content-type": "application/octet-stream",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=self._timeout) as response:
                return str(json.loads(response.read())["mediaId"])
        except urllib.error.HTTPError as error:
            raise _error_from(error) from None
        except urllib.error.URLError as error:
            # A refused upload can arrive as a dropped connection rather than a
            # status. Say what it was, instead of letting a transport error
            # reach a bot author who has no way to read it.
            raise BotError(0, "upload_failed", f"The upload did not complete: {error.reason}") from None

    def send_photo(
        self,
        to: str,
        data: bytes,
        *,
        caption: str = "",
        name: str = "photo",
        group_id: str | None = None,
        buttons: list[tuple[str, str]] | None = None,
    ) -> int:
        """Sends a picture, drawn in the chat.

        ``caption`` is the message text; an empty one is allowed, so a picture
        can arrive on its own. The app falls back to a file row if the bytes
        turn out not to be an image — the declared kind is a hint, not a
        promise the app takes on trust.
        """
        media_id = self._upload(data, kind="image", name=name)
        return self._send_with_media(
            to, caption, media_id, "image", name, group_id=group_id, buttons=buttons,
        )

    def send_document(
        self,
        to: str,
        data: bytes,
        name: str,
        *,
        caption: str = "",
        group_id: str | None = None,
        buttons: list[tuple[str, str]] | None = None,
    ) -> int:
        """Sends a file, shown as a row with its name and size."""
        media_id = self._upload(data, kind="file", name=name)
        return self._send_with_media(
            to, caption, media_id, "file", name, group_id=group_id, buttons=buttons,
        )

    def _send_with_media(
        self,
        to: str,
        text: str,
        media_id: str,
        kind: str,
        name: str | None,
        *,
        group_id: str | None,
        buttons: list[tuple[str, str]] | None,
    ) -> int:
        body: dict[str, Any] = {
            "to": to,
            # The server wants at least one character of text. A picture with no
            # caption gets a single space rather than this client inventing a
            # sentence for it.
            "text": text or " ",
            "mediaId": media_id,
            "mediaKind": kind,
        }
        if name:
            body["fileName"] = name
        if group_id:
            body["groupId"] = group_id
        if buttons:
            body["buttons"] = [{"id": key, "label": label} for key, label in buttons]
        return int(self._request("POST", "/v1/bot/send", body)["messageId"])

    # -- polls -------------------------------------------------------------

    def send_poll(
        self,
        to: str,
        question: str,
        options: list[str],
        *,
        max_choices: int = 1,
        show_results: bool = False,
        closes_at: datetime | str | None = None,
        text: str | None = None,
        group_id: str | None = None,
    ) -> SentPoll:
        """Asks somebody a question with fixed answers.

        Two to ten answers, no two the same. ``max_choices`` above 1 lets a
        person pick up to that many. Answers arrive as updates whose ``vote`` is
        set, telling you **who** answered **what** — a bot poll is not
        anonymous to the bot, and like everything on the bot path it is not
        encrypted.

        ``show_results`` lets the people answering see the tally once they have
        answered, or once it has closed. It is off unless you ask: they do not
        know who else you asked, and with few people a tally gives away how
        somebody else answered.

        Keep the returned ``poll_id`` to put the same question to more people
        with [resend_poll] and read one tally back with [poll_results].
        """
        if not 2 <= len(options) <= MAX_POLL_OPTIONS:
            raise ValueError(f"a poll offers 2 to {MAX_POLL_OPTIONS} answers")
        poll: dict[str, Any] = {
            "question": question,
            "options": list(options),
            "maxChoices": max_choices,
            "showResults": show_results,
        }
        if closes_at is not None:
            poll["closesAt"] = _iso(closes_at)
        body: dict[str, Any] = {"to": to, "poll": poll}
        if text:
            body["text"] = text
        if group_id:
            body["groupId"] = group_id
        raw = self._request("POST", "/v1/bot/send", body)
        return SentPoll(message_id=int(raw["messageId"]), poll_id=int(raw["pollId"]))

    def resend_poll(self, to: str, poll_id: int, *, group_id: str | None = None) -> int:
        """Puts a poll this bot already made to one more person.

        Answers are per person and per poll: somebody sent it twice has one
        answer, shown under both. A closed poll is refused with
        ``poll_closed``.
        """
        body: dict[str, Any] = {"to": to, "pollId": poll_id}
        if group_id:
            body["groupId"] = group_id
        return int(self._request("POST", "/v1/bot/send", body)["messageId"])

    def poll_results(self, poll_id: int) -> PollResults:
        """The tally across everybody the poll was sent to."""
        return PollResults.from_json(self._request("GET", f"/v1/bot/polls/{int(poll_id)}"))

    def close_poll(self, poll_id: int) -> PollResults:
        """Stops a poll taking answers and returns the final tally.

        Final: there is no reopening. Closing a closed poll returns the same
        tally, so a retry is harmless.
        """
        return PollResults.from_json(
            self._request("POST", f"/v1/bot/polls/{int(poll_id)}/close", {})
        )

    # -- in a group, when an admin has granted the right ------------------

    def group_members(self, group_id: str) -> list[dict[str, Any]]:
        """Who is in a group this bot is in. Needs *Restrict members*.

        Behind the same right as removing somebody, not readable for merely
        being present: a list of who is in a group is exactly what a bot should
        not get for being added to it. Each entry carries ``removable``, so
        there is no need to find out by being refused.
        """
        raw = self._request("GET", f"/v1/bot/group/members?groupId={group_id}")
        return list(raw.get("members", []))

    def remove_member(self, group_id: str, account_id: str) -> bool:
        """Removes a member. Needs *Restrict members*.

        Refused for an **admin**, and for the bot itself. A bot that could
        remove admins would be a bot that can take over a group by removing
        everybody able to switch it off.
        """
        return bool(self._request(
            "POST",
            "/v1/bot/group/members/remove",
            {"groupId": group_id, "accountId": account_id},
        )["removed"])

    def rotate_invite(self, group_id: str) -> str:
        """Renews the group's invite link and returns the new code.

        Needs *Manage invites*. The old link stops working; nobody already in
        the group is affected.
        """
        return str(self._request(
            "POST", "/v1/bot/group/invite/rotate", {"groupId": group_id},
        )["inviteCode"])

    def set_commands(self, commands: list[tuple[str, str]]) -> None:
        """Publishes the command menu people see in the app."""
        self._request(
            "PATCH",
            "/v1/bot/me",
            {"commands": [{"command": name, "description": text} for name, text in commands]},
        )

    def set_webhook(self, url: str) -> str:
        """Registers a webhook and returns its signing secret.

        The secret is shown **once**. There is no route that reads it back.
        """
        return str(self._request("PUT", "/v1/bot/webhook", {"url": url})["secret"])

    def delete_webhook(self) -> None:
        self._request("DELETE", "/v1/bot/webhook")

    # -- the loop ----------------------------------------------------------

    def poll(self, *, timeout: int = 25) -> Iterator[Update]:
        """Yields updates forever, reconnecting through transport failures.

        Backs off on failure rather than hammering: a server that is down does
        not need a thousand requests a second from every bot pointed at it.
        """
        backoff = 1.0
        while True:
            try:
                for update in self.get_updates(timeout=timeout):
                    yield update
                backoff = 1.0
            except BotError as error:
                if error.status in (401, 403):
                    # The token is wrong or revoked. Retrying cannot fix it.
                    raise
                time.sleep(backoff)
                backoff = min(backoff * 2, 60.0)
            except (urllib.error.URLError, TimeoutError, OSError):
                time.sleep(backoff)
                backoff = min(backoff * 2, 60.0)

    def run(self, handler: Callable[["Bot", Update], None], *, timeout: int = 25) -> None:
        """Calls [handler] for every update, and keeps going if one raises."""
        for update in self.poll(timeout=timeout):
            try:
                handler(self, update)
            except Exception as error:  # noqa: BLE001 - one bad update is not fatal
                print(f"handler failed on update {update.update_id}: {error!r}")
