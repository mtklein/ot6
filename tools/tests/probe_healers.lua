-- probe_healers.lua -- survey: at each of a few field fixtures, who is in the
-- party, what HP/MP they have, and which cure spells they actually know.
-- Reads only.  Answers "is there a healer here" from the learn array
-- ($1A6E + 54*actor + spell, field-care-menu.md section 5.3) rather than from
-- a level table or a design document.
--
--   OT6_KEEP_RUNS=1 OT6_NO_PUBLISH=1 tools/tests/run.sh tools/tests/probe_healers.lua
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = { [0] = "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN",
                "CELES", "STRAGO", "RELM", "SETZER", "MOG", "GAU", "GOGO",
                "UMARO" }
local SPELLS = { [0x2D] = "Cure", [0x2E] = "Cure2", [0x2F] = "Cure3",
                 [0x30] = "Life", [0x31] = "Life2" }

-- compose.py inlines savestate sidecars it can see as string literals, so
-- these have to be written out rather than built by concatenation.
--
-- Only fixtures that tools/tests/lib/savestate_ninja.py still names are
-- listed.  The originally surveyed set included vargas_doorstep,
-- kolts_doorstep and tunnelarmr_doorstep, which exist in a seeded
-- build/states from before those three were renamed to *_entry but are not
-- targets any more, so a survey naming them would stop working the moment
-- the chain is regenerated.
local STATES = {
  { "sfigaro_passage",    "build/states/sfigaro_passage.mss.lua" },
  { "returner_hideout",   "build/states/returner_hideout.mss.lua" },
  { "gau_joined",         "build/states/gau_joined.mss.lua" },
  { "zozo_arrival",       "build/states/zozo_arrival.mss.lua" },
  { "reunion_ready",      "build/states/reunion_ready.mss.lua" },
}

local steps = { H.waitFrames(20) }
for _, st in ipairs(STATES) do
  local name, path = st[1], st[2]
  steps[#steps + 1] = H.loadState(path)
  steps[#steps + 1] = H.waitFrames(20)
  steps[#steps + 1] = H.call(function()
    H.log("=== " .. name .. "  map " .. H.mapId())
    for _, c in ipairs(H.partyMembers()) do
      local base = 0x1600 + 37 * c
      local actor = H.readByte(base)
      local known = {}
      for id = 0x2D, 0x31 do
        local pct = H.readByte(0x1A6E + 54 * actor + id)
        if pct > 0 then
          known[#known + 1] = string.format("%s=%s", SPELLS[id],
            pct == 0xFF and "known" or tostring(pct))
        end
      end
      H.log(string.format(
        "  c%-2d %-6s actor %-2d lv %-2d  hp %4d/%-4d  mp %3d/%-3d  %s",
        c, NAMES[c] or "?", actor, H.readByte(base + 8),
        H.readWord(base + 9), H.charMaxHp(c),
        H.readWord(base + 13), H.readWord(base + 15) & 0x3FFF,
        #known > 0 and table.concat(known, " ") or "no cure spells"))
    end
    H.log(string.format("  bag: tonic=%d potion=%d fenix=%d",
      H.invCountOf(0xE8), H.invCountOf(0xE9), H.invCountOf(0xF0)))
  end)
end

H.run({ maxFrames = 40000 }, steps)
