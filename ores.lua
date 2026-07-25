--[[
Overworld quartz and ancient debris.

Both are normally Nether-only. Quartz gets its own Overworld ore nodes so the
veins do not look like netherrack embedded in stone; ancient debris keeps its
own distinctive block and simply generates down in the deep-dark band.

Mineclonia ships two map generators. Worlds on the builtin mapgens (v7 and
friends) use core.register_ore; singlenode worlds use mcl_levelgen, which has
its own feature pipeline and ignores registered ores entirely. Both are set up
here, and the levelgen half lives in lg_ores.lua because it has to run inside
the map generation environment.
]]

local S = mcla_server.S
local modpath = core.get_modpath(core.get_current_modname())

local generate_quartz = mcla_server.setting_bool("overworld_quartz", true)
local generate_debris = mcla_server.setting_bool("overworld_ancient_debris", true)

------------------------------------------------------------------------------
-- Overworld quartz ore
------------------------------------------------------------------------------

local quartz_ore_definition = {
	description = S("Quartz Ore"),
	_doc_items_longdesc = S("Quartz ore contains quartz crystals. Unlike in vanilla it forms "
		.. "veins deep underground in the Overworld."),
	tiles = { "mcla_server_quartz_ore.png" },
	groups = {
		pickaxey = 1, building_block = 1, material_stone = 1, xp = 3,
		blast_furnace_smeltable = 1,
	},
	drop = "mcl_nether:quartz",
	sounds = mcl_sounds.node_sound_stone_defaults(),
	_mcl_hardness = 3,
	_mcl_silk_touch_drop = true,
	_mcl_fortune_drop = mcl_core.fortune_drop_ore,
	_mcl_cooking_output = "mcl_nether:quartz",
}

core.register_node("mcla_server:quartz_ore", quartz_ore_definition)

-- Deepslate and tuff get their own variant, the same way Mineclonia's own ores
-- do, so a vein does not switch to stone-coloured blocks halfway down.
local have_deepslate = core.get_modpath("mcl_deepslate") ~= nil
if have_deepslate then
	local deepslate_quartz = table.copy(quartz_ore_definition)
	deepslate_quartz.description = S("Deepslate Quartz Ore")
	deepslate_quartz._doc_items_longdesc =
		S("Deepslate quartz ore is a variant of quartz ore that generates in deepslate and tuff.")
	deepslate_quartz.tiles = { "mcla_server_deepslate_quartz_ore.png" }
	core.register_node("mcla_server:deepslate_quartz_ore", deepslate_quartz)
end

------------------------------------------------------------------------------
-- Ore generation
------------------------------------------------------------------------------

if not core.settings:get_bool("mcl_generate_ores", true) then
	return
end

if core.global_exists("mcl_levelgen") and mcl_levelgen.levelgen_enabled then
	-- Singlenode worlds: the level generator owns ore placement.
	core.log("action", "[mcla_server] Overworld ores: using the mcl_levelgen feature pipeline")
	mcl_levelgen.register_levelgen_script(modpath .. "/lg_ores.lua")
	return
end

core.log("action", "[mcla_server] Overworld ores: using core.register_ore")

-- Builtin mapgens. Heights are expressed relative to the bottom of the world
-- so that they land in the right place whatever mcl_vars decides the Overworld
-- floor is.
local BOTTOM = mcl_vars.mg_overworld_min

local STONE = { "mcl_core:stone", "mcl_core:diorite", "mcl_core:andesite", "mcl_core:granite" }
local DEEPSLATE = { "mcl_deepslate:deepslate", "mcl_deepslate:tuff" }

local quartz_scarcity = mcla_server.setting_number("quartz_scarcity", 3400)
-- Tuned by counting a 384x384 slab of generated v7 world: this puts roughly
-- one debris block per chunk in the band, which is about what the levelgen
-- side produces and about what the Nether gives you in vanilla.
local debris_scarcity = mcla_server.setting_number("ancient_debris_scarcity", 9000)

if generate_quartz then
	local bands = {
		-- wherein, ore node, scarcity, cluster size, blob size
		{ STONE, "mcla_server:quartz_ore", quartz_scarcity, 4, 3 },
		{ STONE, "mcla_server:quartz_ore", quartz_scarcity * 2, 7, 4 },
	}
	if have_deepslate then
		bands[#bands + 1] =
			{ DEEPSLATE, "mcla_server:deepslate_quartz_ore", quartz_scarcity, 4, 3 }
		bands[#bands + 1] =
			{ DEEPSLATE, "mcla_server:deepslate_quartz_ore", quartz_scarcity * 2, 7, 4 }
	end

	for _, band in ipairs(bands) do
		core.register_ore({
			ore_type = "scatter",
			wherein = band[1],
			ore = band[2],
			clust_scarcity = band[3],
			clust_num_ores = band[4],
			clust_size = band[5],
			y_min = BOTTOM + 5,
			y_max = BOTTOM + 80,
		})
	end
end

if generate_debris then
	local wherein = table.copy(STONE)
	if have_deepslate then
		for _, name in ipairs(DEEPSLATE) do
			wherein[#wherein + 1] = name
		end
	end

	-- Main band, level with the deep dark.
	core.register_ore({
		ore_type = "scatter",
		wherein = wherein,
		ore = "mcl_nether:ancient_debris",
		clust_scarcity = debris_scarcity,
		clust_num_ores = 2,
		clust_size = 3,
		y_min = BOTTOM + 8,
		y_max = BOTTOM + 28,
	})

	-- A thinner scattering above it, so digging out of the very bottom is not
	-- the only way to find any.
	core.register_ore({
		ore_type = "scatter",
		wherein = wherein,
		ore = "mcl_nether:ancient_debris",
		clust_scarcity = math.floor(debris_scarcity * 1.7),
		clust_num_ores = 1,
		clust_size = 2,
		y_min = BOTTOM + 28,
		y_max = BOTTOM + 44,
	})
end
