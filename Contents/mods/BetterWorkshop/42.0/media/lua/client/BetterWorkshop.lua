require "OptionScreens/WorkshopSubmitScreen"
local BetterWorkshopScreen = require "BWScreen"

local vanilla = {
	create = WorkshopSubmitScreen.create,
	fillList = WorkshopSubmitScreen.fillList,
	onButtonBack = WorkshopSubmitScreen.onButtonBack,
	onGainJoypadFocus = WorkshopSubmitScreen.onGainJoypadFocus
}

local function setVanillaPagesVisible(host, visible)
	for i = 1, 10 do
		local page = host["page" .. i]
		if page then page:setVisible(visible) end
	end
end

local function focusJoypad(target)
	local joypadData = JoypadState.getMainMenuJoypad()
	if joypadData and target then
		joypadData.focus = target
		updateJoypadFocus(joypadData)
	end
end

-- "Classic" button: show the untouched vanilla wizard.
local function showClassic(host)
	host.bwClassic = true
	host.betterWorkshop:setVisible(false)
	vanilla.fillList(host)
	focusJoypad(host.page9)
end

-- Better Workshop's own Back button: leave to the main menu.
local function closeScreen(host)
	host.bwClassic = false
	host.betterWorkshop:setVisible(false)
	vanilla.onButtonBack(host)
	local joypadData = JoypadState.getMainMenuJoypad()
	if joypadData and joypadData.focus == host.betterWorkshop then
		joypadData.focus = MainScreen.instance
		updateJoypadFocus(joypadData)
	end
end

function WorkshopSubmitScreen:create()
	vanilla.create(self)
	-- If anything goes wrong building the new screen, the vanilla wizard still works.
	local ok, err = pcall(function ()
		local host = self
		local screen = BetterWorkshopScreen:new(0, 0, self.width, self.height, {
			onClose = function () closeScreen(host) end,
			onClassic = function () showClassic(host) end
		})
		screen:initialise()
		screen:create()
		self:addChild(screen)
		screen:setVisible(false)
		self.betterWorkshop = screen
	end)
	if not ok then
		print("[BetterWorkshop] failed to create screen, using the vanilla Workshop wizard: " .. tostring(err))
		self.betterWorkshop = nil
	end
end

function WorkshopSubmitScreen:fillList()
	local screen = self.betterWorkshop
	if screen and not self.bwClassic then
		setVanillaPagesVisible(self, false)
		screen:setVisible(true)
		screen:aboutToShow(false)
		return
	end
	if screen then screen:setVisible(false) end
	vanilla.fillList(self)
end

function WorkshopSubmitScreen:onGainJoypadFocus(joypadData)
	local screen = self.betterWorkshop
	if screen and screen:isVisible() then
		ISPanelJoypad.onGainJoypadFocus(self, joypadData)
		joypadData.focus = screen
		updateJoypadFocus(joypadData)
		return
	end
	vanilla.onGainJoypadFocus(self, joypadData)
end

-- Leaving the classic wizard (its Back/Close buttons) returns to Better Workshop.
function WorkshopSubmitScreen:onButtonBack()
	local screen = self.betterWorkshop
	if screen and self.bwClassic then
		self.bwClassic = false
		setVanillaPagesVisible(self, false)
		screen:setVisible(true)
		-- The classic wizard may have rewritten workshop.txt files, so reload them.
		screen:aboutToShow(true)
		focusJoypad(screen)
		return
	end
	vanilla.onButtonBack(self)
end

-- Steam upload callbacks go to whichever screen started the upload.
if WorkshopSubmitScreen.TEST or getSteamModeActive() then
	local function reroute(eventName, vanillaHandler, method)
		local event = Events[eventName]
		if not event then return end
		event.Remove(vanillaHandler)
		event.Add(function (arg1, arg2)
			local host = WorkshopSubmitScreen.instance
			local screen = host and host.betterWorkshop
			if screen and screen.uploader:isWaiting() then
				screen.uploader[method](screen.uploader, arg1, arg2)
			else
				vanillaHandler(arg1, arg2)
			end
		end)
	end
	reroute("OnSteamWorkshopItemCreated", WorkshopSubmitScreen.OnSteamWorkshopItemCreated, "onItemCreated")
	reroute("OnSteamWorkshopItemNotCreated", WorkshopSubmitScreen.OnSteamWorkshopItemNotCreated, "onItemNotCreated")
	reroute("OnSteamWorkshopItemUpdated", WorkshopSubmitScreen.OnSteamWorkshopItemUpdated, "onItemUpdated")
	reroute("OnSteamWorkshopItemNotUpdated", WorkshopSubmitScreen.OnSteamWorkshopItemNotUpdated, "onItemNotUpdated")
end
