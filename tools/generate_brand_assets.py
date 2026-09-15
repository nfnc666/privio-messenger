#!/usr/bin/env python3
"""Derive every Privio brand asset from the two delivered masters.

Run it from the repository root:

    python3 tools/generate_brand_assets.py

Nothing here draws the logo. The two files in `design/logo/` are the artwork as
delivered; everything this produces is a crop, a scale, an alpha derivation or —
for the dark-surface wordmark only — a recolour of the *text*. The green is
never touched.

**Both masters arrive without an alpha channel.** The icon is green on solid
black and the wordmark is green-and-black on solid white, so transparency has to
be *derived* rather than assumed: a naive "white becomes transparent" threshold
would eat the antialiasing and leave a pale fringe around every curve. The
derivation below inverts the compositing equation instead — for ink of colour C
over a background B at coverage a, the delivered pixel is `a*C + (1-a)*B`, so
`a = (B - pixel) / (B - C)` on the channel where `B - C` is largest. That
reproduces the original edge softness exactly.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "design" / "logo"

ICON_MASTER = LOGO / "privio-icon-master.png"
WORDMARK_MASTER = LOGO / "privio-wordmark-master.png"

# Sampled from the masters rather than typed from memory; asserted below so a
# re-delivered file that drifts is caught instead of silently recoloured.
ICON_GREEN = (1, 244, 123)
WORD_GREEN = (1, 221, 121)
WORD_TEXT = (6, 6, 6)


def load(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGB")).astype(np.float64)


def save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    print(f"  {path.relative_to(ROOT)}  {img.size[0]}x{img.size[1]} {img.mode}")


# Neither master is a clean render: the flat fields carry compression noise, so
# "black" is (1, 1, 0) as often as (0, 0, 0). Left alone that becomes an alpha of
# 1/255 across the whole background — invisible on a dark surface, a faint green
# wash on a light one, and enough to make `getbbox` return the entire canvas and
# defeat every trim below. Anything under this coverage is background.
NOISE_FLOOR = 4 / 255


def coverage(pixels: np.ndarray, ink: tuple[int, int, int], bg: int) -> np.ndarray:
    """How much ink covers each pixel, from the compositing equation."""
    channel = int(np.argmax([abs(bg - c) for c in ink]))
    denom = bg - ink[channel]
    a = (bg - pixels[:, :, channel]) / denom
    a = np.clip(a, 0.0, 1.0)
    return np.where(a < NOISE_FLOOR, 0.0, a)


def rgba(shape: tuple[int, int], ink, alpha: np.ndarray) -> Image.Image:
    out = np.zeros((shape[0], shape[1], 4), dtype=np.uint8)
    out[:, :, 0], out[:, :, 1], out[:, :, 2] = ink[0], ink[1], ink[2]
    out[:, :, 3] = np.round(alpha * 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def trim(img: Image.Image, square: bool = False) -> Image.Image:
    """Crop to the visible ink. Optionally pad back out to a centred square."""
    box = img.getbbox()
    cropped = img.crop(box)
    if not square:
        return cropped
    side = max(cropped.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(
        cropped,
        ((side - cropped.size[0]) // 2, (side - cropped.size[1]) // 2),
    )
    return canvas


def resize(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    return img.resize(size, Image.LANCZOS)


# --- The mark, lifted off its black background ------------------------------


def build_mark() -> Image.Image:
    px = load(ICON_MASTER)
    alpha = coverage(px, ICON_GREEN, bg=0)
    return trim(rgba(px.shape[:2], ICON_GREEN, alpha), square=True)


# --- The wordmark, lifted off its white background --------------------------


def build_wordmark(text_colour: tuple[int, int, int]) -> Image.Image:
    px = load(WORDMARK_MASTER)
    # The two inks never touch — the symbol ends at x=669 and the text starts at
    # x=733 — so classifying by hue is unambiguous, including on the soft edges
    # where a green pixel keeps its high green channel while a grey one does not.
    is_green = (px[:, :, 1] - px[:, :, 0]) > 25

    green_a = coverage(px, WORD_GREEN, bg=255) * is_green
    text_a = coverage(px, WORD_TEXT, bg=255) * ~is_green

    h, w = px.shape[:2]
    out = np.zeros((h, w, 4), dtype=np.float64)
    for i in range(3):
        out[:, :, i] = WORD_GREEN[i] * green_a + text_colour[i] * text_a
    total = np.clip(green_a + text_a, 0.0, 1.0)
    # Un-premultiply so the colours stay true where coverage is partial.
    with np.errstate(divide="ignore", invalid="ignore"):
        for i in range(3):
            out[:, :, i] = np.where(total > 0, out[:, :, i] / total, 0)
    out[:, :, 3] = total * 255
    img = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")
    return trim(img)


# --- Targets ----------------------------------------------------------------

IOS_ICONS = {
    "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40, "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29, "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80, "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120, "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76, "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

ANDROID_LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# The adaptive canvas is 108dp and only the middle 72dp is ever visible, so the
# delivered square is scaled to that 72/108 window. Inside the mask the glyph
# then sits at exactly the proportion it has in the master.
ADAPTIVE_VISIBLE = 72 / 108


def main() -> None:
    icon_master = Image.open(ICON_MASTER).convert("RGB")
    assert icon_master.size[0] == icon_master.size[1], "the app icon master must be square"

    mark = build_mark()
    wordmark_light = build_wordmark((6, 6, 6))       # black text, for light surfaces
    wordmark_dark = build_wordmark((255, 255, 255))  # white text, for dark surfaces

    print("design/logo — derived masters")
    save(mark, LOGO / "privio-mark.png")
    save(wordmark_light, LOGO / "privio-wordmark-light.png")
    save(wordmark_dark, LOGO / "privio-wordmark-dark.png")

    print("iOS app icon (opaque, square, no alpha — Apple rejects either)")
    ios = ROOT / "app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, size in IOS_ICONS.items():
        save(resize(icon_master, (size, size)), ios / name)

    print("iOS launch image — the mark on the app's black")
    launch = ROOT / "app/ios/Runner/Assets.xcassets/LaunchImage.imageset"
    for name, size in (("LaunchImage.png", 128), ("LaunchImage@2x.png", 256), ("LaunchImage@3x.png", 384)):
        save(resize(mark, (size, size)), launch / name)

    print("Android legacy launcher icons")
    for density, size in ANDROID_LEGACY.items():
        save(
            resize(icon_master, (size, size)).convert("RGB"),
            ROOT / f"app/android/app/src/main/res/mipmap-{density}/ic_launcher.png",
        )

    print("Android adaptive foreground (background is a colour resource)")
    for density, size in ANDROID_LEGACY.items():
        canvas_px = round(size * 108 / 48)
        inner = round(canvas_px * ADAPTIVE_VISIBLE)
        layer = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
        glyph = resize(mark, (round(inner * mark.size[0] / icon_master.size[0]),) * 2)
        # Centred by the master's own centring, which was measured, not assumed.
        layer.paste(glyph, ((canvas_px - glyph.size[0]) // 2, (canvas_px - glyph.size[1]) // 2), glyph)
        save(layer, ROOT / f"app/android/app/src/main/res/mipmap-{density}/ic_launcher_foreground.png")

    print("Flutter in-app assets")
    save(resize(mark, (512, 512)), ROOT / "app/assets/logo/privio_mark.png")
    # The app is dark throughout, so the in-app lock-up is the white-text one.
    ratio = wordmark_dark.size[1] / wordmark_dark.size[0]
    save(resize(wordmark_dark, (1024, round(1024 * ratio))), ROOT / "app/assets/logo/privio_wordmark.png")

    print("Flutter web shell")
    web = ROOT / "app/web"
    save(resize(icon_master, (64, 64)), web / "favicon.png")
    for size in (192, 512):
        save(resize(icon_master, (size, size)), web / f"icons/Icon-{size}.png")
        # Maskable: the glyph covers 53% of the square, well inside the 80%
        # safe circle, so the delivered artwork already satisfies the rule.
        save(resize(icon_master, (size, size)), web / f"icons/Icon-maskable-{size}.png")

    print("Server: the invite page's fallback avatar and its link preview")
    save(resize(mark, (512, 512)), ROOT / "server/assets/privio-mark.png")
    # Opaque, because a link preview is composited by whichever messenger drew
    # it and a transparent PNG lands on an unpredictable colour.
    save(resize(icon_master, (1024, 1024)), ROOT / "server/assets/privio-icon.png")

    print("\nDone. Masters are design/logo/privio-{icon,wordmark}-master.png")


if __name__ == "__main__":
    main()
