--[[
Bedrock portals.

The Nether is unused on this server, so `mcl_portals:portal` is repurposed: a
portal lit near the surface links to a matching portal in a sealed chamber just
above bedrock at the *same* X/Z, and the portal down there links back up again.
Everything else about nether portals (lighting them with flint and steel,
obsidian frames, portals breaking when their frame is broken) is untouched --
this file only replaces where the portal sends you.

mcl_portals' own destination logic lives entirely in local functions behind
`_on_object_in`, so overriding that one field takes it out of the picture
completely; none of its nether linking code can run any more.
]]

local S = mcla_server.S
local storage = mcla_server.storage

-- Optional: supplies the "loading terrain" screen while a destination chunk is
-- generated. Absent on very old Mineclonia versions, in which case players
-- simply wait in place.
local biome_dispatch = core.global_exists("mcl_biome_dispatch")
	and mcl_biome_dispatch or nil

-- Present only on singlenode worlds, where the level generator finishes a
-- chunk well after core.emerge_area says it is done.
local levelgen_generate_area = core.global_exists("mcl_levelgen")
	and mcl_levelgen.levelgen_enabled and mcl_levelgen.generate_area or nil

------------------------------------------------------------------------------
-- Tunables
------------------------------------------------------------------------------

-- Seconds a player must stand in a portal before it fires.
local TELEPORT_DELAY = 3
-- Seconds after stepping *out* of a portal before it may fire again. The
-- cooloff is also held for as long as the object stays inside a portal, which
-- is what stops you from bouncing back and forth on arrival.
local TELEPORT_COOLOFF = 1
-- An existing portal this far (Chebyshev, horizontally) from the destination
-- column is reused instead of building a new one.
local LINK_RADIUS = 16
-- Safety valve for the flood fill that finds the nodes of a portal.
local MAX_PORTAL_NODES = 256

local BEDROCK_TOP = mcl_vars.mg_bedrock_overworld_max
-- Solid floor of the arrival chamber, the first layer above bedrock.
local DEEP_FLOOR_Y = BEDROCK_TOP + 1
-- Where the lowest portal node sits, i.e. where you land.
local DEEP_BASE_Y = DEEP_FLOOR_Y + 1
local CHAMBER_RADIUS = 3
local CHAMBER_HEIGHT = 6

-- A portal at or below this height is a "deep" portal and sends you back up;
-- anything above it sends you down.
local DEEP_THRESHOLD = mcla_server.setting_number("deep_portal_threshold",
	BEDROCK_TOP + 16)

-- Vertical band searched when a return portal has to be built from scratch.
local SURFACE_MIN = mcl_vars.mg_overworld_min + 48
local SURFACE_MAX = mcl_vars.mg_overworld_max_official
-- Horizontal radius of that search. Kept well inside LINK_RADIUS so that the
-- portal we build is guaranteed to be found again by the reverse trip.
local SURFACE_SEARCH_RADIUS = 8

local MAP_LIMIT = (mcl_vars.mapgen_limit or 31000) - 32

-- Node groups a portal may be built on top of, same set mcl_portals uses.
local GROUND_GROUPS = { "group:building_block", "group:dig_by_water", "group:liquid" }

-- Offsets tried, in order, when the ideal chamber site turns out to be
-- protected.
local CHAMBER_OFFSETS = {
	{ 0, 0 }, { 8, 0 }, { -8, 0 }, { 0, 8 }, { 0, -8 },
	{ 8, 8 }, { -8, -8 }, { 8, -8 }, { -8, 8 },
	{ 15, 0 }, { -15, 0 }, { 0, 15 }, { 0, -15 },
}

------------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------------

local function chebyshev(a, b)
	return math.max(math.abs(a.x - b.x), math.abs(a.z - b.z))
end

local function clamp_to_map(n)
	return math.max(-MAP_LIMIT, math.min(MAP_LIMIT, n))
end

-- Rotate a portal-local offset by 90 degrees for odd param2, exactly as
-- mcl_portals does, so portals we build line up with hand-built ones.
local function orient(v, param2)
	if param2 % 2 == 1 then
		return vector.new(v.z, v.y, v.x)
	end
	return v
end

local function is_liquid(name)
	return core.get_item_group(name, "liquid") ~= 0
end

local function is_valid_object(obj)
	if not obj or not obj:is_valid() then
		return false
	end
	return obj:is_player() or obj:get_luaentity() ~= nil
end

------------------------------------------------------------------------------
-- Locating portals in the world
------------------------------------------------------------------------------

-- All portal nodes connected to `pos`, or nil if `pos` is not a portal node.
local function connected_portal_nodes(pos)
	local node = core.get_node(pos)
	if node.name ~= "mcl_portals:portal" then
		return nil
	end

	local param2 = node.param2
	local nodes = { vector.copy(pos) }
	local seen = { [core.hash_node_position(pos)] = true }

	local function visit(p)
		local hash = core.hash_node_position(p)
		if seen[hash] then
			return
		end
		local n = core.get_node(p)
		if n.name == "mcl_portals:portal" and n.param2 == param2 then
			seen[hash] = true
			nodes[#nodes + 1] = p
		end
	end

	local i = 1
	while i <= #nodes and #nodes < MAX_PORTAL_NODES do
		local p = nodes[i]
		-- A portal is flat, so only spread along its own plane.
		if param2 % 2 == 0 then
			visit(vector.offset(p, -1, 0, 0))
			visit(vector.offset(p, 1, 0, 0))
		else
			visit(vector.offset(p, 0, 0, -1))
			visit(vector.offset(p, 0, 0, 1))
		end
		visit(vector.offset(p, 0, -1, 0))
		visit(vector.offset(p, 0, 1, 0))
		i = i + 1
	end

	return nodes, param2
end

-- The single node of a portal used as its identity and as the arrival spot.
local function portal_center(nodes)
	local center = vector.zero()
	for _, p in ipairs(nodes) do
		center = center + p
	end
	center = center:divide(#nodes):round()

	-- Drop to the bottom row so players always arrive standing on the frame.
	while core.get_node(vector.offset(center, 0, -1, 0)).name == "mcl_portals:portal" do
		center = vector.offset(center, 0, -1, 0)
	end
	return center
end

local function cache_center(nodes, center)
	local serialized = core.serialize(center)
	for _, p in ipairs(nodes) do
		core.get_meta(p):set_string("mcla_portal", serialized)
	end
end

-- Returns (center, node) for the portal containing `pos`, or nil.
local function get_portal(pos)
	local node = core.get_node(pos)
	if node.name ~= "mcl_portals:portal" then
		return nil
	end

	local cached = core.deserialize(core.get_meta(pos):get_string("mcla_portal"))
	if cached then
		local center = vector.new(cached.x, cached.y, cached.z)
		if core.get_node(center).name == "mcl_portals:portal" then
			return center, node
		end
	end

	local nodes = connected_portal_nodes(pos)
	if not nodes then
		return nil
	end
	local center = portal_center(nodes)
	cache_center(nodes, center)
	return center, node
end

-- Which node an entity position falls in. This deliberately does not use
-- vector.round: core.get_node rounds with floor(v + 0.5), and the two disagree
-- on negative halves -- exactly the case that comes up at bedrock level, where
-- an arriving object sits at y = -122.5.
local function node_position(v)
	return vector.new(math.floor(v.x + 0.5),
			  math.floor(v.y + 0.5),
			  math.floor(v.z + 0.5))
end

-- The portal an object is currently standing in, if any.
local function object_portal(obj)
	local pos = obj:get_pos()
	if not pos then
		return nil
	end
	local feet = node_position(pos)
	local center = get_portal(feet)
	if center then
		return center
	end
	return get_portal(vector.offset(feet, 0, 1, 0))
end

------------------------------------------------------------------------------
-- Registry of known portals
--
-- Only used to find a portal to link to. Entries are validated against the
-- world every time they are read and dropped when they turn out to be stale,
-- so a registry that has drifted out of date repairs itself.
------------------------------------------------------------------------------

local portals = {}

local function load_registry()
	for _, p in ipairs(core.deserialize(storage:get_string("portals")) or {}) do
		local v = vector.new(p.x, p.y, p.z)
		portals[core.hash_node_position(v)] = v
	end
end

local function save_registry()
	local list = {}
	for _, v in pairs(portals) do
		list[#list + 1] = v
	end
	storage:set_string("portals", core.serialize(list))
end

local function register_portal(center)
	local hash = core.hash_node_position(center)
	if portals[hash] then
		return
	end
	portals[hash] = vector.copy(center)
	save_registry()
	core.log("action", "[mcla_server] registered portal at " .. core.pos_to_string(center))
end

local function unregister_portal(center)
	local hash = core.hash_node_position(center)
	if not portals[hash] then
		return
	end
	portals[hash] = nil
	save_registry()
	core.log("action", "[mcla_server] unregistered portal at " .. core.pos_to_string(center))
end

local function is_deep(pos)
	return pos.y <= DEEP_THRESHOLD
end

-- Nearest registered portal on the requested side of DEEP_THRESHOLD that is
-- within LINK_RADIUS of the target column and still actually exists.
local function find_link(target, want_deep)
	local best, best_distance
	local stale = {}

	for hash, p in pairs(portals) do
		if is_deep(p) == want_deep then
			local distance = chebyshev(p, target)
			if distance <= LINK_RADIUS
				and (not best_distance or distance < best_distance) then
				core.load_area(p)
				local name = core.get_node(p).name
				if name == "mcl_portals:portal" then
					best, best_distance = p, distance
				elseif name ~= "ignore" then
					-- Definitely gone, as opposed to merely not loaded.
					stale[#stale + 1] = hash
				end
			end
		end
	end

	for _, hash in ipairs(stale) do
		portals[hash] = nil
	end
	if #stale > 0 then
		save_registry()
	end

	return best
end

------------------------------------------------------------------------------
-- Building portals
------------------------------------------------------------------------------

-- Places the obsidian frame and the portal nodes, with `pos` as the lower
-- left interior node. Geometry matches mcl_portals' own generated portals.
-- When `platform` is set the portal also gets a small landing built around it,
-- for spots over water or in mid-air.
local function build_portal(pos, param2, platform)
	local obsidian, portal_nodes, air = {}, {}, {}

	for i = -1, 2 do
		obsidian[#obsidian + 1] = pos + orient(vector.new(i, -1, 0), param2)
		obsidian[#obsidian + 1] = pos + orient(vector.new(i, 3, 0), param2)
	end

	for i = 0, 2 do
		obsidian[#obsidian + 1] = pos + orient(vector.new(-1, i, 0), param2)
		obsidian[#obsidian + 1] = pos + orient(vector.new(2, i, 0), param2)
		portal_nodes[#portal_nodes + 1] = pos + orient(vector.new(0, i, 0), param2)
		portal_nodes[#portal_nodes + 1] = pos + orient(vector.new(1, i, 0), param2)
	end

	if platform then
		for _, dz in ipairs({ -1, 1 }) do
			for dx = 0, 1 do
				obsidian[#obsidian + 1] =
					pos + orient(vector.new(dx, -1, dz), param2)
				for i = 0, 2 do
					air[#air + 1] =
						pos + orient(vector.new(dx, i, dz), param2)
				end
			end
		end
	end

	core.bulk_set_node(obsidian, { name = "mcl_core:obsidian" })
	core.bulk_set_node(air, { name = "air" })
	core.bulk_set_node(portal_nodes, { name = "mcl_portals:portal", param2 = param2 })

	local center = portal_center(portal_nodes)
	cache_center(portal_nodes, center)
	-- Keep mcl_portals' own metadata in sync too, so anything still reading it
	-- (or a future revert of this mod) sees a sane value.
	local serialized = core.serialize(center)
	for _, p in ipairs(portal_nodes) do
		core.get_meta(p):set_string("portal", serialized)
	end

	register_portal(center)
	core.log("action", "[mcla_server] built portal at " .. core.pos_to_string(center))
	return center
end

local function chamber_bounds(cx, cz)
	local r = CHAMBER_RADIUS
	local inner_min = vector.new(cx - r, DEEP_BASE_Y, cz - r)
	local inner_max = vector.new(cx + r, DEEP_BASE_Y + CHAMBER_HEIGHT - 1, cz + r)
	local outer_min = vector.new(cx - r - 1, DEEP_FLOOR_Y, cz - r - 1)
	local outer_max = vector.new(cx + r + 1, DEEP_BASE_Y + CHAMBER_HEIGHT, cz + r + 1)
	return inner_min, inner_max, outer_min, outer_max
end

local NEIGHBOURS = {
	vector.new(1, 0, 0), vector.new(-1, 0, 0),
	vector.new(0, 1, 0), vector.new(0, -1, 0),
	vector.new(0, 0, 1), vector.new(0, 0, -1),
}

local function touches_liquid(pos)
	if is_liquid(core.get_node(pos).name) then
		return true
	end
	for _, d in ipairs(NEIGHBOURS) do
		if is_liquid(core.get_node(pos + d).name) then
			return true
		end
	end
	return false
end

-- Hollows out the arrival chamber at bedrock level.
--
-- The shell is only replaced where it has to be: obsidian wherever lava or
-- water is in contact (bedrock level sits inside the lava sea), stone bricks
-- where the shell would otherwise be open air, and untouched natural rock
-- everywhere else. That keeps the room sealed without walling players in
-- behind a solid obsidian box they would need a diamond pickaxe to escape.
local function build_chamber(cx, cz)
	local inner_min, inner_max, outer_min, outer_max = chamber_bounds(cx, cz)
	local obsidian, bricks, air = {}, {}, {}

	for x = outer_min.x, outer_max.x do
		for y = outer_min.y, outer_max.y do
			for z = outer_min.z, outer_max.z do
				local p = vector.new(x, y, z)
				local inside = x >= inner_min.x and x <= inner_max.x
					and y >= inner_min.y and y <= inner_max.y
					and z >= inner_min.z and z <= inner_max.z
				if inside then
					air[#air + 1] = p
				else
					local name = core.get_node(p).name
					-- Never touch the world floor itself.
					if name ~= "mcl_core:bedrock" then
						if touches_liquid(p) then
							obsidian[#obsidian + 1] = p
						elseif name == "air"
							or core.get_item_group(name, "dig_by_water") ~= 0 then
							bricks[#bricks + 1] = p
						end
					end
				end
			end
		end
	end

	core.bulk_set_node(obsidian, { name = "mcl_core:obsidian" })
	core.bulk_set_node(bricks, { name = "mcl_core:stonebrick" })
	core.bulk_set_node(air, { name = "air" })
end

local function chamber_protected(cx, cz, player_name)
	local _, _, outer_min, outer_max = chamber_bounds(cx, cz)
	return core.is_area_protected(outer_min, outer_max, player_name) ~= false
end

-- First chamber site near the target column that nobody has claimed.
local function pick_chamber_site(target, player_name)
	for _, offset in ipairs(CHAMBER_OFFSETS) do
		local cx = clamp_to_map(target.x + offset[1])
		local cz = clamp_to_map(target.z + offset[2])
		if not chamber_protected(cx, cz, player_name) then
			return cx, cz
		end
	end
	return nil
end

-- Does a full portal (frame plus headroom) fit standing on `pos`?
local function suitable_for_portal(pos, param2)
	local ground_min = pos + orient(vector.new(-1, 0, -1), param2)
	local ground_max = pos + orient(vector.new(2, 0, 1), param2)
	if #core.find_nodes_in_area(ground_min, ground_max, GROUND_GROUPS) ~= 12 then
		return false
	end

	local air_min = pos + orient(vector.new(-1, 1, -1), param2)
	local air_max = pos + orient(vector.new(2, 4, 1), param2)
	return #core.find_nodes_in_area(air_min, air_max, { "air" }) == 48
end

local function spot_protected(pos, player_name)
	local min = vector.offset(pos, -2, -1, -2)
	local max = vector.offset(pos, 3, 5, 3)
	return core.is_area_protected(min, max, player_name) ~= false
end

-- Finds where to put a return portal near the target column. Returns the node
-- the portal should stand on plus whether it needs a landing platform.
local function find_surface_spot(target, param2, player_name)
	local r = SURFACE_SEARCH_RADIUS
	local min = vector.new(target.x - r, SURFACE_MIN, target.z - r)
	local max = vector.new(target.x + r, SURFACE_MAX, target.z + r)

	-- The highest air-covered node in a column is that column's surface;
	-- everything below it is a cave and no place to come back up in.
	local tops = {}
	for _, p in ipairs(core.find_nodes_in_area_under_air(min, max, GROUND_GROUPS)) do
		local key = p.x .. "," .. p.z
		if not tops[key] or p.y > tops[key].y then
			tops[key] = p
		end
	end

	local candidates = {}
	for _, p in pairs(tops) do
		candidates[#candidates + 1] = p
	end
	table.sort(candidates, function(a, b)
		return chebyshev(a, target) < chebyshev(b, target)
	end)

	local over_liquid
	for _, p in ipairs(candidates) do
		if suitable_for_portal(p, param2) and not spot_protected(p, player_name) then
			local name = core.get_node(p).name
			if not is_liquid(name) then
				-- Sink into snow cover or tall grass so the frame sits on
				-- real ground.
				if core.get_item_group(name, "dig_by_water") ~= 0 then
					p = vector.offset(p, 0, -1, 0)
				end
				return p, false
			elseif not over_liquid then
				over_liquid = p
			end
		end
	end

	if over_liquid then
		return over_liquid, true
	end

	-- Nothing suitable: build a landing directly above the target column,
	-- on top of whatever the highest node there is.
	local column_min = vector.new(target.x, SURFACE_MIN, target.z)
	local column_max = vector.new(target.x, SURFACE_MAX, target.z)
	local column = core.find_nodes_in_area(column_min, column_max, GROUND_GROUPS)
	local highest
	for _, p in ipairs(column) do
		if not highest or p.y > highest.y then
			highest = p
		end
	end
	if highest and not spot_protected(highest, player_name) then
		return highest, true
	end
	return nil
end

------------------------------------------------------------------------------
-- Teleporting
------------------------------------------------------------------------------

-- Objects that may not teleport right now. An entry is held for as long as the
-- object stays inside a portal and for TELEPORT_COOLOFF after it steps out.
local cooloff = {}
-- How long an object has been standing in a portal.
local charge = {}

local function now()
	return core.get_us_time() / 1000000
end

local function release_cooloff(obj)
	local function tick()
		if not is_valid_object(obj) then
			cooloff[obj] = nil
			return
		end
		if object_portal(obj) then
			core.after(1, tick)
		else
			core.after(TELEPORT_COOLOFF, function()
				cooloff[obj] = nil
			end)
		end
	end
	core.after(1, tick)
end

local function arrive(obj, dest, from_param2, to_param2)
	if obj:is_player() and from_param2 and to_param2 then
		-- Keep the player facing "through" the portal they came out of.
		local turn = (from_param2 - to_param2 + 2) * math.pi / 2
		obj:set_look_horizontal(obj:get_look_horizontal() + turn)
	end

	core.load_area(dest)
	mcl_util.teleport_safely(obj, vector.offset(dest, 0, -0.5, 0))

	if obj:is_player() then
		core.sound_play("mcl_portals_teleport",
			{ pos = dest, gain = 0.5, max_hear_distance = 1 }, true)
		core.log("action", "[mcla_server] " .. obj:get_player_name()
			.. " portalled to " .. core.pos_to_string(dest))
	else
		local entity = obj:get_luaentity()
		if entity and entity.is_mob then
			entity._just_portaled = 10
			entity.reset_fall_damage = true
		end
	end

	charge[obj] = nil
	cooloff[obj] = true
	release_cooloff(obj)
end

-- Puts the object back where it came from when a destination cannot be made.
local function abort(obj, source, message)
	if is_valid_object(obj) then
		if obj:is_player() and message then
			core.chat_send_player(obj:get_player_name(), message)
		end
		core.load_area(source)
		mcl_util.teleport_safely(obj, vector.offset(source, 0, -0.5, 0))
	end
	charge[obj] = nil
	cooloff[obj] = true
	release_cooloff(obj)
end

-- Where does a portal at `pos` lead? Returns "deep" or "surface" plus the
-- column to aim for.
local function destination_of(portal)
	local x = clamp_to_map(portal.x)
	local z = clamp_to_map(portal.z)
	local dimension = mcl_worlds.pos_to_dimension(portal)

	-- A portal somewhere other than the Overworld (a leftover from before this
	-- mod, or one lit in the Nether in creative) always leads back home.
	if dimension ~= "overworld" or is_deep(portal) then
		return "surface", vector.new(x, 0, z)
	end
	return "deep", vector.new(x, DEEP_BASE_Y, z)
end

-- Runs `callback(obj)` once the destination area exists. Players get
-- Mineclonia's "loading terrain" screen; other objects simply wait where they
-- are.
local function with_emerged_area(obj, min, max, message, callback)
	if obj:is_player() and biome_dispatch and biome_dispatch.teleport_with_emerge then
		biome_dispatch.teleport_with_emerge(obj, min, max, message,
			function(player)
				callback(player)
			end, {})
		return
	end

	-- core.emerge_area is not enough on a levelgen world: it returns before
	-- the level generator has finished with the chunk, and until then
	-- mcl_levelgen reports the whole chunk as protected -- which would make
	-- every candidate site look claimed. generate_area waits for the real
	-- thing.
	if levelgen_generate_area then
		local done = false
		levelgen_generate_area(min.x, min.y, min.z, max.x, max.y, max.z,
			function(progress)
				-- Called repeatedly as the area fills in.
				if not done
					and progress.n_regenerated == progress.total_regen
					and progress.n_emerged == progress.total_emerge then
					done = true
					callback(obj)
				end
			end)
		return
	end

	core.emerge_area(min, max, function(_, _, calls_remaining)
		if calls_remaining == 0 then
			callback(obj)
		end
	end)
end

-- Emerging can take seconds. Players spend that time in limbo and are always
-- still owed a destination; anything else has to have stayed in the portal.
local function still_wants_teleport(obj)
	if not is_valid_object(obj) then
		cooloff[obj] = nil
		charge[obj] = nil
		return false
	end
	if not obj:is_player() and not object_portal(obj) then
		cooloff[obj] = nil
		charge[obj] = nil
		return false
	end
	return true
end

local function make_deep_portal(obj, source, target, param2, player_name)
	if not still_wants_teleport(obj) then
		return
	end

	-- Somebody else may have built one while we were waiting on the emerge.
	local linked = find_link(target, true)
	if linked then
		arrive(obj, linked, param2, core.get_node(linked).param2)
		return
	end

	local cx, cz = pick_chamber_site(target, player_name)
	if not cx then
		abort(obj, source, S("The bedrock below is claimed; the portal fizzles out."))
		return
	end

	build_chamber(cx, cz)
	local center = build_portal(vector.new(cx, DEEP_BASE_Y, cz), param2, false)
	arrive(obj, center, param2, param2)
end

local function make_surface_portal(obj, source, target, param2, player_name)
	if not still_wants_teleport(obj) then
		return
	end

	local linked = find_link(target, false)
	if linked then
		arrive(obj, linked, param2, core.get_node(linked).param2)
		return
	end

	local spot, platform = find_surface_spot(target, param2, player_name)
	if not spot then
		abort(obj, source, S("There is nowhere to surface here; the portal fizzles out."))
		return
	end

	local center = build_portal(vector.offset(spot, 0, 1, 0), param2, platform)
	arrive(obj, center, param2, param2)
end

local function teleport(obj, node_pos)
	local portal, node = get_portal(node_pos)
	if not portal then
		return
	end

	-- Claim the object straight away: emerging can take seconds and nothing
	-- else may start a second teleport in the meantime.
	cooloff[obj] = true
	charge[obj] = nil

	local param2 = node.param2 or 0
	local kind, target = destination_of(portal)
	local player_name = obj:is_player() and obj:get_player_name() or ""

	local linked = find_link(target, kind == "deep")
	if linked then
		arrive(obj, linked, param2, core.get_node(linked).param2)
		return
	end

	if kind == "deep" then
		local r = CHAMBER_RADIUS + 18
		local min = vector.new(target.x - r, DEEP_FLOOR_Y - 2, target.z - r)
		local max = vector.new(target.x + r, DEEP_BASE_Y + CHAMBER_HEIGHT + 2, target.z + r)
		with_emerged_area(obj, min, max, S("Descending to bedrock"), function(o)
			make_deep_portal(o, portal, target, param2, player_name)
		end)
	else
		local r = SURFACE_SEARCH_RADIUS + 4
		local min = vector.new(target.x - r, SURFACE_MIN, target.z - r)
		local max = vector.new(target.x + r, SURFACE_MAX, target.z + r)
		with_emerged_area(obj, min, max, S("Returning to the surface"), function(o)
			make_surface_portal(o, portal, target, param2, player_name)
		end)
	end

	-- If the emerge callback never arrives (a cancelled limbo, a shutdown
	-- mid-generation) the claim above would lock this object out of portals
	-- for good. Hand it back after a generous grace period.
	core.after(120, function()
		if cooloff[obj] then
			release_cooloff(obj)
		end
	end)
end

------------------------------------------------------------------------------
-- Hooks
------------------------------------------------------------------------------

-- Replaces mcl_portals' nether teleport. mcl_walkover caches this field on
-- mods-loaded, which happens after this file runs, so the override is the one
-- that ends up being used.
core.override_item("mcl_portals:portal", {
	_on_object_in = function(pos, _, obj)
		if not is_valid_object(obj) or cooloff[obj] then
			return
		end
		if not mcl_portals.object_teleport_allowed(obj) then
			return
		end

		local delay
		local entity = obj:get_luaentity()
		if entity and entity.is_mob then
			if entity._just_portaled then
				return
			end
			delay = 0
		elseif obj:is_player() then
			delay = core.is_creative_enabled(obj:get_player_name())
				and 0 or TELEPORT_DELAY
		else
			-- Dropped items and the like stay put, same as in mcl_portals.
			return
		end

		local t = now()
		local state = charge[obj]
		if not state or t - state.last > 0.6 then
			state = { first = t, last = t }
			charge[obj] = state
		else
			state.last = t
		end

		if t - state.first >= delay then
			teleport(obj, pos)
		end
	end,
})

-- Drop portals from the registry as they are broken.
local portal_def = core.registered_nodes["mcl_portals:portal"]
local previous_on_destruct = portal_def and portal_def.on_destruct
core.override_item("mcl_portals:portal", {
	on_destruct = function(pos, node)
		local cached = core.deserialize(core.get_meta(pos):get_string("mcla_portal"))
		if cached then
			unregister_portal(vector.new(cached.x, cached.y, cached.z))
		end
		if previous_on_destruct then
			previous_on_destruct(pos, node)
		end
	end,
})

-- Register portals the moment they are lit, so that a portal built at bedrock
-- level by hand links up with one built at the surface even if nobody has
-- stepped through either of them yet.
local obsidian_def = core.registered_nodes["mcl_core:obsidian"]
local previous_on_ignite = obsidian_def and obsidian_def._on_ignite
if previous_on_ignite then
	core.override_item("mcl_core:obsidian", {
		_on_ignite = function(user, pointed_thing)
			local lit = previous_on_ignite(user, pointed_thing)
			if lit and pointed_thing and pointed_thing.above then
				local center = get_portal(pointed_thing.above)
				if center then
					register_portal(center)
				end
			end
			return lit
		end,
	})
end

-- ... and the same for portals lit through mcl_portals' public API rather than
-- by a player with flint and steel.
local previous_light = mcl_portals.light_nether_portal
function mcl_portals.light_nether_portal(pos)
	local lit = previous_light(pos)
	if lit then
		local center = get_portal(pos)
		if center then
			register_portal(center)
		end
	end
	return lit
end

-- Backstop: any portal that stays loaded gets picked up eventually, including
-- ones that predate this mod or were placed by a structure.
core.register_abm({
	label = "mcla_server: discover nether portals",
	nodenames = { "mcl_portals:portal" },
	interval = 17,
	chance = 4,
	action = function(pos)
		local center = get_portal(pos)
		if center then
			register_portal(center)
		end
	end,
})

core.register_on_leaveplayer(function(player)
	cooloff[player] = nil
	charge[player] = nil
end)

-- Objects keyed in the tables above keep an ObjectRef alive. Mobs die, despawn
-- and get unloaded all the time, so sweep the dead ones out periodically.
local function sweep_object_tables()
	for _, tbl in ipairs({ cooloff, charge }) do
		for obj in pairs(tbl) do
			if not obj:is_valid() then
				tbl[obj] = nil
			end
		end
	end
	core.after(60, sweep_object_tables)
end
core.after(60, sweep_object_tables)

core.register_chatcommand("mcla_portals", {
	description = S("List the portals mcla_server knows about"),
	privs = { debug = true },
	params = "[deep | surface]",
	func = function(_, param)
		local lines = {}
		for _, p in pairs(portals) do
			local deep = is_deep(p)
			if param == "" or (param == "deep") == deep then
				lines[#lines + 1] = string.format("%s (%s)",
					core.pos_to_string(p), deep and "deep" or "surface")
			end
		end
		table.sort(lines)
		if #lines == 0 then
			return true, S("No portals registered.")
		end
		return true, table.concat(lines, "\n")
	end,
})

load_registry()

core.log("action", string.format(
	"[mcla_server] bedrock portals active: arrival level y=%d, deep threshold y=%d",
	DEEP_BASE_Y, DEEP_THRESHOLD))
