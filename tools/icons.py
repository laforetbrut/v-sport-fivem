"""
Render the item icons to PNG.

WHY THIS EXISTS ALONGSIDE THE SVGs: every FiveM inventory wants a PNG, and the usual answer -
ImageMagick or Inkscape - is a dependency most server owners do not have and should not need to
install to see a whey tub in a slot. This draws the same four icons with Pillow, which is already
in this project's toolchain, and writes 100x100 RGBA files.

    python tools/icons.py                      writes images/*.png
    python tools/icons.py <inventory/images>   also copies them into an inventory

The SVGs in images/ remain the editable source and scale to any size; these are the convenience
build. If you have ImageMagick, images/README.md has the one-liner and it will look slightly better
than this does - antialiasing here is done by drawing at 4x and downsampling.
"""
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "images"

# Drawn at 4x and downsampled: Pillow has no antialiased primitives, and a 400px circle shrunk to
# 100 is indistinguishable from one drawn with antialiasing.
SCALE = 4
SIZE = 100 * SCALE


def s(*values):
    """Scale coordinates from the 100x100 design space."""
    return tuple(int(round(v * SCALE)) for v in values)


def vertical_gradient(size, box, top, bottom):
    """A vertical linear gradient clipped to `box`, as an RGBA layer."""
    x0, y0, x1, y1 = box
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    height = max(1, y1 - y0)

    for y in range(y0, y1):
        t = (y - y0) / height
        colour = tuple(int(round(top[i] + (bottom[i] - top[i]) * t)) for i in range(4))
        draw.line([(x0, y), (x1, y)], fill=colour)

    return layer


def horizontal_gradient(size, box, left, right):
    """The same, across. Used for anything cylindrical, where the shading runs sideways."""
    x0, y0, x1, y1 = box
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    width = max(1, x1 - x0)

    for x in range(x0, x1):
        t = (x - x0) / width
        colour = tuple(int(round(left[i] + (right[i] - left[i]) * t)) for i in range(4))
        draw.line([(x, y0), (x, y1)], fill=colour)

    return layer


def new():
    return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))


def rounded(image, box, radius, fill):
    ImageDraw.Draw(image).rounded_rectangle(s(*box), radius=int(radius * SCALE), fill=fill)


def paste_shaped(base, gradient, mask_shape):
    """Paste a gradient through a shape mask, so the gradient only fills the shape."""
    mask = Image.new("L", (SIZE, SIZE), 0)
    mask_shape(ImageDraw.Draw(mask))
    base.paste(gradient, (0, 0), mask)


# --------------------------------------------------------------------------------------
# whey: a tub with a red label band and a dumbbell on it
def whey():
    image = new()

    # lid
    rounded(image, (26, 14, 74, 26), 3, (44, 52, 62, 255))
    rounded(image, (28, 16, 72, 21), 2, (65, 76, 89, 255))

    # body, shaded across because it is a cylinder
    body = horizontal_gradient(
        (SIZE, SIZE), s(28, 26, 72, 86),
        (63, 74, 90, 255), (51, 60, 72, 255))
    paste_shaped(image, body,
                 lambda d: d.rounded_rectangle(s(28, 26, 72, 86), radius=int(5 * SCALE), fill=255))

    # label band
    ImageDraw.Draw(image).rectangle(s(28, 42, 72, 64), fill=(200, 84, 58, 255))

    # a dumbbell, so it reads as sport at 32px
    draw = ImageDraw.Draw(image)
    bar = (244, 239, 230, 255)
    draw.rectangle(s(44, 51, 56, 55), fill=bar)
    draw.rounded_rectangle(s(39, 47, 43, 59), radius=int(1.5 * SCALE), fill=bar)
    draw.rounded_rectangle(s(57, 47, 61, 59), radius=int(1.5 * SCALE), fill=bar)
    draw.rounded_rectangle(s(35, 49.5, 38, 56.5), radius=int(SCALE), fill=bar)
    draw.rounded_rectangle(s(62, 49.5, 65, 56.5), radius=int(SCALE), fill=bar)

    # highlight
    draw.rounded_rectangle(s(32, 28, 37, 84), radius=int(2.5 * SCALE), fill=(255, 255, 255, 26))
    return image


# --------------------------------------------------------------------------------------
# protein bar: a foil wrapper with the bar half out
def protein_bar():
    image = new()
    draw = ImageDraw.Draw(image)

    # foil, behind
    foil = horizontal_gradient((SIZE, SIZE), s(16, 40, 60, 60),
                               (201, 205, 212, 255), (174, 180, 189, 255))
    paste_shaped(image, foil, lambda d: d.rectangle(s(16, 40, 60, 60), fill=255))
    draw.polygon(s(16, 40, 8, 44, 16, 48), fill=(154, 161, 170, 255))
    draw.polygon(s(16, 56, 8, 60, 16, 64), fill=(154, 161, 170, 255))

    # the bar itself
    bar = vertical_gradient((SIZE, SIZE), s(46, 38, 88, 62),
                            (122, 74, 42, 255), (90, 53, 29, 255))
    paste_shaped(image, bar,
                 lambda d: d.rounded_rectangle(s(46, 38, 88, 62), radius=int(3 * SCALE), fill=255))

    # chocolate top
    draw.rounded_rectangle(s(46, 38, 88, 45), radius=int(3 * SCALE), fill=(78, 45, 24, 200))

    # oats, so it is not a plank
    for cx, cy, r in ((55, 51, 2), (63, 55, 1.6), (71, 49, 1.8), (79, 54, 1.5), (60, 47, 1.3)):
        draw.ellipse(s(cx - r, cy - r, cx + r, cy + r), fill=(216, 165, 106, 190))

    return image.rotate(18, resample=Image.BICUBIC, center=(SIZE // 2, SIZE // 2))


# --------------------------------------------------------------------------------------
# pre-workout: a shaker of something violently pink, with a bolt
def pre_workout():
    image = new()
    draw = ImageDraw.Draw(image)

    # flip cap
    draw.rounded_rectangle(s(37, 10, 63, 20), radius=int(3 * SCALE), fill=(27, 32, 38, 255))
    draw.rounded_rectangle(s(44, 6, 56, 11), radius=int(2 * SCALE), fill=(240, 65, 125, 255))

    # bottle
    body = horizontal_gradient((SIZE, SIZE), s(37, 20, 63, 86),
                               (61, 70, 82, 255), (32, 38, 44, 255))
    paste_shaped(image, body,
                 lambda d: d.rounded_rectangle(s(37, 20, 63, 86), radius=int(6 * SCALE), fill=255))

    # the liquid, two thirds up
    juice = horizontal_gradient((SIZE, SIZE), s(39, 44, 61, 84),
                                (194, 24, 91, 255), (160, 16, 72, 255))
    paste_shaped(image, juice,
                 lambda d: d.rounded_rectangle(s(39, 44, 61, 84), radius=int(5 * SCALE), fill=255))

    # measure lines
    for y in (34, 48, 62):
        draw.line(s(55, y, 61, y), fill=(255, 255, 255, 90), width=int(1.4 * SCALE))

    # lightning bolt
    draw.polygon(s(50, 50, 43, 62, 49, 62, 46, 72, 56, 58, 50, 58), fill=(255, 225, 77, 255))

    draw.rounded_rectangle(s(40, 22, 44, 82), radius=int(2 * SCALE), fill=(255, 255, 255, 30))
    return image


# --------------------------------------------------------------------------------------
# sports drink: a translucent bottle with a green drink and a waist
def sports_drink():
    image = new()
    draw = ImageDraw.Draw(image)

    # sports cap
    draw.rectangle(s(45, 8, 55, 14), fill=(232, 236, 239, 255))
    draw.rounded_rectangle(s(42, 14, 58, 22), radius=int(2 * SCALE), fill=(30, 143, 78, 255))

    # shoulders and body. The waist is drawn as two boxes rather than a curve: at 100px the
    # difference is invisible and a polygon with a bezier is not worth the code.
    plastic = (198, 232, 242, 190)
    draw.polygon(s(43, 22, 57, 22, 61, 32, 39, 32), fill=plastic)
    draw.rounded_rectangle(s(39, 32, 61, 50), radius=int(2 * SCALE), fill=plastic)
    draw.rectangle(s(43, 48, 57, 56), fill=plastic)
    draw.rounded_rectangle(s(39, 54, 61, 86), radius=int(5 * SCALE), fill=plastic)

    # the drink
    drink = horizontal_gradient((SIZE, SIZE), s(41, 40, 59, 84),
                                (30, 143, 78, 255), (23, 122, 65, 255))

    def drink_mask(d):
        d.rounded_rectangle(s(41, 40, 59, 50), radius=int(2 * SCALE), fill=255)
        d.rectangle(s(44, 48, 56, 56), fill=255)
        d.rounded_rectangle(s(41, 54, 59, 84), radius=int(4 * SCALE), fill=255)

    paste_shaped(image, drink, drink_mask)

    # label
    draw.rectangle(s(41, 62, 59, 74), fill=(244, 247, 248, 230))
    draw.rounded_rectangle(s(44, 66, 56, 68), radius=int(SCALE), fill=(23, 122, 65, 255))
    draw.rounded_rectangle(s(44, 70, 52, 72), radius=int(SCALE), fill=(23, 122, 65, 255))

    draw.rounded_rectangle(s(42, 34, 45, 86), radius=int(1.5 * SCALE), fill=(255, 255, 255, 90))
    return image


ICONS = {
    "whey": whey,
    "protein_bar": protein_bar,
    "pre_workout": pre_workout,
    "sports_drink": sports_drink,
}


def main():
    OUT.mkdir(exist_ok=True)
    written = []

    for name, build in ICONS.items():
        path = OUT / f"{name}.png"
        build().resize((100, 100), Image.LANCZOS).save(path, "PNG")
        written.append(path)
        print(f"  wrote {path.relative_to(ROOT)}")

    if len(sys.argv) > 1:
        target = Path(sys.argv[1])
        if not target.is_dir():
            print(f"\n{target} is not a directory; nothing copied")
            return 1

        print(f"\ncopying into {target}")
        for path in written:
            shutil.copy2(path, target / path.name)
            print(f"  {path.name}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
