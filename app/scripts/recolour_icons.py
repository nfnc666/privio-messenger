# -*- coding: utf-8 -*-
"""Recolour the Privio mark without touching its shape.

The delivered icon is two tones: the brand green over black (iOS, opaque) or
over nothing (Android's adaptive foreground, transparent). Every pixel is a
blend of those two, and the blend factor can be recovered exactly from one
channel — the green one, which has the most range in #01F47B:

    pixel = black*(1-t) + brand*t    =>    t = pixel.g / brand.g

Writing back `target*t` reproduces the identical coverage in a different hue,
so the glyph keeps its exact edges, proportions and padding. Nothing is
redrawn, scaled or re-antialiased, and the alpha channel is carried across
untouched where there is one.
"""
import os
from PIL import Image

BRAND_GREEN = 244              # the green channel of the delivered #01F47B

# The accent menu's own values, so the icon and the interface name the same
# colours. Green is absent on purpose: that variant is the delivered artwork,
# copied rather than recoloured, so "restore the original" returns the original
# file and not a close approximation of it.
COLOURS = {
    'blue':   (0x3B, 0x82, 0xF6),
    'teal':   (0x14, 0xB8, 0xA6),
    'purple': (0xA8, 0x55, 0xF7),
    'pink':   (0xEC, 0x48, 0x99),
    'red':    (0xF4, 0x3F, 0x5E),
    'orange': (0xF9, 0x73, 0x16),
    'yellow': (0xEA, 0xB3, 0x08),
}

def recolour(src, dst, target):
    original = Image.open(src)
    keeps_alpha = original.mode in ('RGBA', 'LA') or 'transparency' in original.info
    rgba = original.convert('RGBA')

    # How much of the mark covers each pixel, 0..255.
    coverage = rgba.getchannel('G').point(
        lambda value: min(255, round(value * 255 / BRAND_GREEN))
    )
    solid = Image.new('RGB', rgba.size, target)
    black = Image.new('RGB', rgba.size, (0, 0, 0))
    out = Image.composite(solid, black, coverage)

    if keeps_alpha:
        out = out.convert('RGBA')
        out.putalpha(rgba.getchannel('A'))

    os.makedirs(os.path.dirname(dst), exist_ok=True)
    out.save(dst)


if __name__ == '__main__':
    import json
    # Regenerates every variant from the delivered artwork. Run from `app/`
    # after the original icon changes; see docs/app-icon.md.
    src = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    contents = json.load(open(f'{src}/Contents.json'))
    for name, target in COLOURS.items():
        dst = f'ios/Runner/Assets.xcassets/AppIcon-{name}.appiconset'
        os.makedirs(dst, exist_ok=True)
        for entry in contents['images']:
            filename = entry.get('filename')
            if filename:
                recolour(f'{src}/{filename}', f'{dst}/{filename}', target)
        json.dump(contents, open(f'{dst}/Contents.json', 'w'), indent=2)
        for density in ('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'):
            base = f'android/app/src/main/res/mipmap-{density}'
            recolour(f'{base}/ic_launcher.png', f'{base}/ic_launcher_{name}.png', target)
            recolour(
                f'{base}/ic_launcher_foreground.png',
                f'{base}/ic_launcher_{name}_foreground.png',
                target,
            )
    print(f'regenerated {len(COLOURS)} variants')
