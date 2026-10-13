local BW = {}

BW.VERSION = "0.1.0"

BW.FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
BW.FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
BW.FONT_HGT_LARGE = getTextManager():getFontHeight(UIFont.Large)

BW.VISIBILITY = { "public", "friendsOnly", "private", "unlisted" }

BW.COLOR_GOOD = { r = 0.55, g = 0.85, b = 0.55 }
BW.COLOR_BAD = { r = 0.95, g = 0.5, b = 0.45 }
BW.COLOR_WARN = { r = 0.95, g = 0.78, b = 0.4 }
BW.COLOR_MUTED = { r = 0.6, g = 0.6, b = 0.6 }
BW.COLOR_LABEL = { r = 0.75, g = 0.75, b = 0.75 }
BW.COLOR_LINK = { r = 0.45, g = 0.7, b = 1.0 }

function BW.measure(font, text)
	return getTextManager():MeasureStringX(font, text)
end

-- Shortens text with "..." so it fits within width.
function BW.truncate(font, text, width)
	if BW.measure(font, text) <= width then return text end
	local ellipsis = "..."
	local lo, hi = 0, #text
	while lo < hi do
		local mid = math.floor((lo + hi + 1) / 2)
		if BW.measure(font, string.sub(text, 1, mid) .. ellipsis) <= width then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return string.sub(text, 1, lo) .. ellipsis
end

-- Splits on "\n" without pattern captures
function BW.splitLines(text)
	local parts = {}
	local pos = 1
	while true do
		local nl = string.find(text, "\n", pos, true)
		if not nl then
			table.insert(parts, string.sub(text, pos))
			return parts
		end
		table.insert(parts, string.sub(text, pos, nl - 1))
		pos = nl + 1
	end
end

-- Word-wraps text into a list of lines.
function BW.wrap(font, text, width)
	local lines = {}
	for _, para in ipairs(BW.splitLines(text)) do
		local line = ""
		for word in string.gmatch(para, "%S+") do
			local test = (line == "") and word or (line .. " " .. word)
			if line ~= "" and BW.measure(font, test) > width then
				table.insert(lines, line)
				line = word
			else
				line = test
			end
		end
		table.insert(lines, line)
	end
	return lines
end

function BW.textOr(key, fallbackKey)
	local text = getText(key)
	if text == key then return getText(fallbackKey) end
	return text
end

function BW.normPath(path)
	if not path then return "" end
	return string.lower(string.gsub(path, "\\", "/"))
end

function BW.trim(text)
	return string.trim(text or "")
end

local function pad2(n)
	if n < 10 then return "0" .. tostring(n) end
	return tostring(n)
end

-- Unix seconds -> "YYYY-MM-DD" (UTC)
function BW.formatDate(seconds)
	seconds = tonumber(seconds)
	if not seconds or seconds <= 0 then return "?" end
	local days = math.floor(seconds / 86400) + 719468
	local era = math.floor(days / 146097)
	local doe = days - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m = (mp < 10) and (mp + 3) or (mp - 9)
	if m <= 2 then y = y + 1 end
	return tostring(y) .. "-" .. pad2(m) .. "-" .. pad2(d)
end

function BW.formatSize(bytes)
	bytes = tonumber(bytes) or 0
	if bytes >= 1024 * 1024 then
		return tostring(math.floor(bytes / (1024 * 1024) * 10 + 0.5) / 10) .. " MB"
	elseif bytes >= 1024 then
		return tostring(math.floor(bytes / 1024 + 0.5)) .. " KB"
	end
	return tostring(bytes) .. " B"
end

-- Scrollbars added with addScrollBars() don't follow their owner when it is
-- resized from Lua, so resize them explicitly after setWidth/setHeight.
function BW.fitScrollBars(ui)
	local bar = ui.vscroll
	if bar then
		bar:setX(ui.width - bar.width)
		bar:setY(0)
		bar:setHeight(ui.height)
	end
end

-- Vanilla multi-line text boxes never scroll to follow the cursor
-- (UITextBox2.keepCursorVisible only handles single-line boxes), so typing below
-- the visible lines looks like nothing happens. Call every frame for multi-line
-- entries; it only scrolls when the cursor or text changed, so the mouse wheel still works.
function BW.keepCursorVisible(entry)
	local box = entry.javaObject
	if not box or not box:isDoingTextEntry() then
		entry.bwCursorPos = nil
		return
	end
	local pos = box:getCursorPos()
	local len = #entry:getText()
	if pos == entry.bwCursorPos and len == entry.bwTextLen then return end
	entry.bwCursorPos, entry.bwTextLen = pos, len

	local lineHgt = getTextManager():getFontFromEnum(entry.font):getLineHeight()
	local inset = box:getInset()
	local visible = math.max(1, math.floor((entry.height - inset * 2) / lineHgt))
	local line = box:toDisplayLine(pos)
	local top = math.floor((-entry:getYScroll() + inset) / lineHgt)
	if line < top then
		entry:setYScroll(-line * lineHgt)
	elseif line >= top + visible then
		entry:setYScroll(-(line - visible + 1) * lineHgt)
	end
end

-- setText keeps the previous scroll position; call after loading new text.
function BW.resetScroll(entry)
	entry:setYScroll(0)
	entry:setCursorPos(0)
	entry.bwCursorPos = nil
end

function BW.workshopFolder()
	return Core.getMyDocumentFolder() .. getFileSeparator() .. "Workshop"
end

function BW.openWorkshopPage(itemID)
	if isSteamOverlayEnabled() then
		activateSteamOverlayToWorkshopItem(itemID)
	else
		openUrl("https://steamcommunity.com/sharedfiles/filedetails/?id=" .. itemID)
	end
end

-----------------------------------------------------------------------------
-- BBCode -> ISRichTextPanel markup, for the description preview.
-- This is an approximation of Steam's renderer: headings, bold, links, lists,
-- quotes, rules and tables are styled; images and videos become placeholders.
-----------------------------------------------------------------------------

local RESET = " <SIZE:small> <RGB:0.85,0.85,0.85> "
local INDENT_STEP = 16

function BW.bbcodeToRichText(text)
	text = text or ""
	text = string.gsub(text, "\r", "")
	-- ISRichTextPanel turns &lt; / &gt; back into < and > after parsing commands.
	text = string.gsub(text, "<", "&lt;")
	text = string.gsub(text, ">", "&gt;")

	local out = {}
	local lists = {}
	local quoteDepth = 0
	local function emit(s)
		out[#out + 1] = s
	end
	local function indent()
		return " <INDENT:" .. tostring((#lists + quoteDepth) * INDENT_STEP) .. "> "
	end
	local function newline()
		if #out > 0 then emit(" <LINE> ") end
	end
	-- ISRichTextPanel drops the spaces next to a command, so colour changes in the
	-- middle of a sentence need an explicit <SPACE> on whichever side had one.
	local lastText = ""
	local afterInline = false
	local function emitText(t)
		if t == "" then return end
		if afterInline and string.find(t, "^%s") then emit(" <SPACE> ") end
		emit(t)
		lastText = t
		afterInline = false
	end
	local function emitInline(cmd)
		if string.find(lastText, "%s$") then emit(" <SPACE> ") end
		emit(cmd)
		lastText = ""
		afterInline = true
	end

	emit(RESET)
	local pos = 1
	local len = #text
	while pos <= len do
		-- No pattern captures here: Kahlua mishandles captures that can be empty.
		local s, e = string.find(text, "%[/?[%a%*][%w]*[^%]\n]*%]", pos)
		if not s then
			emitText(string.sub(text, pos))
			break
		end
		local inner = string.sub(text, s + 1, e - 1)
		local closing = string.sub(inner, 1, 1) == "/"
		if closing then inner = string.sub(inner, 2) end
		local name = string.lower(string.match(inner, "^[%a%*][%w]*") or "")
		local arg = ""
		local eq = string.find(inner, "=", 1, true)
		if eq then arg = string.sub(inner, eq + 1) end

		-- Newlines right next to block tags would otherwise add blank lines.
		local chunk = string.sub(text, pos, s - 1)
		if name == "*" or (closing and (name == "list" or name == "olist")) then
			chunk = string.gsub(chunk, "\n[ \t]*$", "")
		end
		emitText(chunk)
		pos = e + 1
		local blockTag = name == "list" or name == "olist" or name == "quote" or name == "hr" or name == "table"
			or (closing and (name == "h1" or name == "h2" or name == "h3" or name == "tr"))
		if blockTag then
			local _, nlEnd = string.find(text, "^[ \t]*\n", pos)
			if nlEnd then pos = nlEnd + 1 end
		end

		if name == "h1" or name == "h2" or name == "h3" then
			if closing then
				emit(" <LINE> " .. RESET)
			else
				newline()
				if name == "h1" then
					emit(" <SIZE:large> <RGB:1,1,1> ")
				else
					emit(" <SIZE:medium> <RGB:0.95,0.95,0.95> ")
				end
			end
		elseif name == "b" then
			emitInline(closing and " <POPRGB> " or " <PUSHRGB:1,1,1> ")
		elseif name == "url" then
			emitInline(closing and " <POPRGB> " or " <PUSHRGB:0.45,0.7,1> ")
		elseif name == "spoiler" then
			emitInline(closing and " <POPRGB> " or " <PUSHRGB:0.45,0.45,0.45> ")
		elseif name == "i" or name == "u" or name == "strike" or name == "code" or name == "noparse" then
			-- No italic/underline fonts available; show the text as-is.
		elseif name == "list" or name == "olist" then
			if closing then
				table.remove(lists)
				emit(indent() .. " <LINE> ")
			else
				table.insert(lists, { ordered = (name == "olist"), n = 0 })
				emit(indent())
			end
		elseif name == "*" then
			local list = lists[#lists]
			newline()
			if list and list.ordered then
				list.n = list.n + 1
				emitText(tostring(list.n) .. ". ")
			else
				emitText("- ")
			end
		elseif name == "quote" then
			if closing then
				quoteDepth = math.max(0, quoteDepth - 1)
				emit(" <POPRGB> " .. indent() .. " <LINE> ")
			else
				newline()
				quoteDepth = quoteDepth + 1
				emit(indent() .. " <PUSHRGB:0.6,0.6,0.6> ")
				if arg ~= "" then
					emit(arg .. ": <LINE> ")
				end
			end
		elseif name == "hr" then
			if not closing then
				newline()
				emit("------------------------------------------------ <LINE> ")
			end
		elseif name == "img" or name == "previewyoutube" then
			if not closing then
				local placeholder = getText(
					(name == "img") and "UI_BetterWorkshop_PreviewImage" or "UI_BetterWorkshop_PreviewVideo"
				)
				emitInline(" <PUSHRGB:0.5,0.5,0.5> " .. placeholder .. " <POPRGB> ")
				local cs, ce = string.find(string.lower(text), "[/" .. name .. "]", pos, true)
				if cs then pos = ce + 1 end
			end
		elseif name == "table" then
			newline()
		elseif name == "tr" then
			if closing then emit(" <LINE> ") end
		elseif name == "td" or name == "th" then
			if closing then emit("    ") end
		else
			-- Unknown tag: show it literally so typos are visible.
			emitText(string.sub(text, s, e))
		end
	end
	return table.concat(out)
end

return BW
