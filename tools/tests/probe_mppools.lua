-- probe_mppools.lua -- MEASUREMENT, not an assertion.  Boots minted states
-- across the WoB bands and dumps every character's $1600 record (level, cur/max
-- HP, cur/max MP) so the MP economy can be priced against REAL pools instead of
-- against the base-stat estimate mp-economy.md's "Early pools" section carries.
--
-- Record layout ($1600 + 37*charId, field-ram.txt:885-898, same fields
-- battle_levelup.lua reads): +$08 level, +$09/$0b cur/max HP,
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

-- One state per band.  BATTLE-time states are deliberately absent: inside a
-- battle the $1600 block is not the field record layout, so it reads as
-- nonsense (narshe_battle dumps every character at "LV7, 1799/1799") -- use a
-- field doorstep for every band.
local STATES = {
  "build/states/worldmap_narshe.mss.lua",   -- Narshe band (opening)
  "build/states/kolts_doorstep.mss.lua",    -- Mt Kolts band
  "build/states/gau_joined.mss.lua",        -- Veldt/Serpent-Trench band
  "build/states/scenario_hub.mss.lua",      -- post-scenario band
  "build/states/zozo_arrival.mss.lua",      -- Zozo band
  "build/states/opera_doorstep.mss.lua",    -- Opera band
  "build/states/vector_doorstep.mss.lua",   -- Vector band
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
