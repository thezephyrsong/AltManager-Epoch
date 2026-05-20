if not AltManager then return end

local L = LibStub('AceLocale-3.0'):GetLocale('AltManager')
local me = GetUnitName("Player").." - "..GetRealmName()

function AltManager:Options()
	local AMOptions = {
	  type="group",
	  args={
		HandleRaid={
		  name=L.RaidIDs,
		  type="group",
		  args={
			HandleOny25={
			  name=L.Ony25,
			  desc=L.ToggleDesc..L.Ony25,
			  type="toggle",
			  set = function(info,val) AltManager.db.global[me].Ony25.handle = val end,
			  get = function(info) return AltManager.db.global[me].Ony25.handle end
			},
			HandleMC25={
			  name=L.MC25,
			  desc=L.ToggleDesc..L.MC25,
			  type="toggle",
			  set = function(info,val) AltManager.db.global[me].MC25.handle = val end,
			  get = function(info) return AltManager.db.global[me].MC25.handle end
			},
		  },
		},
		HandleJobQuests={
		  name=L.JobQuests,
		  type="group",
		  args={
			HandleSili={
			  name=L.Sili,
			  desc=L.ToggleDesc..L.Sili,
			  type="toggle",
			  set = function(info,val) AltManager.db.global[me].Sili.handle = val end,
			  get = function(info) return AltManager.db.global[me].Sili.handle end
			},
		  },
		},
		HandleMisc={
		  name=L.Misc,
		  type="group",
		  args={
			HandleBG={
			  name=L.BG,
			  desc=L.ToggleDesc..L.BG,
			  type="toggle",
			  set = function(info,val) AltManager.db.global[me].BG.handle = val end,
			  get = function(info) return AltManager.db.global[me].BG.handle end
			},
		  },
		},
	  },
	}
	return AMOptions
end
