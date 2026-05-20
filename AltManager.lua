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
-- Profession cooldown definitions
-- Each entry defines one trackable cooldown.
-- cdSlot: "3day" or "7day" — which column it appears in
-- checkFn: called on the logged-in character to get expiry timestamp
--          returns nil if the character doesn't have this cooldown available
-- icon: texture path shown in the cell
------------------------------------------------------------------------
local PROF_COOLDOWNS = {
	-- 3-day cooldowns
	{
		key      = "SaltShaker",
		cdSlot   = "3day",
		profID   = 165,  -- Leatherworking
		minSkill = 250,  -- Required skill level
		itemID   = 15846,
		icon     = "Interface\\Icons\\inv_egg_05",
		label    = "Salt Shaker",
		checkFn  = function()
			local start, duration = GetItemCooldown(15846)
			if start and duration and duration > 0 then
				local remaining = (start + duration) - GetTime()
				return time() + remaining
			end
			return 0
		end,
	},
	{
		key      = "Transmute",
		cdSlot   = "3day",
		profID   = 171,  -- Alchemy
		minSkill = 275,  -- Required skill level (Arcanite requires 275)
		spellID  = 17187,
		icon     = "Interface\\Icons\\INV_Misc_StoneTablet_05",
		label    = "Transmute",
		checkFn  = function()
			local start, duration = GetSpellCooldown(17187)
			if start and duration and duration > 0 then
				local remaining = (start + duration) - GetTime()
				return time() + remaining
			end
			return 0
		end,
	},
	{
		key      = "Mooncloth",
		cdSlot   = "3day",
		profID   = 197,  -- Tailoring
		minSkill = 250,  -- Required skill level
		spellID  = 18560,
		icon     = "Interface\\Icons\\INV_Fabric_Moonrag_01",
		label    = "Mooncloth",
		checkFn  = function()
			local start, duration = GetSpellCooldown(18560)
			if start and duration and duration > 0 then
				local remaining = (start + duration) - GetTime()
				return time() + remaining
			end
			return 0
		end,
	},
	-- 7-day cooldowns (Epoch custom items - usually requiring max skill)
	{
		key      = "MasterworkSalt",
		cdSlot   = "7day",
		profID   = 165,  -- Leatherworking
		minSkill = 300,  -- Project Epoch endgame requirement
		itemID   = 60571,
		icon     = "Interface\\Icons\\inv_misc_enggizmos_40",
		label    = "Masterwork Salt",
		checkFn  = function()
			local start, duration = GetItemCooldown(60571)
			if start and duration and duration > 0 then
				local remaining = (start + duration) - GetTime()
				return time() + remaining
			end
			return 0
		end,
	},
	{
		key      = "CrystalLattice",
		cdSlot   = "7day",
		profID   = 171,  -- Alchemy
		minSkill = 300,  -- Project Epoch endgame requirement
		itemID   = 60686,
		icon     = "Interface\\Icons\\INV_Misc_StoneTablet_05",
		label    = "Crystal Lattice",
		checkFn  = function()
			local start, duration = GetItemCooldown(60686)
			if start and duration and duration > 0 then
				local remaining = (start + duration) - GetTime()
				return time() + remaining
			end
			return 0
		end,
	},
	{
		key      = "SignetMoonlit",
		cdSlot   = "7day",
		profID   = 197,  -- Tailoring
		minSkill = 300,  -- Project Epoch endgame requirement
		itemID   = 60603,
		icon     = "Interface\\Icons\\INV_Fabric_Moonrag_01",
		label    = "Signet",
		checkFn  = function()
			local start, duration = GetItemCooldown(60603)
			if start and duration and duration > 0 then
				local remaining = (start + duration) - GetTime()
				return time() + remaining
			end
			return 0
		end,
	},
}

-- Profession ID -> name mapping for display
local PROF_NAMES = {
	[165] = "Leatherworking",
	[171] = "Alchemy",
	[197] = "Tailoring",
}

-- Database defaults
local DBDefault = {
	profile = {
		minimap = { hide = false },
	},
	global = {
		[me] = {
			LastReset = { reset = nil },
			Sili  = { done = -1, handle = true },
			BG    = { done = -1, handle = true },
			Ony25 = { done = -1, handle = true },
			MC25  = { done = -1, handle = true },
			-- profCooldowns: { key -> expiry_timestamp }
			-- professions:   { profID -> true }
			profCooldowns = {},
			professions   = {},
		}
	},
}

local listChars = {}

local tasks = {
	Ony25 = { done = -1, tipe = "raid", isDaily = false, levelRequire = 60 },
	MC25  = { done = -1, tipe = "raid", isDaily = false, levelRequire = 60 },
	BG    = { done = -1, tipe = "misc", isDaily = true,  levelRequire = 10 },
	Sili  = { done = -1, tipe = "job",  isDaily = true,  levelRequire = 54 },
}

local questsList = {
	Sili = { 27390, 27391, 27392, 27393, 27394, 27395 },
}

local BG_CURRENCY_ID   = 90533
local bgCurrencySnapshot = 0

local WORLD_BOSS_ZONES = {
	["Blasted Lands"]   = true,
	["Burning Steppes"] = true,
}

local columnOrder = { "Ony25", "MC25", "Sili", "BG" }

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local DAILY_RESET_HOUR = 8

local function SecondsUntilDailyReset()
	local serverHour, serverMin = GetGameTime()
	local secondsNow  = serverHour * 3600 + serverMin * 60
	local resetSeconds = DAILY_RESET_HOUR * 3600
	local diff = resetSeconds - secondsNow
	if diff <= 0 then diff = diff + 86400 end
	return diff
end

local function FormatTimeUntil(resetTimestamp, isDaily)
	local secs
	if isDaily then
		secs = SecondsUntilDailyReset()
	else
		if not resetTimestamp then return "?" end
		secs = resetTimestamp - time()
		if secs <= 0 then return L.ResetDue end
	end
	if secs <= 0 then return L.ResetDue end
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

local function FormatCooldownExpiry(expiry)
	if not expiry or expiry == 0 then return L.CDReady end
	local secs = expiry - time()
	
	-- Safety Gate: If clock drifts cause minor negative values but 
	-- the character file hasn't been refreshed yet, treat it as ready.
	if secs <= 0 then return L.CDReady end
	
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
	local db = AltManager.db.global[charKey]
	if not db or not db[taskKey] then return -1 end
	return db[taskKey].done or -1
end

local function GetResetForAlt(charKey, taskKey)
	local db = AltManager.db.global[charKey]
	if not db or not db[taskKey] then return nil end
	return db[taskKey].reset
end

-- Returns list of PROF_COOLDOWNS entries for a given alt and cdSlot
-- Only returns entries where the alt has the required profession saved
local function GetProfCooldownsForAlt(charKey, cdSlot)
	local db = AltManager.db.global[charKey]
	if not db or not db.professions then return {} end
	local result = {}
	for _, cd in ipairs(PROF_COOLDOWNS) do
		if cd.cdSlot == cdSlot then
			-- Check if the character has the profession AND meets the minimum level requirement
			local currentSkill = db.professions[cd.profID] or 0
			if currentSkill >= (cd.minSkill or 0) then
				table.insert(result, cd)
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
	if done == 2     then return L.Done
	elseif done == 1 then return L.InProgress
	elseif done == 0 then return L.NotDone
	else                  return "-"
	end
end

------------------------------------------------------------------------
-- Main table frame
------------------------------------------------------------------------
local mainFrame = nil

local function BuildMainFrame()
	local chars = {}
	for k,_ in pairs(AltManager.db.global) do
		if k ~= "LastReset" then
			table.insert(chars, k)
		end
	end
	table.sort(chars, function(a,b)
		if a == me then return true end
		if b == me then return false end
		return a < b
	end)

	local COL_LABEL_W  = 120
	local COL_ALT_W    = 70
	local ROW_H        = 30
	local HEADER_H     = 36
	local PAD          = 8
	local TITLE_H      = 22
	local ICON_SIZE    = 16

	-- Unify both standard tasks and profession cooldown tracking into rows
	local allRows = {}
	for _, taskKey in ipairs(columnOrder) do
		table.insert(allRows, { type = "task", key = taskKey })
	end
	table.insert(allRows, { type = "prof", key = "3day", label = "Profession CDs (3d)" })
	table.insert(allRows, { type = "prof", key = "7day", label = "Profession CDs (7d)" })

	local numTasks = #allRows
	local numAlts  = #chars
	local frameW = PAD*2 + COL_LABEL_W + numAlts * COL_ALT_W
	local frameH = PAD*2 + TITLE_H + HEADER_H + numTasks * ROW_H + PAD

	if mainFrame then
		mainFrame:SetScript("OnHide", nil)
		mainFrame:Hide()
		mainFrame = nil
	end

	mainFrame = CreateFrame("Frame", "AltManagerMainFrame", UIParent)
	mainFrame:SetWidth(frameW)
	mainFrame:SetHeight(frameH)
	mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	mainFrame:SetFrameStrata("DIALOG")
	mainFrame:SetMovable(true)
	mainFrame:EnableMouse(true)
	mainFrame:RegisterForDrag("LeftButton")
	mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
	mainFrame:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
	mainFrame:SetScript("OnHide", function() mainFrame = nil end)

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
	closeBtn:SetScript("OnClick", function()
		mainFrame:SetScript("OnHide", nil)
		mainFrame:Hide()
		mainFrame = nil
	end)

	local yStart   = -(TITLE_H + PAD)

	local titleTxt = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleTxt:SetWidth(COL_LABEL_W - 4) -- Give it a matching width boundaries
	titleTxt:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", PAD + 2, yStart - 6)
	titleTxt:SetText("AltManager")
	titleTxt:SetJustifyH("CENTER") -- Keeps it cleanly centered over the tasks column

	-- ── Column headers ─────────────────────────────────────────────────
	for ci, charKey in ipairs(chars) do
		local x = PAD + COL_LABEL_W + (ci-1)*COL_ALT_W
		local displayName = charKey:match("^(.+) %- ") or charKey
		local realmName   = charKey:match(" %- (.+)$") or ""
		local nameColor   = (charKey == me) and "|cFFFFD700" or "|cFFFFFFFF"

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

	-- ── Table Rows Renderer ───────────────────────────────────────────
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

		if rowData.type == "task" then
			local taskKey = rowData.key
			local labelStr = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			labelStr:SetWidth(COL_LABEL_W - PAD - 4)
			labelStr:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", PAD + 2, y - 2)
			labelStr:SetText("|cFFFFFFFF"..L[taskKey].."|r")
			labelStr:SetJustifyH("CENTER")

			local resetStr
			if tasks[taskKey].isDaily then
				resetStr = FormatTimeUntil(nil, true)
			else
				resetStr = FormatTimeUntil(GetResetForAlt(me, taskKey), false)
			end
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
			end
		elseif rowData.type == "prof" then
			local cdSlot = rowData.key
			local labelStr = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			labelStr:SetWidth(COL_LABEL_W - PAD - 4)
			labelStr:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", PAD + 2, y - 8)
			labelStr:SetText("|cFFFFCC00"..rowData.label.."|r")
			labelStr:SetJustifyH("CENTER")

			for ci, charKey in ipairs(chars) do
				local x    = PAD + COL_LABEL_W + (ci-1)*COL_ALT_W
				local db   = AltManager.db.global[charKey]

				local cellBg = mainFrame:CreateTexture(nil, "BACKGROUND")
				cellBg:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT", x + 1,             y - 1)
				cellBg:SetPoint("BOTTOMRIGHT", mainFrame, "TOPLEFT", x + COL_ALT_W - 2, y - ROW_H + 1)
				cellBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
				cellBg:SetVertexColor(0.1, 0.1, 0.1, 0.4)

				if db then
					local cds = GetProfCooldownsForAlt(charKey, cdSlot)
					if #cds == 1 then
						local cd = cds[1]
						local iconX = x + 27
						local iconY = y - 2

						local iconTex = mainFrame:CreateTexture(nil, "OVERLAY")
						iconTex:SetWidth(ICON_SIZE)
						iconTex:SetHeight(ICON_SIZE)
						iconTex:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", iconX, iconY)
						iconTex:SetTexture(cd.icon)

						local expiry = db.profCooldowns and db.profCooldowns[cd.key] or 0
						local cdStr  = FormatCooldownExpiry(expiry)
						local isReady = (not expiry or expiry == 0 or expiry <= time())
						local cdColor = isReady and "|cFF00FF00" or "|cFFFFAAAA"

						local cdTxt = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
						cdTxt:SetWidth(COL_ALT_W - 4)
						cdTxt:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", x + 2, y - 16)
						cdTxt:SetText(cdColor..cdStr.."|r")
						cdTxt:SetJustifyH("CENTER")
					elseif #cds == 2 then
						local cd1 = cds[1]
						local icon1X = x + 9
						local icon1Y = y - 2

						local iconTex1 = mainFrame:CreateTexture(nil, "OVERLAY")
						iconTex1:SetWidth(ICON_SIZE)
						iconTex1:SetHeight(ICON_SIZE)
						iconTex1:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", icon1X, icon1Y)
						iconTex1:SetTexture(cd1.icon)

						local expiry1 = db.profCooldowns and db.profCooldowns[cd1.key] or 0
						local cdStr1  = FormatCooldownExpiry(expiry1)
						local isReady1 = (not expiry1 or expiry1 == 0 or expiry1 <= time())
						local cdColor1 = isReady1 and "|cFF00FF00" or "|cFFFFAAAA"

						local cdTxt1 = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
						cdTxt1:SetWidth(34)
						cdTxt1:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", x + 1, y - 16)
						cdTxt1:SetText(cdColor1..cdStr1.."|r")
						cdTxt1:SetJustifyH("CENTER")

						local cd2 = cds[2]
						local icon2X = x + 45
						local icon2Y = y - 2

						local iconTex2 = mainFrame:CreateTexture(nil, "OVERLAY")
						iconTex2:SetWidth(ICON_SIZE)
						iconTex2:SetHeight(ICON_SIZE)
						iconTex2:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", icon2X, icon2Y)
						iconTex2:SetTexture(cd2.icon)

						local expiry2 = db.profCooldowns and db.profCooldowns[cd2.key] or 0
						local cdStr2  = FormatCooldownExpiry(expiry2)
						local isReady2 = (not expiry2 or expiry2 == 0 or expiry2 <= time())
						local cdColor2 = isReady2 and "|cFF00FF00" or "|cFFFFAAAA"

						local cdTxt2 = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
						cdTxt2:SetWidth(34)
						cdTxt2:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", x + 35, y - 16)
						cdTxt2:SetText(cdColor2..cdStr2.."|r")
						cdTxt2:SetJustifyH("CENTER")
					end
				end
			end
		end
	end

	mainFrame:Show()
end

function AltManager:ToggleMainFrame()
	if mainFrame then
		mainFrame:SetScript("OnHide", nil)
		mainFrame:Hide()
		mainFrame = nil
	else
		BuildMainFrame()
	end
end

------------------------------------------------------------------------
-- Profession detection and cooldown saving
------------------------------------------------------------------------
-- Profession name -> profID mapping for skill line name matching
local PROF_SKILL_NAMES = {
	["Leatherworking"] = 165,
	["Alchemy"]        = 171,
	["Tailoring"]      = 197,
}

function AltManager:SaveProfessions()
	local db = self.db.global[me]
	if not db.professions then db.professions = {} end

	local numSkills = GetNumSkillLines()
	if numSkills == 0 then return end -- Guard gate against loading screens

	local tempProfessions = {}
	local foundAny = false

	for i = 1, numSkills do
		-- skillRank is the 4th value returned by GetSkillLineInfo
		local skillName, isHeader, _, skillRank = GetSkillLineInfo(i)
		if not isHeader and skillName then
			local profID = PROF_SKILL_NAMES[skillName]
			if profID then
				-- Store the numeric skill level (e.g. 265) instead of just 'true'
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
	local db = self.db.global[me]
	if not db.profCooldowns  then db.profCooldowns = {} end
	if not db.professions    then db.professions   = {} end
	for _, cd in ipairs(PROF_COOLDOWNS) do
		local currentSkill = db.professions[cd.profID] or 0
		-- Only check and overwrite a cooldown if the current character meets the skill level requirement
		if currentSkill >= (cd.minSkill or 0) then
			local expiry = cd.checkFn()
			if expiry and (expiry > time() or expiry == 0) then
				db.profCooldowns[cd.key] = expiry
			end
		end
	end
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------
function AltManager:OnInitialize()
	self:RegisterChatCommand("am", "SlashHandler")
	self:RegisterChatCommand("altmanager", "SlashHandler")
	self.db = LibStub("AceDB-3.0"):New("AMdb", DBDefault)
	self:CreateMinimapIcon()
end

function AltManager:OnEnable()
	self:GetWeeklyReset()
	self:RegisterEvent("PLAYER_LOGOUT",        "OnLogout")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "CheckIDs")
	self:RegisterEvent("SKILL_LINES_CHANGED",   "SaveProfessions")
	self:RegisterEvent("CURRENCY_DISPLAY_UPDATE","CheckBGCurrency")
	-- SPELL_UPDATE_COOLDOWN fires when any spell CD changes — use to detect transmute/mooncloth use
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnCooldownUpdate")
	-- BAG_UPDATE_COOLDOWN fires when item CDs change (salt shaker, Epoch items)
	self:RegisterEvent("BAG_UPDATE_COOLDOWN",   "OnCooldownUpdate")
	self:RegisterEvent("QUEST_LOG_UPDATE", "ScanQuestLog")
	quixote.RegisterCallback(AltManager, "Quest_Abandoned")
	quixote.RegisterCallback(AltManager, "Quest_Gained")
	quixote.RegisterCallback(AltManager, "Quest_Lost")
	self:ScheduleTimer("Loading", 1)
end

function AltManager:Loading()
	self:CheckLevel()
	self:GetWeeklyReset()
	self:LoadSV()
	self:CheckIDs()
	self:CheckQuest()
	self:SaveProfessions()
	
	-- Force scan active profession timers directly upon log-in
	self:SaveProfCooldowns()

	-- BG currency snapshot — GetCurrencyInfo(id) returns name, texture, count in 3.3.5a
	if GetCurrencyInfo then
		local _, _, qty = GetCurrencyInfo(BG_CURRENCY_ID)
		bgCurrencySnapshot = qty or 0
	else
		bgCurrencySnapshot = 0
	end

	self:ScheduleTimer("LoadSV", GetQuestResetTime()+60)
	AMConfig:RegisterOptionsTable("AltManager", AltManager:Options())
	AMConfigDialog:AddToBlizOptions("AltManager", "AltManager-Epoch")
	
	-- Listen for whenever the player changes zones or finishes loading screens 
	-- to ensure existing cooldown states check continuously.
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "SaveProfCooldowns")
end

function AltManager:OnCooldownUpdate()
	-- Re-save cooldowns whenever spell or item CDs change
	self:SaveProfCooldowns()
end

------------------------------------------------------------------------
-- Slash commands
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
			listChars[i] = k
			self:Printf("%s - %s", i, k)
			i = i+1
		end
	elseif string.find(msg, "del") then
		local num = tonumber(string.match(msg, "%d+"))
		if num and listChars[num] then
			self:Printf("%s %s - %s. %s.", L.SlashCmdDeleting, num, listChars[num], L.SlashCmdWiped)
			wipe(self.db.global[listChars[num]])
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
-- Quest callbacks
------------------------------------------------------------------------
function AltManager:Quest_Abandoned(event, name, uid)
	for tipe,_ in pairs(questsList) do
		for k,id in pairs(questsList[tipe]) do
			if uid == id then self:SetDone(tipe, 0) end
		end
	end
end

function AltManager:Quest_Gained(event, name, uid)
	for tipe,_ in pairs(questsList) do
		for k,id in pairs(questsList[tipe]) do
			if uid == id then self:SetDone(tipe, 1) end
		end
	end
end

function AltManager:Quest_Lost(event, name, uid)
	for tipe,_ in pairs(questsList) do
		for k,id in pairs(questsList[tipe]) do
			if uid == id then
				if self:GetStatus(tipe) == 1 then
					self:SetDone(tipe, 2, GetQuestResetTime())
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Task state management
------------------------------------------------------------------------
function AltManager:SetDone(task, number, reset)
	tasks[task].done = number
	self.db.global[me][task].done = number
	if reset then
		if reset < time() then
			self.db.global[me][task].reset = time() + reset
		else
			self.db.global[me][task].reset = reset
		end
	end
end

function AltManager:SetZero(task)
	tasks[task].done = 0
	if self.db.global[me][task].done == -1 then self.db.global[me][task].done = 0 end
end

function AltManager:GetStatus(task, charKey)
	local targetChar = charKey or me
	local db = self.db.global[targetChar]
	if db and db[task] then 
		return db[task].done or -1 
	end
	return -1
end
------------------------------------------------------------------------
-- Checking functions
------------------------------------------------------------------------
function AltManager:CheckLevel()
	local lv = UnitLevel("player")
	-- If they don't meet minimum requirements, set status to -1 (Untracked/Hidden)
	if lv < 10 then 
		self:SetDone("BG", -1) 
	elseif self:GetStatus("BG") == -1 then
		self:SetDone("BG", 0) -- Activate tracking once eligible
	end

	if lv < 54 then 
		self:SetDone("Sili", -1) 
	elseif self:GetStatus("Sili") == -1 then
		self:SetDone("Sili", 0) 
	end
end

function AltManager:GetWeeklyReset()
	local db = self.db.global[me]
	if not db then return end
	if not db.LastReset then db.LastReset = { reset = nil } end -- Safety gate

	local numInstances = GetNumSavedInstances()
	for i = 1, numInstances do
		local _, _, reset, _, locked, extended, _, isRaid = GetSavedInstanceInfo(i)
		if isRaid and (locked or extended) then
			db.LastReset.reset = reset
		end
	end
end

function AltManager:CheckIDs()
	-- First reset current local character raid statuses to 0 before validating lockouts
	for k, v in pairs(tasks) do
		if v.tipe == "raid" and self:GetStatus(k) ~= -1 then
			self:SetDone(k, 0)
		end
	end

	local numInstances = GetNumSavedInstances()
	for i = 1, numInstances do
		local name, _, reset, _, locked, extended, _, isRaid, maxPlayers = GetSavedInstanceInfo(i)
		if isRaid and (locked or extended) then
			name = name.." "..maxPlayers
			for k, v in pairs(tasks) do
				if v.tipe == "raid" and name == L[k] then
					self:SetDone(k, 2, reset)
				end
			end
		end
	end
end

function AltManager:CheckBGCurrency()
	-- Only run checks if the daily task is actively "Not Done" (0)
	if self:GetStatus("BG") == 0 then
		if not GetCurrencyInfo then return end
		local _, _, quantity = GetCurrencyInfo(BG_CURRENCY_ID)
		quantity = quantity or 0

		-- Ensure a meaningful token gain occurred, and ignore baseline setup values (0)
		if bgCurrencySnapshot > 0 and quantity > bgCurrencySnapshot then
			local inBG       = UnitInBattleground("player")
			local inBossZone = WORLD_BOSS_ZONES[GetZoneText()]
			
			if inBG and not inBossZone then
				self:SetDone("BG", 2, GetQuestResetTime())
			end
		end
		bgCurrencySnapshot = quantity
	else
		-- If already marked completed, keep updating the snapshot silently 
		-- to prevent reload/desync spikes later.
		if GetCurrencyInfo then
			local _, _, quantity = GetCurrencyInfo(BG_CURRENCY_ID)
			bgCurrencySnapshot = quantity or 0
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
-- Saved variable loading / expiry
------------------------------------------------------------------------
function AltManager:LoadSV()
	if self.db.char then wipe(self.db.char) end
	if self.db.global then
		for k1, v1 in pairs(self.db.global) do
			if k1 ~= "LastReset" then
				for k2, v2 in pairs(v1) do
					-- Explicitly bypass custom layout metrics tables
					if k2 ~= "profCooldowns" and k2 ~= "professions" and type(v2) == "table" then
						local dbDone = v2.done
						local dbReset = v2.reset
						
						if dbDone and dbDone == 2 then
							if not dbReset then
								if tasks[k2] and tasks[k2].isDaily then
									dbReset = time() + SecondsUntilDailyReset()
								else
									dbReset = self.db.global[k1].LastReset and self.db.global[k1].LastReset.reset
								end
							end
							
							-- CRITICAL: Ensure local modifications are completely character isolated
							if dbReset and dbReset < time() then 
								if k1 == me then
									self:SetDone(k2, 0) 
								else
									self.db.global[k1][k2].done = 0 
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
-- Minimap icon
------------------------------------------------------------------------
function AltManager:CreateMinimapIcon()
	if not LDB then return end

	local function BuildTooltip(tt)
		tt:AddLine("|cFFFFD700AltManager-Epoch|r")
		tt:AddLine("|cFFAAAAAA"..L.ClickToOpen.."|r")
		tt:AddLine(" ")

		local function ResetStr(taskKey)
			if tasks[taskKey].isDaily then
				return FormatTimeUntil(nil, true)
			else
				return FormatTimeUntil(GetResetForAlt(me, taskKey), false)
			end
		end

		tt:AddLine("|cFFFFFFFF"..L.RaidIDs.."|r")
		for _, taskKey in ipairs(columnOrder) do
			if tasks[taskKey].tipe == "raid" then
				local done = GetDoneForAlt(me, taskKey)
				local r,g,b = DoneColor(done)
				tt:AddDoubleLine(L[taskKey], DoneText(done).." |cFFAAAAAA("..ResetStr(taskKey)..")|r", 1,1,1, r,g,b)
			end
		end
		tt:AddLine(" ")
		tt:AddLine("|cFFFFFFFF"..L.DailyQuests.."|r")
		for _, taskKey in ipairs(columnOrder) do
			if tasks[taskKey].tipe == "job" or tasks[taskKey].tipe == "misc" then
				local done = GetDoneForAlt(me, taskKey)
				local r,g,b = DoneColor(done)
				tt:AddDoubleLine(L[taskKey], DoneText(done).." |cFFAAAAAA("..ResetStr(taskKey)..")|r", 1,1,1, r,g,b)
			end
		end

		-- Profession cooldowns for current character
		local db = AltManager.db.global[me]
		if db and db.professions then
			local hasAny = false
			for _, cd in ipairs(PROF_COOLDOWNS) do
				if db.professions[cd.profID] then hasAny = true break end
			end
			if hasAny then
				tt:AddLine(" ")
				tt:AddLine("|cFFFFFFFFProfession Cooldowns|r")
				for _, cd in ipairs(PROF_COOLDOWNS) do
					if db.professions[cd.profID] then
						local expiry  = db.profCooldowns and db.profCooldowns[cd.key] or 0
						local cdStr   = FormatCooldownExpiry(expiry)
						local isReady = (not expiry or expiry == 0 or expiry <= time())
						local r,g,b   = isReady and 0.2,0.8,0.2 or 1.0,0.5,0.5
						tt:AddDoubleLine(cd.label.." ("..cd.cdSlot..")", cdStr, 1,1,1, r,g,b)
					end
				end
			end
		end
	end

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
		OnTooltipShow = function(tt)
			BuildTooltip(tt)
		end,
	})

	if LDBIcon then
		LDBIcon:Register("AltManager", AltManagerLDB, self.db.profile.minimap)
	end
end

------------------------------------------------------------------------
-- Logout
------------------------------------------------------------------------
function AltManager:OnLogout()
	self:GetWeeklyReset()
	self:CheckIDs()
	self:SaveProfessions()
	self:SaveProfCooldowns()
end
