require "ISUI/ISPanelJoypad"
local BW = require "BWUtil"

local BWTagGrid = ISPanelJoypad:derive("BWTagGrid")

function BWTagGrid:new(x, y, width, height)
	local o = ISPanelJoypad:new(x, y, width, height)
	setmetatable(o, self)
	self.__index = self
	o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.5 }
	o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
	o.font = UIFont.Small
	o.rowHgt = math.max(20, BW.FONT_HGT_SMALL + 4)
	o.boxSize = 16
	o.padX = 6
	o.padY = 4
	o.cols = 4
	o.tags = {}
	o.checked = {}
	o.cursor = 1
	o.mouseOver = -1
	o.enabled = true
	o.tickTexture = getTexture("media/ui/inventoryPanes/Tickbox_Tick.png")
	return o
end

function BWTagGrid:setTags(allowedTags)
	self.tags = {}
	for i = 1, allowedTags:size() do
		table.insert(self.tags, allowedTags:get(i - 1))
	end
end

-- The map is shared with the item's draft, so toggling edits the draft directly.
function BWTagGrid:setCheckedMap(map)
	self.checked = map or {}
end

function BWTagGrid:setColumns(cols)
	self.cols = math.max(1, cols)
end

function BWTagGrid:getRowCount()
	return math.max(1, math.ceil(#self.tags / self.cols))
end

function BWTagGrid:getRequiredHeight()
	return self:getRowCount() * self.rowHgt + self.padY * 2
end

function BWTagGrid:getColWidth()
	return (self.width - self.padX * 2) / self.cols
end

function BWTagGrid:cellAt(x, y)
	local col = math.floor((x - self.padX) / self:getColWidth())
	local row = math.floor((y - self.padY) / self.rowHgt)
	if col < 0 or col >= self.cols or row < 0 then return -1 end
	local index = row * self.cols + col + 1
	if index > #self.tags then return -1 end
	return index
end

function BWTagGrid:toggle(index)
	local tag = self.tags[index]
	if not tag or not self.enabled then return end
	self.checked[tag] = not self.checked[tag] or nil
	getSoundManager():playUISound("UIToggleTickBox")
end

function BWTagGrid:prerender()
	self:drawRect(
		0, 0, self.width, self.height, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g,
		self.backgroundColor.b
	)
	self:drawRectBorder(
		0, 0, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b
	)
end

function BWTagGrid:render()
	local colW = self:getColWidth()
	local boxDY = (self.rowHgt - self.boxSize) / 2
	local textDY = (self.rowHgt - BW.FONT_HGT_SMALL) / 2
	for i, tag in ipairs(self.tags) do
		local col = (i - 1) % self.cols
		local row = math.floor((i - 1) / self.cols)
		local x = self.padX + col * colW
		local y = self.padY + row * self.rowHgt
		if self.joyfocus and i == self.cursor then
			self:drawRect(x, y, colW, self.rowHgt, 0.2, 1, 1, 1)
		elseif i == self.mouseOver then
			self:drawRect(x, y, colW, self.rowHgt, 0.1, 1, 1, 1)
		end
		self:drawRectBorder(x + 2, y + boxDY, self.boxSize, self.boxSize, 1, 0.4, 0.4, 0.4)
		local checked = self.checked[tag] == true
		if checked then
			self:drawTextureScaled(self.tickTexture, x + 2 + 2, y + boxDY + 1, 14, 14, 1, 1, 1, 1)
		end
		local textX = x + 2 + self.boxSize + 5
		local label = BW.truncate(self.font, tag, colW - (textX - x) - 4)
		local c = checked and 1 or 0.75
		self:drawText(label, textX, y + textDY, c, c, c, 1, self.font)
	end
	if self.joypadFocused or self.joyfocus then
		local r, g, b = 0.2, 1.0, 1.0
		if not self.joyfocus then
			r, g, b = 1.0, 1.0, 1.0
		end
		self:drawRectBorder(0, 0, self.width, self.height, 0.4, r, g, b)
		self:drawRectBorder(1, 1, self.width - 2, self.height - 2, 0.4, r, g, b)
	end
end

function BWTagGrid:onMouseMove(dx, dy)
	self.mouseOver = self:cellAt(self:getMouseX(), self:getMouseY())
end

function BWTagGrid:onMouseMoveOutside(dx, dy)
	self.mouseOver = -1
end

function BWTagGrid:onMouseDown(x, y)
	local index = self:cellAt(x, y)
	if index > 0 then
		self.cursor = index
		self:toggle(index)
	end
	return true
end

-- Controller: A on the grid enters it, then the d-pad moves and A toggles; B leaves.
function BWTagGrid:setJoypadFocused(focused, joypadData)
	self.joypadFocused = focused
end

function BWTagGrid:onJoypadDownInParent(button, joypadData)
	if button == Joypad.AButton then
		joypadData.focus = self
		return true
	end
	return false
end

function BWTagGrid:onJoypadDown(button, joypadData)
	if button == Joypad.AButton then
		self:toggle(self.cursor)
	elseif button == Joypad.BButton then
		joypadData.focus = self.parent
		updateJoypadFocus(joypadData)
		self:setJoypadFocused(true, joypadData)
	end
end

function BWTagGrid:moveCursor(delta)
	local index = self.cursor + delta
	if index >= 1 and index <= #self.tags then
		self.cursor = index
	end
end

function BWTagGrid:onJoypadDirLeft(joypadData)
	self:moveCursor(-1)
end
function BWTagGrid:onJoypadDirRight(joypadData)
	self:moveCursor(1)
end
function BWTagGrid:onJoypadDirUp(joypadData)
	self:moveCursor(-self.cols)
end
function BWTagGrid:onJoypadDirDown(joypadData)
	self:moveCursor(self.cols)
end

-- Checked tags as an ArrayList: allowed tags in their usual order, then any
-- tags from workshop.txt that the game doesn't list (kept, never dropped).
function BWTagGrid.toArrayList(checked, allowedOrder)
	local list = ArrayList.new()
	local seen = {}
	for _, tag in ipairs(allowedOrder) do
		if checked[tag] then
			list:add(tag)
			seen[tag] = true
		end
	end
	local extra = {}
	for tag, on in pairs(checked) do
		if on and not seen[tag] then table.insert(extra, tag) end
	end
	table.sort(extra)
	for _, tag in ipairs(extra) do
		list:add(tag)
	end
	return list
end

return BWTagGrid
