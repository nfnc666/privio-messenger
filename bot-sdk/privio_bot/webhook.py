"""Verifying a webhook delivery.

A delivery is signed over ``"{timestamp}.{body}"`` with the secret the server
showed once at registration, as ``X-Privio-Signature: sha256=<hex>``.

Check the timestamp as well as the signature. A signature alone is valid
forever, so a delivery captured off the wire can be replayed at leisure; a
window makes that useless after a few minutes.
"""

from __future__ import annotations

import hashlib
import hmac
import time


def signature_for(secret: bytes, timestamp: str, body: str) -> str:
    return hmac.new(secret, f"{timestamp}.{body}".encode("utf-8"), hashlib.sha256).hexdigest()


def verify(
    secret: bytes,
    timestamp: str,
    body: str,
    header: str,
    *,
    tolerance_seconds: int = 300,
) -> bool:
    """Whether a delivery is genuine and recent.

    ``header`` is the raw ``X-Privio-Signature`` value, with or without the
    ``sha256=`` prefix.
    """
    provided = header.split("=", 1)[1] if "=" in header else header
    expected = signature_for(secret, timestamp, body)
    if not hmac.compare_digest(expected, provided):
        return False

    try:
        sent_at = int(timestamp) / 1000.0
    except ValueError:
        return False
    return abs(time.time() - sent_at) <= tolerance_seconds
