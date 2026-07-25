--[[
mcla_server -- server-side gameplay tweaks for Mineclonia.

The server this mod is written for does not use the Nether, so everything the
Nether normally gates behind itself is moved into the Overworld instead:

  * Nether portals become "deep portals": they drop you into a sealed chamber
    just above bedrock and bring you back up again (portals.lua)
  * Nether quartz and ancient debris generate in the Overworld (ores.lua)
  * The netherite upgrade template becomes obtainable without a bastion
    (netherite.lua)
  * Dungeon mob spawners have a small chance of being blaze spawners, so blaze
    rods (and therefore brewing) stay reachable (spawners.lua)

Each part can be switched off individually, see settingtypes.txt.
]]

mcla_server = {}

local modpath = core.get_modpath(core.get_current_modname())

mcla_server.S = core.get_translator("mcla_server")
mcla_server.storage = core.get_mod_storage()

--- Reads a boolean setting, defaulting to `default` when unset.
function mcla_server.setting_bool(name, default)
	local value = core.settings:get_bool("mcla_server_" .. name)
	if value == nil then
		return default
	end
	return value
end

--- Reads a numeric setting, falling back to `default` when unset or unparsable.
function mcla_server.setting_number(name, default)
	return tonumber(core.settings:get("mcla_server_" .. name)) or default
end

if mcla_server.setting_bool("bedrock_portals", true) then
	dofile(modpath .. "/portals.lua")
end
