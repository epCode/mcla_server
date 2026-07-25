--[[
Netherite without the Nether.

With ancient debris generating in the Overworld the netherite chain is almost
complete on its own: debris smelts into scrap in any furnace, and four scrap
plus four gold ingots already make an ingot. The one remaining Nether
dependency is the netherite upgrade template, which vanilla only ever hands out
in bastion remnant chests, and whose duplication recipe calls for netherrack.

So: one costly recipe to make the first template, and an Overworld version of
the vanilla duplication recipe. The original netherrack duplication recipe is
left registered -- it simply never comes up.
]]

local TEMPLATE = "mcl_nether:netherite_upgrade_template"

if not core.registered_items[TEMPLATE] then
	core.log("warning", "[mcla_server] " .. TEMPLATE .. " does not exist; "
		.. "skipping the Overworld netherite recipes")
	return
end

-- Vanilla duplicates a template with seven diamonds and one netherrack. The
-- Overworld stand-in is the deep stone ancient debris is found in, so the cost
-- stays where vanilla put it.
local FILLER = core.registered_items["mcl_deepslate:deepslate"]
	and "mcl_deepslate:deepslate" or "mcl_core:obsidian"

-- The first template. Same shape and diamond cost as duplication, with a lump
-- of ancient debris standing in for the template you do not have yet -- which
-- means finding debris is the only prerequisite, exactly as finding a bastion
-- used to be.
core.register_craft({
	output = TEMPLATE,
	recipe = {
		{ "mcl_core:diamond", "mcl_nether:ancient_debris", "mcl_core:diamond" },
		{ "mcl_core:diamond", FILLER, "mcl_core:diamond" },
		{ "mcl_core:diamond", "mcl_core:diamond", "mcl_core:diamond" },
	},
})

-- Duplication, with the same seven-diamond cost as vanilla.
core.register_craft({
	output = TEMPLATE .. " 2",
	recipe = {
		{ "mcl_core:diamond", TEMPLATE, "mcl_core:diamond" },
		{ "mcl_core:diamond", FILLER, "mcl_core:diamond" },
		{ "mcl_core:diamond", "mcl_core:diamond", "mcl_core:diamond" },
	},
})
