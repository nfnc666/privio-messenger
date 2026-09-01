# Security Policy

## Reporting a vulnerability

Email **security@getprivio.com**. Do not open a public issue, and do not post
details in a pull request or a chat channel before the fix has shipped.

Useful reports include: what you did, what happened, what you expected, the
commit or build you tested, and — if you have one — a proof of concept. If a
report is thin we will ask; a thin report is still much better than none.

What to expect:

| | |
| --- | --- |
| Acknowledgement | Within 3 working days |
| First assessment | Within 10 working days |
| Fix and disclosure | Coordinated with you, once a fix exists |

We will tell you what we think the impact is and whether we agree with your
severity. If we disagree, we will say why rather than quietly downgrade it.
Credit is offered by default and withheld only if you ask.

There is no paid bug bounty today. If that changes it will be announced here
rather than promised in advance.

## Scope

In scope: everything in this repository — the Flutter client (`app/`), the
server (`server/`), and the deployment material in `docs/`. Also in scope:
anything that breaks one of the claims in
[`docs/security-model.md`](docs/security-model.md), because those claims are
the product.

Particularly interesting:

* Anything that lets the server, or someone who has taken it, read message
  content, attachments, backups or group metadata.
* Anything that lets one account read, send as, or bind a license to another.
* Key handling: session setup, prekey exchange, safety numbers, device
  linking, backup and recovery keys.
* Metadata leaks — a request that reveals who is talking to whom beyond what
  the routing genuinely requires.
* License redemption: any path to redeeming one key twice, or to being served
  while unlicensed on a server with `LICENSE_REQUIRED=true`.

Out of scope: findings against a self-hosted deployment's own configuration
(a missing TLS certificate, an exposed database) rather than against this
code; denial of service by volume; social engineering; automated scanner
output with no demonstrated impact.

Client-side license checks are explicitly out of scope. Privio Libre is open
source and can be built with the license screen removed — only the server
refusing service enforces anything, which is
[documented](docs/licensing.md#enforcement), not an oversight.

## What we do not claim

Privio has not been independently audited. Until a review has actually
happened and been published, no audit, certification or compliance claim will
appear here or on the website. The security model describes what the code
does; where something is not implemented yet, it says so.

## Verifying what you run

Privio Libre is built to be reproducible from this source. Building the APK
yourself and comparing it with the published one is a check anyone can make
without trusting us — see [`docs/privio-libre.md`](docs/privio-libre.md).
