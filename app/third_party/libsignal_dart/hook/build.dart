/// Privio's build hook for libsignal: **built from source, never downloaded.**
///
/// This replaces the upstream hook, which fetched pre-built native libraries
/// from its author's GitHub releases and checked them against a checksum file
/// from the same release. That verifies a download, not the person who built
/// it, and Privio does not ship a native library it did not compile itself.
/// See `../PRIVIO_VENDORING.md` and `docs/sealed-sender.md`.
///
/// What it does: find `libsignal_frb`, compiled by `app/scripts/build_libsignal.sh`
/// from the pinned sources in `../rust` (Signal's libsignal at tag v0.103.1,
/// commit e8cc2ddd), and register it as the package's native code asset.
/// What it does not do: touch the network. When the library for the target
/// being built is missing, the build stops and says how to build it.
library;

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _packageName = 'libsignal';

/// The asset id the Dart side loads (`lib/src/libsignal.dart`).
const _assetId = 'libsignal';
const _crateName = 'libsignal_frb';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    final os = code.targetOS;
    final arch = code.targetArchitecture;
    final root = input.packageRoot;
    final triple = rustTriple(
      os,
      arch,
      iosSimulator: os == OS.iOS && code.iOS.targetSdk == IOSSdk.iPhoneSimulator,
    );
    final fileName = libraryFileName(os);

    final candidates = <Uri>[
      if (triple != null) root.resolve('rust/target/$triple/release/$fileName'),
      // A plain `cargo build --release` is a host build. Only good for the host.
      if (os == OS.current && arch == Architecture.current)
        root.resolve('rust/target/release/$fileName'),
    ];

    // Rebuild when the sources or the lock change, whatever is found.
    output.dependencies
      ..add(root.resolve('rust/Cargo.lock'))
      ..add(root.resolve('rust/Cargo.toml'));

    for (final candidate in candidates) {
      if (File.fromUri(candidate).existsSync()) {
        output.dependencies.add(candidate);
        output.assets.code.add(
          CodeAsset(
            package: _packageName,
            name: _assetId,
            linkMode: DynamicLoadingBundled(),
            file: candidate,
          ),
        );
        return;
      }
    }

    throw StateError(
      'libsignal has not been built for $os-$arch'
      '${triple == null ? '' : ' ($triple)'}.\n'
      'Privio builds it from source and never downloads it. Run:\n'
      '  app/scripts/build_libsignal.sh ${triple ?? 'host'}\n'
      'Looked in: ${candidates.map((c) => c.toFilePath()).join(', ')}',
    );
  });
}

/// The Rust target triple for a Flutter target, or null for one Privio does
/// not build.
String? rustTriple(OS os, Architecture arch, {bool iosSimulator = false}) {
  return switch ((os, arch)) {
    (OS.android, Architecture.arm64) => 'aarch64-linux-android',
    (OS.android, Architecture.arm) => 'armv7-linux-androideabi',
    (OS.android, Architecture.x64) => 'x86_64-linux-android',
    (OS.android, Architecture.ia32) => 'i686-linux-android',
    (OS.iOS, Architecture.arm64) =>
      iosSimulator ? 'aarch64-apple-ios-sim' : 'aarch64-apple-ios',
    (OS.iOS, Architecture.x64) => 'x86_64-apple-ios',
    (OS.linux, Architecture.x64) => 'x86_64-unknown-linux-gnu',
    (OS.linux, Architecture.arm64) => 'aarch64-unknown-linux-gnu',
    (OS.macOS, Architecture.arm64) => 'aarch64-apple-darwin',
    (OS.macOS, Architecture.x64) => 'x86_64-apple-darwin',
    _ => null,
  };
}

String libraryFileName(OS os) => switch (os) {
  OS.macOS || OS.iOS => 'lib$_crateName.dylib',
  OS.windows => '$_crateName.dll',
  _ => 'lib$_crateName.so',
};
