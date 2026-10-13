require "ISUI/ISPanelJoypad"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISScrollingListBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISRichTextPanel"
local BW = require "BWUtil"
local BWTagGrid = require "BWTagGrid"
local BWTextEditor = require "BWTextEditor"
local BWUploadPanel = require "BWUploadPanel"

local FONT_HGT_SMALL = BW.FONT_HGT_SMALL
local FONT_HGT_MEDIUM = BW.FONT_HGT_MEDIUM
local FONT_HGT_LARGE = BW.FONT_HGT_LARGE

local PAD = 16
local INNER = 10
local STATUS_LINES = 3
local CONTENT_LINES = 2
local NOTES_LINES = 3
local VALIDATIONS_PER_FRAME = 1

local BetterWorkshopScreen = ISPanelJoypad:derive("BetterWorkshopScreen")

-- callbacks = { onClose = fn, onClassic = fn }, provided by BetterWorkshop.lua
function BetterWorkshopScreen:new(x, y, width, height, callbacks)
	local o = ISPanelJoypad:new(x, y, width, height)
	setmetatable(o, self)
	self.__index = self
	o:noBackground()
	o.anchorRight = true
	o.anchorBottom = true
	o.callbacks = callbacks
	o.entries = {}
	o.drafts = {}
	o.changeNotes = {}
	o.steamDetails = {}
	o.validateQueue = {}
	o.descPreviewing = false
	o.lastSearch = ""
	o.copiedTicks = 0
	return o
end

-----------------------------------------------------------------------------
-- Construction
-----------------------------------------------------------------------------

function BetterWorkshopScreen:makeButton(title, onClick, small, minWidth)
	local hgt = small and (FONT_HGT_SMALL + 4) or math.max(25, FONT_HGT_SMALL + 3 * 2)
	local b = ISButton:new(0, 0, 100, hgt, title, self, onClick)
	b:initialise()
	b.borderColor = { r = 1, g = 1, b = 1, a = small and 0.25 or 0.1 }
	b:setWidthToTitle(minWidth or (small and 50 or 100))
	self:addChild(b)
	return b
end

function BetterWorkshopScreen:makeEntry(font, multiline)
	local entry = ISTextEntryBox:new("", 0, 0, 100, 20)
	entry.font = font
	entry:initialise()
	entry:instantiate()
	if multiline then
		entry:setMultipleLine(true)
		entry:setMaxLines(4096)
		entry:addScrollBars()
	end
	self:addChild(entry)
	return entry
end

function BetterWorkshopScreen:create()
	-- Header
	self.btnBrowse = self:makeButton(getText("UI_BetterWorkshop_BrowseWorkshop"), self.onButtonBrowse, false, 80)
	self.btnYourItems = self:makeButton(getText("UI_BetterWorkshop_YourItems"), self.onButtonYourItems, false, 80)
	self.btnOpenFolder = self:makeButton(getText("UI_BetterWorkshop_OpenFolder"), self.onButtonOpenFolder, false, 80)
	self.btnRefresh = self:makeButton(getText("UI_BetterWorkshop_Refresh"), self.onButtonRefresh, false, 80)
	for _, b in ipairs({ self.btnBrowse, self.btnYourItems, self.btnOpenFolder, self.btnRefresh }) do
		b.borderColor = { r = 1, g = 1, b = 1, a = 0.25 }
	end

	-- Item list
	self.searchEntry = self:makeEntry(UIFont.Small, false)
	self.searchEntry:setPlaceholderText(getText("UI_BetterWorkshop_Search"))
	self.searchEntry:setClearButton(true)

	self.listbox = ISScrollingListBox:new(0, 0, 100, 100)
	self.listbox:initialise()
	self.listbox:setFont("Small", 4)
	self.listbox.itemheight = math.max(48, FONT_HGT_SMALL * 3 + 10)
	self.listbox.drawBorder = true
	self.listbox.screen = self
	self.listbox.doDrawItem = BetterWorkshopScreen.doDrawListItem
	self.listbox:setOnMouseDownFunction(self, self.onSelectEntry)
	self.listbox.onJoypadDownInParent = function () return false end
	self:addChild(self.listbox)

	-- Details
	self.titleEntry = self:makeEntry(UIFont.Medium, false)
	self.idEntry = self:makeEntry(UIFont.Small, false)
	self.idEntry:setOnlyNumbers(true)
	self.idEntry:setPlaceholderText(getText("UI_BetterWorkshop_IdPlaceholder"))
	self.btnCopyId = self:makeButton(getText("UI_BetterWorkshop_Copy"), self.onButtonCopyId, true)
	self.btnCopyId:setWidth(
		math.max(self.btnCopyId.width, BW.measure(UIFont.Small, getText("UI_BetterWorkshop_Copied")) + 10)
	)

	self.visibilityCombo = ISComboBox:new(0, 0, 100, FONT_HGT_SMALL + 6)
	self.visibilityCombo:initialise()
	self.visibilityCombo:addOption(getText("UI_WorkshopSubmit_VisibilityPublic"))
	self.visibilityCombo:addOption(getText("UI_WorkshopSubmit_VisibilityFriendsOnly"))
	self.visibilityCombo:addOption(getText("UI_WorkshopSubmit_VisibilityPrivate"))
	self.visibilityCombo:addOption(getText("UI_WorkshopSubmit_VisibilityUnlisted"))
	self:addChild(self.visibilityCombo)

	self.btnDescEdit = self:makeButton(getText("UI_BetterWorkshop_Edit"), self.onButtonDescEdit, true)
	self.btnDescPreview = self:makeButton(getText("UI_BetterWorkshop_Preview"), self.onButtonDescPreview, true)
	self.btnDescExpand = self:makeButton(getText("UI_BetterWorkshop_Expand"), self.onButtonDescExpand, true)
	self.descEntry = self:makeEntry(UIFont.Small, true)

	self.descPreview = ISRichTextPanel:new(0, 0, 100, 100)
	self.descPreview:initialise()
	self.descPreview.autosetheight = false
	self.descPreview.clip = true
	self.descPreview.background = true
	self.descPreview.backgroundColor = { r = 0, g = 0, b = 0, a = 0.5 }
	self.descPreview.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
	self.descPreview:setMargins(8, 6, 20, 6)
	self:addChild(self.descPreview)
	self.descPreview:addScrollBars()
	self.descPreview:setVisible(false)

	self.tagGrid = BWTagGrid:new(0, 0, 100, 100)
	self.tagGrid:initialise()
	self.allowedTags = {}
	local allowed = SteamWorkshopItem.getAllowedTags()
	for i = 1, allowed:size() do
		table.insert(self.allowedTags, allowed:get(i - 1))
	end
	self.tagGrid:setTags(allowed)
	self:addChild(self.tagGrid)

	self.btnNotesExpand = self:makeButton(getText("UI_BetterWorkshop_Expand"), self.onButtonNotesExpand, true)
	self.notesEntry = self:makeEntry(UIFont.Small, true)
	self.notesEntry:setPlaceholderText(getText("UI_BetterWorkshop_NotesPlaceholder"))

	-- Footer
	self.btnBack = self:makeButton(getText("UI_btn_back"), self.onButtonBack)
	self.btnClassic = self:makeButton(getText("UI_BetterWorkshop_Classic"), self.onButtonClassic)
	self.btnClassic:setTooltip(getText("UI_BetterWorkshop_ClassicTooltip"))
	self.btnSave = self:makeButton(getText("UI_BetterWorkshop_Save"), self.onButtonSave)
	self.btnSave:setTooltip(getText("UI_BetterWorkshop_SaveTooltip"))
	self.btnUpload = self:makeButton(getText("UI_BetterWorkshop_PublishNew"), self.onButtonUpload)
	self.btnUpload.borderColor = { r = 1, g = 1, b = 1, a = 0.5 }
	local uploadW = math.max(
		BW.measure(UIFont.Small, getText("UI_BetterWorkshop_PublishNew")),
		BW.measure(UIFont.Small, getText("UI_BetterWorkshop_UploadUpdate"))
	)
		+ 20
	self.btnUpload:setWidth(math.max(120, uploadW))

	-- Overlays (added last so they sit on top)
	self.editor = BWTextEditor:new(0, 0, self.width, self.height)
	self.editor:initialise()
	self.editor:create()
	self:addChild(self.editor)
	self.editor:setVisible(false)

	self.uploader = BWUploadPanel:new(0, 0, self.width, self.height, self)
	self.uploader:initialise()
	self.uploader:create()
	self:addChild(self.uploader)
	self.uploader:setVisible(false)

	-- Controller navigation rows
	self.joypadIndexY = 1
	self.joypadIndex = 1
	self:insertNewLineOfButtons(self.btnBrowse, self.btnYourItems, self.btnOpenFolder, self.btnRefresh)
	self:insertNewLineOfButtons(self.searchEntry, self.titleEntry)
	self:insertNewLineOfButtons(self.listbox, self.idEntry, self.btnCopyId, self.visibilityCombo)
	self:insertNewLineOfButtons(self.btnDescEdit, self.btnDescPreview, self.btnDescExpand)
	self:insertNewLineOfButtons(self.tagGrid)
	self:insertNewLineOfButtons(self.btnNotesExpand)
	self:insertNewLineOfButtons(self.btnBack, self.btnClassic, self.btnSave, self.btnUpload)

	self:setDetailsVisible(false)
	self:layout()
end

-----------------------------------------------------------------------------
-- Layout (recomputed whenever the screen size or notes visibility changes)
-----------------------------------------------------------------------------

function BetterWorkshopScreen:layout()
	self.layoutW, self.layoutH = self.width, self.height
	local w, h = self.width, self.height
	local btnHgt = self.btnBack.height
	local smallHgt = self.btnDescEdit.height
	local L = {}
	self.L = L

	-- Header: title on the left, link buttons on the right
	L.titleY = 10
	local hy = L.titleY + (FONT_HGT_LARGE - btnHgt) / 2
	local hx = w - PAD
	for _, b in ipairs({ self.btnRefresh, self.btnOpenFolder, self.btnYourItems, self.btnBrowse }) do
		hx = hx - b.width
		b:setX(hx)
		b:setY(hy)
		hx = hx - 6
	end
	local bodyTop = L.titleY + FONT_HGT_LARGE + 12

	-- Footer: two lines of text in the middle, buttons on each side
	L.footerH = math.max(btnHgt, FONT_HGT_SMALL * 2 + 2)
	L.footerY = h - 5 - L.footerH
	local by = L.footerY + (L.footerH - btnHgt) / 2
	self.btnBack:setX(PAD)
	self.btnBack:setY(by)
	self.btnClassic:setX(self.btnBack:getRight() + 6)
	self.btnClassic:setY(by)
	self.btnUpload:setX(w - PAD - self.btnUpload.width)
	self.btnUpload:setY(by)
	self.btnSave:setX(self.btnUpload.x - 6 - self.btnSave.width)
	self.btnSave:setY(by)
	L.footerTextX = self.btnClassic:getRight() + 16
	L.footerTextW = self.btnSave.x - 16 - L.footerTextX
	local bodyBottom = L.footerY - 10

	-- Left column
	local listW = math.floor(math.min(380, math.max(240, w * 0.28)))
	local searchH = FONT_HGT_SMALL + 8
	self.searchEntry:setX(PAD)
	self.searchEntry:setY(bodyTop)
	self.searchEntry:setWidth(listW)
	self.searchEntry:setHeight(searchH)
	self.listbox:setX(PAD)
	self.listbox:setY(bodyTop + searchH + 4)
	self.listbox:setWidth(listW)
	self.listbox:setHeight(bodyBottom - self.listbox.y)

	-- Right pane frame
	L.paneX = PAD + listW + 12
	L.paneY = bodyTop
	L.paneW = w - PAD - L.paneX
	L.paneH = bodyBottom - bodyTop
	local ix = L.paneX + INNER
	local iw = L.paneW - INNER * 2
	local y = L.paneY + INNER

	-- Preview image + fields beside it
	L.previewSize = (h < 720) and 96 or 128
	L.previewX, L.previewY = ix, y
	local fx = ix + L.previewSize + 8 + 12
	local fw = ix + iw - fx
	L.fieldsX = fx
	L.titleLabelY = y
	self.titleEntry:setX(fx)
	self.titleEntry:setY(y + FONT_HGT_SMALL + 2)
	self.titleEntry:setWidth(fw)
	self.titleEntry:setHeight(FONT_HGT_MEDIUM + 4)

	local halfW = math.floor((fw - 12) / 2)
	L.idLabelY = self.titleEntry:getBottom() + 6
	local entryY = L.idLabelY + FONT_HGT_SMALL + 2
	local smallEntryH = FONT_HGT_SMALL + 6
	self.btnCopyId:setX(fx + halfW - self.btnCopyId.width)
	self.btnCopyId:setY(entryY + (smallEntryH - self.btnCopyId.height) / 2)
	self.idEntry:setX(fx)
	self.idEntry:setY(entryY)
	self.idEntry:setWidth(halfW - self.btnCopyId.width - 4)
	self.idEntry:setHeight(smallEntryH)
	L.visibilityX = fx + halfW + 12
	self.visibilityCombo:setX(L.visibilityX)
	self.visibilityCombo:setY(entryY)
	self.visibilityCombo:setWidth(fw - halfW - 12)
	self.visibilityCombo:setHeight(smallEntryH)
	L.steamY = entryY + smallEntryH + 6
	L.fieldsW = fw

	y = math.max(L.previewY + L.previewSize + 8, L.steamY + FONT_HGT_SMALL) + 8

	-- Status banner
	L.statusY = y
	L.statusH = STATUS_LINES * FONT_HGT_SMALL + 8
	L.innerX, L.innerW = ix, iw
	y = y + L.statusH + 8

	-- Contents
	L.contentsLabelY = y
	L.contentsY = y + FONT_HGT_SMALL + 2
	L.contentsH = CONTENT_LINES * FONT_HGT_SMALL + 8
	y = L.contentsY + L.contentsH + 8

	-- Description header row
	L.descLabelY = y + (smallHgt - FONT_HGT_SMALL) / 2
	self.btnDescExpand:setX(ix + iw - self.btnDescExpand.width)
	self.btnDescExpand:setY(y)
	self.btnDescPreview:setX(self.btnDescExpand.x - 12 - self.btnDescPreview.width)
	self.btnDescPreview:setY(y)
	self.btnDescEdit:setX(self.btnDescPreview.x - 4 - self.btnDescEdit.width)
	self.btnDescEdit:setY(y)
	local descTop = y + smallHgt + 4

	-- Bottom-up: change notes, then tags, then the description takes what's left
	local bottom = L.paneY + L.paneH - INNER
	L.showNotes = self:selectedHasID()
	self.notesEntry:setVisible(L.showNotes and self.selected ~= nil)
	self.btnNotesExpand:setVisible(L.showNotes and self.selected ~= nil)
	if L.showNotes then
		local notesH = NOTES_LINES * FONT_HGT_SMALL + 8
		self.notesEntry:setX(ix)
		self.notesEntry:setY(bottom - notesH)
		self.notesEntry:setWidth(iw)
		self.notesEntry:setHeight(notesH)
		BW.fitScrollBars(self.notesEntry)
		local rowY = self.notesEntry.y - 4 - smallHgt
		self.btnNotesExpand:setX(ix + iw - self.btnNotesExpand.width)
		self.btnNotesExpand:setY(rowY)
		L.notesLabelY = rowY + (smallHgt - FONT_HGT_SMALL) / 2
		bottom = rowY - 8
	end

	self.tagGrid:setColumns(math.max(3, math.floor(iw / 160)))
	local tagsH = self.tagGrid:getRequiredHeight()
	self.tagGrid:setX(ix)
	self.tagGrid:setY(bottom - tagsH)
	self.tagGrid:setWidth(iw)
	self.tagGrid:setHeight(tagsH)
	L.tagsLabelY = self.tagGrid.y - 2 - FONT_HGT_SMALL
	bottom = L.tagsLabelY - 8

	local descH = math.max(FONT_HGT_SMALL * 3 + 8, bottom - descTop)
	for _, ui in ipairs({ self.descEntry, self.descPreview }) do
		ui:setX(ix)
		ui:setY(descTop)
		ui:setWidth(iw)
		ui:setHeight(descH)
		BW.fitScrollBars(ui)
	end
	self.descPreview.textDirty = true
end

function BetterWorkshopScreen:setDetailsVisible(visible)
	for _, ui in ipairs({
		self.titleEntry,
		self.idEntry,
		self.btnCopyId,
		self.visibilityCombo,
		self.btnDescEdit,
		self.btnDescPreview,
		self.btnDescExpand,
		self.tagGrid
	}) do
		ui:setVisible(visible)
	end
	self.descEntry:setVisible(visible and not self.descPreviewing)
	self.descPreview:setVisible(visible and self.descPreviewing)
	-- Change notes only exist for items with an ID; layout() positions them.
	local showNotes = visible and self:selectedHasID()
	self.notesEntry:setVisible(showNotes)
	self.btnNotesExpand:setVisible(showNotes)
	if visible and self.L and showNotes ~= self.L.showNotes then self:layout() end
end

-----------------------------------------------------------------------------
-- Data
-----------------------------------------------------------------------------

local function visibilityIndex(visibility)
	for i, v in ipairs(BW.VISIBILITY) do
		if v == visibility then return i end
	end
	return 1
end

function BetterWorkshopScreen:draftFromItem(item)
	local tags = {}
	local itemTags = item:getTags()
	for i = 1, itemTags:size() do
		tags[itemTags:get(i - 1)] = true
	end
	return {
		title = item:getTitle() or "",
		description = item:getDescription() or "",
		visibility = visibilityIndex(item:getVisibility()),
		id = item:getID() or "",
		tags = tags
	}
end

function BetterWorkshopScreen:getDraft(entry)
	local draft = self.drafts[entry.folder]
	if not draft then
		draft = self:draftFromItem(entry.item)
		self.drafts[entry.folder] = draft
	end
	return draft
end

-- The multi-line text box can hand text back with different line endings or
-- trailing whitespace; neither counts as a change.
local CR = string.char(13)
local function sameText(a, b)
	a = string.gsub(string.gsub(a or "", CR, ""), "%s+$", "")
	b = string.gsub(string.gsub(b or "", CR, ""), "%s+$", "")
	return a == b
end

function BetterWorkshopScreen:isDirty(entry)
	local d = self.drafts[entry.folder]
	if not d then return false end
	local item = entry.item
	if not sameText(d.title, item:getTitle()) then return true end
	if not sameText(d.description, item:getDescription()) then return true end
	if d.visibility ~= visibilityIndex(item:getVisibility()) then return true end
	if d.id ~= (item:getID() or "") then return true end
	local itemTags = item:getTags()
	local count = 0
	for _, on in pairs(d.tags) do
		if on then count = count + 1 end
	end
	if count ~= itemTags:size() then return true end
	for i = 1, itemTags:size() do
		if not d.tags[itemTags:get(i - 1)] then return true end
	end
	return false
end

function BetterWorkshopScreen:getDisplayName(entry)
	local d = self.drafts[entry.folder]
	local title = BW.trim(d and d.title or entry.item:getTitle())
	if title == "" then return entry.folder end
	return title
end

-- Returns kind ("pending"|"error"|"warn"|"ok"), a short label for the list and a full sentence.
function BetterWorkshopScreen:getStatus(entry)
	if not entry.checked then
		local t = getText("UI_BetterWorkshop_Checking")
		return "pending", t, t
	end
	if entry.err then
		local short = BW.textOr("UI_BetterWorkshop_Err_" .. entry.err, "UI_BetterWorkshop_Err_Generic")
		local long = string.gsub(
			getText("UI_WorkshopError_" .. entry.err, entry.item:getExtendedErrorInfo(entry.err)), "\\n", "\n"
		)
		return "error", short, long
	end
	local d = self.drafts[entry.folder]
	local title = d and d.title or entry.item:getTitle()
	local desc = d and d.description or entry.item:getDescription()
	if BW.trim(title) == "" then
		return "error", getText("UI_BetterWorkshop_NeedsTitle"), getText("UI_BetterWorkshop_NeedsTitleLong")
	end
	if BW.trim(desc) == "" then
		return "error", getText("UI_BetterWorkshop_NeedsDescription"), getText("UI_BetterWorkshop_NeedsDescriptionLong")
	end
	if d and d.id ~= "" and not isValidSteamID(d.id) then
		return "error", getText("UI_BetterWorkshop_InvalidId"), getText("UI_BetterWorkshop_InvalidIdLong")
	end
	if self:isDirty(entry) then
		return "warn", getText("UI_BetterWorkshop_Unsaved"), getText("UI_BetterWorkshop_UnsavedLong")
	end
	return "ok", getText("UI_BetterWorkshop_Ready"), getText("UI_BetterWorkshop_ReadyLong")
end

function BetterWorkshopScreen:statusColor(kind)
	if kind == "error" then return BW.COLOR_BAD end
	if kind == "warn" then return BW.COLOR_WARN end
	if kind == "ok" then return BW.COLOR_GOOD end
	return BW.COLOR_MUTED
end

function BetterWorkshopScreen:validateEntry(entry)
	entry.err = entry.item:validateContents()
	entry.checked = true
end

-- Mods inside Contents/mods, found through the game's own mod scan
-- (staged Workshop folders are part of it).
function BetterWorkshopScreen:collectModInfos()
	local found = {}
	local dirs = getModDirectoryTable()
	local workshopPrefix = BW.normPath(BW.workshopFolder())
	for _, dir in ipairs(dirs) do
		local norm = BW.normPath(dir)
		if string.sub(norm, 1, #workshopPrefix) == workshopPrefix then
			local info = getModInfo(dir)
			if info then
				table.insert(found, { dir = norm, info = info })
			end
		end
	end
	return found
end

local function describeMod(mod)
	local info = mod.info
	local folder = string.match(mod.dir, "([^/]+)/*$") or mod.dir
	local parts = { "mods/" .. folder, "id " .. tostring(info:getId()) }
	local version = info:getModVersion()
	if version and version ~= "" then table.insert(parts, "v" .. version) end
	local vmin = info:getVersionMin()
	if vmin then
		table.insert(parts, "B" .. tostring(vmin:getMajor()) .. "." .. tostring(vmin:getMinor()) .. "+")
	end
	return table.concat(parts, "  -  ")
end

function BetterWorkshopScreen:refresh(clearDrafts)
	if clearDrafts then
		self.drafts = {}
	end
	local keepFolder = self.selected and self.selected.folder
	self.selected = nil
	self.entries = {}
	self.validateQueue = {}

	local modInfos = self:collectModInfos()
	local staged = getSteamWorkshopStagedItems()
	for i = 1, staged:size() do
		local item = staged:get(i - 1)
		local entry = { item = item, folder = item:getFolderName(), checked = false, mods = {} }
		local prefix = BW.normPath(item:getContentFolder()) .. "/mods/"
		for _, mod in ipairs(modInfos) do
			if string.sub(mod.dir, 1, #prefix) == prefix then
				table.insert(entry.mods, describeMod(mod))
			end
		end
		table.insert(self.entries, entry)
		table.insert(self.validateQueue, entry)
	end
	table.sort(self.entries, function (a, b)
		return string.lower(self:getDisplayName(a)) < string.lower(self:getDisplayName(b))
	end)

	self:querySteamDetails()
	self:rebuildList()

	local select = nil
	for _, entry in ipairs(self.entries) do
		if entry.folder == keepFolder then select = entry end
	end
	select = select or self.entries[1]
	if select then
		self:onSelectEntry(select)
	else
		self:setDetailsVisible(false)
		self:layout()
	end
end

function BetterWorkshopScreen:rebuildList()
	local filter = string.lower(BW.trim(self.searchEntry:getText()))
	self.lastSearch = self.searchEntry:getText()
	self.listbox:clear()
	self.listbox.selected = -1
	for _, entry in ipairs(self.entries) do
		local id = entry.item:getID() or ""
		local haystack = string.lower(self:getDisplayName(entry) .. " " .. entry.folder .. " " .. id)
		if filter == "" or string.find(haystack, filter, 1, true) then
			self.listbox:addItem(self:getDisplayName(entry), entry)
			if entry == self.selected then
				self.listbox.selected = #self.listbox.items
			end
		end
	end
end

function BetterWorkshopScreen:querySteamDetails()
	local ids = ArrayList.new()
	for _, entry in ipairs(self.entries) do
		local id = entry.item:getID()
		if id and self.steamDetails[id] == nil then
			ids:add(id)
			self.steamDetails[id] = "pending"
		end
	end
	if ids:isEmpty() then return end
	querySteamWorkshopItemDetails(ids, BetterWorkshopScreen.onSteamDetails, self)
end

function BetterWorkshopScreen:onSteamDetails(status, info)
	if status == "Completed" and info then
		for i = 1, info:size() do
			local details = info:get(i - 1)
			self.steamDetails[details:getIDString()] = { updated = details:getTimeUpdated(), size = details:getFileSize() }
		end
	end
	if status ~= "Completed" and status ~= "NotCompleted" then return end
	for id, value in pairs(self.steamDetails) do
		if value == "pending" then self.steamDetails[id] = "failed" end
	end
end

-----------------------------------------------------------------------------
-- Selection and editing
-----------------------------------------------------------------------------

function BetterWorkshopScreen:selectedHasID()
	local e = self.selected
	if not e then return false end
	if e.item:getID() then return true end
	local d = self.drafts[e.folder]
	return d ~= nil and d.id ~= "" and isValidSteamID(d.id)
end

-- Copies what's in the widgets into the selected entry's draft.
function BetterWorkshopScreen:syncDraft()
	local e = self.selected
	if not e then return end
	local d = self:getDraft(e)
	d.title = self.titleEntry:getText()
	d.description = self.descEntry:getText()
	d.visibility = self.visibilityCombo.selected
	if not e.item:getID() then
		d.id = BW.trim(self.idEntry:getText())
	end
	self.changeNotes[e.folder] = self.notesEntry:getText()
end

function BetterWorkshopScreen:onSelectEntry(entry)
	if not entry then return end
	if entry == self.selected then return end
	self:syncDraft()
	self.selected = entry
	if not entry.checked then self:validateEntry(entry) end

	local d = self:getDraft(entry)
	self.titleEntry:setText(d.title)
	self.descEntry:setText(d.description)
	BW.resetScroll(self.descEntry)
	self.idEntry:setText(d.id)
	self.idEntry:setEditable(entry.item:getID() == nil)
	self.visibilityCombo.selected = d.visibility
	self.tagGrid:setCheckedMap(d.tags)
	self.notesEntry:setText(self.changeNotes[entry.folder] or "")
	BW.resetScroll(self.notesEntry)

	for i, item in ipairs(self.listbox.items) do
		if item.item == entry then
			self.listbox.selected = i
			self.listbox:ensureVisible(i)
		end
	end

	self:setDetailsVisible(true)
	if self.descPreviewing then self:updateDescPreview() end
	self:layout()
end

function BetterWorkshopScreen:updateDescPreview()
	self.descPreview.text = BW.bbcodeToRichText(self.descEntry:getText())
	self.descPreview:paginate()
	self.descPreview:setYScroll(0)
end

function BetterWorkshopScreen:setDescPreviewing(previewing)
	self.descPreviewing = previewing
	if previewing then self:updateDescPreview() end
	self:setDetailsVisible(self.selected ~= nil)
	self.btnDescEdit.backgroundColor = previewing and { r = 0, g = 0, b = 0, a = 1 }
		or { r = 0.3, g = 0.3, b = 0.3, a = 1 }
	self.btnDescPreview.backgroundColor = previewing and { r = 0.3, g = 0.3, b = 0.3, a = 1 }
		or { r = 0, g = 0, b = 0, a = 1 }
end

function BetterWorkshopScreen:saveEntry(entry)
	if entry == self.selected then self:syncDraft() end
	local d = self.drafts[entry.folder]
	if not d then return end
	local item = entry.item
	item:setTitle(d.title)
	item:setDescription(d.description)
	item:setTags(BWTagGrid.toArrayList(d.tags, self.allowedTags))
	item:setVisibilityInteger(d.visibility - 1)
	if not item:getID() and d.id ~= "" and isValidSteamID(d.id) then
		item:setID(d.id)
	end
	item:writeWorkshopTxt()
	-- Keep the draft in step with what was written (e.g. a rejected ID).
	d.id = item:getID() or ""
	if entry == self.selected then
		self.idEntry:setText(d.id)
		self.idEntry:setEditable(item:getID() == nil)
	end
	if item:getID() and self.steamDetails[item:getID()] == nil then
		self:querySteamDetails()
	end
	self:layout()
end

-- Steam assigned an ID to a newly created item (mid-upload).
function BetterWorkshopScreen:onItemIdAssigned(entry)
	local id = entry.item:getID() or ""
	local d = self.drafts[entry.folder]
	if d then d.id = id end
	if entry == self.selected then
		self.idEntry:setText(id)
		self.idEntry:setEditable(false)
	end
	self:layout()
end

function BetterWorkshopScreen:onUploadFinished(entry, success)
	local d = self.drafts[entry.folder]
	if d then d.id = entry.item:getID() or "" end
	if entry == self.selected then
		self.idEntry:setText(entry.item:getID() or "")
		self.idEntry:setEditable(entry.item:getID() == nil)
		if success then self.notesEntry:setText("") end
	end
	if success then
		self.changeNotes[entry.folder] = ""
		entry.item:setChangeNote("")
	end
	local id = entry.item:getID()
	if id then
		self.steamDetails[id] = nil
		self:querySteamDetails()
	end
	self:layout()
end

-----------------------------------------------------------------------------
-- Buttons
-----------------------------------------------------------------------------

function BetterWorkshopScreen:onButtonBrowse()
	if isSteamOverlayEnabled() then
		activateSteamOverlayToWorkshop()
	else
		openUrl("https://steamcommunity.com/app/108600/workshop/")
	end
end

function BetterWorkshopScreen:onButtonYourItems()
	if isSteamOverlayEnabled() then
		activateSteamOverlayToWorkshopUser()
	else
		openUrl("https://steamcommunity.com/my/myworkshopfiles/?appid=108600")
	end
end

function BetterWorkshopScreen:onButtonOpenFolder()
	local folder = BW.workshopFolder()
	if self.selected then
		local content = self.selected.item:getContentFolder()
		folder = string.sub(content, 1, #content - #"Contents" - 1)
	end
	showFolderInDesktop(folder)
end

function BetterWorkshopScreen:onButtonRefresh()
	self:syncDraft()
	self:refresh(false)
end

function BetterWorkshopScreen:onButtonCopyId()
	local id = self.selected and self.selected.item:getID()
	if not id then return end
	Clipboard.setClipboard(id)
	self.btnCopyId:setTitle(getText("UI_BetterWorkshop_Copied"))
	self.copiedTicks = 90
end

function BetterWorkshopScreen:onButtonDescEdit()
	self:setDescPreviewing(false)
end
function BetterWorkshopScreen:onButtonDescPreview()
	self:setDescPreviewing(true)
end

function BetterWorkshopScreen:onButtonDescExpand()
	self.editor:open(getText("UI_WorkshopSubmit_TitleEditDescription"), self.descEntry:getText(), true, self, function (
		screen, text
	)
		screen.descEntry:setText(text)
		if screen.descPreviewing then screen:updateDescPreview() end
	end)
end

function BetterWorkshopScreen:onButtonNotesExpand()
	self.editor:open(
		getText("UI_WorkshopSubmit_TitleEditChangeNotes"), self.notesEntry:getText(), true, self,
		function (screen, text) screen.notesEntry:setText(text) end
	)
end

function BetterWorkshopScreen:onButtonBack()
	self:syncDraft()
	self.callbacks.onClose()
end

function BetterWorkshopScreen:onButtonClassic()
	self:syncDraft()
	self.callbacks.onClassic()
end

function BetterWorkshopScreen:onButtonSave()
	if not self.selected then return end
	self:saveEntry(self.selected)
end

function BetterWorkshopScreen:onButtonUpload()
	local entry = self.selected
	if not entry then return end
	self:syncDraft()
	if not entry.checked then self:validateEntry(entry) end
	local kind = self:getStatus(entry)
	if kind == "error" or kind == "pending" then return end
	self:saveEntry(entry)
	entry.item:setChangeNote(self.changeNotes[entry.folder] or "")
	self.uploader:start(entry)
end

function BetterWorkshopScreen:onMouseDown(x, y)
	local link = self.legalLink
	if link and x >= link.x and x <= link.x + link.w and y >= link.y and y <= link.y + link.h then
		if isSteamOverlayEnabled() then
			activateSteamOverlayToWebPage("https://steamcommunity.com/sharedfiles/workshoplegalagreement")
		else
			openUrl("https://steamcommunity.com/sharedfiles/workshoplegalagreement")
		end
		return true
	end
	return ISPanelJoypad.onMouseDown(self, x, y)
end

-----------------------------------------------------------------------------
-- Showing
-----------------------------------------------------------------------------

function BetterWorkshopScreen:aboutToShow(clearDrafts)
	self.uploader:setVisible(false)
	self.editor:setVisible(false)
	self:refresh(clearDrafts)
	self:setDescPreviewing(self.descPreviewing)
end

-----------------------------------------------------------------------------
-- Per-frame update and drawing
-----------------------------------------------------------------------------

function BetterWorkshopScreen:prerender()
	if self.layoutW ~= self.width or self.layoutH ~= self.height then
		self:layout()
	end

	-- Check a few items per frame so large Workshop folders don't stall the menu.
	local checked = 0
	while checked < VALIDATIONS_PER_FRAME and #self.validateQueue > 0 do
		local entry = table.remove(self.validateQueue, 1)
		if not entry.checked then
			self:validateEntry(entry)
			checked = checked + 1
		end
	end

	if self.searchEntry:getText() ~= self.lastSearch then
		self:syncDraft()
		self:rebuildList()
	end

	if self.selected and not self.uploader:isVisible() and not self.editor:isVisible() then
		self:syncDraft()
		local hasID = self:selectedHasID()
		if hasID ~= self.L.showNotes then self:layout() end
	end

	if self.copiedTicks > 0 then
		self.copiedTicks = self.copiedTicks - 1
		if self.copiedTicks == 0 then self.btnCopyId:setTitle(getText("UI_BetterWorkshop_Copy")) end
	end

	BW.keepCursorVisible(self.descEntry)
	BW.keepCursorVisible(self.notesEntry)
	self:updateButtons()
	ISPanelJoypad.prerender(self)
	-- Drawn here, not in render(): render() runs after child widgets and would
	-- paint over them and over the editor/upload overlays.
	self:drawScreen()
end

function BetterWorkshopScreen:updateButtons()
	local e = self.selected
	local kind = e and self:getStatus(e) or "error"
	self.btnUpload:setTitle(
		self:selectedHasID() and getText("UI_BetterWorkshop_UploadUpdate") or getText("UI_BetterWorkshop_PublishNew")
	)
	self.btnUpload:setEnable(e ~= nil and kind ~= "error" and kind ~= "pending")
	self.btnSave:setEnable(e ~= nil and self:isDirty(e))
	self.btnCopyId:setEnable(e ~= nil and e.item:getID() ~= nil)
	self.btnOpenFolder:setTooltip(
		e and getText("UI_BetterWorkshop_OpenFolderItem") or getText("UI_BetterWorkshop_OpenFolderAll")
	)
end

function BetterWorkshopScreen:drawLabel(text, x, y)
	local c = BW.COLOR_LABEL
	self:drawText(text, x, y, c.r, c.g, c.b, 1, UIFont.Small)
end

function BetterWorkshopScreen:drawScreen()
	local L = self.L

	self:drawText(getText("UI_BetterWorkshop_Header"), PAD, L.titleY, 1, 1, 1, 1, UIFont.Large)

	-- Right pane frame
	self:drawRect(L.paneX, L.paneY, L.paneW, L.paneH, 0.3, 0, 0, 0)
	self:drawRectBorder(L.paneX, L.paneY, L.paneW, L.paneH, 0.9, 0.4, 0.4, 0.4)

	-- Footer text: fullscreen warning and the Workshop legal line
	local mid = L.footerTextX + L.footerTextW / 2
	local fy = L.footerY + (L.footerH - FONT_HGT_SMALL * 2 - 2) / 2
	local warn = BW.truncate(UIFont.Small, getText("UI_BetterWorkshop_FullscreenWarning"), L.footerTextW)
	self:drawTextCentre(warn, mid, fy, 0.85, 0.6, 0.55, 1, UIFont.Small)
	local legal1 = getText("UI_WorkshopSubmit_Legal1") .. " "
	local legal2 = getText("UI_WorkshopSubmit_Legal2")
	local w1, w2 = BW.measure(UIFont.Small, legal1), BW.measure(UIFont.Small, legal2)
	local lx = mid - (w1 + w2) / 2
	local ly = fy + FONT_HGT_SMALL + 2
	self:drawText(legal1, lx, ly, 0.7, 0.7, 0.7, 1, UIFont.Small)
	self:drawText(legal2, lx + w1, ly, BW.COLOR_LINK.r, BW.COLOR_LINK.g, BW.COLOR_LINK.b, 1, UIFont.Small)
	self.legalLink = { x = lx + w1, y = ly, w = w2, h = FONT_HGT_SMALL }

	local e = self.selected
	if not e then
		local msg = (#self.entries == 0) and getText("UI_BetterWorkshop_NoItems", BW.workshopFolder())
			or getText("UI_BetterWorkshop_SelectItem")
		local lines = BW.wrap(UIFont.Medium, msg, L.paneW - 40)
		local y = L.paneY + L.paneH / 3
		for _, line in ipairs(lines) do
			self:drawTextCentre(line, L.paneX + L.paneW / 2, y, 0.8, 0.8, 0.8, 1, UIFont.Medium)
			y = y + FONT_HGT_MEDIUM
		end
		return
	end

	-- Preview image
	local ps = L.previewSize
	self:drawRect(L.previewX, L.previewY, ps + 8, ps + 8, 1, 0.12, 0.12, 0.12)
	self:drawRectBorder(L.previewX, L.previewY, ps + 8, ps + 8, 1, 0.4, 0.4, 0.4)
	self:drawRectBorder(L.previewX + 1, L.previewY + 1, ps + 6, ps + 6, 1, 0.4, 0.4, 0.4)
	local tex = self:getPreviewTexture(e)
	if tex then
		self:drawTextureScaledAspect(tex, L.previewX + 4, L.previewY + 4, ps, ps, 1, 1, 1, 1)
	else
		self:drawTextCentre(
			getText("UI_BetterWorkshop_NoPreview"), L.previewX + (ps + 8) / 2,
			L.previewY + (ps + 8 - FONT_HGT_SMALL) / 2, 0.5, 0.5, 0.5, 1, UIFont.Small
		)
	end

	-- Field labels
	self:drawLabel(getText("UI_BetterWorkshop_Title"), L.fieldsX, L.titleLabelY)
	self:drawLabel(getText("UI_BetterWorkshop_WorkshopId"), L.fieldsX, L.idLabelY)
	self:drawLabel(getText("UI_BetterWorkshop_Visibility"), L.visibilityX, L.idLabelY)
	self:drawText(
		BW.truncate(UIFont.Small, self:getSteamLine(e), L.fieldsW), L.fieldsX, L.steamY, 0.55, 0.55, 0.55, 1,
		UIFont.Small
	)

	-- Status banner
	local kind, _, long = self:getStatus(e)
	local c = self:statusColor(kind)
	self:drawRect(L.innerX, L.statusY, L.innerW, L.statusH, 0.18, c.r, c.g, c.b)
	self:drawRectBorder(L.innerX, L.statusY, L.innerW, L.statusH, 0.6, c.r, c.g, c.b)
	local lines = BW.wrap(UIFont.Small, long, L.innerW - 16)
	local ty = L.statusY + 4
	for i = 1, math.min(#lines, STATUS_LINES) do
		self:drawText(lines[i], L.innerX + 8, ty, c.r, c.g, c.b, 1, UIFont.Small)
		ty = ty + FONT_HGT_SMALL
	end

	-- Contents
	self:drawLabel(getText("UI_BetterWorkshop_Contents"), L.innerX, L.contentsLabelY)
	self:drawRectBorder(L.innerX, L.contentsY, L.innerW, L.contentsH, 1, 0.3, 0.3, 0.3)
	local cy = L.contentsY + 4
	if #e.mods == 0 then
		self:drawText(getText("UI_BetterWorkshop_NoMods"), L.innerX + 6, cy, 0.55, 0.55, 0.55, 1, UIFont.Small)
	else
		for i = 1, math.min(#e.mods, CONTENT_LINES) do
			local text = e.mods[i]
			if i == CONTENT_LINES and #e.mods > CONTENT_LINES then
				text = getText("UI_BetterWorkshop_MoreMods", tostring(#e.mods - CONTENT_LINES + 1))
			end
			self:drawText(
				BW.truncate(UIFont.Small, text, L.innerW - 12), L.innerX + 6, cy, 0.8, 0.8, 0.8, 1, UIFont.Small
			)
			cy = cy + FONT_HGT_SMALL
		end
	end

	self:drawLabel(getText("UI_BetterWorkshop_Description"), L.innerX, L.descLabelY)
	self:drawLabel(getText("UI_BetterWorkshop_Tags"), L.innerX, L.tagsLabelY)
	if L.showNotes then
		self:drawLabel(getText("UI_BetterWorkshop_ChangeNotes"), L.innerX, L.notesLabelY)
	end
end

function BetterWorkshopScreen:getPreviewTexture(entry)
	if not entry.checked then return nil end
	if entry.err == "PreviewNotFound" or entry.err == "PreviewFormat" or entry.err == "MissingContents" then
		return nil
	end
	if not entry.textureTried then
		entry.textureTried = true
		entry.texture = getTexture(entry.item:getPreviewImage())
	end
	return entry.texture
end

function BetterWorkshopScreen:getSteamLine(entry)
	local id = entry.item:getID()
	if not id then return getText("UI_BetterWorkshop_SteamNew") end
	local details = self.steamDetails[id]
	if details == "pending" or details == nil then return getText("UI_BetterWorkshop_SteamChecking") end
	if details == "failed" then return getText("UI_BetterWorkshop_SteamUnavailable") end
	return getText("UI_BetterWorkshop_SteamDetails", BW.formatDate(details.updated), BW.formatSize(details.size))
end

-- Drawn with self = the listbox.
function BetterWorkshopScreen.doDrawListItem(self, y, item, alt)
	local h = self.itemheight
	local scrollY = self:getYScroll()
	if y + scrollY + h < 0 or y + scrollY > self.height then
		return y + h
	end
	local screen = self.screen
	local entry = item.item
	local w = self:getWidth()
	if self:isVScrollBarVisible() then w = w - 13 end

	if self.selected == item.index then
		self:drawRect(0, y, w, h - 1, 0.3, 0.7, 0.35, 0.15)
	elseif self.mouseoverselected == item.index then
		self:drawRect(0, y, w, h - 1, 0.1, 1, 1, 1)
	end
	self:drawRect(0, y + h - 1, w, 1, 0.5, 0.3, 0.3, 0.3)

	local thumb = h - 12
	local tx, ty = 6, y + 6
	self:drawRect(tx, ty, thumb, thumb, 1, 0.12, 0.12, 0.12)
	local tex = screen:getPreviewTexture(entry)
	if tex then
		self:drawTextureScaledAspect(tex, tx, ty, thumb, thumb, 1, 1, 1, 1)
	end
	self:drawRectBorder(tx, ty, thumb, thumb, 0.8, 0.4, 0.4, 0.4)

	local textX = tx + thumb + 8
	local textW = w - textX - 6
	local lineY = y + (h - FONT_HGT_SMALL * 3) / 2
	local name = BW.truncate(UIFont.Small, screen:getDisplayName(entry), textW)
	self:drawText(name, textX, lineY, 1, 1, 1, 1, UIFont.Small)

	local id = entry.item:getID()
	local sub = id and getText("UI_BetterWorkshop_Published", id) or getText("UI_BetterWorkshop_NotPublished")
	local g = id and 0.7 or 0.5
	self:drawText(BW.truncate(UIFont.Small, sub, textW), textX, lineY + FONT_HGT_SMALL, g, g, g, 1, UIFont.Small)

	local kind, short = screen:getStatus(entry)
	local c = screen:statusColor(kind)
	self:drawText(
		BW.truncate(UIFont.Small, short, textW), textX, lineY + FONT_HGT_SMALL * 2, c.r, c.g, c.b, 1, UIFont.Small
	)

	return y + h
end

-----------------------------------------------------------------------------
-- Controller
-----------------------------------------------------------------------------

function BetterWorkshopScreen:onGainJoypadFocus(joypadData)
	ISPanelJoypad.onGainJoypadFocus(self, joypadData)
	self:setISButtonForB(self.btnBack)
	if not self:getJoypadFocus() then
		self:setJoypadFocusTopLeft(joypadData)
	else
		self:restoreJoypadFocus(joypadData)
	end
end

function BetterWorkshopScreen:onJoypadDirUp(joypadData)
	if self:getJoypadFocus() == self.listbox and self.listbox.selected > 1 then
		self.listbox:onJoypadDirUp()
		return
	end
	ISPanelJoypad.onJoypadDirUp(self, joypadData)
end

function BetterWorkshopScreen:onJoypadDirDown(joypadData)
	if self:getJoypadFocus() == self.listbox and self.listbox.selected < #self.listbox.items then
		self.listbox:onJoypadDirDown()
		return
	end
	ISPanelJoypad.onJoypadDirDown(self, joypadData)
end

return BetterWorkshopScreen
