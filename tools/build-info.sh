#!/usr/bin/env bash
# Prints the --dart-define arguments that make a build traceable.
#
#   flutter build apk --release --flavor libre \
#     --dart-define=PRIVIO_EDITION=libre $(tools/build-info.sh)
#
# Deliberately tiny and deliberately not clever: it reads the version from the
# pubspec and the commit from git, and prints nothing else. Anything that ends
# up in a shipped binary should be something you can see here in one screen.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(grep -m1 '^version:' "$root/app/pubspec.yaml" | awk '{print $2}' | cut -d+ -f1)"

if commit="$(git -C "$root" rev-parse HEAD 2>/dev/null)"; then
  # A build from a dirty tree is not the commit it names, and saying so is
  # better than a hash that does not match what was compiled.
  if ! git -C "$root" diff --quiet HEAD 2>/dev/null; then
    commit="${commit}-dirty"
  fi
else
  commit=""
fi

printf -- '--dart-define=PRIVIO_VERSION=%s --dart-define=PRIVIO_COMMIT=%s\n' "$version" "$commit"
