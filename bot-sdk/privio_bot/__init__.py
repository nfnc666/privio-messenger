"""A small client for the Privio bot API.

Deliberately small and dependency-free: it speaks HTTP with the standard
library, so a bot is a single file plus this package and nothing to install.

Read this before writing a bot:

    A bot conversation is **not** end-to-end encrypted. The text a person
    sends your bot is readable by your server and by the Privio server it
    passes through. That is a property of what a bot is — a program reached
    over HTTP cannot hold Signal keys without somebody else holding them for
    it — and the Privio app says so to the person before their first message.
    Do not build anything that implies otherwise.

In a group your bot receives only what a member's device handed it: a command,
a mention of it, or a reply to one of its messages — unless an admin has
explicitly switched on "receive all new messages". It holds no key for the
group, so this is not a filter it could be talked out of.
"""

from .client import Bot, Update, Command, Press, BotError

__all__ = ["Bot", "Update", "Command", "Press", "BotError"]
