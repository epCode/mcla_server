# mcla_server

Server-side gameplay tweaks for [Mineclonia](https://codeberg.org/mineclonia/mineclonia),
for a server that does not use the Nether. Everything the Nether normally gates
behind itself is moved into the Overworld instead.

Drop it in your `mods/` folder and enable it for the world. Nothing here needs a
new world; existing worlds keep working, and newly generated chunks pick up the
new ores.

## What it changes

### Nether portals go to bedrock level instead

Light a nether portal the way you always have. Instead of the Nether it now
drops you into a chamber just above bedrock at the **same X and Z**, and the
portal down there brings you back up. Portals are matched to each other by
column within 16 nodes, so a return trip lands on the portal you came from
rather than scattering new ones around.

The arrival chamber is dug out and sealed for you. Bedrock level sits inside the
Overworld lava sea, so the walls are obsidian wherever they touch lava or water
and stone bricks elsewhere -- you can mine your way out into the caves without a
diamond pickaxe, but nothing floods in while you stand there.

Details:

* Destination terrain is generated before anything is built or teleported;
  players see Mineclonia's usual "loading terrain" screen while they wait.
* Protected areas are respected. If the spot below you is claimed, nearby sites
  are tried, and if they are all claimed the portal simply fizzles and puts you
  back.
* A portal at or below y=-108 counts as a "deep" portal and sends you up;
  anything above it sends you down. Configurable.
* Mobs and minecarts travel through portals exactly as they did before. Dropped
  items still do not, matching vanilla Mineclonia.
* The cooloff after arriving lasts as long as you stand in the portal rather
  than expiring on a timer, so you never bounce straight back.
* `/mcla_portals [deep | surface]` lists the portals the mod knows about
  (requires the `debug` privilege).

The Nether itself is untouched and still reachable by other means (`/teleport`,
for instance) -- portals just no longer go there.

### Quartz in the Overworld

Quartz ore forms veins deep underground, with its own Overworld textures rather
than netherrack blocks embedded in stone, plus a deepslate variant for the lower
band. It drops, smelts, silk-touches and enchants exactly like nether quartz
ore.

### Ancient debris in the Overworld

Ancient debris generates level with the deep dark, in a rare band, and never
exposed to air -- you have to dig for it, the same as in the Nether.

### Netherite without a bastion

Debris smelts to scrap and four scrap plus four gold ingots already make an
ingot, so the only missing piece was the netherite upgrade template, which
vanilla only puts in bastion remnant chests. Two recipes are added, both with
vanilla's seven-diamond cost:

| Recipe | Ingredients | Output |
| --- | --- | --- |
| First template | 7 diamonds + 1 ancient debris + 1 deepslate | 1 template |
| Duplication | 7 diamonds + 1 template + 1 deepslate | 2 templates |

(Deepslate stands in for netherrack. On installs without `mcl_deepslate`,
obsidian is used instead.)

### Blaze spawners in dungeons

Blazes only ever spawn from nether fortress spawners in vanilla, which would
leave blaze rods -- and therefore brewing -- unreachable. Dungeon spawners now
have a **1 in 8** chance of being a blaze spawner. The other seven eighths keep
vanilla's zombie / spider / skeleton split, making a blaze spawner roughly twice
as rare as any single one of them.

Only dungeon spawners are affected. Mineshaft cave spiders, stronghold
silverfish, woodland mansion spiders and trial chamber spawners are all left
alone.

## Settings

Every part can be turned off on its own, and the generation rates and the blaze
chance are tunable. See `settingtypes.txt`, or look under
*Settings → All settings → Mods → mcla_server*.

## Map generators

Mineclonia ships two map generators and they do not share ore registration, so
both are supported: `core.register_ore` on the builtin mapgens (v7 and friends)
and the `mcl_levelgen` feature pipeline on singlenode worlds. Which one is in
use is printed to the log at startup.

## Textures

`tools/make_quartz_textures.py` regenerates the quartz ore textures from
Mineclonia's own art, by lifting the crystals off the nether quartz ore texture
and recompositing them onto stone and deepslate:

    tools/make_quartz_textures.py /path/to/games/mineclonia

## License

MIT, see `LICENSE`. Textures are derived from Mineclonia's own artwork and
remain under its license.
