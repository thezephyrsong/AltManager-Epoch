-- Initialization
AltManager = LibStub("AceAddon-3.0"):NewAddon("AltManager", "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
local L = LibStub('AceLocale-3.0'):GetLocale('AltManager')
local LDB = LibStub("LibDataBroker-1.1", true)
local LDBIcon = LDB and LibStub("LibDBIcon-1.0", true)
local AMConfig = LibStub("AceConfig-3.0")
local AMConfigDialog = LibStub("AceConfigDialog-3.0")
local quixote = LibStub("LibQuixote-2.0")
local me = GetUnitName("Player").." - "..GetRealmName()

------------------------------------------------------------------------
-- Static Server Reset Definitions
------------------------------------------------------------------------
-- Days: 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat
local WEEKLY_RESET_DAY  = 3  -- Tuesday (Corrected to standard Lua calendar index 3)
local WEEKLY_RESET_HOUR = 8  -- 8:00 AM
local DAILY_RESET_HOUR  = 8  -- 8:00 AM
local ONY_RESET_CYCLE   = 5 * 86400 -- 5 days in seconds

-- UPSTREAM TASK DEFINITION TRACKS (Placed here so all functions below can see it)
local tasks = {
	Ony25 = { done = -1, type = "fiveday", isDaily = false, levelRequire = 60 }, -- Custom 5-day lock for Onyxia
	MC10 = { done = -1, type = "weekly", isDaily = false, levelRequire = 60 },
	BWL10 = { done = -1, type = "weekly", isDaily = false, levelRequire = 60 },
	ZG = { done = -1, type = "threeday", isDaily = false, levelRequire = 60 },
	AQ20 = { done = -1, type = "threeday", isDaily = false, levelRequire = 60 },
	AQ40 = { done = -1, type = "weekly", isDaily = false, levelRequire = 60 },
	Naxx = { done = -1, type = "weekly", isDaily = false, levelRequire = 60 },
	BGDaily = { done = false, type = "daily", isDaily = true, levelRequire = 10 },
}

local function GetCharProfile(name)
	name = name or me
	if not AltManager.db.global.chars[name] then
		AltManager.db.global.chars[name] = {}
	end
	return AltManager.db.global.chars[name]
end

function AltManager:OnInitialize()
	local defaults = {
		global = {
			chars = {},
			resets = {},
		},
		profile = {
			minimap = { hide = false },
		}
	}
	self.db = LibStub("AceDB-3.0"):New("AltManagerDB", defaults, true)
	
	AMConfig:RegisterOptionsTable("AltManager", self:Options())
	self.optionsFrame = AMConfigDialog:AddToBlizOptions("AltManager", "AltManager")
	
	self:CreateMinimapIcon()
end

function AltManager:OnEnable()
	self:RegisterEvent("PLAYER_LOGOUT", "OnLogout")
	self:RegisterEvent("CURRENCY_DISPLAY_UPDATE", "OnCurrencyUpdate")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
end

function AltManager:OnDisable()
	-- Event cleanup handled automatically by AceEvent
end

------------------------------------------------------------------------
-- Custom Core Conquest & BG Tracking Engine
------------------------------------------------------------------------
function AltManager:GetConquestCount()
	for i = 1, GetCurrencyListSize() do
		local _, isHeader, _, _, _, count, _, _, itemID = GetCurrencyListInfo(i)
		if not isHeader and itemID == 43307 then
			return count
		end
	end
	return 0
end

function AltManager:OnEnteringWorld()
	self.lastConquestCount = self:GetConquestCount()
	self:GetWeeklyReset()
	if self.mainFrame and self.mainFrame:IsShown() then
		self:UpdateMainFrame()
	end
end

function AltManager:OnCurrencyUpdate()
	local currentCount = self:GetConquestCount()
	
	if self.lastConquestCount and currentCount > self.lastConquestCount then
		local diff = currentCount - self.lastConquestCount
		
		-- Match or exceed the first win payout of 10 Conquest Points
		if diff >= 10 then
			local db = GetCharProfile()
			if db then
				db.BGDaily = true
				-- Push an immediate cosmetic refresh to the display layout frame if open
				if self.mainFrame and self.mainFrame:IsShown() then
					self:UpdateMainFrame()
				end
			end
		end
	end
	self.lastConquestCount = currentCount
end

------------------------------------------------------------------------
-- Reset Management Core
------------------------------------------------------------------------
function AltManager:GetWeeklyReset()
	local now = time()
	local regionReset = self.db.global.resets
	
	if not regionReset.daily or now > regionReset.daily then
		local nextDaily = time() + GetQuestResetTime()
		regionReset.daily = nextDaily
		
		-- Clean historical daily entries for all roster alts
		for charName, data in pairs(self.db.global.chars) do
			for taskName, taskInfo in pairs(tasks) do
				if taskInfo.isDaily then
					data[taskName] = false
				end
			end
		end
	end

	if not regionReset.weekly or now > regionReset.weekly then
		local d = date("*t", now)
		local daysTillReset = (WEEKLY_RESET_DAY - d.wday) % 7
		if daysTillReset == 0 and d.hour >= WEEKLY_RESET_HOUR then
			daysTillReset = 7
		end
		
		local targetResetDate = now + (daysTillReset * 86400)
		local rD = date("*t", targetResetDate)
		local weeklyResetTimestamp = time({year=rD.year, month=rD.month, day=rD.day, hour=WEEKLY_RESET_HOUR, min=0, sec=0})
		
		regionReset.weekly = weeklyResetTimestamp
		
		for charName, data in pairs(self.db.global.chars) do
			for taskName, taskInfo in pairs(tasks) do
				if not taskInfo.isDaily and taskInfo.type == "weekly" then
					data[taskName] = -1
				end
			end
		end
	end
end

function AltManager:CheckIDs()
	local db = GetCharProfile()
	for i = 1, GetNumSavedInstances() do
		local name, id, reset, difficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
		if locked then
			if name == "Onyxia's Lair" and maxPlayers == 25 then
				db.Ony25 = reset
			elseif name == "Molten Core" then
				db.MC10 = reset
			elseif name == "Blackwing Lair" then
				db.BWL10 = reset
			elseif name == "Zul'Gurub" then
				db.ZG = reset
			elseif name == "Ruins of Ahn'Qiraj" then
				db.AQ20 = reset
			elseif name == "Ahn'Qiraj Temple" then
				db.AQ40 = reset
			elseif name == "Naxxramas" then
				db.Naxx = reset
			end
		end
	end
end

------------------------------------------------------------------------
-- Profession Scanning & Data Gathering
------------------------------------------------------------------------
function AltManager:SaveProfessions()
	local db = GetCharProfile()
	db.Professions = db.Professions or {}
	table.wipe(db.Professions)
	
	local prof1, prof2 = GetProfessions()
	local profs = {prof1, prof2}
	
	for _, profIndex in pairs(profs) do
		if profIndex then
			local name, icon, rank, maxRank, numSpells, spellOffset, skillLine = GetProfessionInfo(profIndex)
			if name then
				table.insert(db.Professions, { name = name, rank = rank })
			end
		end
	end
end

function AltManager:SaveProfCooldowns()
	local db = GetCharProfile()
	db.Cooldowns = db.Cooldowns or {}
	table.wipe(db.Cooldowns)

	local cds = {
		["Transmute"] = { 28596, 48441, 48443 },
		["Moonshroud"] = { 56145 },
		["Spellweave"] = { 56146 },
		["Ebonweave"] = { 56148 },
		["Titansteel"] = { 55208 },
		["Glacial Bag"] = { 56005 }
	}

	for cdName, spellIDs in pairs(cds) do
		for _, spellID in ipairs(spellIDs) do
			if IsSpellKnown(spellID) then
				local start, duration = GetSpellCooldown(spellID)
				if start and duration and duration > 0 then
					local remaining = (start + duration) - time()
					if remaining > 0 then
						db.Cooldowns[cdName] = time() + remaining
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Graphical User Interface Display Operations
------------------------------------------------------------------------
local function FormatResetTime(seconds)
	if not seconds or seconds <= 0 then return "|cff00ff00Available|r" end
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local mins = math.floor((seconds % 3600) / 60)
	
	if days > 0 then
		return string.format("|cffff0000%dd %dh|r", days, hours)
	elseif hours > 0 then
		return string.format("|cffff5500%dh %dm|r", hours, mins)
	else
		return string.format("|cffffaa00%dm|r", mins)
	end
end

function AltManager:CreateMainFrame()
	if self.mainFrame then return end

	local f = CreateFrame("Frame", "AltManagerMainFrame", UIParent)
	f:SetSize(750, 450)
	f:SetPoint("CENTER")
	f:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 }
	})
	f:SetBackdropColor(0, 0, 0, 0.85)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -15)
	title:SetText("AltManager - Account Roster")

	f.rows = {}
	f.headers = {}
	self.mainFrame = f
end

function AltManager:UpdateMainFrame()
	if not self.mainFrame then return end
	local f = self.mainFrame

	for _, label in ipairs(f.headers) do label:Hide() end
	for _, row in ipairs(f.rows) do
		row.label:Hide()
		for _, cell in ipairs(row.cells) do cell:Hide() end
	end

	local sortedChars = {}
	for name, data in pairs(self.db.global.chars) do
		table.insert(sortedChars, { name = name, level = data.Level or 1, class = data.Class or "WARRIOR" })
	end
	table.sort(sortedChars, function(a, b) return a.level > b.level end)

	local colWidth = 110
	local startX = 140
	local startY = -55

	for idx, charInfo in ipairs(sortedChars) do
		local h = f.headers[idx] or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		h:SetPoint("TOPLEFT", f, "TOPLEFT", startX + ((idx-1) * colWidth), -35)
		local color = RAID_CLASS_COLORS[charInfo.class] or NORMAL_FONT_COLOR
		local shortName = string.gsub(charInfo.name, " %- .*", "")
		h:SetText(string.format("%s\n|cffaaaaaaLvl %d|r", color:WrapTextInColorCode(shortName), charInfo.level))
		h:Show()
		f.headers[idx] = h
	end

	local rowIdx = 1
	for taskKey, taskInfo in pairs(tasks) do
		local r = f.rows[rowIdx] or { cells = {} }
		
		local rl = r.label or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		rl:SetPoint("TOPLEFT", f, "TOPLEFT", 15, startY - ((rowIdx-1) * 22))
		rl:SetText(taskKey == "BGDaily" and "Daily BG Win" or taskKey)
		rl:Show()
		r.label = rl

		for cIdx, charInfo in ipairs(sortedChars) do
			local cell = r.cells[cIdx] or f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			cell:SetPoint("CENTER", f, "TOPLEFT", startX + ((cIdx-1) * colWidth) + (colWidth/2), startY - ((rowIdx-1) * 22) - 5)
			
			local data = self.db.global.chars[charInfo.name]
			local val = data and data[taskKey]
			
			if charInfo.level < (taskInfo.levelRequire or 0) then
				cell:SetText("|cff666666Ineligible|r")
			elseif taskInfo.isDaily then
				if val == true then
					cell:SetText("|cff00ff00Completed|r")
				else
					cell:SetText("|cffff0000Incomplete|r")
				end
			else
				if not val or val == -1 then
					cell:SetText("|cff00ff00Available|r")
				else
					local remaining = val - time()
					cell:SetText(FormatResetTime(remaining))
				end
			end
			cell:Show()
			r.cells[cIdx] = cell
		end

		f.rows[rowIdx] = r
		rowIdx = rowIdx + 1
	end

	local totalWidth = startX + (#sortedChars * colWidth) + 20
	local totalHeight = math.abs(startY - ((rowIdx-1) * 22)) + 30
	f:SetSize(math.max(totalWidth, 400), math.max(totalHeight, 200))
end

function AltManager:ToggleMainFrame()
	self:CreateMainFrame()
	if self.mainFrame:IsShown() then
		self.mainFrame:Hide()
	else
		self:GetWeeklyReset()
		self:CheckIDs()
		self:UpdateMainFrame()
		self.mainFrame:Show()
	end
end

local function BuildTooltip(tt)
	tt:AddLine("AltManager", 1, 1, 1)
	tt:AddLine("Left-Click: Open status panel summary Grid", 0.2, 1, 0.2)
	tt:AddLine("Right-Click: Interface configuration screen options", 0.2, 0.8, 1)
	
	local now = time()
	if AltManager.db and AltManager.db.global.resets then
		local resets = AltManager.db.global.resets
		if resets.daily then
			tt:AddLine(" ")
			tt:AddLine(string.format("Next Daily Reset: %s", FormatResetTime(resets.daily - now)), 0.9, 0.9, 0.9)
		end
		if resets.weekly then
			tt:AddLine(string.format("Next Weekly Reset: %s", FormatResetTime(resets.weekly - now)), 0.9, 0.9, 0.9)
		end
	end
end

------------------------------------------------------------------------
-- Minimap Broker Icon Registration & Setup
------------------------------------------------------------------------
function AltManager:CreateMinimapIcon()
	if not LDB then return end

	local AltManagerLDB = LDB:NewDataObject("AltManager", {
		type = "launcher",
		icon = "Interface\\Icons\\SPELL_nature_invisibilty",
		OnClick = function(frame, btn)
			if btn == "LeftButton" then
				AltManager:ToggleMainFrame()
			else
				InterfaceOptionsFrame_OpenToCategory("AltManager-Epoch")
			end
		end,
		OnTooltipShow = function(tt) BuildTooltip(tt) end,
	})

	if LDBIcon then
		LDBIcon:Register("AltManager", AltManagerLDB, self.db.profile.minimap)
	end
end

function AltManager:OnLogout()
	local db = GetCharProfile()
	db.Level = UnitLevel("player") or 1
	local _, classToken = UnitClass("player")
	db.Class = classToken

	self:GetWeeklyReset()
	self:CheckIDs()
	self:SaveProfessions()
	self:SaveProfCooldowns()
end

function AltManager:Options()
	return {
		type = "group",
		name = "AltManager",
		args = {
			minimap = {
				type = "toggle",
				name = "Hide Minimap Button",
				get = function() return AltManager.db.profile.minimap.hide end,
				set = function(info, v)
					AltManager.db.profile.minimap.hide = v
					if LDBIcon then
						if v then LDBIcon:Hide("AltManager") else LDBIcon:Show("AltManager") end
					end
				end,
				order = 1,
			},
			purge = {
				type = "execute",
				name = "Clear Database",
				desc = "Wipes stored configuration metrics profiles for all characters completely.",
				func = function()
					table.wipe(AltManager.db.global.chars)
					print("|cffff0000[AltManager]: Character records fully purged.|r")
					if AltManager.mainFrame and AltManager.mainFrame:IsShown() then
						AltManager:UpdateMainFrame()
					end
				end,
				order = 2,
			}
		}
	}
end
