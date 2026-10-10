#!/usr/bin/env python3
"""Work around Flutter's fixed iOS 13 native-asset metadata; verify the IPA.

Flutter 3.47.1 packages native dylibs with targetIOSVersion = 13 regardless of
Runner's deployment target. Our Rust dylib is compiled for iOS 15. Patch the
packager BEFORE compilation/signing, never the signed archive or IPA.
Upstream: https://github.com/flutter/flutter/issues/145104
"""
import argparse
import plistlib
import re
import struct
import zipfile
from pathlib import Path


def version(text):
    if not isinstance(text, str) or not re.fullmatch(r"\d+(\.\d+){0,2}", text):
        raise ValueError(f"Invalid or missing iOS minimum: {text!r}")
    return tuple((list(map(int, text.split('.'))) + [0, 0])[:3])


def configure(flutter_root):
    path = Path(flutter_root) / 'packages/flutter_tools/lib/src/isolated/native_assets/ios/native_assets.dart'
    source = path.read_text()
    pattern = r'^const targetIOSVersion = (\d+);$'
    matches = re.findall(pattern, source, re.M)
    if len(matches) != 1 or matches[0] not in ('13', '15'):
        raise ValueError('Flutter native asset packager changed; review the iOS minimum workaround before building.')
    path.write_text(re.sub(pattern, 'const targetIOSVersion = 15;', source, flags=re.M))
    # flutter-action may have cached flutter_tools.snapshot. Invalidate it so
    # the next flutter command runs the corrected packager, not the old code.
    for name in ('flutter_tools.snapshot', 'flutter_tools.stamp'):
        (Path(flutter_root) / 'bin/cache' / name).unlink(missing_ok=True)
    print('Flutter native asset framework minimum set to iOS 15 before signing.')


def macho_minima(data):
    """Read each device slice's actual linked minimum, including fat dylibs."""
    if data[:4] in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        wide = data[:4] == b'\xca\xfe\xba\xbf'
        count = struct.unpack_from('>I', data, 4)[0]
        result = []
        for i in range(count):
            entry = 8 + i * (32 if wide else 20)
            offset, size = struct.unpack_from('>QQ' if wide else '>II', data, entry + 8)
            result.extend(macho_minima(data[offset:offset + size]))
        return result
    if data[:4] != b'\xcf\xfa\xed\xfe':
        raise ValueError('Expected a 64-bit iOS Mach-O binary')
    count = struct.unpack_from('<I', data, 16)[0]
    offset = 32
    minima = []
    for _ in range(count):
        command, size = struct.unpack_from('<II', data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError('Malformed Mach-O load command')
        if command == 0x32:  # LC_BUILD_VERSION
            platform, minimum = struct.unpack_from('<II', data, offset + 8)
            if platform != 2:  # iOS device, not simulator or macOS
                raise ValueError(f'Non-device platform {platform} in release framework')
            minima.append((minimum >> 16, (minimum >> 8) & 255, minimum & 255))
        elif command == 0x25:  # LC_VERSION_MIN_IPHONEOS
            minimum = struct.unpack_from('<I', data, offset + 8)[0]
            minima.append((minimum >> 16, (minimum >> 8) & 255, minimum & 255))
        offset += size
    if not minima:
        raise ValueError('No iOS deployment version in native binary')
    return minima


def verify(ipa):
    with zipfile.ZipFile(ipa) as archive:
        app_plists = [n for n in archive.namelist()
                      if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', n)]
        if len(app_plists) != 1:
            raise ValueError('Expected exactly one application in the IPA')
        app = app_plists[0].removesuffix('Info.plist')
        app_min = version(plistlib.loads(archive.read(app_plists[0])).get('MinimumOSVersion'))
        framework = app + 'Frameworks/libsignal_frb.framework/'
        metadata = plistlib.loads(archive.read(framework + 'Info.plist'))
        declared = version(metadata.get('MinimumOSVersion'))
        binary = archive.read(framework + metadata['CFBundleExecutable'])
        linked = macho_minima(binary)
        if not linked or max(linked) > declared or declared > app_min:
            raise ValueError(f'ITMS-90208: libsignal linked minima {linked}, '
                             f'framework declares {declared}, app declares {app_min}')
        print(f'libsignal verified: linked {linked}, framework {declared}, app {app_min}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--configure', metavar='FLUTTER_ROOT')
    group.add_argument('--verify', metavar='IPA')
    args = parser.parse_args()
    try:
        configure(args.configure) if args.configure else verify(args.verify)
    except (ValueError, KeyError, OSError, struct.error, zipfile.BadZipFile) as error:
        parser.exit(1, f'::error::{error}\n')
