#!/usr/bin/env python3
"""Generate the Overworld quartz ore textures.

Mineclonia's nether quartz ore texture is the netherrack texture with the
quartz crystals painted on top, so the crystals can be lifted back off by
diffing the two and re-composited onto Overworld stone instead. Run from a
checkout of the Mineclonia game:

    tools/make_quartz_textures.py /path/to/games/mineclonia
"""

import sys
import os
from PIL import Image

# (backdrop, output name, crystal contrast). Stone is nearly the same
# brightness as the crystals, so they get pushed apart a little there; on
# deepslate they already stand out on their own.
VARIANTS = [
    ("mods/ITEMS/mcl_core/textures/default_stone.png",
     "mcla_server_quartz_ore.png", 1.6),
    ("mods/ITEMS/mcl_deepslate/textures/mcl_deepslate.png",
     "mcla_server_deepslate_quartz_ore.png", 1.0),
]

ORE = "mods/ITEMS/mcl_nether/textures/mcl_nether_quartz_ore.png"
BACKDROP = "mods/ITEMS/mcl_nether/textures/mcl_nether_netherrack.png"


def main(game_path, out_dir):
    ore = Image.open(os.path.join(game_path, ORE)).convert("RGBA")
    backdrop = Image.open(os.path.join(game_path, BACKDROP)).convert("RGBA")
    if ore.size != backdrop.size:
        raise SystemExit("quartz ore and netherrack textures differ in size")

    # A differing pixel is only a crystal if it is also near-greyscale. The
    # diff otherwise picks up the netherrack shading that got shuffled around
    # to make room for the crystals, which would drag red blotches along.
    def is_crystal(pixel):
        r, g, b, a = pixel
        return a > 0 and max(r, g, b) - min(r, g, b) < 40

    crystals = [
        o if o != b and is_crystal(o) else (0, 0, 0, 0)
        for o, b in zip(ore.getdata(), backdrop.getdata())
    ]
    overlay = Image.new("RGBA", ore.size)
    overlay.putdata(crystals)

    for source, name, contrast in VARIANTS:
        base = Image.open(os.path.join(game_path, source)).convert("RGBA")
        if base.size != overlay.size:
            base = base.resize(overlay.size, Image.NEAREST)

        layer = overlay
        if contrast != 1.0:
            def stretch(value):
                return max(0, min(255, round(160 + (value - 160) * contrast)))

            layer = Image.new("RGBA", overlay.size)
            layer.putdata([
                (stretch(r), stretch(g), stretch(b), a) if a else (0, 0, 0, 0)
                for r, g, b, a in overlay.getdata()
            ])

        result = base.copy()
        result.alpha_composite(layer)
        result.save(os.path.join(out_dir, name))
        print("wrote", name)


if __name__ == "__main__":
    game = sys.argv[1] if len(sys.argv) > 1 else "."
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "textures")
    main(game, out)
