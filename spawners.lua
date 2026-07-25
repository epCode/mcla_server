--[[
Blaze dungeon spawners.

Blazes normally only spawn from nether fortress spawners, which takes blaze
rods -- and therefore brewing -- off the table on a server with no Nether. So
dungeon spawners get a chance of being blaze spawners instead.

Mineclonia picks the dungeon spawner mob in two different places: mcl_dungeons
generates dungeons itself on the builtin mapgens, while singlenode worlds get
them from a level generation script that reports the chosen mob back through a
notification handler. Both are covered here, and care is taken not to touch mob
spawners that belong to anything else -- mineshaft cave spiders, stronghold
silverfish, woodland mansion spiders and trial chamber spawners all stay as
they are.
]]

local DUNGEON_MOBS = {
	["mobs_mc:zombie"] = true,
	["mobs_mc:spider"] = true,
	["mobs_mc:skeleton"] = true,
}

local BLAZE = "mobs_mc:blaze"

-- Dungeons are the only thing built out of these.
local DUNGEON_FLOOR = {
	["mcl_core:cobble"] = true,
	["mcl_core:mossycobble"] = true,
}

-- One in this many dungeon spawners is a blaze spawner.
local BLAZE_CHANCE = math.max(1, math.floor(mcla_server.setting_number("blaze_spawner_chance", 8)))

if not core.registered_entities[BLAZE] then
	core.log("warning", "[mcla_server] " .. BLAZE .. " does not exist; "
		.. "skipping blaze dungeon spawners")
	return
end

local map_seed = tonumber(core.get_mapgen_setting("seed")) or 0

-- Decided from the spawner's position and the map seed rather than from
-- math.random, so that a dungeon which gets generated twice comes out the same
-- way both times.
local function rolls_blaze(pos)
	local rng = PcgRandom(core.hash_node_position(vector.round(pos)), map_seed)
	return rng:next(1, BLAZE_CHANCE) == 1
end

-- Set while a wrapped handler is choosing the mob itself, so the
-- setup_spawner wrapper below knows to keep its hands off.
local decided_elsewhere = false

local function with_guard(fn)
	decided_elsewhere = true
	local ok, err = pcall(fn)
	decided_elsewhere = false
	if not ok then
		error(err, 0)
	end
end

------------------------------------------------------------------------------
-- Singlenode worlds: mcl_dungeons reports the mob it picked through
-- mcl_levelgen. Rewriting it here is exact -- no other structure reports under
-- this name.
------------------------------------------------------------------------------

local handlers = core.global_exists("mcl_levelgen")
	and mcl_levelgen.registered_notification_handlers

if handlers and handlers["mcl_dungeons:dungeon_meta"] then
	local previous = handlers["mcl_dungeons:dungeon_meta"]
	mcl_levelgen.register_notification_handler("mcl_dungeons:dungeon_meta",
		function(name, data)
			if data.position and DUNGEON_MOBS[data.mob] and rolls_blaze(data.position) then
				data.mob = BLAZE
			end
			with_guard(function()
				previous(name, data)
			end)
		end)
end

-- Mineshafts and woodland mansions share a handler and place spawners of their
-- own. Guard it so the fallback below cannot mistake one for a dungeon.
if handlers and handlers["mcl_levelgen:mob_spawner_constructor"] then
	local previous = handlers["mcl_levelgen:mob_spawner_constructor"]
	mcl_levelgen.register_notification_handler("mcl_levelgen:mob_spawner_constructor",
		function(name, data)
			with_guard(function()
				previous(name, data)
			end)
		end)
end

------------------------------------------------------------------------------
-- Builtin mapgens: mcl_dungeons calls setup_spawner directly, with the mob
-- chosen in a local table there is no hook into. Catch it at the spawner
-- instead, and only when the spawner is standing on a dungeon floor, so that
-- hand-placed and other structures' spawners are left alone.
------------------------------------------------------------------------------

local setup_spawner = mcl_mobspawners.setup_spawner

function mcl_mobspawners.setup_spawner(pos, mob, min_light, max_light,
				       max_mobs, player_distance, spawn_delay)
	if not decided_elsewhere and DUNGEON_MOBS[mob] then
		local below = core.get_node(vector.offset(pos, 0, -1, 0)).name
		if DUNGEON_FLOOR[below] and rolls_blaze(pos) then
			mob = BLAZE
		end
	end
	return setup_spawner(pos, mob, min_light, max_light, max_mobs,
			     player_distance, spawn_delay)
end

core.log("action", string.format(
	"[mcla_server] blaze dungeon spawners active: 1 in %d", BLAZE_CHANCE))
