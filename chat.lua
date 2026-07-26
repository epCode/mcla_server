--[[
Chat decoration.

Public chat messages are rewritten before they go out, so players can colour
their own text with plain uppercase words. The words are case sensitive and are
eaten from the message, so nothing extra shows up in chat:

  Hey BLUEman!                 -- "man" is blue, "!" is not
  REDBLUE ON please bro OFF    -- "please bro" alternates red / blue
  BLUEREDFLASHINGNOW!          -- "NOW" alternates four shades

A colour on its own paints the next word. Followed by ON or START it paints
everything until OFF or STOP (or the end of the message). Several colours in a
row build a cycle that is laid across the text one character at a time.

FLASH marks the colour immediately before it, FLASHING marks every colour in
the group, and a flashing colour alternates between its own shade and a
brighter one as the cycle comes back around to it. (Luanti chat lines cannot
animate -- they are immutable once sent -- so "flashing" is a shimmer across the
characters rather than over time.)

A backslash escapes a keyword: "\BLUE" is just the word BLUE.

Other mods can add to this; see register_color and register_rule below.
]]

local chat = {}
mcla_server.chat = chat

local ESCAPE = "\27"
local DEFAULT_COLOR = "#fff"

chat.colors = {}   -- NAME -> { color = "#rrggbb", flash = "#rrggbb" }
chat.rules = {}    -- name -> rule definition

local keywords = {}       -- WORD -> handler(group, word)
local sorted_keywords = {} -- every WORD, longest first, for greedy matching

--- Rebuilds the greedy match order. Longest first so FLASHING beats FLASH.
local function resort_keywords()
	sorted_keywords = {}
	for word in pairs(keywords) do
		sorted_keywords[#sorted_keywords + 1] = word
	end
	table.sort(sorted_keywords, function(a, b)
		if #a ~= #b then
			return #a > #b
		end
		return a < b
	end)
end

--
-- Colours
--

--- The shade a colour flashes to: a little more desaturated, just as bright.
--- Every channel climbs by 0x33 unless it is already near the top, which turns
--- #ff4444 into #ff7777. Colours that are already white have nowhere to climb,
--- so they drop instead.
local function derive_flash(hex)
	local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
	if not r then
		return hex
	end
	local channels = { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) }
	local moved = false
	for i, value in ipairs(channels) do
		if value < 0xcc then
			channels[i] = math.min(value + 0x33, 0xff)
			moved = true
		end
	end
	if not moved then
		for i, value in ipairs(channels) do
			channels[i] = math.max(value - 0x33, 0)
		end
	end
	return string.format("#%02x%02x%02x", channels[1], channels[2], channels[3])
end

--- Registers a colour keyword.
---
--- @param name  uppercase word players type, e.g. "RED"
--- @param def   { color = "#rrggbb", flash = "#rrggbb" }, or a bare "#rrggbb".
---              `flash` defaults to a brighter version of `color`.
function chat.register_color(name, def)
	assert(type(name) == "string" and name ~= "", "colour name must be a non-empty string")
	if type(def) == "string" then
		def = { color = def }
	end
	assert(type(def) == "table" and type(def.color) == "string", "colour needs a `color` field")

	local color = { color = def.color, flash = def.flash or derive_flash(def.color) }
	chat.colors[name] = color
	keywords[name] = {
		on_token = function(state)
			state.group.colors[#state.group.colors + 1] = {
				color = color.color,
				alt = color.flash,
				flash = state.group.flash_all,
			}
		end,
	}
	resort_keywords()
end

--- Registers a keyword that is not a colour.
---
--- @param def { name = "flash", words = { "FLASH" }, on_token = function(state, word) end,
---              applies = function(state, word) end }
---
--- `state` is the parser as it stands where the word was found:
---   group   -- the run of keywords being read, or nil between runs, carrying
---              colors     (ordered cycle entries, each { color, alt, flash })
---              block      (true once ON / START has been seen)
---              stop       (true once OFF / STOP has been seen)
---              flash_all  (colours added from here on start out flashing)
---   active  -- the cycle painting the rest of the message, or nil
---   pending -- the cycle waiting to paint the next word, or nil
---
--- `applies` decides whether the word counts as a keyword at all. Without it a
--- word is always a keyword; with it, a word that does not apply stays ordinary
--- text. That is what keeps "TURN IT OFF" readable when no colour is running.
--- `on_token` is only called with a `group`, which is created on demand.
function chat.register_rule(def)
	assert(type(def) == "table", "rule definition must be a table")
	assert(type(def.name) == "string", "rule needs a `name`")
	assert(type(def.words) == "table" and #def.words > 0, "rule needs at least one word")
	assert(type(def.on_token) == "function", "rule needs an `on_token` handler")

	chat.rules[def.name] = def
	for _, word in ipairs(def.words) do
		keywords[word] = def
	end
	resort_keywords()
end

for name, hex in pairs({
	RED = "#ff4444",
	GREEN = "#44ff44",
	BLUE = "#4444ff",
	YELLOW = "#ffff44",
	CYAN = "#44ffff",
	MAGENTA = "#ff44ff",
	WHITE = "#ffffff",
	BLACK = "#444444",
	ORANGE = "#ff8844",
	PURPLE = "#8844ff",
	PINK = "#ff88bb",
	GRAY = "#888888",
	GREY = "#888888",
}) do
	chat.register_color(name, hex)
end

--- True when a colour is already waiting in the run being read. The words
--- below only mean anything after a colour, and staying ordinary text
--- everywhere else is what stops them being eaten out of ordinary shouting.
local function follows_a_color(state)
	return state.group ~= nil and #state.group.colors > 0
end

chat.register_rule({
	name = "flash",
	words = { "FLASH" },
	applies = follows_a_color,
	-- Marks the colour it stands in front of, so REDBLUE FLASH flashes only
	-- the blue.
	on_token = function(state)
		local colors = state.group.colors
		colors[#colors].flash = true
	end,
})

chat.register_rule({
	name = "flashing",
	words = { "FLASHING" },
	applies = follows_a_color,
	-- Marks every colour behind it, and any that follow in the same run, so a
	-- long cycle does not need FLASH spelled out per colour.
	on_token = function(state)
		state.group.flash_all = true
		for _, entry in ipairs(state.group.colors) do
			entry.flash = true
		end
	end,
})

chat.register_rule({
	name = "block_start",
	words = { "ON", "START" },
	applies = follows_a_color,
	on_token = function(state)
		state.group.block = true
	end,
})

chat.register_rule({
	name = "block_stop",
	words = { "OFF", "STOP" },
	-- Only a stop when there is something to stop.
	applies = function(state)
		return state.active ~= nil
	end,
	on_token = function(state)
		state.group.stop = true
	end,
})

--
-- Parsing
--

--- Splits a string into UTF-8 characters, so multi-byte letters survive being
--- coloured one character at a time.
local function utf8_chars(str)
	local chars, i, len = {}, 1, #str
	while i <= len do
		local byte = str:byte(i)
		local width = 1
		if byte >= 0xf0 then
			width = 4
		elseif byte >= 0xe0 then
			width = 3
		elseif byte >= 0xc0 then
			width = 2
		end
		chars[#chars + 1] = str:sub(i, i + width - 1)
		i = i + width
	end
	return chars
end

local function is_word_char(ch)
	return #ch > 1 or ch:match("^%w") ~= nil
end

local function is_space(ch)
	return #ch == 1 and ch:match("^%s") ~= nil
end

--- True for characters that stay inside a word when a letter follows, so
--- "don't" and "well-fed" colour as one word.
local function is_joiner(ch)
	return ch == "'" or ch == "-"
end

--- Longest registered word starting at `pos`, whether or not it means anything
--- here. Used to escape a keyword and to spot where one needs weighing up.
local function spelled_keyword_at(message, pos)
	for _, word in ipairs(sorted_keywords) do
		if message:sub(pos, pos + #word - 1) == word then
			return word
		end
	end
	return nil
end

--- Longest keyword starting at `pos` that actually applies in `state`. Words
--- whose rule turns them down here go back to being ordinary text.
local function keyword_at(message, pos, state)
	for _, word in ipairs(sorted_keywords) do
		if message:sub(pos, pos + #word - 1) == word then
			local rule = keywords[word]
			if not rule.applies or rule.applies(state, word) then
				return word
			end
		end
	end
	return nil
end

--- A keyword only counts where it cannot be the tail of a word somebody typed
--- in capitals: at the start of the message, straight after another keyword, or
--- after a character that is not an uppercase letter. That is what lets
--- "broOFF" close a block while "SCARED" stays a word.
local function at_boundary(message, pos, after_keyword)
	return pos == 1 or after_keyword
		or message:sub(pos - 1, pos - 1):match("%u") == nil
end

--- Next colour in a cycle. `span.n` counts visible characters painted so far:
--- it picks the entry, and how many times the cycle has come around picks which
--- shade a flashing entry shows.
local function next_color(span)
	local n = span.n
	span.n = n + 1
	local size = #span.cycle
	local entry = span.cycle[(n % size) + 1]
	if entry.flash and math.floor(n / size) % 2 == 1 then
		return entry.alt
	end
	return entry.color
end

--- Rewrites a chat message, returning it with colour escape sequences applied.
function chat.decorate(message)
	-- Players have no business emitting escape sequences of their own.
	message = message:gsub(ESCAPE, "")

	local out = {}
	local current = nil
	local state = { group = nil, active = nil, pending = nil }
	local buffer = {}

	local function put(text, color)
		if color ~= current then
			out[#out + 1] = ESCAPE .. "(c@" .. (color or DEFAULT_COLOR) .. ")"
			current = color
		end
		out[#out + 1] = text
	end

	local function emit(text)
		local chars = utf8_chars(text)
		local i = 1
		while i <= #chars do
			local ch = chars[i]
			if state.pending and is_word_char(ch) then
				-- A colour with no ON paints exactly one word, punctuation
				-- excluded.
				local last = i
				while last <= #chars do
					local c = chars[last]
					if is_word_char(c) then
						last = last + 1
					elseif is_joiner(c) and chars[last + 1] and is_word_char(chars[last + 1]) then
						last = last + 1
					else
						break
					end
				end
				for k = i, last - 1 do
					put(chars[k], next_color(state.pending))
				end
				state.pending = nil
				i = last
			else
				if is_space(ch) then
					-- Colouring a space shows nothing, so it does not take a
					-- turn in the cycle either.
					put(ch, current)
				elseif state.active then
					put(ch, next_color(state.active))
				else
					put(ch, nil)
				end
				i = i + 1
			end
		end
	end

	local function commit(group)
		if group.stop then
			state.active, state.pending = nil, nil
		end
		if #group.colors > 0 then
			if group.block then
				state.active = { cycle = group.colors, n = 0 }
				state.pending = nil
			else
				state.pending = { cycle = group.colors, n = 0 }
			end
		end
	end

	--- Emits the text read so far. Text arriving is what closes a run of
	--- keywords, so this is also where a run takes effect.
	local function flush()
		if #buffer == 0 then
			return
		end
		local text = table.concat(buffer)
		buffer = {}
		if state.group then
			commit(state.group)
			state.group = nil
			-- The space that separated the keywords from the message is part
			-- of the markup, not of what was said.
			text = text:gsub("^ ", "", 1)
		end
		emit(text)
	end

	local pos, after_keyword = 1, false
	while pos <= #message do
		local ch = message:sub(pos, pos)
		if ch == "\\" then
			-- A backslash hands the next keyword back to the player as text.
			local escaped = spelled_keyword_at(message, pos + 1)
			if escaped then
				buffer[#buffer + 1] = escaped
				pos = pos + 1 + #escaped
			elseif message:sub(pos + 1, pos + 1) == "\\" then
				buffer[#buffer + 1] = "\\"
				pos = pos + 2
			else
				buffer[#buffer + 1] = "\\"
				pos = pos + 1
			end
			after_keyword = false
		elseif at_boundary(message, pos, after_keyword) and spelled_keyword_at(message, pos) then
			-- Text ends a run of keywords, so everything read so far has to
			-- land before the rules get to ask what is currently running.
			flush()
			local word = keyword_at(message, pos, state)
			if word then
				state.group = state.group
					or { colors = {}, block = false, stop = false, flash_all = false }
				keywords[word].on_token(state, word)
				pos = pos + #word
				after_keyword = true
				-- A run of keywords may be spaced out; those spaces belong to
				-- the run rather than to the message.
				local skip = pos
				while message:sub(skip, skip) == " " do
					skip = skip + 1
				end
				if skip > pos and keyword_at(message, skip, state) then
					pos = skip
				end
			else
				buffer[#buffer + 1] = ch
				pos = pos + 1
				after_keyword = false
			end
		else
			buffer[#buffer + 1] = ch
			pos = pos + 1
			after_keyword = false
		end
	end
	flush()

	if current ~= nil then
		out[#out + 1] = ESCAPE .. "(c@" .. DEFAULT_COLOR .. ")"
	end
	return table.concat(out)
end

--
-- Hook
--

-- Decorating inside format_chat_message rather than on_chat_message keeps the
-- shout privilege check, the server's chat logging and every other mod's chat
-- handler working, and leaves commands and /me alone. Wrapping whatever is
-- already there means mods that colour player names still get their turn.
local previous_format = core.format_chat_message

function core.format_chat_message(name, message)
	return previous_format(name, chat.decorate(message))
end

core.register_chatcommand("mcla_chat", {
	params = "[<message>]",
	description = "Preview chat decoration, or list the keywords with no argument",
	func = function(name, param)
		if param == "" then
			local words = {}
			for word in pairs(keywords) do
				words[#words + 1] = word
			end
			table.sort(words)
			return true, "Chat keywords: " .. table.concat(words, " ")
				.. "\nA colour paints the next word; add ON / START to paint until OFF / STOP."
				.. "\nStack colours to alternate them, FLASH or FLASHING to shimmer, \\ to escape."
		end
		return true, chat.decorate(param)
	end,
})
