# -*- coding: utf-8 -*-
"""Turn a delivered square artwork into every launcher size both platforms want.

A *style* is not a recolour. `recolour_icons.py` takes the one delivered mark
and shifts its hue, which works because that artwork is two tones and the blend
factor comes back out of one channel. These four are their own pictures —
camouflage plate, neon glass, a shield, a mesh — and nothing about them can be
derived from anything else. So they are imported rather than generated: the
delivered file is the source of truth and this script only resizes it.

What it writes, per style:

* iOS   `Assets.xcassets/AppIcon-<style>.appiconset/` — every size the existing
        sets carry, plus a Contents.json copied from one of them so the two
        cannot drift.
* Android `mipmap-<density>/ic_launcher_<style>.png` — the legacy icon for
        Android 7 and below, the artwork at the density's size.
* Android `mipmap-<density>/ic_launcher_<style>_foreground.png` — the adaptive
        foreground. The launcher masks the middle 72dp of a 108dp canvas, so the
        artwork is scaled into that window and the rest is transparent; the
        background layer is the same flat black the other icons use.
* Flutter `assets/launcher_styles/<style>.png` — 256px, for the picker. The
        colour swatches are the mark tinted at draw time, which cannot work for
        a picture that is not one colour, so these are real thumbnails.

Run it from `app/`:

    python3 scripts/import_icon_styles.py <camo.png> <camo_shield.png> …
"""
import json
import os
import shutil
import sys

from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

#: The styles, in the order the picker shows them. The code is the wire name:
#: it reaches the keystore, the Android alias and the iOS alternate icon, so it
#: may not change once a build has shipped with it.
STYLES = ['camo', 'camo_shield', 'neon', 'neon_mesh']

#: Android's legacy icon size per density, and the adaptive canvas (108dp).
DENSITIES = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}

#: The share of the 108dp adaptive canvas the launcher actually shows.
SAFE_ZONE = 72 / 108

#: Every file an existing appiconset carries, and the pixel size of each.
IOS_SIZES = {
    'Icon-App-20x20@1x.png': 20, 'Icon-App-20x20@2x.png': 40, 'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29, 'Icon-App-29x29@2x.png': 58, 'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40, 'Icon-App-40x40@2x.png': 80, 'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120, 'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76, 'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
}


def square(image):
    """The artwork as an opaque square, trimmed of any stray alpha."""
    rgb = Image.new('RGB', image.size, (0, 0, 0))
    source = image.convert('RGBA')
    rgb.paste(source, mask=source.split()[3])
    if rgb.width != rgb.height:
        raise SystemExit(f'the artwork must be square, not {rgb.size}')
    return rgb


def scaled(image, size):
    return image.resize((size, size), Image.LANCZOS)


def write_ios(art, style):
    target = os.path.join(HERE, 'ios/Runner/Assets.xcassets', f'AppIcon-{style}.appiconset')
    os.makedirs(target, exist_ok=True)
    # Copied rather than written out: the catalogue's shape is the existing
    # one's, and a second hand-written copy is a second thing to keep in step.
    shutil.copyfile(
        os.path.join(HERE, 'ios/Runner/Assets.xcassets/AppIcon-blue.appiconset/Contents.json'),
        os.path.join(target, 'Contents.json'),
    )
    listed = {entry['filename'] for entry in
              json.load(open(os.path.join(target, 'Contents.json')))['images']}
    missing = listed - set(IOS_SIZES)
    if missing:
        raise SystemExit(f'Contents.json names files this script does not make: {sorted(missing)}')
    for name, size in IOS_SIZES.items():
        scaled(art, size).save(os.path.join(target, name))
    return len(IOS_SIZES)


def write_android(art, style):
    written = 0
    for density, size in DENSITIES.items():
        folder = os.path.join(HERE, 'android/app/src/main/res', f'mipmap-{density}')
        os.makedirs(folder, exist_ok=True)
        scaled(art, size).save(os.path.join(folder, f'ic_launcher_{style}.png'))

        # The adaptive foreground: the same picture inside the 72/108 window the
        # launcher shows, on transparency. The background layer is flat black,
        # so the artwork's own black edges vanish into it under any mask shape.
        canvas = size * 108 // 48 if density == 'mdpi' else round(size * 108 / 48)
        inner = round(canvas * SAFE_ZONE)
        foreground = Image.new('RGBA', (canvas, canvas), (0, 0, 0, 0))
        offset = (canvas - inner) // 2
        foreground.paste(scaled(art, inner).convert('RGBA'), (offset, offset))
        foreground.save(os.path.join(folder, f'ic_launcher_{style}_foreground.png'))
        written += 2
    return written


def write_preview(art, style):
    folder = os.path.join(HERE, 'assets/launcher_styles')
    os.makedirs(folder, exist_ok=True)
    scaled(art, 256).save(os.path.join(folder, f'{style}.png'))


def main(argv):
    if len(argv) != len(STYLES):
        raise SystemExit(f'give one file per style, in this order: {", ".join(STYLES)}')
    for style, path in zip(STYLES, argv):
        art = square(Image.open(path))
        ios = write_ios(art, style)
        android = write_android(art, style)
        write_preview(art, style)
        print(f'{style}: {ios} iOS files, {android} Android files, 1 preview')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
