-- gen_sabin_kefka.lua -- leg 3 of SABIN's scenario: the LEO scene, the
-- poisoning of Doma, both KEFKA gags, the pursuit, and the handoff back to
-- CYAN.  Mints one state:
--   kefka_done.mss  map 121 (DOMA CASTLE grounds), CYAN alone, controllable
--                   -- the first frame after the camp is behind us
--
-- THE CAMP IS A SWITCH LADDER, and the map enforces its order
-- (ff6/src/event/event_main.asm):
--   $002B  _cb0f2e :40303  trigger (36,22) -- the LEO scene
--   $002C  _cb1032 :40499  trigger (36,23) -- the poisoning, whose tail is
--          `switch $002C=1` + `call _cb1126` (:40639-40640).  THE FIRST
--          KEFKA FIGHT IS NOT SOMETHING YOU WALK UP TO: it is the last two
--          commands of the poisoning cutscene and it happens regardless.
--   $002D  _cb1126 :40670  `battle 56`, then KEFKA walks off DOWN_RIGHT
--   $002E  _cb1170 :40714  second talk -- NO battle, he only runs further
--   $002F  _cb1193 :40734  third talk, `battle 56` again
--   $0155  _cb1209 :40794  `battle 44`, the Kefka/poison cutscene, and
--          `call _cba0ec` (:40877)
--
-- ORDER IS NOT OPTIONAL, AND THE MAP WILL SHOVE YOU.  Once $002C is set,
-- two tile bands turn into one-way barriers:
--   (35..37,14) _cb1104 :40656  pushes the party DOWN 1 -- you cannot walk
--                               back north toward the gate
--   (18,29..32) _cb1112 :40668  pushes the party RIGHT 1 *unless* $002F
-- The second is why the KEFKA talks come before the walk west: (17,29) and
-- (17,31) are the tiles that fire the pursuit (_cb11cb/_cb11da, :40946
-- /:40955), they sit past the x=18 band, and the band only opens after the
-- third gag.  Walking west first would be shoved back east forever.
--
-- BOTH KEFKA GAGS ARE FIGHTS WITH NOTHING IN THEM.  `battle 56` is event
-- battle GROUP 56 (EventBattle, field/event.asm:1910-1919, reads
-- EventBattleGroup at group*4 as two formation words); group 56 is
-- {504, 504}, and formation 504's record in battle_monsters.dat (stride 15)
-- is present mask $00 with all six id slots the $01ff empty sentinel.  No
-- monster is loaded, so Ot6SeedShields never runs and the kill-bit idiom
-- has nothing to write to.  What ends the fight is battle_prop's
-- character-AI script ($2f49 bit 7, $2f4a = $04 = CHAR_AI::KEFKA_IMP_CAMP_1)
-- playing its lines out.  The driver treats "battle up, zero monsters
-- present" as a set-piece: hands off for 300 frames, then edge-tap A.
--
-- THE PURSUIT IS A REAL FIGHT: group 44 = formation 410, present mask $0f,
-- two $002 and two $001 -- four ordinary Imperial troops, kill-bitted.
--
-- WHERE THIS LEG ENDS, AND WHY NOT AT DOMA.  _cba0ec (:61858) does not
-- hand SABIN to map 119.  It takes CYAN back to Doma -- `load_map 121,
-- {23,12}` (:61870) -- and gives the player control of him again at
-- :62104.  Getting from there to SABIN on map 119 is another two maps of
-- walking (121 -> 123 -> 124, where trigger (28,36) fires the family scene
-- _cb1283 at :40863), so it is the next leg's problem and this one stops
-- on the first controllable frame of map 121.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/camp_intro.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local function seq(steps) return H.cond(function() return true end, steps) end

local CH_SEL, CH_MAX = 0x056E, 0x056F
local NAME_MENU = 0x0200
local function monSpecies(i) return H.readWord(0x57c0 + i * 2) end
local function monHp(i) return H.readWord(0x3bfc + i * 2) end
local function monShields(i) return H.readByte(0x3e40 + i * 2) end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local function monCount()
  local n = 0
  for i = 0, 5 do if monPresent(i) then n = n + 1 end end
  return n
end

-- BATTLE DETECTION, SLOT-AGNOSTIC -- and this is the whole reason run 2 of
-- this file died.  lib/ot6.lua's battleLoadStarted() reads ONE word, party
-- battle-HP slot 0 at $3BF4, and calls it "a battle has begun loading".
-- That holds for every fixture the harness had before this arc, because
-- every one of them fought with a party whose slot 0 was occupied.  CYAN's
-- solo defence of Doma does not: measured across the whole fight,
--     $3BF4=0000  $3BF6=00FE  $3BF8=0000  $3BFA=0000
-- CYAN is in battle slot ONE.  So battleLoadStarted() stayed false for the
-- entire battle, every driver in the run treated it as "no battle", nobody
-- pressed anything, and CYAN stood there while his HP ticked
-- FE -> D4 -> 94 -> 5A and the fight was lost.  The loss is then silent by
-- design: `battle 46` is followed by `call _ca5ea9` (:61522-61523), and
-- _ca5ea9 is `if_b_switch $40, _ca5eb2 / call GameOver` -- so a lost battle
-- leaves the event PC parked at $CB9EBB forever with the field still drawn.
--
-- So scan all four slots -- but VALIDATE THE WHOLE TABLE, not just "some
-- slot looks like HP".  A first attempt that returned true on any single
-- plausible word fired on map 123 while the CYAN name menu was open:
--     $3BF4=FF00 $3BF6=0020 $3BF8=FF00 $3BFA=0020
-- ($3BF6 = 32 reads perfectly like a hit point).  That is OpenMenu_ext
-- scribbling on the same RAM while the field module is suspended, and
-- taking it for a battle made the driver kill-bit and mash A at the name
-- menu instead of pressing START -- a new stall in place of the old one.
-- A LOADED battle party table only ever holds a real HP, or 0 / $FFFF for
-- a slot nobody is in; $FF00 is neither, and one impossible word condemns
-- the table.
local function inBattle()
  local any = false
  for i = 0, 3 do
    local hp = H.readWord(0x3bf4 + i * 2)
    if hp == 0xFFFF or hp == 0 then                 -- empty slot: no opinion
    elseif hp < 10000 then any = true               -- a real party member
    else return false end                           -- impossible: not a table
  end
  return any
end

local FACE = { up = 0, right = 1, down = 2, left = 3 }
local NEIGHBOURS = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
}

local function talkToObj(obj, what, maxF)
  local engaged = false
  local function objAt() return objX(obj), objY(obj) end
  local function adjacent()
    local ox, oy = objAt()
    return math.abs(ox - H.fieldX()) + math.abs(oy - H.fieldY()) == 1
  end
  local apFrame, apPick = -1000, nil
  local function approach()
    if H.frame - apFrame >= 30 then
      apFrame = H.frame
      local ox, oy = objAt()
      apPick = { ox, oy + 1 }
      for _, c in ipairs(NEIGHBOURS) do
        local cx, cy = ox + c[1], oy + c[2]
        if H.bfsPath(cx, cy) then apPick = { cx, cy }; break end
      end
    end
    return apPick
  end
  local function walkStep()
    return H.navTo(function() return approach()[1] end,
                   function() return approach()[2] end, {
      maxFrames = maxF or 20000,
      arrive = function()
        return engaged or (adjacent() and H.hasControl() and H.tileAligned())
      end,
    })
  end
  local function pokeStep(round, budget, hard)
    local started, waited, aPh = 0, 0, 0
    return H.driveUntil(function()
      started = (H.eventRunning() or H.dialogWaiting()) and started + 1 or 0
      if started >= 6 then engaged = true; return true end
      waited = waited + 1
      return not hard and waited > budget
    end, budget + 120, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if not (H.hasControl() and H.tileAligned() and adjacent()) then
          H.setPad({}); return
        end
        local ox, oy = objAt()
        local dx, dy = ox - H.fieldX(), oy - H.fieldY()
        local dir = dx == 1 and "right" or dx == -1 and "left"
                 or dy == 1 and "down" or "up"
        if facing() ~= FACE[dir] then H.setPad({ [dir] = true }); return end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, string.format("%s: activation round %d", what, round))
  end
  return seq({
    H.call(function() engaged, apFrame, apPick = false, -1000, nil end),
    walkStep(), pokeStep(1, 600, false),
    H.cond(function() return not engaged end,
      { walkStep(), pokeStep(2, 900, true) }, {}),
    H.release(),
  })
end

-- No `choice` exists anywhere on this leg -- map 117's only prompt is the
-- sealed-chest gag _cb0dbe (:40058) on obj 29 at {45,5}, which the route
-- never touches, and map 120 has none at all.  CHOICES stays empty so an
-- unexpected prompt is a hard failure rather than a blind A-press.
local CHOICES = {}   -- this leg reaches no `choice` at all
local ci, inChoice = 0, false
local nameMenus, battles = 0, {}

local function rideUntil(pred, what, budget)
  local phase, battN, dlgN, quiet, hb = 0, 0, 0, 0, -900
  return H.driveUntil(pred, budget or 40000, {
    H.call(function()
      phase = (phase + 1) % 8
      -- THE MAP IS IN THE HEARTBEAT.  Run 1's log had everything except
      -- the one field that would have explained it.
      if H.frame - hb >= 900 then
        hb = H.frame
        H.log(string.format("kefka f%d map=%d (%d,%d) face=%d ctl=%s dlg=%s " ..
          "batt=%s ev=%s br=%d menu=%d/%d $02E2=%d | evpc=%02X%02X%02X " ..
          "$0084=%02X $087C=%02X $00BA=%02X $00D3=%02X $0026=%02X " ..
          "$0027=%02X hp0=%04X mon=%d",
          H.frame, map(), H.fieldX(), H.fieldY(), facing(),
          tostring(H.hasControl()), tostring(H.dialogWaiting()),
          tostring(inBattle()), tostring(H.eventRunning()),
          bright(), H.readByte(NAME_MENU), H.readByte(0x0059), sw(0x02E2),
          H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5),
          H.readByte(0x0084), H.readByte(0x087c + H.readWord(0x0803)),
          H.readByte(0x00ba), H.readByte(0x00d3), H.readByte(0x0026),
          H.readByte(0x0027), H.readWord(0x3bf6), monCount()))
      end

      battN = inBattle() and battN + 1 or 0
      dlgN  = H.dialogWaiting() and dlgN + 1 or 0

      local chMax = (battN == 0) and H.readByte(CH_MAX) or 0
      if chMax >= 2 then
        quiet = 0
        if not H.dialogWaiting() then H.setPad({}); return end
        if not inChoice then
          inChoice = true
          ci = ci + 1
          if not CHOICES[ci] then
            error(string.format("kefka: unexpected choice prompt (%d options) " ..
              "on map %d at (%d,%d) -- this leg expects none",
              chMax, map(), H.fieldX(), H.fieldY()), 0)
          end
        end
        local c, sel = CHOICES[ci], H.readByte(CH_SEL)
        if sel < c.want then H.setPad(phase < 4 and { "down" } or {})
        elseif sel > c.want then H.setPad(phase < 4 and { "up" } or {})
        else H.setPad(phase < 4 and { "a" } or {}) end
        return
      elseif inChoice then
        inChoice = false
      end

      if battN >= 3 then
        quiet = 0
        if battN == 3 then
          local w = H.formationWords()
          battles[#battles + 1] = string.format("map%d:%04X/%d",
            map(), w[1], monCount())
          H.log(string.format("kefka: battle up f%d map=%d present=%d " ..
            "(%04X %04X %04X %04X %04X %04X) php=%04X %04X %04X %04X",
            H.frame, map(), monCount(), w[1], w[2], w[3], w[4], w[5], w[6],
            H.readWord(0x3bf4), H.readWord(0x3bf6), H.readWord(0x3bf8),
            H.readWord(0x3bfa)))
          for i = 0, 5 do
            if monPresent(i) then
              H.log(string.format("   slot %d species $%04X hp=%d shields=%d",
                i, monSpecies(i), monHp(i), monShields(i)))
            end
          end
        end
        -- A SCRIPT BATTLE (zero monsters present) has nothing to kill-bit
        -- and ends on its character-AI script's own schedule.  Hands off
        -- for 300 frames, then edge-tap A to advance its text.
        if monCount() == 0 then
          H.setPad(battN > 300 and phase < 4 and { "a" } or {})
          return
        end
        for slot = 0, 5 do
          if monPresent(slot) then
            H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
          end
        end
        H.setPad(phase < 4 and { "a" } or {})
        return
      end

      if dlgN >= 3 then quiet = 0; H.setPad(phase < 4 and { "a" } or {}); return end

      -- THE NAME MENU, detected on the MENU MODULE'S OWN STATE.  $0200 == 1
      -- is event command $98's marker (field/event.asm:3607) but goes stale
      -- the moment the menu closes, and $0059 ~= 0 is true of a good deal
      -- more than menus -- it read 82 mid-cutscene on map 120 in run 2 of
      -- this file.  The precise term is zMenuState/zNextMenuState == $5F
      -- (menu_ram.inc:112-113 at direct-page $26/$27; $5F is what
      -- MenuState_5d parks in, name_change.asm:60-61).  Either byte serves:
      -- during the menu's fade-in the state is still FADE_IN and only
      -- zNextMenuState reads $5F.
      if H.readByte(NAME_MENU) == 1 and H.readByte(0x0059) ~= 0
         and (H.readByte(0x0026) == 0x5F or H.readByte(0x0027) == 0x5F) then
        quiet = quiet + 1
        if quiet >= 30 then
          if quiet == 30 then
            nameMenus = nameMenus + 1
            H.log(string.format("kefka: NAME MENU #%d at f%d (map %d) -- START",
              nameMenus, H.frame, map()))
          end
          H.setPad(phase < 4 and { "start" } or {})
          return
        end
        H.setPad({})
        return
      end
      quiet = 0

      H.setPad({})
    end),
  }, what)
end

-- "THE STORY BEAT IS OVER", written so a flapping trigger tile still
-- counts.  The obvious predicate -- n CONSECUTIVE frames of full control --
-- cannot be satisfied anywhere on this map, because every one of these
-- scenes leaves the party standing ON the trigger tile that fired it and
-- CheckEventTriggers (field/event.asm:5740) has no once-per-tile latch: it
-- re-fires the script every single frame.  The scripts are inert by then
-- (_cb0f2e opens `if_switch $002B=1, EventReturn`, :40303) but each firing
-- still flips $087C to 4 for a frame or two, so hasControl() oscillates
-- forever.  Measured, run 1: the party sat on (36,22) for 12,000 frames
-- with the heartbeat reading ctl=true and the every-frame settle sample
-- reading ctl=false, and "10 consecutive" never happened once.
--
-- So: require the map to be STATICALLY quiet for 4n frames -- right map,
-- tile-aligned, fully faded in, no battle, no dialog -- and require real
-- user control in at least n of them.  A cutscene fails the second half
-- (hasControl() folds in `not eventRunning()`, so it stays false
-- throughout); a trigger-tile flap passes it, which is correct, because a
-- flapping trigger tile IS a state the player can walk out of.
local function landedField(m, n)
  local seen, good, hb = 0, 0, -600
  return function()
    local static = map() == m and H.tileAligned() and bright() >= 15
               and not inBattle() and not H.dialogWaiting()
    if not static then
      seen, good = 0, 0
    else
      seen = seen + 1
      if H.hasControl() then good = good + 1 end
    end
    if H.frame - hb >= 900 then
      hb = H.frame
      H.log(string.format("landed(%d): map=%d algn=%s br=%d batt=%s " ..
        "quiet=%d ctl=%d/%d", m, map(), tostring(H.tileAligned()), bright(),
        tostring(inBattle()), seen, good, n))
    end
    return seen >= 4 * n and good >= n
  end
end

-- Walk to (x,y) and then wait out whatever the tile fired.  navTo's own
-- terminator is "standing on the tile with control", which a trigger that
-- takes the party away never satisfies -- so `untilPred` is the real goal
-- and the walk is only how we get there.
local function stepOnto(x, y, untilPred, what, budget)
  return H.cond(function() return true end, {
    H.logStep(function()
      return string.format("kefka: walking to (%d,%d) from (%d,%d) -- %s",
        x, y, H.fieldX(), H.fieldY(), what)
    end),
    H.navTo(x, y, {
      maxFrames = budget or 12000,
      arrive = function() return untilPred() end,
    }),
    rideUntil(untilPred, what, budget or 12000),
  })
end

H.run({ maxFrames = 90000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 117, "booted on map 117, the Imperial Camp")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(sw(0x02E2), 1, "$02E2 set -- the gate scene is behind us")
    H.assertEq(sw(0x002B), 0, "$002B clear -- the LEO scene is ahead")
    H.log(string.format("[kefka] f%d at (%d,%d); KEFKA obj 21 at (%d,%d)",
      H.frame, H.fieldX(), H.fieldY(), objX(21), objY(21)))
  end),

  -- 1. the LEO scene, then one more tile south for the poisoning, whose
  --    tail runs KEFKA gag 1 without being asked.
  stepOnto(36, 22, function() return sw(0x002B) == 1 end,
    "the LEO scene (_cb0f2e, $002B)", 20000),
  rideUntil(landedField(117, 10), "control back after the LEO scene", 12000),
  H.waitFrames(30),
  stepOnto(36, 23, function() return sw(0x002D) == 1 end,
    "the poisoning + KEFKA gag 1 (_cb1032 -> _cb1126)", 30000),
  rideUntil(landedField(117, 10), "control back after KEFKA gag 1", 12000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x002C), 1, "$002C set -- Doma is poisoned")
    H.assertEq(sw(0x002D), 1, "$002D set -- KEFKA gag 1 fought")
    H.log(string.format("[kefka] gag 1 done f%d; party (%d,%d) KEFKA (%d,%d)",
      H.frame, H.fieldX(), H.fieldY(), objX(21), objY(21)))
  end),

  -- 2. chase him twice.  talkToObj re-resolves his tile every 30 frames, so
  --    it does not matter where the previous scene parked him.
  talkToObj(21, "KEFKA, talk 2 (_cb1170, no battle)", 20000),
  rideUntil(function()
    return sw(0x002E) == 1 and H.hasControl() and H.tileAligned()
       and bright() >= 15
  end, "KEFKA gag 2 ($002E)", 20000),
  H.waitFrames(30),
  H.logStep(function()
    return string.format("[kefka] $002E f%d; party (%d,%d) KEFKA (%d,%d)",
      H.frame, H.fieldX(), H.fieldY(), objX(21), objY(21))
  end),

  talkToObj(21, "KEFKA, talk 3 (_cb1193, battle 56)", 20000),
  rideUntil(function()
    return sw(0x002F) == 1 and H.hasControl() and H.tileAligned()
       and bright() >= 15
  end, "KEFKA gag 3 ($002F)", 20000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(sw(0x002F), 1, "$002F set -- the x=18 band is open")
    H.log(string.format("[kefka] $002F f%d; party (%d,%d) KEFKA (%d,%d)",
      H.frame, H.fieldX(), H.fieldY(), objX(21), objY(21)))
  end),

  -- 3. west to the pursuit, then ride all the way to CYAN's control on 121
  stepOnto(17, 31, function() return sw(0x0155) == 1 end,
    "the pursuit (_cb11da -> _cb1209, battle 44)", 25000),
  rideUntil(landedField(121, 10), "CYAN back at DOMA (map 121)", 40000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 121, "map 121 -- the DOMA CASTLE grounds")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(inBattle(), false, "no battle")
    H.assertEq(inParty(2), true, "CYAN is the party")
    H.assertEq(inParty(5), false, "SABIN is out")
    H.assertEq(sw(0x0155), 1, "$0155 set -- the camp is behind us")
    H.assertEq(sw(0x050B), 1, "$050B set by _cba0ec's tail (:62098)")
    H.assertEq(sw(0x0044), 0, "$0044 clear -- the scenario is not done")
    H.log("[kefka] battles seen: " .. table.concat(battles, " "))
    for c = 0, 15 do
      if inParty(c) then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d level=%d hp=%d/%d mp=%d/%d",
          c, H.readByte(base + 8), H.readWord(base + 9),
          H.readWord(base + 11), H.readWord(base + 13),
          H.readWord(base + 15)))
      end
    end
    H.log(string.format("[kefka_done] f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.screenshot("kefka_done")
  end),
  -- mint on a frame where control is REALLY ours, not on whichever frame
  -- of the flap the step machine happened to land on
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end,
    900, "a genuinely controllable frame to mint on"),
  H.saveState("kefka_done.mss"),
  H.logStep(function()
    return string.format("kefka_done minted at frame %d", H.frame)
  end),
})
