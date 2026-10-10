#!/usr/bin/env bash
# Builds libsignal for Privio from source. Never downloads a binary.
#
#   app/scripts/build_libsignal.sh host
#   app/scripts/build_libsignal.sh aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
#   app/scripts/build_libsignal.sh aarch64-apple-ios
#
# The sources are app/third_party/libsignal_dart/rust: a thin binding over
# Signal's own libsignal, pinned by Cargo.lock to tag v0.103.1 (commit
# e8cc2ddd). `--locked` refuses to build if the lock would have to change, so
# what is compiled is exactly what was reviewed. The Rust toolchain is pinned by
# rust-toolchain.toml next to it.
#
# Android needs the NDK: set ANDROID_NDK_HOME (GitHub's runners provide
# ANDROID_NDK_LATEST_HOME, which is used when it is not set). The build hook in
# third_party/libsignal_dart/hook/build.dart picks the results up from
# rust/target/<triple>/release and refuses to build the app without them.
set -euo pipefail

cd "$(dirname "$0")/../third_party/libsignal_dart/rust"

# The lowest Android API the libraries are linked for. Rust's standard library
# needs 21; Flutter's own minimum is above that.
ANDROID_API="${ANDROID_API:-24}"

if [ "$#" -eq 0 ]; then
  echo "usage: $0 host | <rust target triple>..." >&2
  exit 2
fi

for target in "$@"; do
  case "$target" in
    host)
      cargo build --release --locked
      ;;
    *-linux-android*)
      ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-}}"
      if [ -z "$ndk" ] || [ ! -d "$ndk" ]; then
        echo "ANDROID_NDK_HOME is not set to an NDK directory" >&2
        exit 2
      fi
      host_tag="linux-x86_64"
      [ "$(uname)" = "Darwin" ] && host_tag="darwin-x86_64"
      bin="$ndk/toolchains/llvm/prebuilt/$host_tag/bin"
      case "$target" in
        aarch64-linux-android) clang_prefix="aarch64-linux-android$ANDROID_API" ;;
        armv7-linux-androideabi) clang_prefix="armv7a-linux-androideabi$ANDROID_API" ;;
        x86_64-linux-android) clang_prefix="x86_64-linux-android$ANDROID_API" ;;
        i686-linux-android) clang_prefix="i686-linux-android$ANDROID_API" ;;
        *) echo "unknown Android target $target" >&2; exit 2 ;;
      esac
      upper="$(echo "$target" | tr '[:lower:]-' '[:upper:]_')"
      lower="$(echo "$target" | tr '-' '_')"
      rustup target add "$target"
      # 16 KB pages: required of native code in apps on Android 15 and later.
      env \
        "CARGO_TARGET_${upper}_LINKER=$bin/$clang_prefix-clang" \
        "CC_${lower}=$bin/$clang_prefix-clang" \
        "AR_${lower}=$bin/llvm-ar" \
        "CARGO_TARGET_${upper}_RUSTFLAGS=-C link-arg=-Wl,-z,max-page-size=16384" \
        cargo build --release --locked --target "$target"
      ;;
    *-apple-ios*)
      rustup target add "$target"
      # The app's own minimum (Runner.xcodeproj and the Podfile say 15.0), so
      # the library never claims to run somewhere the app does not.
      IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}" \
        cargo build --release --locked --target "$target"
      ;;
    *-apple-darwin)
      rustup target add "$target"
      cargo build --release --locked --target "$target"
      ;;
    *-unknown-linux-gnu)
      rustup target add "$target"
      cargo build --release --locked --target "$target"
      ;;
    *)
      echo "unknown target $target" >&2
      exit 2
      ;;
  esac
done
