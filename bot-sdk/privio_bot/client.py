"""The HTTP client and the polling loop."""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Callable, Iterator


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

    @property
    def in_group(self) -> bool:
        return self.scope == "group" and self.scope_id is not None

    @classmethod
    def from_json(cls, raw: dict[str, Any]) -> "Update":
        chat = raw.get("chat") or {}
        command_raw = raw.get("command")
        button_raw = raw.get("button")
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
            raw = error.read()
            try:
                parsed = json.loads(raw)
            except ValueError:
                parsed = {}
            raise BotError(
                error.code,
                str(parsed.get("error", "http_error")),
                str(parsed.get("message", error.reason)),
            ) from None
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
