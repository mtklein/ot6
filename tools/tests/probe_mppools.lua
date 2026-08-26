-- probe_mppools.lua -- a measurement, not an assertion.  Boots generated
-- states across the WoB areas and dumps every character's $1600 record
-- (level, cur/max HP, cur/max MP).
--
-- Record layout ($1600 + 37*charId): +$08 level, +$09/$0b cur/max HP,
-- +$0d/$0f cur/max MP.
--
-- Output is one "[ot6] POOL <state> <charId> <name> lv=.. mp=../.. hp=../.."
-- line per character per state; grep the run log for POOL.
local H = dofile("tools/tests/lib/ot6.lua")

local CHARS = {
  [0] = "Terra", [1] = "Locke", [2] = "Cyan", [3] = "Shadow", [4] = "Edgar",
  [5] = "Sabin", [6] = "Celes", [7] = "Strago", [8] = "Relm", [9] = "Setzer",
  [10] = "Mog", [11] = "Gau", [12] = "Gogo", [13] = "Umaro",
}

-- One state per area. Battle-time states are excluded: inside a battle
-- the $1600 block is not the field record layout.
local STATES = {
  "build/states/worldmap_narshe.mss.lua",   -- Narshe area (opening)
  "build/states/kolts_entry.mss.lua",    -- Mt Kolts area
  "build/states/gau_joined.mss.lua",        -- Veldt/Serpent-Trench area
  "build/states/scenario_hub.mss.lua",      -- post-scenario area
  "build/states/zozo_arrival.mss.lua",      -- Zozo area
  "build/states/opera_entry.mss.lua",    -- Opera area
  "build/states/vector_entry.mss.lua",   -- Vector area
}

local function dump(tag)
  return H.call(function()
    for id = 0, 13 do
      local b = 0x1600 + 37 * id
      local lv = H.readByte(b + 0x08)
      local mp, mmp = H.readWord(b + 0x0d), H.readWord(b + 0x0f)
      local hp, mhp = H.readWord(b + 0x09), H.readWord(b + 0x0b)
      if lv > 0 and lv < 100 and mhp > 0 then
        H.log(string.format("POOL %-18s %2d %-7s lv=%2d mp=%d/%d hp=%d/%d",
          tag, id, CHARS[id] or "?", lv, mp, mmp, hp, mhp))
      end
    end
  end)
end

local steps = { H.waitFrames(20) }
for _, s in ipairs(STATES) do
  local tag = s:match("([^/]+)%.mss%.lua$")
  steps[#steps + 1] = H.loadState(s)
  steps[#steps + 1] = H.waitFrames(20)
  steps[#steps + 1] = dump(tag)
end
steps[#steps + 1] = H.logStep(function() return "probe_mppools complete" end)

H.run({ maxFrames = 20000 }, steps)
