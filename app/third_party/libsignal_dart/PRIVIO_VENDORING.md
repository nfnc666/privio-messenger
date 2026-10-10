# libsignal Dart binding, vendored into Privio

**What:** the `libsignal` Dart package 7.4.1, a flutter_rust_bridge binding
over Signal's own libsignal (Rust). Privio uses it for **sealed sender only**:
sealing an already-encrypted Signal message and opening one, plus validating
sender certificates. Sessions, prekeys and the inner encryption stay with
`libsignal_protocol_dart`. See `docs/sealed-sender.md`.

**Licence:** AGPL-3.0, like Privio (`LICENSE`), with the binding author's
app-store permission (`LICENSE.appstore`) and libsignal's own licence
(`LICENSE.libsignal`). Nothing here changes Privio's licence.

## Where it came from

| | |
| --- | --- |
| Package | `libsignal` 7.4.1 from pub.dev, <https://github.com/djx-y-z/libsignal_dart> |
| Archive SHA-256 | `4779f5394358874bf7821204c4247feaa0ed49d77ac775f5191dd9bf1931e0ef`, matching pub.dev's published `archive_sha256` |
| libsignal | `signalapp/libsignal` tag **v0.103.1**, commit `e8cc2dddd578859b4a029c9c94670b24ce2b616a`, checked against GitHub (`git ls-remote`, the tag's peeled commit) and pinned in `rust/Cargo.lock` |
| flutter_rust_bridge | 2.13.0 exactly, on both sides (the runtime refuses a mismatch) |

## What was taken, and what was left out

Taken: `lib/`, `rust/src`, `rust/Cargo.toml`, `rust/Cargo.lock`,
`rust/deny.toml`, the licences, README and changelog.

Left out: the example app, the test suite, fuzzing targets, and the upstream
`CLAUDE.md`. Upstream's instructions are not instructions for this repository.

## What was changed

1. **`hook/build.dart` is Privio's own.** Upstream's hook downloaded pre-built
   binaries from the binding author's GitHub releases, verified against a
   checksum file from the same release. It is replaced by a short hook that
   only ever uses a library compiled from `rust/` by
   `app/scripts/build_libsignal.sh`, and fails the build otherwise. It has no
   network code at all.
2. `pubspec.yaml`: the `crypto` dependency, used only by the download code, is
   removed; `publish_to: none`.
3. `rust/rust-toolchain.toml` pins the Rust toolchain to 1.94.1.

Nothing in `lib/` or `rust/src` was changed.

## What was reviewed

* The Rust binding (`rust/src`) has no network, file, environment or process
  access, and forbids `unsafe` code (`[lints.rust] unsafe_code = "deny"`).
* Its native dependencies: no OpenSSL or BoringSSL. The post-quantum code is
  pure Rust (`libcrux`). `cc` appears only for small platform helpers;
  `bindgen` only for `crabgrind`, a Valgrind binding.
* The sealed-sender functions Privio calls validate the sender certificate
  against the trust root, refuse a message addressed as coming from ourselves,
  and check the certificate's identity key against the stored one before
  returning anything (`rust/src/api/sealed_sender.rs`,
  `sealed_sender_decrypt_to_usmc_inner`).

## Updating it

Download the new version's archive into an empty directory, check its SHA-256
against pub.dev, diff `lib/`, `rust/` and `pubspec.yaml` against this copy,
re-check the libsignal tag's commit, keep Privio's hook, and update this file.
A version bump is a security review, not a dependency bump.
