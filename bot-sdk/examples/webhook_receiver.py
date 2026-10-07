#!/usr/bin/env python3
"""A webhook receiver, using nothing but the standard library.

Run it behind a TLS terminator that gives it a public HTTPS URL, then point
the bot at that URL:

    export PRIVIO_BOT_TOKEN=...
    export PRIVIO_BASE_URL=https://your-server.example
    python3 - <<'EOF'
    import os
    from privio_bot import Bot
    bot = Bot(os.environ["PRIVIO_BOT_TOKEN"], os.environ["PRIVIO_BASE_URL"])
    print("secret, shown once:", bot.set_webhook("https://bots.example.com/privio"))
    EOF

    export PRIVIO_WEBHOOK_SECRET=<that secret>
    python3 examples/webhook_receiver.py 8080

The server will not accept an `http://` URL or one that resolves to a private
address, so this cannot be pointed at `localhost` from the outside — that is
the SSRF guard doing its job, not a bug to work around.

Two things this file exists to demonstrate:

* every request is verified before it is read as anything but bytes, and
* an unverified request is answered 401 and dropped, not "logged for later".

A receiver that skips the check accepts a delivery from anyone who learns the
URL, which is exactly the thing the signature is there to prevent.
"""

from __future__ import annotations

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from privio_bot.webhook import verify  # noqa: E402

SECRET = bytes.fromhex(os.environ.get("PRIVIO_WEBHOOK_SECRET", ""))


def handle(update: dict) -> None:
    """What the bot does with one update. Replace with your own."""
    chat = update.get("chat") or {}
    command = update.get("command") or {}
    print(
        f"#{update.get('updateId')} from @{chat.get('username')}"
        f" in {update.get('scope')}: {update.get('text')!r}"
        + (f" [command: {command.get('name')}]" if command else "")
    )


class Receiver(BaseHTTPRequestHandler):
    def do_POST(self) -> None:  # noqa: N802 — the name the base class calls.
        length = int(self.headers.get("content-length") or 0)
        # Read at most what was announced, and cap it: an unauthenticated
        # request must not be able to make this process allocate freely.
        if length > 2_000_000:
            self.send_response(413)
            self.end_headers()
            return
        body = self.rfile.read(length).decode("utf-8", "replace")

        timestamp = self.headers.get("x-privio-timestamp", "")
        signature = self.headers.get("x-privio-signature", "")
        if not SECRET or not verify(SECRET, timestamp, body, signature):
            # No detail. A receiver that says *why* it refused helps whoever is
            # guessing.
            self.send_response(401)
            self.end_headers()
            return

        try:
            payload = json.loads(body)
        except ValueError:
            self.send_response(400)
            self.end_headers()
            return

        # Answer first, work after: the sender counts a slow or failed response
        # as a failure and backs off, and the batch has already been taken.
        self.send_response(200)
        self.end_headers()
        self.wfile.flush()

        for update in payload.get("updates", []):
            try:
                handle(update)
            except Exception as error:  # noqa: BLE001 — one bad update, not the process.
                print(f"handler failed on {update.get('updateId')}: {error}", file=sys.stderr)

    def log_message(self, fmt: str, *args: object) -> None:
        # The default access log writes the path and headers. The path is the
        # secret part of a webhook URL for many people; keep it out.
        pass


def main() -> int:
    if not SECRET:
        print("set PRIVIO_WEBHOOK_SECRET to the hex secret from set_webhook", file=sys.stderr)
        return 2
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    print(f"listening on :{port}")
    HTTPServer(("", port), Receiver).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
