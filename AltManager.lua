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
	Ony25 = { done = -1, type = "fiveday", isDaily = false, levelRequire = 60 }, -- Custom 5-day
	MC25  = { done = -1, type = "raid",    isDaily = false, levelRequire = 60 }, -- Standard weekly lockout
	WSG   = { done = -1, type = "weekly",  isDaily = false, levelRequire = 60 }, -- Weekly quest
	Gilli = { done = -1, type = "weekly",  isDaily = false, levelRequire = 60 }, -- Weekly quest
	BG    = { done = -1, type = "daily",   isDaily = true,  levelRequire = 10 }, -- 24-Hour Daily Win
	Sili  = { done = -1, type = "daily",   isDaily = true,  levelRequire = 54 }, -- 24-Hour Daily Quest
}

------------------------------------------------------------------------
-- Timezone-Safe Server Time Helpers
------------------------------------------------------------------------
local function GetServerUnixTime()
	local dt = date("*t")
	local sHour, sMin = GetGameTime()
	dt.hour = sHour
	dt.min = sMin
	dt.sec = 0
	return time(dt)
end

local function SecondsUntilWeeklyResetFallback()
	local serverTime = GetServerUnixTime()
	local dt = date("*t", serverTime)
	
	-- Calculate seconds passed since the start of today
	local secondsToday = dt.hour * 3600 + dt.min * 60 + dt.sec
	local resetSecondsToday = WEEKLY_RESET_HOUR * 3600
	
	-- Find out how many days away the target weekly reset day is
	local daysDistance = WEEKLY_RESET_DAY - dt.wday
	if daysDistance < 0 or (daysDistance == 0 and secondsToday >= resetSecondsToday) then
		daysDistance = daysDistance + 7
	end
	
	local totalSecondsLeft = (daysDistance * 86400) + (resetSecondsToday - secondsToday)
	return totalSecondsLeft
end

local function SecondsUntilDailyReset()
	local serverHour, serverMin = GetGameTime()
	local secondsNow  = serverHour * 3600 + serverMin * 60
	local resetSeconds = DAILY_RESET_HOUR * 3600
	local diff = resetSeconds - secondsNow
	if diff <= 0 then diff = diff + 86400 end
	return diff
end

local function SecondsUntilFiveDayReset()
	local serverTime = GetServerUnixTime()
	-- Adjusted Anchor to shift the cycle back by exactly 1 day (Unix: 1779139200)
	local anchorTime = 1779139200 
	
	local timePassed = serverTime - anchorTime
	local remainder = timePassed % ONY_RESET_CYCLE
	return ONY_RESET_CYCLE - remainder
end

local function FormatTimeUntil(resetTimestamp, taskKey)
	local secs
	local taskConfig = tasks[taskKey]
	local taskType = taskConfig and taskConfig.type or "weekly"

	-- 1. If we have a live active game client lock timestamp saved, always use it
	if resetTimestamp and resetTimestamp > 0 then
		secs = resetTimestamp - GetServerUnixTime()
	else
		-- 2. Fall back to predictable calendar behaviors if no lock exists
		if taskType == "daily" then
			secs = SecondsUntilDailyReset()
		elseif taskType == "fiveday" then
			secs = SecondsUntilFiveDayReset()
		else
			secs = SecondsUntilWeeklyResetFallback()
		end
	end
	
	if secs <= 0 then return L.ResetDue or "Reset Due" end
	
	local h = math.floor(secs / 3600)
	local m = math.floor((secs % 3600) / 60)
	if h >= 24 then
		local d = math.floor(h / 24)
		h = h % 24
		return string.format("%dd %dh", d, h)
	elseif h > 0 then
		return string.format("%dh %dm", h, m)
	else
		return string.format("%dm", m)
	end
end

------------------------------------------------------------------------
-- Profession Cooldown Definitions
------------------------------------------------------------------------
local PROF_COOLDOWNS = {
	-- 3-day cooldowns
	{
		key      = "SaltShaker",
		cdSlot   = "3day",
		profID   = 165,  -- Leatherworking
		minSkill = 250,  
		levelReq = 50,
		itemID   = 15846,
		icon     = "Interface\\Icons\\inv_egg_05",
		label    = "Salt Shaker",
		checkFn  = function()
			local start, duration = GetItemCooldown(15846)
			if start and duration and duration > 0 then
				local remaining = (start + duration) - GetTime()
				return GetServerUnixTime() + remaining
			elseif start == 0 and duration == 0 then
				return "UNCACHED"
			end
			return 0
		end,
	},
	{
		key      = "Transmute",
		cdSlot   = "3day",
		profID   = 171,  -- Alchemy
		minSkill = 275,  
		levelReq = 50,
		spellID  = 17187,
		icon     = "Interface\\Icons\\INV_Misc_StoneTablet_05",
		label    = "Transmute",
		checkFn  = function()
			local name = GetSpellInfo(17187)
			if not name or name == "" then return "UNCACHED" end

			local start, duration = GetSpellCooldown(17187)
			if start and duration and duration > 0 then
				local remaining = (start + duration) - GetTime()
				return GetServerUnixTime() + remaining
			elseif (not start or start == 0) and (not duration or duration == 0) then
				if not AltManager.spellbookLoaded then return "UNCACHED" end
			end
			return 0
		end,
	},
	{
		key      = "Mooncloth",
		cdSlot   = "3day",
		profID   = 197,  -- Tailoring
		minSkill = 250,  
		levelReq = 50,
		spellID  = 18560,
		icon     = "Interface\\Icons\\INV_Fabric_Moonrag_01",
		label    = "Mooncloth",
		checkFn  = function()
			local name = GetSpellInfo(18560)
			if not name or name == "" then return "UNCACHED" end

			local start, duration = GetSpellCooldown(18560)
			if start and duration and duration > 0 then
				local remaining = (start + duration) - GetTime()
				return GetServerUnixTime() + remaining
			elseif (not start or start == 0) and (not duration or duration == 0) then
				if not AltManager.spellbookLoaded then return "UNCACHED" end
			end
			return 0
		end,
	},
	-- 7-day cooldowns (Epoch custom items)
	{
		key      = "MasterworkSalt",
		cdSlot   = "7day",
		profID   = 165,  
		minSkill = 300,  
		levelReq = 60,
		itemID   = 60571,
		icon     = "Interface\\Icons\\inv_misc_enggizmos_40",
		label    = "Masterwork Salt",
		checkFn  = function()
			local start, duration = GetItemCooldown(60571)
			if start and duration and duration > 0 then
				local remaining = (start + duration) - GetTime()
				return GetServerUnixTime() + remaining
			elseif start == 0 and duration == 0 then
				return "UNCACHED"
			end
			return 0
		end,
	},
	{
		key      = "CrystalLattice",
		cdSlot   = "7day",
		profID   = 171,  
		minSkill = 300,  
		levelReq = 60,
		itemID   = 60686,
		icon     = "Interface\\Icons\\INV_Misc_StoneTablet_05",
		label    = "Crystal Lattice",
		checkFn  = function()
			local start, duration = GetItemCooldown(60686)
			if start and duration and duration > 0 then
				local remaining = (start + duration) - GetTime()
				return GetServerUnixTime() + remaining
			elseif start == 0 and duration == 0 then
				return "UNCACHED"
			end
			return 0
		end,
	},
	{
		key      = "SignetMoonlit",
		cdSlot   = "7day",
		profID   = 197,  
		minSkill = 300,  
		levelReq = 60,
		itemID   = 60603,
		icon     = "Interface\\Icons\\INV_Fabric_Moonrag_01",
		label    = "Signet",
		checkFn  = function()
			local start, duration = GetItemCooldown(60603)
			if start and duration and duration > 0 then
				local remaining = (start + duration) - GetTime()
				return GetServerUnixTime() + remaining
			elseif start == 0 and duration == 0 then
				return "UNCACHED"
			end
			return 0
		end,
	},
}

local PROF_NAMES = {
	[165] = "Leatherworking",
	[171] = "Alchemy",
	[197] = "Tailoring",
}

local DBDefault = {
	profile = { minimap = { hide = false } },
	global = {
		[me] = {
			Level = 1,
			Class = nil,
			LastReset = { reset = nil },
			Sili  = { done = -1, handle = true },
			BG    = { done = -1, handle = true },
			Ony25 = { done = -1, handle = true },
			MC25  = { done = -1, handle = true },
			WSG   = { done = -1, handle = true },
			Gilli = { done = -1, handle = true },
			profCooldowns = {},
			professions   = {},
		}
	},
}

local listChars = {}

local questsList = { 
	Sili  = { 27390, 27391, 27392, 27393, 27394, 27395 },
	WSG   = { 27880, 27881, 27882, 27883 }, 
	Gilli = { 31042, 31043, 31044, 31045 }, 
}

local WORLD_BOSS_ZONES = { ["Blasted Lands"] = true, ["Burning Steppes"] = true }
local columnOrder = { "Ony25", "MC25", "WSG", "Gilli", "Sili", "BG" }

------------------------------------------------------------------------
-- Helpers & Data Scope Isolation Manager
------------------------------------------------------------------------
local function GetCharProfile(charKey)
	local target = charKey or me
	if not AltManager.db.global[target] then
		AltManager.db.global[target] = {
			Level = 1,
			profCooldowns = {},
			professions   = {},
		}
	end
	return AltManager.db.global[target]
end

local function FormatCooldownExpiry(expiry)
	if not expiry or expiry == 0 then return L.CDReady or "Ready!" end
	local secs = expiry - GetServerUnixTime()
	if secs <= 0 then return L.CDReady or "Ready!" end
	local h = math.floor(secs / 3600)
	local m = math.floor((secs % 3600) / 60)
	if h >= 24 then
		local d = math.floor(h / 24)
		h = h % 24
		return string.format("%dd %dh", d, h)
	elseif h > 0 then
		return string.format("%dh %dm", h, m)
	else
		return string.format("%dm", m)
	end
end

local function GetDoneForAlt(charKey, taskKey)
	local db = GetCharProfile(charKey)
	if not db or not db[taskKey] then return -1 end
	return db[taskKey].done or -1
end

local function GetResetForAlt(charKey, taskKey)
	local db = GetCharProfile(charKey)
	if not db or not db[taskKey] then return nil end
	return db[taskKey].reset
end

local function GetProfCooldownsForAlt(charKey, cdSlot)
	local db = GetCharProfile(charKey)
	if not db or not db.professions then return {} end
	local result = {}
	
	for _, cd in ipairs(PROF_COOLDOWNS) do
		if cd.cdSlot == cdSlot then
			local currentSkill = db.professions[cd.profID] or 0
			local altLevel = db.Level or 1
			
			if currentSkill >= (cd.minSkill or 0) then
				if not cd.levelReq or altLevel >= cd.levelReq then
					table.insert(result, cd)
				end
			end
		end
	end
	return result
end

local function DoneColor(done)
	if done == 2     then return 0.2, 0.8, 0.2
	elseif done == 1 then return 1.0, 0.8, 0.0
	elseif done == 0 then return 0.8, 0.2, 0.2
	else                  return 0.5, 0.5, 0.5
	end
end

local function DoneText(done)
	if done == 2     then return L.Done or "Done"
	elseif done == 1 then return L.InProgress or "Active"
	elseif done == 0 then return L.NotDone or "Not Done"
	else                  return "-"
	end
end

------------------------------------------------------------------------
-- Tooltip Construction Helper
------------------------------------------------------------------------
local function BuildTooltip(tt)
	local serverTime = GetServerUnixTime()
	tt:AddLine("|cFFFFD700AltManager-Epoch|r")
	tt:AddLine("|cFFAAAAAA"..(L.ClickToOpen or "Click to open").."|r")
	tt:AddLine(" ")

	local function ResetStr(taskKey)
		return FormatTimeUntil(GetResetForAlt(me, taskKey), taskKey)
	end

	-- 1. Raid Lockouts & 5-Day Resets Grouped Cleanly Together
	tt:AddLine("|cFFFFFFFF"..(L.RaidIDs or "Raid Lockouts").."|r")
	for _, taskKey in ipairs(columnOrder) do
		if tasks[taskKey].type == "raid" or tasks[taskKey].type == "fiveday" then
			local done = GetDoneForAlt(me, taskKey)
			local r,g,b = DoneColor(done)
			
			-- Safe translation lookup via rawget
			local rawLocale = rawget(L, taskKey)
			local localizedLabel = rawLocale or taskKey
			
			tt:AddDoubleLine(localizedLabel, DoneText(done).." |cFFAAAAAA("..ResetStr(taskKey)..")|r", 1,1,1, r,g,b)
		end
	end
	tt:AddLine(" ")
	
	-- 2. Weekly Objectives
	tt:AddLine("|cFFFFFFFFWeekly Objectives|r")
	for _, taskKey in ipairs(columnOrder) do
		if tasks[taskKey].type == "weekly" then
			local done = GetDoneForAlt(me, taskKey)
			local r,g,b = DoneColor(done)
			
			local rawLocale = rawget(L, taskKey)
			local localizedLabel = rawLocale or taskKey
			
			tt:AddDoubleLine(localizedLabel, DoneText(done).." |cFFAAAAAA("..ResetStr(taskKey)..")|r", 1,1,1, r,g,b)
		end
	end
	tt:AddLine(" ")
	
	-- 3. Daily Objectives
	tt:AddLine("|cFFFFFFFF"..(L.DailyQuests or "Daily Objectives").."|r")
	for _, taskKey in ipairs(columnOrder) do
		if tasks[taskKey].type == "daily" then
			local done = GetDoneForAlt(me, taskKey)
			local r,g,b = DoneColor(done)
			
			local rawLocale = rawget(L, taskKey)
			local localizedLabel = rawLocale or taskKey
			
			tt:AddDoubleLine(localizedLabel, DoneText(done).." |cFFAAAAAA("..ResetStr(taskKey)..")|r", 1,1,1, r,g,b)
		end
	end

	-- 4. Profession Cooldowns (Now strictly obeying skill level & character level requirements)
	local db = GetCharProfile()
		if db and db.professions then
			-- Fetch filtered items that the current character actually qualifies for
			local eligible3d = GetProfCooldownsForAlt(me, "3day")
			local eligible7d = GetProfCooldownsForAlt(me, "7day")
		
			if #eligible3d > 0 or #eligible7d > 0 then
				tt:AddLine(" ")
				tt:AddLine("|cFFFFFFFFProfession Cooldowns|r")
			
			-- Process 3-Day Cooldowns
				for _, cd in ipairs(eligible3d) do
					local expiry = 0
					if db.profCooldowns and db.profCooldowns[cd.key] then
						expiry = db.profCooldowns[cd.key]
					end
					local cdStr = FormatCooldownExpiry(expiry)
					local isReady = (not expiry or expiry == 0 or expiry <= serverTime)
					local r,g,b = isReady and 0.2,0.8,0.2 or 1.0,0.5,0.5
					tt:AddDoubleLine(cd.label.." ("..cd.cdSlot..")", cdStr, 1,1,1, r,g,b)
				end
			
			-- Process 7-Day Cooldowns
				for _, cd in ipairs(eligible7d) do
					local expiry = 0
					if db.profCooldowns and db.profCooldowns[cd.key] then
						expiry = db.profCooldowns[cd.key]
					end
					local cdStr = FormatCooldownExpiry(expiry)
					local isReady = (not expiry or expiry == 0 or expiry <= serverTime)
					local r,g,b = isReady and 0.2,0.8,0.2 or 1.0,0.5,0.5
					tt:AddDoubleLine(cd.label.." ("..cd.cdSlot..")", cdStr, 1,1,1, r,g,b)
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Main Interface UI
------------------------------------------------------------------------
local mainFrame = nil

local function BuildMainFrame()
	if mainFrame then
		local children = { mainFrame:GetChildren() }
		for _, child in ipairs(children) do
			child:Hide()
			child:SetParent(nil)
		end
		local regions = { mainFrame:GetRegions() }
		for _, region in ipairs(regions) do
			if region.Hide then region:Hide() end
			region:SetParent(nil)
		end
	else
		mainFrame = CreateFrame("Frame", "AltManagerMainFrame", UIParent, "BackdropTemplate")
		mainFrame:SetFrameStrata("DIALOG")
		mainFrame:SetMovable(true)
		mainFrame:EnableMouse(true)
		mainFrame:RegisterForDrag("LeftButton")
		mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
		mainFrame:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
	end

	mainFrame:SetScript("OnHide", function() mainFrame = nil end)

	local chars = {}
	for k, _ in pairs(AltManager.db.global) do
		if k ~= "LastReset" and k ~= "Config" then
			table.insert(chars, k)
		end
	end
	table.sort(chars, function(a, b)
		if a == me then return true end
		if b == me then return false end
		return a < b
	end)

	local COL_LABEL_W  = 120
	local COL_ALT_W    = 75
	local ROW_H        = 30
	local HEADER_H     = 36
	local PAD          = 8
	local TITLE_H      = 22
	local ICON_SIZE    = 16

	local allRows = {}
	for _, taskKey in ipairs(columnOrder) do
		table.insert(allRows, { type = "task", key = taskKey })
	end
	table.insert(allRows, { type = "prof", key = "3day", label = "Profession CDs (3d)" })
	table.insert(allRows, { type = "prof", key = "7day", label = "Profession CDs (7d)" })

	local numTasks = #allRows
	local numAlts  = #chars
	local frameW = PAD*2 + COL_LABEL_W + (numAlts > 0 and numAlts * COL_ALT_W or COL_ALT_W)
	local frameH = PAD*2 + TITLE_H + HEADER_H + numTasks * ROW_H + PAD

	mainFrame:SetWidth(frameW)
	mainFrame:SetHeight(frameH)
	mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

	mainFrame:SetBackdrop({
		bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile     = true, tileSize = 32, edgeSize = 32,
		insets   = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	mainFrame:SetBackdropColor(0.06, 0.06, 0.06, 0.96)
	mainFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

	local closeBtn = CreateFrame("Button", "AltManagerCloseBtn", mainFrame, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 1, 1)
	closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)

	local yStart = -(TITLE_H + PAD)
	local titleTxt = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleTxt:SetWidth(COL_LABEL_W - 4)
	titleTxt:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", PAD + 2, yStart - 6)
	titleTxt:SetText("AltManager")
	titleTxt:SetJustifyH("CENTER")

	for ci, charKey in ipairs(chars) do
		local x = PAD + COL_LABEL_W + (ci-1)*COL_ALT_W
		local displayName = charKey:match("^(.+) %- ") or charKey
		local realmName   = charKey:match(" %- (.+)$") or ""
		
		local db = GetCharProfile(charKey)
		local nameColor = "|cFFFFFFFF" 

		if db and db.Class and RAID_CLASS_COLORS[db.Class] then
			local colorObj = RAID_CLASS_COLORS[db.Class]
			nameColor = string.format("|cff%02x%02x%02x", colorObj.r * 255, colorObj.g * 255, colorObj.b * 255)
		elseif charKey == me then
			nameColor = "|cFFFFD700" 
		end

		local nameStr = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		nameStr:SetWidth(COL_ALT_W - 2)
		nameStr:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", x, yStart)
		nameStr:SetText(nameColor..displayName.."|r")
		nameStr:SetJustifyH("CENTER")

		local realmStr = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		realmStr:SetWidth(COL_ALT_W - 2)
		realmStr:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", x, yStart - 14)
		realmStr:SetText("|cFF888888"..realmName.."|r")
		realmStr:SetJustifyH("CENTER")
	end

	local hDiv = mainFrame:CreateTexture(nil, "ARTWORK")
	hDiv:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  PAD,  yStart - HEADER_H)
	hDiv:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -PAD, yStart - HEADER_H)
	hDiv:SetHeight(1)
	hDiv:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
	hDiv:SetVertexColor(0.5, 0.5, 0.5, 0.8)

	local vDiv1 = mainFrame:CreateTexture(nil, "ARTWORK")
	vDiv1:SetPoint("TOPLEFT",    mainFrame, "TOPLEFT", PAD + COL_LABEL_W, yStart - HEADER_H)
	vDiv1:SetPoint("BOTTOMLEFT", mainFrame, "TOPLEFT", PAD + COL_LABEL_W, -(frameH - PAD))
	vDiv1:SetWidth(1)
	vDiv1:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
	vDiv1:SetVertexColor(0.4, 0.4, 0.4, 0.7)

	local yContent = yStart - HEADER_H - 2

	for ri, rowData in ipairs(allRows) do
		local y = yContent - (ri-1)*ROW_H

		if ri % 2 == 0 then
			local rowBg = mainFrame:CreateTexture(nil, "BACKGROUND")
			rowBg:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  PAD + 1,  y)
			rowBg:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -PAD - 1, y)
			rowBg:SetHeight(ROW_H)
			rowBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
			rowBg:SetVertexColor(1, 1, 1, 0.05)
		end

		local taskKey = rowData.key

		if rowData.type == "task" then
			local labelStr = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			labelStr:SetWidth(COL_LABEL_W - PAD - 4)
			labelStr:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", PAD + 2, y - 2)
			
			local rawLocale = rawget(L, taskKey)
			local localizedLabel = rawLocale or taskKey
			labelStr:SetText("|cFFFFFFFF"..localizedLabel.."|r")
			labelStr:SetJustifyH("CENTER")

			local resetStr = FormatTimeUntil(GetResetForAlt(me, taskKey), taskKey)
			local timerStr = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			timerStr:SetWidth(COL_LABEL_W - PAD - 4)
			timerStr:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", PAD + 2, y - 16)
			timerStr:SetText("|cFFAAAAAA"..resetStr.."|r")
			timerStr:SetJustifyH("CENTER")

			for ci, charKey in ipairs(chars) do
				local x    = PAD + COL_LABEL_W + (ci-1)*COL_ALT_W
				local done = GetDoneForAlt(charKey, taskKey)
				local r,g,b = DoneColor(done)

				local cellBg = mainFrame:CreateTexture(nil, "BACKGROUND")
				cellBg:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT", x + 1,             y - 1)
				cellBg:SetPoint("BOTTOMRIGHT", mainFrame, "TOPLEFT", x + COL_ALT_W - 2, y - ROW_H + 1)
				cellBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
				cellBg:SetVertexColor(r*0.3, g*0.3, b*0.3, 0.7)

				local cellTxt = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
				cellTxt:SetWidth(COL_ALT_W - 4)
				cellTxt:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", x + 2, y - 8)
				cellTxt:SetText(DoneText(done))
				cellTxt:SetTextColor(r, g, b)
				cellTxt:SetJustifyH("CENTER")

				local cellBtn = CreateFrame("Button", nil, mainFrame)
				cellBtn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", x, y)
				cellBtn:SetSize(COL_ALT_W, ROW_H)
				cellBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
				cellBtn:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					local tipLocale = rawget(L, taskKey)
					GameTooltip:AddLine(tipLocale or taskKey, 1, 1, 1)
					if done == 2 then
						GameTooltip:AddLine("Status: |cff33ff33Completed|r")
					elseif done == 1 then
						GameTooltip:AddLine("Status: |cffffcc00In Progress|r")
					elseif done == 0 then
						GameTooltip:AddLine("Status: |cffff3333Incomplete|r")
					else
						GameTooltip:AddLine("Status: |cff999999Not Eligible|r")
					end
					GameTooltip:Show()
				end)
				cellBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
			end
		elseif rowData.type == "prof" then
			local labelStr = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			labelStr:SetWidth(COL_LABEL_W - PAD - 4)
			labelStr:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", PAD + 2, y - 8)
			labelStr:SetText("|cFFFFCC00"..rowData.label.."|r")
			labelStr:SetJustifyH("CENTER")

			for ci, charKey in ipairs(chars) do
				local x    = PAD + COL_LABEL_W + (ci-1)*COL_ALT_W
				local db   = GetCharProfile(charKey)

				local cellBg = mainFrame:CreateTexture(nil, "BACKGROUND")
				cellBg:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT", x + 1,             y - 1)
				cellBg:SetPoint("BOTTOMRIGHT", mainFrame, "TOPLEFT", x + COL_ALT_W - 2, y - ROW_H + 1)
				cellBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
				cellBg:SetVertexColor(0.1, 0.1, 0.1, 0.4)

				local cds = GetProfCooldownsForAlt(charKey, taskKey)
				
				local cellBtn = CreateFrame("Button", nil, mainFrame)
				cellBtn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", x, y)
				cellBtn:SetSize(COL_ALT_W, ROW_H)
				cellBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
				cellBtn:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
					GameTooltip:AddLine(rowData.label, 1, 1, 1)
					if #cds == 0 then
						GameTooltip:AddLine("No trackable professions active.", 0.5, 0.5, 0.5)
					else
						for _, cd in ipairs(cds) do
							local expiry = db.profCooldowns and db.profCooldowns[cd.key] or 0
							local ready = (not expiry or expiry == 0 or expiry <= GetServerUnixTime())
							local statusText = ready and "|cff33ff33Ready|r" or "|cffff3333On Cooldown|r"
							GameTooltip:AddDoubleLine(cd.label, statusText)
						end
					end
					GameTooltip:Show()
				end)
				cellBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

				if #cds == 1 then
					local cd = cds[1]
					local iconTex = mainFrame:CreateTexture(nil, "OVERLAY")
					iconTex:SetSize(ICON_SIZE, ICON_SIZE)
					iconTex:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", x + (COL_ALT_W/2) - (ICON_SIZE/2), y - 2)
					iconTex:SetTexture(cd.icon)

					local expiry = db.profCooldowns and db.profCooldowns[cd.key] or 0
					local cdStr  = FormatCooldownExpiry(expiry)
					local cdColor = (not expiry or expiry == 0 or expiry <= GetServerUnixTime()) and "|cFF00FF00" or "|cFFFFAAAA"

					local cdTxt = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
					cdTxt:SetWidth(COL_ALT_W - 4)
					cdTxt:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", x + 2, y - 16)
					cdTxt:SetText(cdColor..cdStr.."|r")
					cdTxt:SetJustifyH("CENTER")
				elseif #cds == 2 then
					local cd1 = cds[1]
					local iconTex1 = mainFrame:CreateTexture(nil, "OVERLAY")
					iconTex1:SetSize(ICON_SIZE, ICON_SIZE)
					iconTex1:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", x + 10, y - 2)
					iconTex1:SetTexture(cd1.icon)

					local expiry1 = db.profCooldowns and db.profCooldowns[cd1.key] or 0
					local cdStr1  = FormatCooldownExpiry(expiry1)
					local cdColor1 = (not expiry1 or expiry1 == 0 or expiry1 <= GetServerUnixTime()) and "|cFF00FF00" or "|cFFFFAAAA"

					local cdTxt1 = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
					cdTxt1:SetWidth(36)
					cdTxt1:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", x + 1, y - 16)
					cdTxt1:SetText(cdColor1..cdStr1.."|r")
					cdTxt1:SetJustifyH("CENTER")

					local cd2 = cds[2]
					local iconTex2 = mainFrame:CreateTexture(nil, "OVERLAY")
					iconTex2:SetSize(ICON_SIZE, ICON_SIZE)
					iconTex2:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", x + COL_ALT_W - 26, y - 2)
					iconTex2:SetTexture(cd2.icon)

					local expiry2 = db.profCooldowns and db.profCooldowns[cd2.key] or 0
					local cdStr2  = FormatCooldownExpiry(expiry2)
					local cdColor2 = (not expiry2 or expiry2 == 0 or expiry2 <= GetServerUnixTime()) and "|cFF00FF00" or "|cFFFFAAAA"

					local cdTxt2 = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
					cdTxt2:SetWidth(36)
					cdTxt2:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", x + COL_ALT_W - 37, y - 16)
					cdTxt2:SetText(cdColor2..cdStr2.."|r")
					cdTxt2:SetJustifyH("CENTER")
				end
			end
		end
	end
	mainFrame:Show()
end

function AltManager:ToggleMainFrame()
	if mainFrame and mainFrame:IsShown() then
		mainFrame:Hide()
	else
		BuildMainFrame()
	end
end

------------------------------------------------------------------------
-- Profession Tracking Operations
------------------------------------------------------------------------
local PROF_SKILL_NAMES = {
	["Leatherworking"] = 165,
	["Alchemy"]        = 171,
	["Tailoring"]      = 197,
}

function AltManager:SaveProfessions()
	local db = GetCharProfile()
	if not db.professions then db.professions = {} end

	local numSkills = GetNumSkillLines()
	if numSkills == 0 then return end

	local tempProfessions = {}
	local foundAny = false

	for i = 1, numSkills do
		local skillName, isHeader, _, skillRank = GetSkillLineInfo(i)
		if not isHeader and skillName then
			local profID = PROF_SKILL_NAMES[skillName]
			if profID then
				tempProfessions[profID] = skillRank or 0
				foundAny = true
			end
		end
	end

	if foundAny then
		db.professions = tempProfessions
		self:SaveProfCooldowns()
	end
end

function AltManager:SaveProfCooldowns()
	local db = GetCharProfile()
	local serverTime = GetServerUnixTime()
	
	for _, cd in ipairs(PROF_COOLDOWNS) do
		local expiry = cd.checkFn()
		
		if expiry ~= "UNCACHED" then
			local currentSkill = db.professions[cd.profID] or 0
			
			if (expiry and type(expiry) == "number" and expiry > serverTime) or (currentSkill >= (cd.minSkill or 0)) then
				if expiry and type(expiry) == "number" and expiry > serverTime and currentSkill == 0 then
					db.professions[cd.profID] = cd.minSkill or 300
				end
				
				if expiry and (expiry > serverTime or expiry == 0) then
					db.profCooldowns[cd.key] = expiry
				end
			end
		end
	end
end

function AltManager:WarmupItemCache()
	for _, cd in ipairs(PROF_COOLDOWNS) do
		if cd.itemID then
			GetItemInfo(cd.itemID)
		end
	end
end

function AltManager:PurgeObsoleteProfiles()
	local serverTime = GetServerUnixTime()
	for profileKey, profileData in pairs(self.db.global) do
		if profileKey ~= "LastReset" and type(profileData) == "table" then
			local shouldPurge = true
			
			for key, val in pairs(profileData) do
				if type(val) == "table" and val.done and val.done ~= -1 then
					shouldPurge = false
					break
				end
			end
			
			if shouldPurge and profileData.profCooldowns then
				for _, expiry in pairs(profileData.profCooldowns) do
					if expiry and expiry > serverTime then
						shouldPurge = false
						break
					end
				end
			end
			
			if shouldPurge then
				self.db.global[profileKey] = nil
			end
		end
	end
end

------------------------------------------------------------------------
-- Lifecycle Engine
------------------------------------------------------------------------
function AltManager:OnInitialize()
	self:RegisterChatCommand("am", "SlashHandler")
	self:RegisterChatCommand("altmanager", "SlashHandler")
	self.db = LibStub("AceDB-3.0"):New("AMdb", DBDefault)
	self:CreateMinimapIcon()
	AltManager.spellbookLoaded = false
end

function AltManager:OnEnable()
	self:GetWeeklyReset()
	self:RegisterEvent("PLAYER_LOGOUT",        "OnLogout")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "CheckIDs")
	self:RegisterEvent("SKILL_LINES_CHANGED",   "SaveProfessions")
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnCooldownUpdate")
	self:RegisterEvent("BAG_UPDATE_COOLDOWN",   "OnCooldownUpdate")
	self:RegisterEvent("QUEST_LOG_UPDATE", "ScanQuestLog")
	
	self:RegisterEvent("UPDATE_BATTLEFIELD_STATUS", "CheckBattlegroundWin")
	
	self:RegisterEvent("SPELLS_CHANGED", function()
		AltManager.spellbookLoaded = true
		AltManager:SaveProfCooldowns()
	end)

	quixote.RegisterCallback(AltManager, "Quest_Abandoned")
	quixote.RegisterCallback(AltManager, "Quest_Gained")
	quixote.RegisterCallback(AltManager, "Quest_Lost")
	self:ScheduleTimer("Loading", 1)
end

function AltManager:Loading()
	local db = GetCharProfile()
	db.Level = UnitLevel("player") or 1
	
	local _, classToken = UnitClass("player")
	db.Class = classToken

	self:CheckLevel()
	self:GetWeeklyReset()
	self:LoadSV()
	self:CheckIDs()
	self:CheckQuest()
	self:SaveProfessions()
	self:SaveProfCooldowns()
	self:WarmupItemCache()
	self:PurgeObsoleteProfiles()

	self:ScheduleTimer(function()
		AltManager:SaveProfCooldowns()
	end, 5)

	self:ScheduleTimer("LoadSV", GetQuestResetTime()+60)
	AMConfig:RegisterOptionsTable("AltManager", AltManager:Options())
	AMConfigDialog:AddToBlizOptions("AltManager", "AltManager-Epoch")
	
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "SaveProfCooldowns")
end

function AltManager:OnCooldownUpdate()
	self:SaveProfCooldowns()
end

------------------------------------------------------------------------
-- Simplified Project Epoch Battleground Tracking Parser
------------------------------------------------------------------------
function AltManager:CheckBattlegroundWin()
	if self:GetStatus("BG") == 2 then return end

	for i = 1, MAX_BATTLEFIELD_QUEUES do
		local status, _, _, _, _, _, _, _, _, _, _, _, winner = GetBattlefieldStatus(i)
		if status == "active" then
			local playerFaction = OurFaction or GetGuildFactionGroup or UnitFactionGroup("player")
			local winnerFaction = GetBattlefieldWinner()
			
			if winnerFaction ~= nil then
				local isWin = false
				if playerFaction == "Alliance" and winnerFaction == 0 then
					isWin = true
				elseif playerFaction == "Horde" and winnerFaction == 1 then
					isWin = true
				end
				
				if isWin then
					local inBossZone = WORLD_BOSS_ZONES[GetZoneText()]
					if not inBossZone then
						self:SetDone("BG", 2, GetQuestResetTime())
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Slash Commands
------------------------------------------------------------------------
function AltManager:SlashHandler(msg)
	if msg == "hide" then
		self.db.profile.minimap.hide = not self.db.profile.minimap.hide
		if self.db.profile.minimap.hide then
			LDBIcon:Hide("AltManager")
			self:Printf("%s.", L.SlashCmdHidden)
		else
			LDBIcon:Show("AltManager")
			self:Printf("%s.", L.SlashCmdShown)
		end
	elseif msg == "list" then
		local i = 1
		for k,_ in pairs(self.db.global) do
			if k ~= "LastReset" then
				listChars[i] = k
				self:Printf("%s - %s", i, k)
				i = i+1
			end
		end
	elseif string.find(msg, "del") then
		local num = tonumber(string.match(msg, "%d+"))
		if num and listChars[num] then
			self:Printf("%s %s - %s. %s.", L.SlashCmdDeleting, num, listChars[num], L.SlashCmdWiped)
			self.db.global[listChars[num]] = nil
		elseif num then
			self:Printf("%s %s %s.", L.SlashCmdChar, num, L.SlashCmdNExist)
		end
	else
		self:Printf("%s :", L.SlashCmdHelp)
		self:Printf("/am list :: %s", L.SlashCmdList)
		self:Printf("/am del # :: %s", L.SlashCmdDelete)
		self:Printf("/am hide :: %s", L.SlashCmdHide)
	end
end

------------------------------------------------------------------------
-- Quest Callbacks
------------------------------------------------------------------------
function AltManager:Quest_Abandoned(event, name, uid)
	for type,_ in pairs(questsList) do
		for k,id in pairs(questsList[type]) do
			if uid == id then self:SetDone(type, 0) end
		end
	end
end

function AltManager:Quest_Gained(event, name, uid)
	for type,_ in pairs(questsList) do
		for k,id in pairs(questsList[type]) do
			if uid == id then self:SetDone(type, 1) end
		end
	end
end

function AltManager:Quest_Lost(event, name, uid)
	for type,_ in pairs(questsList) do
		for k,id in pairs(questsList[type]) do
			if uid == id then
				if self:GetStatus(type) == 1 then
					local targetReset
					if tasks[type].type == "daily" then
						targetReset = GetQuestResetTime() or (GetServerUnixTime() + SecondsUntilDailyReset())
					elseif tasks[type].type == "fiveday" then
						targetReset = GetServerUnixTime() + SecondsUntilFiveDayReset()
					else
						local weeklyReset = GetCharProfile().LastReset and GetCharProfile().LastReset.reset
						targetReset = weeklyReset or (GetServerUnixTime() + SecondsUntilWeeklyResetFallback())
					end
					self:SetDone(type, 2, targetReset)
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Task State Management
------------------------------------------------------------------------
function AltManager:SetDone(task, number, reset)
	tasks[task].done = number
	local db = GetCharProfile()
	if not db[task] then db[task] = {} end
	db[task].done = number
	if reset then
		if reset < GetServerUnixTime() then
			db[task].reset = GetServerUnixTime() + reset
		else
			db[task].reset = reset
		end
	end
end

function AltManager:GetStatus(task, charKey)
	local db = GetCharProfile(charKey)
	if db and db[task] then 
		return db[task].done or -1 
	end
	return -1
end

------------------------------------------------------------------------
-- Checking Functions
------------------------------------------------------------------------
function AltManager:CheckLevel()
	local lv = UnitLevel("player")
	
	if lv < 10 then 
		self:SetDone("BG", -1) 
	elseif self:GetStatus("BG") == -1 then
		self:SetDone("BG", 0)
	end

	if lv < 54 then 
		self:SetDone("Sili", -1) 
	elseif self:GetStatus("Sili") == -1 then
		self:SetDone("Sili", 0) 
	end

	if lv < 60 then
		self:SetDone("Ony25", -1)
		self:SetDone("MC25", -1)
		self:SetDone("WSG", -1)
		self:SetDone("Gilli", -1)
	else
		if self:GetStatus("Ony25") == -1 then self:SetDone("Ony25", 0) end
		if self:GetStatus("MC25") == -1 then self:SetDone("MC25", 0) end
		if self:GetStatus("WSG") == -1 then self:SetDone("WSG", 0) end
		if self:GetStatus("Gilli") == -1 then self:SetDone("Gilli", 0) end
	end
end

function AltManager:GetWeeklyReset()
	local db = GetCharProfile()
	if not db.LastReset then db.LastReset = { reset = nil } end

	local numInstances = GetNumSavedInstances()
	for i = 1, numInstances do
		local name, _, reset, _, locked, extended, _, isRaid = GetSavedInstanceInfo(i)
		if isRaid and (locked or extended) and name then
			-- ONLY lock standard weekly raid structures down on LastReset
			if string.find(string.lower(name), "molten core", 1, true) then
				db.LastReset.reset = GetServerUnixTime() + reset
			end
		end
	end
	
	-- Assign our calculated lock limits safely onto completed milestones
	local fallbackRemaining = SecondsUntilWeeklyResetFallback()
	local targetReset = db.LastReset.reset or (GetServerUnixTime() + fallbackRemaining)
	
	if self:GetStatus("WSG") == 2 and not GetResetForAlt(me, "WSG") then
		db["WSG"].reset = targetReset
	end
	if self:GetStatus("Gilli") == 2 and not GetResetForAlt(me, "Gilli") then
		db["Gilli"].reset = targetReset
	end
end

function AltManager:CheckIDs()
	local lv = UnitLevel("player")
	for k, v in pairs(tasks) do
		if v.type == "raid" or v.type == "fiveday" then
			if lv >= (v.levelRequire or 60) then
				if self:GetStatus(k) == -1 then self:SetDone(k, 0) end
			else
				self:SetDone(k, -1)
			end
		end
	end

	local numInstances = GetNumSavedInstances()
	for i = 1, numInstances do
		local name, _, reset, _, locked, extended, _, isRaid = GetSavedInstanceInfo(i)
		if isRaid and (locked or extended) and name then
			-- Split tracking pathways cleanly here to prevent cross-contamination
			if string.find(string.lower(name), "onyxia", 1, true) then
				self:SetDone("Ony25", 2, GetServerUnixTime() + reset)
			elseif string.find(string.lower(name), "molten core", 1, true) then
				self:SetDone("MC25", 2, GetServerUnixTime() + reset)
			end
		end
	end
end

function AltManager:CheckQuest()
	for k,_ in pairs(questsList) do
		if self:GetStatus(k) == 0 then
			if self:ScanQuestLog(questsList[k]) then self:SetDone(k, 1) end
		end
	end
end

function AltManager:ScanQuestLog(ids)
	local i = 1
	while GetQuestLogTitle(i) do
		local _, _, _, _, _, _, _, _, questID = GetQuestLogTitle(i)
		if tContains(ids, questID) then return true end
		i = i + 1
	end
	return false
end

------------------------------------------------------------------------
-- Saved Variable Loading / Expiry
------------------------------------------------------------------------
function AltManager:LoadSV()
	if self.db.char then wipe(self.db.char) end
	if self.db.global then
		local serverTime = GetServerUnixTime()
		for k1, v1 in pairs(self.db.global) do
			if k1 ~= "LastReset" then
				for k2, v2 in pairs(v1) do
					if k2 ~= "profCooldowns" and k2 ~= "professions" and type(v2) == "table" then
						local dbDone = v2.done
						local dbReset = v2.reset
						
						if dbDone and dbDone == 2 then
							if not dbReset or dbReset == 0 then
								if tasks[k2] and tasks[k2].type == "daily" then
									dbReset = serverTime + SecondsUntilDailyReset()
								elseif tasks[k2] and tasks[k2].type == "fiveday" then
									dbReset = serverTime + SecondsUntilFiveDayReset()
								else
									dbReset = self.db.global[k1].LastReset and self.db.global[k1].LastReset.reset
									if not dbReset or dbReset == 0 then
										dbReset = serverTime + SecondsUntilWeeklyResetFallback()
									end
								end
							end
							
							if dbReset and dbReset < serverTime then 
								if k1 == me then
									self:SetDone(k2, 0) 
								else
									self.db.global[k1][k2].done = 0 
									self.db.global[k1][k2].reset = nil
								end
							end
						end
					end
				end
			end
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
				set = function(_, val)
					AltManager.db.profile.minimap.hide = val
					if val then LDBIcon:Hide("AltManager") else LDBIcon:Show("AltManager") end
				end,
				order = 1,
			},
		},
	}
end