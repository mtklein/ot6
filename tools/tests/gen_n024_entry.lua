-- gen_n024_entry.lua -- v0.6 step 9: magicite_ifrit_shiva (map 264
-- {9,7}) -> a grind on map 264's y=7 row until every member is L21
-- (#173) -> {9,5} -> map 269 {44,53} -> {42,12} -> map 271 "MAGITEK RES.
-- FACILITY" {31,28} -> {3,27} -> map 273 {30,60} -> parked at {25,52}
-- facing UP, one A-press below NUMBER 024.  Generates n024_entry.

-- Three ordinary short entrances:
--     264 {9,5}   -> 269 {44,53}
--     269 {42,12} -> 271 {31,28}
--     271 {3,27}  -> 273 {30,60}
-- Unlike maps 262/263, 269/271/273 are single walking regions; the census
-- after each landing is logged below as the evidence.

-- NUMBER 024 is map 273 NPC_1 at {25,51}, behind switch $0649, with event
-- _cc79ed: battle 72, then switch $0649=0.  It stands directly below the
-- {25,50} short entrance to map 274 (the esper tube room), so it blocks
-- the only way on; the entry point asserts {25,50} is NO-PATH now, so a
-- later claim that the fight opened it can be checked.

local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end

local MAP_TITLE_PTRS, MAP_TITLE = 0x268400, 0x0EF100
local function mapTitleHere()
  local p = H.readRomWord(MAP_TITLE_PTRS + H.readByte(0x0520) * 2)
  local a, s = MAP_TITLE + p, ""
  for _ = 1, 24 do
    local c = H.readRomByte(a)
    if c == 0 then break end
    if     c >= 0x20 and c <= 0x39 then s = s .. string.char(65 + c - 0x20)
    elseif c >= 0x3A and c <= 0x53 then s = s .. string.char(97 + c - 0x3A)
    elseif c >= 0x54 and c <= 0x5D then s = s .. string.char(48 + c - 0x54)
    elseif c == 0x65 then s = s .. "."
    elseif c == 0x7F then s = s .. " "
    else s = s .. string.format("<%02X>", c) end
    a = a + 1
  end
  return s
end

local CHARS = { "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN",
                "CELES", "STRAGO", "RELM", "SETZER", "MOG", "GAU",
                "GOGO", "UMARO" }
local function partyReport(tag)
  local party, raw = {}, {}
  local cur = H.readByte(0x1A6D)
  for c = 0, 13 do
    local b = H.readByte(0x1850 + c)
    raw[#raw + 1] = string.format("%s=%02X", CHARS[c + 1], b)
    if (b & 0x07) == cur and b ~= 0 then
      local base = 0x1600 + 37 * c
      party[#party + 1] = string.format("%s(order %d, L%d, weapon %02X)",
        CHARS[c + 1], (b >> 3) & 3, H.readByte(base + 0x08),
        H.readByte(base + 0x1F))
    end
  end
  return string.format("[party @ %s] party#%d = %s   | $1850: %s | $1EDE=%02X $1EDF=%02X",
    tag, cur, table.concat(party, ", "), table.concat(raw, " "),
    H.readByte(0x1EDE), H.readByte(0x1EDF))
end

-- ------------------------------------------------------------ the roster --
-- $1600 + 37*c: +8 level, +$11 a 3-byte total experience (the same read
-- gen_zozo2_arrival's grind logs).
local POTION, TONIC, FENIX = 0xE9, 0xE8, 0xF0
local function levelOf(c) return H.readByte(0x1600 + 37 * c + 8) end
local function expOf(c)
  local b = 0x1600 + 37 * c + 0x11
  return H.readByte(b) + (H.readByte(b + 1) << 8) + (H.readByte(b + 2) << 16)
end
local function rosterLine()
  local out = {}
  for _, c in ipairs(H.partyMembers()) do
    out[#out + 1] = string.format("c%d L%d xp=%d %d/%d hp %d/%d mp", c,
      levelOf(c), expOf(c), H.charHp(c), H.charMaxHp(c),
      H.charMp(c), H.charMaxMp(c))
  end
  return string.format("%s | tonic=%d potion=%d fenix=%d",
    table.concat(out, " | "), H.invCountOf(TONIC), H.invCountOf(POTION),
    H.invCountOf(FENIX))
end
local function minLevel()
  local m = 99
  for _, c in ipairs(H.partyMembers()) do m = math.min(m, levelOf(c)) end
  return m
end
local function levels(tag)
  H.log(string.format("[levels @ %s] min L%d f%d %s", tag, minLevel(),
    H.frame, rosterLine()))
end

-- ----------------------------------------------------------- the grind --
-- Owner decision (#173, 2026-09-17): every member at least L21 before map
-- 269.  The Trapper trio's L4 Flare (docs/design/map269-random.md) hits
-- every member whose level is a multiple of 4, and the #198 chain brought
-- the party here at LOCKE L19 / EDGAR L20 / SABIN L20 / CELES L19 (all
-- four L20 by map 273), so one Flare killed EDGAR and SABIN from full.
-- L21 (26360 experience) is clear of L5 Doom, L4 Flare and L3 Muddle;
-- L24 (39056) is a multiple of 4 again, ~12700 experience past L21, far
-- more than maps 269/271/273 pay.
--
-- Where: the Flan room itself, map 264, the row y=7 between the save-room
-- door (3,5) and the 269 door (9,5).  It is where the party stands after
-- the save, the chute down from 263 is one-way ($0273, gen_ifrit_entry),
-- and its pool (group 104) is Flan x4 / Flan x1 only -- no Trapper.
-- Flan: L19, 255 HP, defence 13, weak fire, 160 experience (x2 OT6
-- reward, split among the living): ~320 each for x4, ~80 for x1.
local LEVEL_TARGET = 21
local grindLaps = 0
local function grindDone() return minLevel() >= LEVEL_TARGET end
local GRIND_NAV = { maxFrames = 9000, playBattles = "tactical",
                    avoid = { { 3, 6 }, { 9, 6 } } }
local function lap(n)
  return H.cond(function() return not grindDone() end, {
    H.logStep(function()
      return string.format("grind lap %d: min L%d (target L%d) %s f%d", n,
        minLevel(), LEVEL_TARGET, rosterLine(), H.frame)
    end),
    H.navTo(4, 7, GRIND_NAV),
    H.navTo(9, 7, GRIND_NAV),
    H.call(function() grindLaps = n end),
    -- care between fights: navTo's own after-battle stop (Tonics, then
    -- Potions) runs after every fight; this lap stop tops up a slow bleed
    -- with items only (magic = false: Tonics are the field heal)
    H.fieldCare({ tag = "care grind lap " .. n, threshold = 0.6, magic = false }),
  }, {})
end
local function grind()
  local steps = {
    H.call(function()
      H.assertEq(map(), 264, "grinding on map 264")
      levels("grind start")
    end),
  }
  for n = 1, 400 do steps[#steps + 1] = lap(n) end
  steps[#steps + 1] = H.call(function()
    H.log(string.format("[grind] %d laps: min L%d (target L%d) f%d",
      grindLaps, minLevel(), LEVEL_TARGET, H.frame))
    levels("grind end")
    H.assertEq(grindDone(), true,
      string.format("the grind reached L%d for every member in %d laps " ..
        "(lowest L%d)", LEVEL_TARGET, grindLaps, minLevel()))
  end)
  return H.cond(function() return true end, steps)
end

local DELTA = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 } }

local function census(tag, targets)
  local sx, sy = H.fieldX(), H.fieldY()
  local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
  local seen, q, qi = { [(sy & ym) * 256 + (sx & xm)] = true }, { { sx, sy } }, 1
  while qi <= #q and qi <= 3000 do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    for d, v in pairs(DELTA) do
      if H.canStep(x, y, d) then
        local nx, ny = (x + v[1]) & xm, (y + v[2]) & ym
        local k = ny * 256 + nx
        if not seen[k] then seen[k] = true; q[#q + 1] = { nx, ny } end
      end
    end
  end
  H.log(string.format("[census %s] from (%d,%d) on map %d: %d tiles reachable",
    tag, sx, sy, map(), #q))
  for _, t in ipairs(targets or {}) do
    local p = H.bfsPath(t[1], t[2])
    H.log(string.format("[census %s] -> (%d,%d) %-34s : %s", tag, t[1], t[2],
      t[3] or "", p and (#p .. " steps: " .. table.concat(p, " ")) or "NO PATH"))
  end
end

H.run({ maxFrames = 400000 }, {
  H.loadState("build/states/magicite_ifrit_shiva.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 264, "booted on map 264")
    H.assertEq(H.readByte(0x1A69) & 0x07, 0x07,
      "booted owning RAMUH + IFRIT + SHIVA ($1A69 bits 0-2)")
    H.log(partyReport("magicite_ifrit_shiva"))
  end),

  -- Care at the save before walking on.  magicite_ifrit_shiva is saved as
  -- battle 70 leaves the party: SABIN dead (the no-raise rule held through
  -- the win) and nobody healed since, and the first random on map 269 is
  -- Trapper x3, whose L4 Flare one-shots the L16s (docs/design/
  -- map269-random.md).  Measured there over 15 seeds: walking in cared
  -- (SABIN up, HP topped) versus as-saved cut the fight from a mean 8050
  -- frames to 3355, in-battle Fenix Downs from 27 to 0 and deaths from 16
  -- to 8; the remaining deaths are the level-parity finding, not the kit.
  -- Threshold 0.95 is gen_ifrit_magicite's own pre-battle-70 stop.  MP is
  -- left alone: battle_magicite / battle_subjob assert on this fixture's
  -- MP-dry CELES.
  H.fieldCare({ tag = "care at the Ifrit & Shiva save", threshold = 0.95 }),
  H.call(function() H.log(partyReport("after the save-room care")) end),

  grind(),
  H.fieldCare({ tag = "care after the grind", threshold = 0.95, magic = false }),
  H.call(function() levels("after the grind care") end),

  -- 264 {9,5} -> 269 {44,53}
  H.navTo(9, 5, { maxFrames = 9000, playBattles = "tactical", arrive = function() return map() == 269 end }),
  H.waitUntil(function() return map() == 269 and settled() end, 6000,
    "map 269 control", 5),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 269, "map 269")
    H.assertEq(H.fieldX(), 44, "269 landing x")
    H.assertEq(H.fieldY(), 53, "269 landing y")
    levels("map 269")
    census("269", { { 42, 12, "-> map 271" } })
  end),

  -- 269 {42,12} -> 271 {31,28}
  H.navTo(42, 12, { maxFrames = 25000, playBattles = "tactical", arrive = function() return map() == 271 end }),
  H.waitUntil(function() return map() == 271 and settled() end, 6000,
    "map 271 control", 5),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(mapTitleHere(), "MAGITEK RES. FACILITY",
      "the map the party is standing on calls itself MAGITEK RES. FACILITY")
    H.assertEq(map(), 271, "map 271")
    H.assertEq(H.fieldX(), 31, "271 landing x")
    H.assertEq(H.fieldY(), 28, "271 landing y")
    levels("map 271")
    census("271", { { 3, 27, "-> map 273" } })
    H.screenshot("mrf_facility")
  end),

  H.openChest{ stand = { 8, 38 }, face = "up", bit = 94,
               what = "Break Blade",
               nav = { playBattles = "tactical", careThreshold = 0.85, healPercent = 45, magic = { [6] = { spell = 2 } }, summon = { [6] = {} } } },

  -- 271 {3,27} -> 273 {30,60}
  H.navTo(3, 27, { maxFrames = 25000, playBattles = "tactical", arrive = function() return map() == 273 end }),
  H.waitUntil(function() return map() == 273 and settled() end, 6000,
    "map 273 control", 5),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 273, "map 273")
    H.assertEq(H.fieldX(), 30, "273 landing x")
    H.assertEq(H.fieldY(), 60, "273 landing y")
    H.assertEq(sw(0x0649), 1, "$0649 SET -- NUMBER 024 is on {25,51}")
    levels("map 273")
    census("273", {
      { 25, 52, "the 024 entry point" },
      { 25, 50, "the door to map 274 (esper tubes)" },
    })
  end),

  H.navTo(26, 52, { maxFrames = 9000, playBattles = "tactical", careThreshold = 0.85, healPercent = 45, magic = { [6] = { spell = 2 } }, summon = { [6] = {} } }),
  (function() local calm, W = 0, H.newWalkFighter("onto the save tile 273 (26,53)")
    return H.driveUntil(function()
      calm = (H.fieldX() == 26 and H.fieldY() == 53 and sw(0x01BF) == 1
              and H.tileAligned() and not H.dialogWaiting()
              and not H.battleLoadStarted()) and calm + 1 or 0
      return calm >= 8
    end, 9000, {
      H.call(function()
        if W.frame() then return end
        if H.dialogWaiting() then H.setPad({ "a" }); return end
        if H.fieldX() == 26 and H.fieldY() == 53 then H.setPad({}); return end
        H.setPad({ down = true })
      end),
    }, "onto the NEW save tile 273 (26,53)")
  end)(),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(sw(0x01BF), 1,
      "$01BF SET -- the NEW 273 save point runs the SavePoint script")
    H.assertEq(sw(0x01B5), 1, "$01B5 SET -- the once-per-tile latch took")
    -- the sparkle NPC is present at the authored tile: 273's NPCs are
    -- object $10 (NUMBER 024) and the appended $11 (the sparkle; record
    -- order is the object's identity)
    local off = 0x29 * 0x11
    H.assertEq(H.readWord(0x086a + off) >> 4, 26, "sparkle object $11 x")
    H.assertEq(H.readWord(0x086d + off) >> 4, 53, "sparkle object $11 y")
    H.assertExitContractPreSave("n024-entry-save-v1")
    H.screenshot("n024_save_point")
  end),

  -- park at {25,52}, facing UP into NUMBER 024 on {25,51}
  H.navTo(25, 52, { maxFrames = 15000, playBattles = "tactical", careThreshold = 0.85, healPercent = 45, magic = { [6] = { spell = 2 } }, summon = { [6] = {} } }),
  H.hold({ "up" }), H.waitFrames(8), H.release(), H.waitFrames(20),
  (function() local calm = 0
    return H.driveUntil(function()
      local ok = H.fieldX() == 25 and H.fieldY() == 52 and settled()
             and H.readByte(0x087f + H.readWord(0x0803)) == 0
      calm = ok and calm + 1 or 0
      if calm >= 20 then H.setPad({}); return true end
      return false
    end, 3000, {
      H.call(function()
        -- #183: no L+R here.  The pad is empty: no step, no encounter roll.
        if H.battleLoadStarted() then H.setPad({}); return end
        H.setPad({})
      end) }, "twenty settled frames below NUMBER 024")
  end)(),

  H.call(function()
    H.assertEq(map(), 273, "on map 273")
    H.assertEq(H.fieldX(), 25, "024 entry point x")
    H.assertEq(H.fieldY(), 52, "024 entry point y")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 0,
      "facing UP toward NUMBER 024 (EVENT_DIR 0)")
    H.assertEq(settled(), true, "the entry point is QUIET")
    H.assertEq(sw(0x0649), 1, "$0649 SET -- 024 has not been fought")
    H.assertEq(H.bfsPath(25, 50), nil,
      "CONTROL: the esper-tube door (25,50) is NO-PATH -- 024 plugs {25,51}")
    H.log(string.format("[n024_entry] f%d map=%d (%d,%d) face=%d",
      H.frame, map(), H.fieldX(), H.fieldY(),
      H.readByte(0x087f + H.readWord(0x0803))))
    H.log(partyReport("n024_entry"))
    levels("n024_entry")
    H.screenshot("n024_entry")
  end),
  H.saveState("n024_entry.mss"),

  -- Verify the entry point is one A-press from battle 72, after the state
  -- is generated.
  (function() local aPh = 0
    return H.driveUntil(function()
      return H.battleLoadStarted() and H.formationHas({ [0x010a] = true })
    end, 9000, {
      H.call(function() aPh = (aPh + 1) % 8
        H.setPad(aPh < 4 and { "a", "up" } or { "up" })
      end) }, "one A-press fires _cc79ed -> battle 72")
  end)(),
  H.call(function()
    local w = H.formationWords()
    H.assertEq(H.formationHas({ [0x010a] = true }), true,
      "VERIFIED: one A-press opened battle 72 with species $010A (Number 024)")
    H.log(string.format("[verify] formation = %04X %04X %04X %04X %04X %04X",
      w[1], w[2], w[3], w[4], w[5], w[6]))
    H.screenshot("n024_entry_verify")
  end),
  H.logStep(function()
    return string.format("n024_entry generated at frame %d -- map 273 (25,52) "
      .. "facing NUMBER 024, one A-press from battle 72", H.frame)
  end),
})
