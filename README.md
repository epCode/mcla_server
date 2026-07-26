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

### How much of it there is

Counted over a generated 384x384 by 91-deep slab of world, on both map
generators, alongside Mineclonia's own ores for scale:

| | builtin mapgen (v7) | singlenode (mcl_levelgen) |
| --- | --- | --- |
| Quartz ore | 1 per 627 nodes | 1 per 1455 |
| Gold ore (for comparison) | 1 per 583 | 1 per 1209 |
| Diamond ore (for comparison) | 1 per 888 | 1 per 1230 |
| Ancient debris | 1 per 18.9k (1.2 per chunk) | 1 per 24.5k (0.95 per chunk) |

So quartz lands at about gold's abundance, and ancient debris at roughly one
block per chunk in its band -- about what a Nether trip gives you in vanilla,
and rare enough that a full netherite kit is still a project.

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

## Chat colours

Public chat messages can be coloured with plain uppercase words. The words are
**case sensitive** and are eaten from the message, so nothing extra shows up:

    Hey BLUEman!                 "man" is blue, "!" is not
    REDBLUE ON please bro OFF    "please bro" alternates red and blue
    BLUEREDFLASHINGNOW!          "NOW" cycles four shades

A colour on its own paints the word after it, with or without a space in
between, and punctuation is left out. Follow the colour with `ON` or `START`
and it paints everything until `OFF` or `STOP`, or the end of the message.

Colours written back to back build a cycle that is laid across the text one
character at a time, so `REDBLUE David` alternates red and blue per letter.

`FLASH` marks the colour **before** it and `FLASHING` marks every colour in the
run, so `REDBLUE FLASHING` flashes both without spelling out `FLASH` twice. A
flashing colour alternates between its own shade and a brighter one each time
the cycle comes back around to it — `RED FLASH ON` shimmers between `#ff4444`
and `#ff7777` letter by letter. Luanti chat lines cannot animate (they are
immutable once sent), so a flash is a shimmer across the characters rather than
over time.

The colours are `RED` `GREEN` `BLUE` `YELLOW` `CYAN` `MAGENTA` `WHITE` `BLACK`
`ORANGE` `PURPLE` `PINK` `GRAY` (`GREY` works too).

`/mcla_chat <message>` previews a message to yourself without saying it, and
`/mcla_chat` on its own lists the keywords. Neither needs a privilege.

### Staying out of the way

Keywords are ignored where they would swallow ordinary words:

* `ON`, `START`, `FLASH` and `FLASHING` only count directly after a colour, and
  `OFF` / `STOP` only when something is actually being painted. "TURN THE LIGHT
  OFF" and "COME ON everybody" come through untouched.
* A keyword is never read out of the tail of a word typed in capitals, so
  "SCARED" keeps its `RED`. It is still read after a lowercase letter, which is
  what lets `broOFF` close a block.
* A backslash escapes one keyword: `\BLUE` is the word BLUE, and `\\` is a
  backslash.

A colour at the very end of a message has no word to paint and is simply eaten;
write `\RED` if you meant to say it.

### Adding your own

`mcla_server.chat` is an API, so other mods can extend the grammar:

```lua
mcla_server.chat.register_color("LIME", "#aaff44")
mcla_server.chat.register_color("GOLD", { color = "#ffcc44", flash = "#ffee99" })
```

`flash` defaults to a brighter version of `color`, so one hex is usually enough.
Anything that is not a colour is a rule:

```lua
mcla_server.chat.register_rule({
    name = "rainbow",
    words = { "RAINBOW" },
    on_token = function(state)
        for _, name in ipairs({ "RED", "ORANGE", "YELLOW", "GREEN", "BLUE", "PURPLE" }) do
            local color = mcla_server.chat.colors[name]
            state.group.colors[#state.group.colors + 1] =
                { color = color.color, alt = color.flash }
        end
    end,
})
```

`state.group` is the run of keywords being read, `state.active` and
`state.pending` are the cycles painting the rest of the message and the next
word. An optional `applies = function(state, word)` decides whether the word
counts as a keyword at all — that is how `OFF` stays a normal word when nothing
is being painted. See the header of `chat.lua` for the rest.

Decoration happens inside `core.format_chat_message`, wrapping whatever was
already there. That keeps the shout privilege check, the server's chat logging
and other mods' `on_chat_message` handlers working, and leaves commands and
`/me` alone.

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

## Verified behaviour

Everything above was exercised on a headless server on both map generators
before release: a full portal round trip (surface to bedrock and back to the
portal you came from), the arrival chamber holding back the lava sea, ore
counts over a generated slab of world, and 400 dungeon spawners per code path
to confirm the blaze rate and that other structures' spawners are untouched.

## License

MIT, see `LICENSE`. Textures are derived from Mineclonia's own artwork and
remain under its license.
