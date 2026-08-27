-- probe_ifritlab_grind.lua -- Ifrit & Shiva lab: the LEVEL ARM feasibility probe.
--
-- Question: can the Facility party grind UP at this checkpoint before the
-- Ifrit & Shiva fight?  The design's own grind pocket (Chimera, level-curve.md
-- "Pre-FC grinding") is reachable only with the Blackjack, which is awarded
-- AFTER the MRF escape -- so the only pre-fight grind is the MRF's own random
-- trash.  Map 264 (the Ifrit/Shiva alcove) is battle group 104: Flan x4 / x1
-- (break-coverage-vector.md), Flan = L19, 255 HP, XP 160, fire-weak,
-- BLUDGEON-shielded (Sabin's Pummel is the party's only class key on it).
--
-- This probe boots ifritlab_entry.mss, paces the alcove WITHOUT pressing A
-- (A into IFRIT starts battle 70, not a random), fights up to FIGHTS random
-- encounters with the lib tactical driver, Tonic-cares between them, and logs
-- per-character XP/level deltas and the bag (Tonic/Potion/Fenix) after each.
-- It PASSes either way -- it measures the grind's price tag (XP/fight,
-- fights-to-L+1, resource drain, wipe risk), it does not assert a level.
--
-- Run:  OT6_TIMEOUT=1800 tools/tests/run.sh tools/tests/probe_ifritlab_grind.lua \
--       build/ifritlab/grind_smoke.log

local H = dofile("tools/tests/lib/ot6.lua")

local LOCKE, EDGAR, SABIN, CELES = 1, 4, 5, 6
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local FIGHTS = tonumber("@FIGHTS@") or 6
if tostring(FIGHTS):find("@") then FIGHTS = 6 end
-- Resumable rolling-fixture grind (probe_grind_run.lua pattern): a shell loop
-- seeds ifritlab_grind_run.mss from ifritlab_entry.mss, then runs this probe
-- over it repeatedly; each chunk grinds FIGHTS fights and re-saves the rolling
-- fixture, so XP accumulates and at most one fight is ever lost to a wipe.
-- When every character is at least GOAL_LEVEL the probe also banks
-- ifritlab_entry_healthy.mss (the level arm's re-test fixture).
local FIXTURE = "@FIXTURE@"
if FIXTURE:find("@") then FIXTURE = "ifritlab_entry" end
local GOAL_LEVEL = tonumber("@GOAL@") or 20
if tostring(GOAL_LEVEL):find("@") then GOAL_LEVEL = 20 end

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function seq(steps) return H.cond(function() return true end, steps) end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted()
end

local CHARS = { [LOCKE] = "LOCKE", [EDGAR] = "EDGAR", [SABIN] = "SABIN",
                [CELES] = "CELES" }
local function charLevel(c) return H.readByte(0x1600 + 37 * c + 0x08) end
local function charXp(c)
  local b = 0x1600 + 37 * c
  return H.readByte(b + 0x11) | (H.readByte(b + 0x12) << 8)
         | (H.readByte(b + 0x13) << 16)
end
local function partyLine(tag)
  local out = {}
  for _, c in ipairs({ LOCKE, EDGAR, SABIN, CELES }) do
    out[#out + 1] = string.format("%s L%d xp=%d", CHARS[c], charLevel(c), charXp(c))
  end
  H.log(string.format("[grind %s] %s | bag t/p/f=%d/%d/%d", tag,
    table.concat(out, "  "), H.invCountOf(TONIC), H.invCountOf(POTION),
    H.invCountOf(FENIX_DOWN)))
end

-- tactical fighter for the trash: Sabin Pummel is bludgeon (Flan's class
-- key); AutoCrossbow is pierce; boost banks for the break burst.  A
-- designated healer would tie up a chipper, so leave healing opportunistic.
local tactical = H.newFightDriver("grind", { tactical = true, boost = true,
  bank = 2, items = true, healPercent = 55 })

local xp0 = {}
local wiped = false
local fightsFought, fightsFled = 0, 0

-- pace the alcove: walk one direction until the tile stops changing (a wall),
-- then reverse.  NEVER press A (that starts battle 70 or talks an esper).
local paceDir = "right"
local lastX, lastY, stuck = -1, -1, 0
local function paceFrame()
  local battN = H.battleLoadStarted() and 1 or 0
  if H.battleActive() or battN > 0 then return "battle" end
  if not settled() then H.setPad({}); return "wait" end
  local x, y = H.fieldX(), H.fieldY()
  if x == lastX and y == lastY then stuck = stuck + 1 else stuck = 0 end
  lastX, lastY = x, y
  if stuck >= 6 then
    -- hit a wall or the NPC row: rotate the pace direction
    local order = { right = "up", up = "left", left = "down", down = "right" }
    paceDir = order[paceDir]
    stuck = 0
  end
  -- keep clear of the two esper tiles (IFRIT {3,8}, SHIVA {9,6}) so a bump
  -- can never auto-trigger; steer away if adjacent
  H.setPad({ [paceDir] = true })
  return "pace"
end

local res = { deaths = 0 }
local wasAlive = {}
local function trackDeaths()
  for e = 0, 3 do
    if H.readWord(0x3C1C + e * 2) > 0 then
      local alive = H.readWord(0x3BF4 + e * 2) > 0
      if wasAlive[e] and not alive then res.deaths = res.deaths + 1 end
      wasAlive[e] = alive
    else wasAlive[e] = nil end
  end
end

local function oneFight(i)
  local phase, fightF, sawBattle, done = 0, 0, false, false
  return seq({
    H.call(function() H.log(string.format("[grind] --- pacing for fight %d ---", i)) end),
    -- pace until a battle starts (or give up after a long walk)
    H.driveUntil(function()
      if H.battleLoadStarted() or H.battleActive() then sawBattle = true end
      if sawBattle and (H.battleLoadStarted() or H.battleActive()) then return true end
      fightF = fightF + 1
      return fightF > 12000
    end, 13000, { H.call(function()
      local st = paceFrame()
      if st == "battle" then sawBattle = true end
    end) }, "pace to a random encounter " .. i),
    -- fight it (or note no encounter came)
    H.cond(function() return sawBattle end, {
      H.waitUntil(function() return H.battleActive() end, 1200, "grind battle up " .. i, 20),
      H.call(function()
        local w = H.formationWords()
        H.log(string.format("[grind] fight %d formation = %04X %04X %04X %04X %04X %04X",
          i, w[1], w[2], w[3], w[4], w[5], w[6]))
      end),
      (function()
        local bf, notB, hb = 0, 0, 0
        return H.driveUntil(function()
          if H.battleLoadStarted() or H.battleActive() then notB = 0
          else notB = notB + 1 end
          if bf > 40 then
            local anyAlive = false
            for e = 0, 3 do if H.readWord(0x3BF4 + e * 2) > 0
              and H.readWord(0x3C1C + e * 2) > 0 then anyAlive = true end end
            if not anyAlive and (H.battleActive() or H.battleLoadStarted()) then
              wiped = true; return true end
          end
          return notB >= 90
        end, 40000, { H.call(function()
          if H.battleLoadStarted() or H.battleActive() then
            bf = bf + 1; trackDeaths()
          end
          hb = hb + 1
          tactical.frame()
        end) }, "grind fight " .. i)
      end)(),
      H.call(function()
        tactical.idle(); H.setPad({})
        if wiped then H.log(string.format("[grind] WIPE in fight %d", i))
        else fightsFought = fightsFought + 1 end
      end),
      -- Tonic care between fights (owner directive: field care with Tonics)
      H.cond(function() return not wiped and settled() end, {
        H.fieldCare({ tag = "grind care " .. i, threshold = 0.85 }),
      }, {}),
      H.call(function() partyLine("after fight " .. i) end),
    }, {
      H.call(function()
        H.log(string.format("[grind] NO encounter in fight %d's pace window", i))
      end),
    }),
  })
end

local steps = {
  -- compose.py embeds savestates by scanning loadState string LITERALS, so
  -- both the seed fixture and the rolling fixture are spelled out and FIXTURE
  -- picks at runtime.
  (function()
    local fixtures = {
      ifritlab_entry     = H.loadState("build/states/ifritlab_entry.mss.lua"),
      ifritlab_grind_run = H.loadState("build/states/ifritlab_grind_run.mss.lua"),
    }
    return assert(fixtures[FIXTURE], "unknown FIXTURE " .. FIXTURE)
  end)(),
  H.waitFrames(90),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
       and not H.dialogWaiting() and not H.battleLoadStarted()
  end, 2400, "grind fixture settled", 5),
  H.call(function()
    H.assertEq(map(), 264, "grind fixture on map 264")
    for _, c in ipairs({ LOCKE, EDGAR, SABIN, CELES }) do xp0[c] = charXp(c) end
    partyLine("start")
  end),
}
for i = 1, FIGHTS do
  steps[#steps + 1] = H.cond(function() return not wiped end, { oneFight(i) }, {})
end
-- On a clean chunk (no wipe): walk back to the (3,7) entry point, Tonic-care,
-- and re-bank the rolling fixture so the next chunk resumes with the XP.  A
-- wipe saves nothing (the last good rolling save stands).
local reachedGoal = false
steps[#steps + 1] = H.cond(function() return not wiped end, {
  H.navTo(3, 7, { maxFrames = 12000, playBattles = "tactical" }),
  H.fieldCare({ tag = "grind end care", threshold = 0.9 }),
  H.call(function()
    reachedGoal = true
    for _, c in ipairs({ LOCKE, EDGAR, SABIN, CELES }) do
      if charLevel(c) < GOAL_LEVEL then reachedGoal = false end
    end
  end),
  H.saveState("ifritlab_grind_run.mss"),
  H.cond(function() return reachedGoal end, {
    H.saveState("ifritlab_entry_healthy.mss"),
    H.call(function()
      H.log(string.format("[grind] GOAL REACHED (all >= L%d) -- baked "
        .. "ifritlab_entry_healthy.mss", GOAL_LEVEL))
    end),
  }, {}),
}, {})
steps[#steps + 1] = H.call(function()
  H.setPad({})
  local perLevel = {}
  for _, c in ipairs({ LOCKE, EDGAR, SABIN, CELES }) do
    perLevel[#perLevel + 1] = string.format("%s +%dxp L%d",
      CHARS[c], charXp(c) - (xp0[c] or 0), charLevel(c))
  end
  H.log(string.format(
    "[grind result] fixture=%s fights_fought=%d wiped=%s goal=%s deaths=%d "
    .. "gains: %s | bag_end t/p/f=%d/%d/%d",
    FIXTURE, fightsFought, tostring(wiped), tostring(reachedGoal), res.deaths,
    table.concat(perLevel, "  "),
    H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX_DOWN)))
end)

H.run({ maxFrames = 300000, allowGameOver = true }, steps)
