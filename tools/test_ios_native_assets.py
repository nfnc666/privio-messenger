import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from ios_native_assets import configure, macho_minima, verify


def binary(minimum=15, platform=2):
    header = struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 6, 1, 24, 0, 0)
    return header + struct.pack('<6I', 0x32, 24, platform, minimum << 16, 26 << 16, 0)


class NativeAssetsTests(unittest.TestCase):
    def test_packager_and_cached_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'packages/flutter_tools/lib/src/isolated/native_assets/ios/native_assets.dart'
            source.parent.mkdir(parents=True)
            source.write_text('const targetIOSVersion = 13;\n')
            cache = root / 'bin/cache'
            cache.mkdir(parents=True)
            for name in ('flutter_tools.snapshot', 'flutter_tools.stamp'):
                (cache / name).write_text('stale')
            configure(root)
            self.assertEqual(source.read_text(), 'const targetIOSVersion = 15;\n')
            self.assertEqual(list(cache.iterdir()), [])
            configure(root)  # Safe on a previously corrected cached SDK.
            source.write_text('const targetIOSVersion = 16;\n')
            with self.assertRaisesRegex(ValueError, 'packager changed'):
                configure(root)

    def test_fat_device_binary(self):
        thin = binary()
        fat = struct.pack('>7I', 0xcafebabe, 1, 0x100000c, 0, 28, len(thin), 0) + thin
        self.assertEqual(macho_minima(fat), [(15, 0, 0)])

    def test_reject_simulator(self):
        with self.assertRaisesRegex(ValueError, 'Non-device'):
            macho_minima(binary(platform=7))

    def make_ipa(self, path, declared, app='15.0', minimum=15):
        root = 'Payload/Runner.app/'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr(root + 'Info.plist', plistlib.dumps({'MinimumOSVersion': app}))
            framework = root + 'Frameworks/libsignal_frb.framework/'
            archive.writestr(framework + 'Info.plist', plistlib.dumps({
                'MinimumOSVersion': declared, 'CFBundleExecutable': 'libsignal_frb'}))
            archive.writestr(framework + 'libsignal_frb', binary(minimum))

    def test_build63_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = Path(directory) / 'bad.ipa'
            self.make_ipa(ipa, '13.0')
            with self.assertRaisesRegex(ValueError, 'ITMS-90208'):
                verify(ipa)

    def test_correct_metadata_passes(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = Path(directory) / 'good.ipa'
            self.make_ipa(ipa, '15.0')
            verify(ipa)

    def test_framework_cannot_require_newer_ios_than_app(self):
        with tempfile.TemporaryDirectory() as directory:
            ipa = Path(directory) / 'newer.ipa'
            self.make_ipa(ipa, '16.0', minimum=16)
            with self.assertRaisesRegex(ValueError, 'ITMS-90208'):
                verify(ipa)


if __name__ == '__main__':
    unittest.main()
