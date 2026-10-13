require "ISUI/ISPanelJoypad"
require "ISUI/ISTextEntryBox"
require "ISUI/ISRichTextPanel"
local BW = require "BWUtil"

local BWTextEditor = ISPanelJoypad:derive("BWTextEditor")

function BWTextEditor:new(x, y, width, height)
	local o = ISPanelJoypad:new(x, y, width, height)
	setmetatable(o, self)
	self.__index = self
	o:noBackground()
	o.anchorRight = true
	o.anchorBottom = true
	o.title = ""
	o.previewing = false
	return o
end

function BWTextEditor:create()
	local btnHgt = math.max(25, BW.FONT_HGT_SMALL + 3 * 2)

	self.entry = ISTextEntryBox:new("", 0, 0, 100, 100)
	self.entry.font = UIFont.Medium
	self.entry:initialise()
	self.entry:instantiate()
	self.entry:setMultipleLine(true)
	self.entry:setMaxLines(4096)
	self.entry:addScrollBars()
	self:addChild(self.entry)

	self.preview = ISRichTextPanel:new(0, 0, 100, 100)
	self.preview:initialise()
	self.preview.autosetheight = false
	self.preview.clip = true
	self.preview.background = true
	self.preview.backgroundColor = { r = 0, g = 0, b = 0, a = 0.5 }
	self.preview.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
	self.preview:setMargins(10, 8, 20, 8)
	self:addChild(self.preview)
	self.preview:addScrollBars()
	self.preview:setVisible(false)

	local function makeButton(title, onClick, width)
		local b = ISButton:new(0, 0, width or 100, btnHgt, title, self, onClick)
		b:initialise()
		b.borderColor = { r = 1, g = 1, b = 1, a = 0.1 }
		self:addChild(b)
		return b
	end

	self.btnEdit = makeButton(getText("UI_BetterWorkshop_Edit"), self.onButtonEdit)
	self.btnPreview = makeButton(getText("UI_BetterWorkshop_Preview"), self.onButtonPreview)
	self.btnEdit:setWidthToTitle(80)
	self.btnPreview:setWidthToTitle(80)
	self.btnCancel = makeButton(getText("UI_btn_cancel"), self.onButtonCancel)
	self.btnAccept = makeButton(getText("UI_btn_accept"), self.onButtonAccept)

	self.joypadIndexY = 1
	self.joypadIndex = 1
	self:insertNewLineOfButtons(self.btnEdit, self.btnPreview)
	self:insertNewLineOfButtons(self.entry)
	self:insertNewLineOfButtons(self.btnCancel, self.btnAccept)

	self:layout()
end

function BWTextEditor:layout()
	self.layoutW, self.layoutH = self.width, self.height
	local pad = 64
	local top = 10 + BW.FONT_HGT_LARGE + 16
	local btnHgt = self.btnCancel.height
	local areaH = self.height - top - btnHgt - 32

	self.btnPreview:setX(self.width - pad - self.btnPreview.width)
	self.btnPreview:setY(top - btnHgt - 6)
	self.btnEdit:setX(self.btnPreview.x - 4 - self.btnEdit.width)
	self.btnEdit:setY(self.btnPreview.y)

	for _, ui in ipairs({ self.entry, self.preview }) do
		ui:setX(pad)
		ui:setY(top)
		ui:setWidth(self.width - pad * 2)
		ui:setHeight(areaH)
		BW.fitScrollBars(ui)
	end
	self.preview.textDirty = true

	local by = top + areaH + 12
	self.btnCancel:setX(self.width / 2 - 15 - self.btnCancel.width)
	self.btnCancel:setY(by)
	self.btnAccept:setX(self.width / 2 + 15)
	self.btnAccept:setY(by)
end

-- onAccept(target, text) is called when the user accepts.
function BWTextEditor:open(title, text, allowPreview, target, onAccept)
	self.title = title
	self.target = target
	self.onAccept = onAccept
	self.allowPreview = allowPreview
	self.entry:setText(text or "")
	BW.resetScroll(self.entry)
	self:setPreviewing(false)
	self.btnEdit:setVisible(allowPreview)
	self.btnPreview:setVisible(allowPreview)
	self:setVisible(true)
	self:bringToTop()
	local joypadData = JoypadState.getMainMenuJoypad()
	if joypadData then
		joypadData.focus = self
		updateJoypadFocus(joypadData)
	else
		self.entry:focus()
	end
end

function BWTextEditor:setPreviewing(previewing)
	self.previewing = previewing
	self.entry:setVisible(not previewing)
	self.preview:setVisible(previewing)
	self.btnEdit.backgroundColor = previewing and { r = 0, g = 0, b = 0, a = 1 } or { r = 0.3, g = 0.3, b = 0.3, a = 1 }
	self.btnPreview.backgroundColor = previewing and { r = 0.3, g = 0.3, b = 0.3, a = 1 }
		or { r = 0, g = 0, b = 0, a = 1 }
	if previewing then
		self.preview.text = BW.bbcodeToRichText(self.entry:getText())
		self.preview:paginate()
		self.preview:setYScroll(0)
	end
end

function BWTextEditor:close()
	self:setVisible(false)
	local joypadData = JoypadState.getMainMenuJoypad()
	if joypadData and self.parent then
		joypadData.focus = self.parent
		updateJoypadFocus(joypadData)
	end
end

function BWTextEditor:onButtonEdit()
	self:setPreviewing(false)
end
function BWTextEditor:onButtonPreview()
	self:setPreviewing(true)
end

function BWTextEditor:onButtonAccept()
	local text = self.entry:getText()
	self:close()
	if self.onAccept then self.onAccept(self.target, text) end
end

function BWTextEditor:onButtonCancel()
	self:close()
end

function BWTextEditor:prerender()
	BW.keepCursorVisible(self.entry)
	if self.layoutW ~= self.width or self.layoutH ~= self.height then
		self:layout()
	end
	self:drawRect(0, 0, self.width, self.height, 0.95, 0, 0, 0)
	self:drawRectBorder(0, 0, self.width, self.height, 0.5, 1, 1, 1)
	self:drawTextCentre(self.title, self.width / 2, 10, 1, 1, 1, 1, UIFont.Large)
end

-- Swallow clicks so nothing underneath reacts.
function BWTextEditor:onMouseDown(x, y)
	return true
end
function BWTextEditor:onMouseUp(x, y)
	return true
end
function BWTextEditor:onMouseWheel(del)
	return true
end

function BWTextEditor:onGainJoypadFocus(joypadData)
	ISPanelJoypad.onGainJoypadFocus(self, joypadData)
	self:setISButtonForB(self.btnCancel)
	self:restoreJoypadFocus(joypadData)
end

return BWTextEditor
