--[[
Overworld quartz and ancient debris for mcl_levelgen (singlenode worlds).

This file runs inside the map generation environment, not the server
environment, so it has mcl_levelgen but no players, entities or mod storage.
Heights here are level coordinates -- the same numbers Minecraft uses, with the
world floor at -64 -- rather than Luanti node coordinates.
]]

local O = mcl_levelgen.construct_ore_substitution_list
local uniform_height = mcl_levelgen.uniform_height

-- Any biome that generates gold is an ordinary stone Overworld biome, which is
-- exactly the set that should get quartz and ancient debris too. Finding the
-- stage this way avoids hard-coding an index that mcl_levelgen is free to
-- renumber.
local ORE_STAGE_MARKER = "mcl_levelgen:ore_gold"

local function find_ore_stage()
	local stage, biomes = nil, {}
	for name, def in pairs(mcl_levelgen.registered_biomes) do
		for step, features in ipairs(def.features or {}) do
			if table.indexof(features, ORE_STAGE_MARKER) ~= -1 then
				stage = stage or step
				if step == stage then
					biomes[#biomes + 1] = name
				end
				break
			end
		end
	end
	return stage, biomes
end

local stage, biomes = find_ore_stage()
if not stage or #biomes == 0 then
	core.log("warning", "[mcla_server] could not locate the Overworld ore "
		.. "generation stage; Overworld quartz and ancient debris are disabled")
	return
end

local function setting_bool(name, default)
	local value = core.settings:get_bool("mcla_server_" .. name)
	if value == nil then
		return default
	end
	return value
end

local function setting_number(name, default)
	return tonumber(core.settings:get("mcla_server_" .. name)) or default
end

local function count_of(n)
	return function()
		return n
	end
end

-- Only substitute into node types that actually exist.
local function substitutions(pairs_list)
	local list = {}
	for _, entry in ipairs(pairs_list) do
		if core.registered_nodes[entry.replacement] then
			list[#list + 1] = entry
		end
	end
	return O(list)
end

local function place(id, configured, modifiers)
	mcl_levelgen.register_placed_feature(id, {
		configured_feature = configured,
		placement_modifiers = modifiers,
	})
	mcl_levelgen.generate_feature(id, ORE_STAGE_MARKER, biomes, stage)
end

------------------------------------------------------------------------------
-- Quartz
------------------------------------------------------------------------------

if setting_bool("overworld_quartz", true) then
	local veins = setting_number("quartz_veins_per_chunk", 3)

	mcl_levelgen.register_configured_feature("mcla_server:ore_quartz", {
		feature = "mcl_levelgen:ore",
		discard_chance_on_air_exposure = 0.0,
		size = 9,
		substitutions = substitutions({
			{
				target = "group:stone_ore_target",
				replacement = "mcla_server:quartz_ore",
			},
			{
				target = "group:deepslate_ore_target",
				replacement = "mcla_server:deepslate_quartz_ore",
			},
		}),
	})

	-- Occasional fat veins, worth tunnelling towards.
	mcl_levelgen.register_configured_feature("mcla_server:ore_quartz_large", {
		feature = "mcl_levelgen:ore",
		discard_chance_on_air_exposure = 0.3,
		size = 16,
		substitutions = substitutions({
			{
				target = "group:stone_ore_target",
				replacement = "mcla_server:quartz_ore",
			},
			{
				target = "group:deepslate_ore_target",
				replacement = "mcla_server:deepslate_quartz_ore",
			},
		}),
	})

	place("mcla_server:ore_quartz", "mcla_server:ore_quartz", {
		mcl_levelgen.build_count(count_of(veins)),
		mcl_levelgen.build_in_square(),
		mcl_levelgen.build_height_range(uniform_height(-60, 16)),
		mcl_levelgen.build_in_biome(),
	})

	place("mcla_server:ore_quartz_large", "mcla_server:ore_quartz_large", {
		mcl_levelgen.build_rarity_filter(6),
		mcl_levelgen.build_count(count_of(1)),
		mcl_levelgen.build_in_square(),
		mcl_levelgen.build_height_range(uniform_height(-60, -16)),
		mcl_levelgen.build_in_biome(),
	})
end

------------------------------------------------------------------------------
-- Ancient debris
------------------------------------------------------------------------------

if setting_bool("overworld_ancient_debris", true) then
	local rarity = math.max(1, setting_number("ancient_debris_rarity", 4))

	-- Never exposed to air, exactly as in the Nether: it has to be dug for.
	mcl_levelgen.register_configured_feature("mcla_server:ore_ancient_debris", {
		feature = "mcl_levelgen:ore",
		discard_chance_on_air_exposure = 1.0,
		size = 3,
		substitutions = substitutions({
			{
				target = "group:stone_ore_target",
				replacement = "mcl_nether:ancient_debris",
			},
			{
				target = "group:deepslate_ore_target",
				replacement = "mcl_nether:ancient_debris",
			},
		}),
	})

	mcl_levelgen.register_configured_feature("mcla_server:ore_ancient_debris_small", {
		feature = "mcl_levelgen:ore",
		discard_chance_on_air_exposure = 1.0,
		size = 2,
		substitutions = substitutions({
			{
				target = "group:stone_ore_target",
				replacement = "mcl_nether:ancient_debris",
			},
			{
				target = "group:deepslate_ore_target",
				replacement = "mcl_nether:ancient_debris",
			},
		}),
	})

	place("mcla_server:ore_ancient_debris", "mcla_server:ore_ancient_debris", {
		mcl_levelgen.build_rarity_filter(rarity),
		mcl_levelgen.build_count(count_of(1)),
		mcl_levelgen.build_in_square(),
		mcl_levelgen.build_height_range(uniform_height(-59, -40)),
		mcl_levelgen.build_in_biome(),
	})

	place("mcla_server:ore_ancient_debris_small", "mcla_server:ore_ancient_debris_small", {
		mcl_levelgen.build_rarity_filter(rarity * 2),
		mcl_levelgen.build_count(count_of(1)),
		mcl_levelgen.build_in_square(),
		mcl_levelgen.build_height_range(uniform_height(-40, -24)),
		mcl_levelgen.build_in_biome(),
	})
end
