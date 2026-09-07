-- probe_shield_rows.lua -- issue #157: do c0fb032's class keys seed?
--
-- Ot6SeedShields (ff6/src/battle/ot6_break.asm) scans Ot6ShieldTbl from
-- the top and takes the first matching species.  Cirpius $0086 and the
-- Zozo four ($0052 $004E $0053 $00DF) carried a shield-only row (class
-- $00) ahead of their keyed row, so the keyed row never seeded.  This
-- probe measures that from a legitimately reached fixture, on whichever
-- ROM build/ot6.sfc is: it walks into randoms, plays them with the
-- route's own tactical driver, and logs per monster slot the class byte
-- the engine seeded (OT6_BP_CLASS, $3E9C + entity; monsters are entity
-- 8 + slot*2, so $3EA4 + slot*2) and per party action the target's
-- shield count before -> after.  A physical Fight whose class is in the
-- seeded mask chips a shield; one whose class is not leaves it alone.
--
--   AREA=zozo   build/states/zozo_arrival.mss  map 221 (61,44): group 78
--               (Gabbldegak x4 / Harvester+Gabbldegak x2 / HadesGigas x1
--               / Harvester+HadesGigas).  The route's driver: tool = Bio
--               Blaster (the poison key), everyone else Fights.
--   AREA=kolts  build/states/kolts_entry.mss    map 95 (14,35): no randoms
--               there; K1 (11,26) -> map 100 shelf F, K2 (19,17) -> map 96
--               cave P, whose group 61 is Cirpius x3 in every roll.
--               The route's driver: tool = AutoCrossbow (default).
--
-- Reads and pad presses only; the CPU exec callbacks are read-only
-- observers.  Battles are fought, never fled; care between fights is the
-- lib's own fieldCare (Tonics).  One [shieldprobe] line per event.
--
--   sed -e 's/@AREA@/zozo/' tools/tests/probe_shield_rows.lua > build/shieldprobe/zozo.lua
--   tools/tests/run.sh build/shieldprobe/zozo.lua build/shieldprobe/zozo_<rom>.log
local H = dofile("tools/tests/lib/ot6.lua")

local AREA = "@AREA@"
if AREA:find("@") then AREA = "zozo" end
local FIGHTS = 4                       -- battles to measure, then stop
local LEGS = 60                        -- pacing legs allowed per random

local SPECIES = { [0x0052] = "SlamDancer", [0x004E] = "Harvester",
                  [0x0053] = "HadesGigas", [0x00DF] = "Gabbldegak",
                  [0x0086] = "Cirpius", [0x007A] = "Tusker", [0x000B] = "Brawler" }
local ATTACK = { [0x7D] = "BioBlaster", [0xA4] = "BioBlaster", [0x5D] = "Pummel",
                 [0x2D] = "Cure", [0xFF] = "Fight", [0xAA] = "AutoCrossbow",
                 [0xEE] = "Battle", [0xEF] = "Special" }
local CLASSNAME = { "SLASH", "PIERCE", "BLUDG", "SPECIAL" }
local function classStr(mask)
  local n = {}
  for i = 0, 3 do if (mask >> i) & 1 == 1 then n[#n + 1] = CLASSNAME[i + 1] end end
  return #n > 0 and table.concat(n, "|") or "none"
end
local function atkName(id) return ATTACK[id] or string.format("$%02X", id) end
local function spName(w) return SPECIES[w] or string.format("$%04X", w) end

local BCHID, BCHP, BCMAXHP = 0x3ED8, 0x3BF4, 0x3C1C
local function map() return H.mapId() & 0x1ff end
local function slotChar(s) return H.readByte(BCHID + s * 2) end
local function monSpecies(i) return H.readWord(0x57C0 + i * 2) end
local function monHp(i) return H.readWord(0x3BFC + i * 2) end
local function monShields(i) return H.readByte(0x3E40 + i * 2) end
local function monMaxShields(i) return H.readByte(0x3E41 + i * 2) end
local function monClass(i) return H.readByte(0x3E9C + 8 + i * 2) end   -- OT6_BP_CLASS, monster half
local function monPresent(i) return H.readByte(0x3AA8 + i * 2) % 2 == 1 end
local function partyHp()
  local p = {}
  for e = 0, 3 do p[e + 1] = H.readWord(BCHP + e * 2) end
  return p
end
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("c%d:%d/%d", slotChar(e), H.readWord(BCHP + e * 2), H.readWord(BCMAXHP + e * 2))
  end
  return table.concat(p, ",")
end
-- $1600 + 37*c: +$1F R-Hand, +$20 L-Hand (item ids; $FF = empty).  (+$1A..
-- +$1D are vigor/speed/stamina/magic; a first draft read those.)
local function hands(c)
  if c > 15 then return string.format("c%d:-", c) end
  local b = 0x1600 + 37 * c
  return string.format("c%d:R=$%02X,L=$%02X", c, H.readByte(b + 0x1F), H.readByte(b + 0x20))
end
local function monsterLine()
  local m = {}
  for i = 0, 5 do
    if monPresent(i) then
      m[#m + 1] = string.format("s%d:%s:hp=%d:sh=%d/%d:class=$%02X(%s)", i, spName(monSpecies(i)),
        monHp(i), monShields(i), monMaxShields(i), monClass(i), classStr(monClass(i)))
    end
  end
  return table.concat(m, " ")
end

-- ---------------------------------------------------- the observers --
-- ExecCmd@battle_code runs with X = the acting entity ($00..$06 party,
-- $08..$12 monsters), $b5/$b6 command/attack after spell folding, $b8
-- the target word.  SaveForMimic runs right after the command resolves.
-- Buffered and flushed from the frame loop.
local pending, events = {}, {}
local function hookObservers()
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if x % 2 ~= 0 or x > 0x06 then return end
    local msh, mhp = {}, {}
    for i = 0, 5 do msh[i + 1] = monShields(i); mhp[i + 1] = monHp(i) end
    pending[x] = { cmd = H.readByte(0xB5), atk = H.readByte(0xB6),
                   tgt = H.readWord(0xB8), msh = msh, mhp = mhp }
  end, emu.callbackType.exec, H.sym("ExecCmd@battle_code"), H.sym("ExecCmd@battle_code"))
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    local p = pending[x]
    if not p then return end
    pending[x] = nil
    local slot = x // 2
    local md = {}
    for i = 0, 5 do
      if monPresent(i) or p.mhp[i + 1] > 0 then
        local chip = (monShields(i) < p.msh[i + 1]) and " CHIP" or ""
        md[#md + 1] = string.format("s%d:%s:hp=%d->%d:sh=%d->%d%s", i, spName(monSpecies(i)),
          p.mhp[i + 1], monHp(i), p.msh[i + 1], monShields(i), chip)
      end
    end
    events[#events + 1] = string.format(
      "[act] f%d c%d(slot%d) cmd=%02X atk=%s tgt=%04X %s", H.frame, slotChar(slot), slot,
      p.cmd, atkName(p.atk), p.tgt, table.concat(md, " "))
  end, emu.callbackType.exec, H.sym("SaveForMimic"), H.sym("SaveForMimic"))
end
local function flushEvents()
  for _, e in ipairs(events) do H.log("[shieldprobe] " .. e) end
  events = {}
end

-- ---------------------------------------------------- the driver --
-- The route's own tactical driver, as navTo builds it (ot6_field.lua
-- newFightDriver("navTo", ...)): tool differs per area the way the
-- generators differ (gen_zozo3_clock: Bio Blaster; gen_kolts: default).
local TOOL = (AREA == "zozo") and H.BIO_BLASTER or nil
local F = H.newFightDriver("shieldprobe " .. AREA,
  { tactical = true, boost = true, items = true, healPercent = 55, tool = TOOL })

local fights = 0
local battle = { started = nil }
local offN, wipeN = 0, 0

local function fightStep()
  return H.driveUntil(function()
    if battle.over then return true end
    if H.battleLoadStarted() then
      offN = 0
      if battle.started == nil then battle.started = H.frame end
      -- the seeded line waits for Ot6SeedShields to have run on every
      -- present slot (max shields nonzero; a 0-shield species would wait
      -- the 120-frame fallback), since slots fill over several frames
      local anyMon, allSeeded = false, true
      for i = 0, 5 do
        if monPresent(i) then
          anyMon = true
          if monMaxShields(i) == 0 then allSeeded = false end
        end
      end
      if battle.form == nil and anyMon and (allSeeded or H.frame - battle.started >= 120) then
        battle.form = true
        local hs = {}
        for s = 0, 3 do hs[#hs + 1] = hands(slotChar(s)) end
        H.log(string.format("[shieldprobe] battle up f%d map=%d party=%s hands=%s",
          H.frame, map(), partyLine(), table.concat(hs, " ")))
        H.log(string.format("[shieldprobe] seeded f%d %s", H.frame, monsterLine()))
      end
      local dead, any = 0, false
      for e = 0, 3 do
        if H.readWord(BCMAXHP + e * 2) > 0 then
          any = true
          if H.readWord(BCHP + e * 2) == 0 then dead = dead + 1 end
        end
      end
      if any and dead == 4 then wipeN = wipeN + 1 else wipeN = 0 end
      if wipeN >= 120 then
        battle.over = H.frame
        H.log(string.format("[shieldprobe] WIPED f%d party=%s vs %s", H.frame, partyLine(), monsterLine()))
        return true
      end
      return false
    end
    if battle.started ~= nil then
      offN = offN + 1
      if offN >= 30 then
        battle.over = H.frame
        F.idle()
        fights = fights + 1
        H.log(string.format("[shieldprobe] battle %d over f%d (%d frames)", fights, H.frame, battle.over - battle.started))
        return true
      end
    end
    return false
  end, 30000, {
    H.call(function()
      flushEvents()
      if H.battleLoadStarted() then F.frame() else H.setPad({}) end
    end),
  }, "the fight")
end

-- Walk toward (tx,ty) until a random rolls (or the map changes, for the
-- crossings).  playBattles is declared so navTo's own driver takes any
-- battle that the arrive predicate somehow misses; fights are ours.
local function walkLeg(tx, ty, opts)
  opts = opts or {}
  return H.navTo(tx, ty, {
    maxFrames = opts.maxFrames or 8000, playBattles = "tactical", care = false,
    tool = TOOL, avoid = opts.avoid,
    arrive = function()
      if H.battleLoadStarted() then return true end
      if opts.untilMap ~= nil and map() == opts.untilMap then return true end
      -- stopShort: settle one tile short of (tx,ty) (an exit tile)
      if opts.stopShort and H.tileAligned()
         and math.abs(H.fieldX() - tx) + math.abs(H.fieldY() - ty) <= 1 then return true end
      return false
    end,
  })
end

local function oneFight(legs)
  -- legs: list of {x, y, stopShort=}; alternate until a battle rolls, then
  -- fight it
  local steps = {}
  for n = 1, LEGS do
    local leg = legs[(n - 1) % #legs + 1]
    steps[#steps + 1] = H.cond(function()
      return battle.started == nil and not H.battleLoadStarted()
    end, { walkLeg(leg[1], leg[2], { stopShort = leg.stopShort }) }, {})
  end
  steps[#steps + 1] = H.call(function()
    if not H.battleLoadStarted() then error("no random rolled in " .. LEGS .. " legs", 0) end
  end)
  steps[#steps + 1] = fightStep()
  steps[#steps + 1] = H.call(function() battle = { started = nil } end)
  steps[#steps + 1] = H.waitFrames(60)
  steps[#steps + 1] = H.fieldCare({ tag = "care after fight", threshold = 0.85 })
  return H.cond(function() return true end, steps)
end

local function settled(n)
  local cnt = 0
  return function()
    local ok = (emu.getState()["ppu.screenBrightness"] or 0) >= 15
      and H.tileAligned() and not H.battleLoadStarted() and not H.dialogWaiting()
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

-- a crossing leg: walk to the entrance tile; if a random rolls on the way,
-- fight it (measured too: Kolts map 100 is Brawler/Tusker) and try again
local function crossTo(tx, ty, dstMap, avoid)
  local steps = {}
  for n = 1, 6 do
    steps[#steps + 1] = H.cond(function() return map() ~= dstMap end, {
      H.call(function() battle = { started = nil } end),
      walkLeg(tx, ty, { untilMap = dstMap, maxFrames = 20000, avoid = avoid }),
      H.cond(function() return H.battleLoadStarted() end, {
        fightStep(),
        H.call(function() battle = { started = nil } end),
        H.waitFrames(60),
        H.fieldCare({ tag = "care after crossing fight", threshold = 0.85 }),
      }, {}),
    }, {})
  end
  steps[#steps + 1] = H.release()
  steps[#steps + 1] = H.waitFrames(90)
  steps[#steps + 1] = H.advanceStory(settled(20), 6000, { playBattles = "tactical" })
  steps[#steps + 1] = H.call(function()
    H.assertEq(map(), dstMap, "crossed to map " .. dstMap)
    H.log(string.format("[shieldprobe] on map %d at (%d,%d) f%d", map(), H.fieldX(), H.fieldY(), H.frame))
  end)
  return H.cond(function() return true end, steps)
end

local steps = {}
if AREA == "zozo" then
  steps[#steps + 1] = H.loadState("build/states/zozo_arrival.mss.lua")
  steps[#steps + 1] = H.waitFrames(150)
  steps[#steps + 1] = H.call(function()
    hookObservers()
    H.assertEq(map(), 221, "booted on the Zozo street (map 221)")
    H.log(string.format("[shieldprobe] zozo start (%d,%d) f%d", H.fieldX(), H.fieldY(), H.frame))
  end)
  steps[#steps + 1] = H.fieldCare({ tag = "care before the street", threshold = 0.95 })
  -- gen_zozo3_clock's first leg is (61,44) -> the cafe door (42,29); pace
  -- the same street between those two points
  for _ = 1, FIGHTS do steps[#steps + 1] = oneFight({ { 42, 29 }, { 61, 44 } }) end
else
  steps[#steps + 1] = H.loadState("build/states/kolts_entry.mss.lua")
  steps[#steps + 1] = H.waitFrames(150)
  local avoid37 = {}
  for x = 0, 27 do avoid37[#avoid37 + 1] = { x, 37 } end
  steps[#steps + 1] = H.call(function()
    hookObservers()
    H.assertEq(map(), 95, "booted at the Mt. Kolts entrance (map 95)")
    H.log(string.format("[shieldprobe] kolts start (%d,%d) f%d", H.fieldX(), H.fieldY(), H.frame))
  end)
  steps[#steps + 1] = crossTo(11, 26, 100, avoid37)        -- K1: entrance -> shelf F
  steps[#steps + 1] = crossTo(19, 17, 96)                  -- K2: shelf F -> cave 96 P
  -- pace cave P between the arrival tile (16,22) (kolts_cave.log: "[K2
  -- shelf F -> cave 96 P] map=96 field=(16,22)") and one tile short of
  -- K3's exit (22,21), which would drop onto shelf D
  for _ = 1, FIGHTS do
    steps[#steps + 1] = oneFight({ { 22, 21, stopShort = true }, { 16, 22 } })
  end
end
steps[#steps + 1] = H.call(function()
  H.log(string.format("[shieldprobe] done: %d fights measured on %s", fights, AREA))
end)

H.run({ maxFrames = 120000 }, steps)
