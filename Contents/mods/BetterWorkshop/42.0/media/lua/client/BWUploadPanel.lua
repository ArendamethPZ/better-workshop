require "ISUI/ISPanelJoypad"
require "ISUI/ISTextEntryBox"
local BW = require "BWUtil"

local BWUploadPanel = ISPanelJoypad:derive("BWUploadPanel")

local STEP_PENDING, STEP_ACTIVE, STEP_DONE, STEP_FAILED = "pending", "active", "done", "failed"
local LOG_HGT = 180

function BWUploadPanel:new(x, y, width, height, screen)
	local o = ISPanelJoypad:new(x, y, width, height)
	setmetatable(o, self)
	self.__index = self
	o:noBackground()
	o.anchorRight = true
	o.anchorBottom = true
	o.screen = screen
	o.steps = {}
	o.logLines = {}
	o.showLog = false
	o.tickTexture = getTexture("media/ui/inventoryPanes/Tickbox_Tick.png")
	return o
end

function BWUploadPanel:create()
	local btnHgt = math.max(25, BW.FONT_HGT_SMALL + 3 * 2)
	local function makeButton(title, onClick)
		local b = ISButton:new(0, 0, 100, btnHgt, title, self, onClick)
		b:initialise()
		b.borderColor = { r = 1, g = 1, b = 1, a = 0.1 }
		b:setWidthToTitle(100)
		self:addChild(b)
		return b
	end
	self.btnLog = makeButton(getText("UI_BetterWorkshop_ShowLog"), self.onButtonLog)
	self.btnView = makeButton(getText("UI_BetterWorkshop_ViewOnWorkshop"), self.onButtonView)
	self.btnClose = makeButton(getText("UI_btn_close"), self.onButtonClose)

	self.log = ISTextEntryBox:new("", 0, 0, 100, LOG_HGT)
	self.log.font = UIFont.Small
	self.log:initialise()
	self.log:instantiate()
	self.log:setMultipleLine(true)
	self.log:setEditable(false)
	self.log:addScrollBars()
	self:addChild(self.log)
	self.log:setVisible(false)

	self.joypadIndexY = 1
	self.joypadIndex = 1
	self:insertNewLineOfButtons(self.btnLog, self.btnView, self.btnClose)
end

function BWUploadPanel:isWaiting()
	return self.state ~= nil
end

function BWUploadPanel:LOG(msg)
	table.insert(self.logLines, msg)
	self.log:setText(table.concat(self.logLines, "\n"))
	print("[BetterWorkshop] " .. msg)
end

function BWUploadPanel:start(entry)
	self.entry = entry
	self.item = entry.item
	self.isNew = (self.item:getID() == nil)
	self.progress = 0
	self.failText = nil
	self.legalNote = false
	self.logLines = {}
	self.log:setText("")
	self.steps = {
		{ text = getText("UI_BetterWorkshop_StepCheck"), state = STEP_ACTIVE },
		{
			text = self.isNew and getText("UI_BetterWorkshop_StepCreate")
				or getText("UI_BetterWorkshop_StepFound", self.item:getID()),
			state = STEP_PENDING
		},
		{ text = getText("UI_BetterWorkshop_StepUpload"), state = STEP_PENDING, progress = true },
		{ text = getText("UI_BetterWorkshop_StepDone"), state = STEP_PENDING }
	}
	self.state = "check"
	self.btnClose:setEnable(false)
	self.btnView:setEnable(false)
	self:setVisible(true)
	self:bringToTop()
	self:LOG(self.isNew and "start creation of new item" or ("start update of existing item ID=" .. self.item:getID()))
	local joypadData = JoypadState.getMainMenuJoypad()
	if joypadData then
		joypadData.focus = self
		updateJoypadFocus(joypadData)
	end
end

function BWUploadPanel:setStep(index, state, text)
	local step = self.steps[index]
	step.state = state
	if text then step.text = text end
	if state == STEP_DONE and self.steps[index + 1] and self.steps[index + 1].state == STEP_PENDING then
		self.steps[index + 1].state = STEP_ACTIVE
	end
end

function BWUploadPanel:fail(index, text)
	self:setStep(index, STEP_FAILED)
	self.failText = text
	self:LOG("finished with error")
	self:finish(false)
end

function BWUploadPanel:finish(success)
	self.state = nil
	self.btnClose:setEnable(true)
	self.btnView:setEnable(self.item:getID() ~= nil)
	self.screen:onUploadFinished(self.entry, success)
end

-- The upload is driven one step per frame, like the vanilla wizard.
function BWUploadPanel:updateState()
	local state = self.state
	if state == "check" then
		local err = self.item:validateContents()
		if err then
			self:LOG("item failed validation: " .. err)
			self:fail(
				1, (string.gsub(getText("UI_WorkshopError_" .. err, self.item:getExtendedErrorInfo(err)), "\\n", "\n"))
			)
			return
		end
		self:setStep(1, STEP_DONE)
		if self.isNew then
			self.state = "create"
		else
			self:setStep(2, STEP_DONE)
			self.steps[3].text = getText("UI_BetterWorkshop_StepConfirm")
			self.state = "updatePrompt"
		end
	elseif state == "create" then
		if self.item:create() then
			self:LOG("success requesting Steam Workshop to create a new item")
			self.state = "createWait"
		else
			self:LOG("error requesting Steam Workshop to create a new item")
			self:fail(2, getText("UI_BetterWorkshop_CreateRequestFailed"))
		end
	elseif state == "updatePrompt" then
		-- Let one frame draw "confirm in the popup" before the blocking prompt opens.
		self.state = "update"
	elseif state == "update" then
		if self.item:submitUpdate() then
			self:LOG("success requesting Steam to update the item")
			self:LOG("there is no way to stop the update once it has started")
			self.steps[3].text = getText("UI_BetterWorkshop_StepUpload")
			self.state = "updateWait"
		else
			self:LOG("upload was cancelled or Steam refused the request")
			self:fail(3, getText("UI_BetterWorkshop_UploadCancelled"))
		end
	elseif state == "updateWait" then
		local progress = { processed = 0, total = 1 }
		if self.item:getUpdateProgress(progress) and progress.total > 0 then
			self.progress = math.min(1, progress.processed / progress.total)
		end
	end
end

function BWUploadPanel:onItemCreated(itemID, bUserNeedsToAcceptWorkshopLegalAgreement)
	self:LOG("new workshop item successfully created with ID=" .. tostring(itemID))
	self.item:setID(itemID)
	self.item:writeWorkshopTxt()
	self.screen:onItemIdAssigned(self.entry)
	if bUserNeedsToAcceptWorkshopLegalAgreement then
		self:LOG("user must agree to the Workshop legal agreement")
		self.legalNote = true
	end
	self:setStep(2, STEP_DONE, getText("UI_BetterWorkshop_StepCreated", tostring(itemID)))
	self.steps[3].text = getText("UI_BetterWorkshop_StepConfirm")
	self.state = "updatePrompt"
end

function BWUploadPanel:onItemNotCreated(result)
	self:LOG("failed to create new workshop item, result=" .. tostring(result))
	self:fail(2, getText("UI_BetterWorkshop_CreateFailed", tostring(result)))
end

function BWUploadPanel:onItemUpdated(bUserNeedsToAcceptWorkshopLegalAgreement)
	self:LOG("success updating item")
	if bUserNeedsToAcceptWorkshopLegalAgreement then
		self:LOG("user must agree to the Workshop legal agreement")
		self.legalNote = true
	end
	self.progress = 1
	self:setStep(3, STEP_DONE)
	self:setStep(4, STEP_DONE)
	self:LOG("finished")
	self:finish(true)
end

function BWUploadPanel:onItemNotUpdated(result)
	self:LOG("failed to update workshop item, result=" .. tostring(result))
	self:fail(3, getText("UI_BetterWorkshop_UpdateFailed", tostring(result)))
end

function BWUploadPanel:onButtonLog()
	self.showLog = not self.showLog
	self.log:setVisible(self.showLog)
	self.btnLog:setTitle(self.showLog and getText("UI_BetterWorkshop_HideLog") or getText("UI_BetterWorkshop_ShowLog"))
end

function BWUploadPanel:onButtonView()
	if self.item:getID() then
		BW.openWorkshopPage(self.item:getID())
	end
end

function BWUploadPanel:onButtonClose()
	if self.state then return end
	self:setVisible(false)
	local joypadData = JoypadState.getMainMenuJoypad()
	if joypadData then
		joypadData.focus = self.screen
		updateJoypadFocus(joypadData)
	end
end

-- Box geometry depends on content (error text, log), so it's recomputed each frame.
function BWUploadPanel:computeBox()
	local boxW = math.min(640, self.width - 64)
	local innerW = boxW - 32
	local lineH = BW.FONT_HGT_MEDIUM + 6
	local h = 16 + BW.FONT_HGT_LARGE + 12 + #self.steps * lineH + 18 + 8
	self.failLines = self.failText and BW.wrap(UIFont.Small, self.failText, innerW) or nil
	if self.failLines then h = h + #self.failLines * BW.FONT_HGT_SMALL + 8 end
	self.noteLines = self.legalNote and BW.wrap(UIFont.Small, getText("UI_BetterWorkshop_LegalNote"), innerW) or nil
	if self.noteLines then h = h + #self.noteLines * BW.FONT_HGT_SMALL + 8 end
	if self.showLog then h = h + LOG_HGT + 8 end
	h = h + self.btnClose.height + 16
	return (self.width - boxW) / 2, (self.height - h) / 2, boxW, h
end

function BWUploadPanel:prerender()
	if self.state then self:updateState() end

	local bx, by, bw, bh = self:computeBox()
	self.box = { x = bx, y = by, w = bw, h = bh }

	self:drawRect(0, 0, self.width, self.height, 0.7, 0, 0, 0)
	self:drawRect(bx, by, bw, bh, 0.95, 0, 0, 0)
	self:drawRectBorder(bx, by, bw, bh, 0.5, 1, 1, 1)

	local name = BW.trim(self.item:getTitle())
	if name == "" then name = self.item:getFolderName() end
	local titleKey = self.isNew and "UI_BetterWorkshop_PublishingTitle" or "UI_BetterWorkshop_UploadingTitle"
	local title = BW.truncate(UIFont.Large, getText(titleKey, name), bw - 32)
	self:drawText(title, bx + 16, by + 16, 1, 1, 1, 1, UIFont.Large)

	local x = bx + 16
	local y = by + 16 + BW.FONT_HGT_LARGE + 12
	local lineH = BW.FONT_HGT_MEDIUM + 6
	local markerW = 22
	for _, step in ipairs(self.steps) do
		local text = step.text
		if step.progress and step.state == STEP_ACTIVE and self.state == "updateWait" then
			text = text .. "  " .. tostring(math.floor(self.progress * 100)) .. "%"
		end
		local c
		if step.state == STEP_DONE then
			c = BW.COLOR_GOOD
			self:drawTextureScaled(self.tickTexture, x, y + (BW.FONT_HGT_MEDIUM - 16) / 2, 16, 16, 1, c.r, c.g, c.b)
		elseif step.state == STEP_FAILED then
			c = BW.COLOR_BAD
			self:drawText("X", x + 3, y, c.r, c.g, c.b, 1, UIFont.Medium)
		elseif step.state == STEP_ACTIVE then
			c = { r = 1, g = 1, b = 1 }
			self:drawText(">", x + 3, y, 1, 1, 1, 1, UIFont.Medium)
		else
			c = BW.COLOR_MUTED
			self:drawText("-", x + 4, y, c.r, c.g, c.b, 1, UIFont.Medium)
		end
		self:drawText(
			BW.truncate(UIFont.Medium, text, bw - 32 - markerW), x + markerW, y, c.r, c.g, c.b, 1, UIFont.Medium
		)
		y = y + lineH
	end

	local barW = bw - 32
	local fraction = self.progress or 0
	self:drawRectBorder(x, y + 2, barW, 14, 0.8, 0.6, 0.6, 0.6)
	if fraction > 0 then
		self:drawRect(x + 2, y + 4, (barW - 4) * fraction, 10, 0.5, 1, 1, 1)
	end
	y = y + 18 + 8

	if self.failLines then
		for _, line in ipairs(self.failLines) do
			self:drawText(line, x, y, BW.COLOR_BAD.r, BW.COLOR_BAD.g, BW.COLOR_BAD.b, 1, UIFont.Small)
			y = y + BW.FONT_HGT_SMALL
		end
		y = y + 8
	end
	if self.noteLines then
		for _, line in ipairs(self.noteLines) do
			self:drawText(line, x, y, BW.COLOR_WARN.r, BW.COLOR_WARN.g, BW.COLOR_WARN.b, 1, UIFont.Small)
			y = y + BW.FONT_HGT_SMALL
		end
		y = y + 8
	end

	if self.showLog then
		self.log:setX(x)
		self.log:setY(y)
		if self.log.width ~= barW then
			self.log:setWidth(barW)
			BW.fitScrollBars(self.log)
		end
		y = y + LOG_HGT + 8
	end

	local btnY = by + bh - 16 - self.btnClose.height
	self.btnLog:setX(x)
	self.btnLog:setY(btnY)
	self.btnClose:setX(bx + bw - 16 - self.btnClose.width)
	self.btnClose:setY(btnY)
	self.btnView:setX(self.btnClose.x - 6 - self.btnView.width)
	self.btnView:setY(btnY)
end

function BWUploadPanel:onMouseDown(x, y)
	return true
end
function BWUploadPanel:onMouseUp(x, y)
	return true
end
function BWUploadPanel:onMouseWheel(del)
	return true
end

function BWUploadPanel:onGainJoypadFocus(joypadData)
	ISPanelJoypad.onGainJoypadFocus(self, joypadData)
	self:setISButtonForB(self.btnClose)
	self:setISButtonForY(self.btnView)
	self:restoreJoypadFocus(joypadData)
end

return BWUploadPanel
