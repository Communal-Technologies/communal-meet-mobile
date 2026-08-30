"""Meet's launcher icons, derived from the fleet's mark rather than a new one.

The member app and the collector app ship the same Communal mark on a white
ground, tinted purple and black respectively, and collector's pubspec says why:
they sit next to each other in the drawer and the tint is how you tell them
apart. Meet is the third icon in that drawer, so it inverts the ground instead
of adding a fourth tint — the same mark, knocked out in white on #742CE7. At
48dp an inverted ground is the only one of the three you can identify without
resolving the mark itself.

The mask comes out of the member app's own PNG, so the geometry and framing are
identical to the fleet's by construction rather than by eye.

    python3 tool/make_icons.py
"""

from PIL import Image

SRC_FULL = "../mobile/assets/images/launcher_icon.png"
SRC_ADAPTIVE = "../mobile/assets/images/launcher_icon_foreground.png"
PURPLE = (116, 44, 231)
WHITE = (255, 255, 255)



def coverage(path):
    """The mark's antialiased coverage, straight off the fleet's own alpha.

    Both fleet files are the mark on a transparent ground — the white you see in
    a viewer is the viewer. So the alpha channel *is* the mask, at the fleet's
    exact geometry, with no resampling and nothing inferred from the tint. The
    two files differ only in framing: launcher_icon.png is full-bleed, the
    foreground is inset to Android's adaptive safe zone.
    """
    return Image.open(path).convert("RGBA").split()[3]


def paint(mask, colour, ground):
    out = Image.new("RGBA", mask.size, ground)
    out.paste(Image.new("RGBA", mask.size, colour + (255,)), (0, 0), mask)
    return out


full = coverage(SRC_FULL)
adaptive = coverage(SRC_ADAPTIVE)

paint(full, WHITE, PURPLE + (255,)).save("assets/images/launcher_icon.png")
paint(adaptive, WHITE, (0, 0, 0, 0)).save("assets/images/launcher_icon_foreground.png")
paint(adaptive, PURPLE, (0, 0, 0, 0)).save("assets/images/mark_purple.png")
paint(adaptive, WHITE, (0, 0, 0, 0)).resize((96, 96), Image.LANCZOS).save(
    "assets/images/notification_icon.png"
)

# The splash sits on white (DESIGN.md §6.0), so it is the purple mark, cropped to
# the ink and re-padded — a splash logo framed for an adaptive icon's safe zone
# looks small on a blank screen for no reason.
purple = paint(adaptive, PURPLE, (0, 0, 0, 0))
box = purple.getbbox()
art = purple.crop(box)
side = max(art.size)
pad = round(side * 0.08)
canvas = Image.new("RGBA", (side + 2 * pad, side + 2 * pad), (0, 0, 0, 0))
canvas.paste(art, (pad + (side - art.width) // 2, pad + (side - art.height) // 2))
canvas.resize((512, 512), Image.LANCZOS).save("assets/images/splash_logo.png")

for name in (
    "launcher_icon.png",
    "launcher_icon_foreground.png",
    "mark_purple.png",
    "notification_icon.png",
    "splash_logo.png",
):
    im = Image.open("assets/images/" + name)
    print(f"{name:34} {im.size[0]}x{im.size[1]} {im.mode}")
