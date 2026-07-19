-- gen_sabin_camp.lua -- leg 2 of SABIN's scenario: the Imperial Camp's
-- opening, which is not about SABIN at all.  Mints one state:
--   camp_intro.mss  map 117 at (36,2), SABIN + SHADOW, controllable, with
--                   $02E2 set so the gate cutscene cannot re-fire
--
-- WALKING ONE TILE SOUTH HANDS THE GAME TO CYAN, ON ANOTHER MAP, FOR ~9,000
-- FRAMES.  This is the whole content of this leg and it is not what the
-- route map suggests.  Stepping from the camp gate onto (36,3) fires
-- _cb0c2f (event_trigger.asm:33, event_main.asm:39785), which walks the
-- party UP 1 / RIGHT 2 to (38,2) and calls the commander scene _cb0c87
-- (:39826).  That scene's LAST act is not "give control back":
--
--     fade_out / wait_fade / switch $01CC=1 / switch $04EE=1
--     wait_1s / call _cb9aae                        (:40019-40027)
--
-- and _cb9aae (:60795) is the Doma interlude:
--     char_party CYAN, 1 / char_party SABIN, 0
--     load_map 120, {33,42}, UP                     (:60802-60806)
-- CYAN, alone, on DOMA CASTLE's interior map.  From there it runs a long
-- automatic stretch, detours through `load_map 123, {10,44}` (:61120), hits
-- `name_menu CYAN` (:61204), comes back with `load_map 120, {33,49}`
-- (:61245), parks SLOT_1 on (33,44) and the commander (NPC_1, obj 16) on
-- (33,54) (:61246-61269), and only then reaches `player_ctrl_on` (:61482).
--
-- WHAT THIS COST, AND WHY THE FILE IS SHAPED THIS WAY.  Run 1 of this leg
-- pointed navTo at the LEO scene's tile and let it walk.  navTo dropped its
-- plan on the first frame ("control lost at (36,2)") and then sat for
-- 20,000 frames while the heartbeat printed the party object drifting
-- (38,2) -> (33,42) -> (10,44) -> (10,39): those are _cb9aae's map-120
-- spawn, map 123's spawn, and CYAN mid-cutscene, all read through the same
-- $0803 offset and all completely invisible as MAP CHANGES because navTo's
-- heartbeat does not print the map.  It froze for good at (10,39) --
-- `name_menu CYAN`, which navTo has no branch for and never will.  So:
-- nothing on this leg is walked with navTo except the two short stretches
-- where the party genuinely has control, and everything else is ridden.
--
-- ONLY THE COMMANDER MATTERS.  Map 120 stands up twelve soldiers (NPCProp
-- ::_120, npc_prop.asm), eleven of which are `battle 43` grinding
-- (_cb9ffb.._cba073, :61739-61802) that hides one NPC each and changes no
-- switch.  The twelfth, obj 16 at (33,54), is the commander: _cb9eb5
-- (:61517) fights `battle 46` and its tail is the scene that ends the
-- interlude and calls _cb0bc4 (:61737) -- the CAMP's own startup event,
-- which re-creates SABIN and SHADOW and reloads map 117 at (36,2).  So the
-- interlude is exactly one fight long and the eleven others are skipped.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/sabin_camp.mss.lua"

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
local CHOICES = {}
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
        H.log(string.format("camp f%d map=%d (%d,%d) face=%d ctl=%s dlg=%s " ..
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
            error(string.format("camp: unexpected choice prompt (%d options) " ..
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
          H.log(string.format("camp: battle up f%d map=%d present=%d " ..
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
            H.log(string.format("camp: NAME MENU #%d at f%d (map %d) -- START",
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

local function landedField(m, n)
  local cnt, hb = 0, -600
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not inBattle()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d): map=%d ctl=%s algn=%s br=%d batt=%s",
        m, map(), tostring(H.hasControl()), tostring(H.tileAligned()),
        bright(), tostring(inBattle())))
    end
    return cnt >= n
  end
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 117, "booted on map 117, the Imperial Camp")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(inParty(5), true, "SABIN in the party")
    H.assertEq(inParty(3), true, "SHADOW in the party")
    H.assertEq(sw(0x02E2), 0, "$02E2 clear -- the gate scene has not played")
    H.log(string.format("[camp] f%d at (%d,%d)", H.frame,
      H.fieldX(), H.fieldY()))
  end),

  -- ==================================================================== --
  -- 1. ONE STEP SOUTH, AND THE GAME IS CYAN'S.  navTo's job here is only
  -- to reach (36,3); the arrive check is the MAP CHANGING, because the
  -- trigger takes control on the same frame the party lands and navTo's own
  -- terminator (on the tile, with control) can never be satisfied.
  -- ==================================================================== --
  H.navTo(36, 3, {
    maxFrames = 3000,
    arrive = function() return map() ~= 117 end,
  }),
  rideUntil(landedField(120, 10), "CYAN at DOMA (map 120)", 30000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 120, "map 120 -- DOMA CASTLE interior, CYAN's defence")
    H.assertEq(inParty(2), true, "CYAN is the party")
    H.assertEq(inParty(5), false, "SABIN is out")
    H.assertEq(nameMenus, 1, "one name menu so far (CYAN, :61204)")
    H.log(string.format("[doma] f%d CYAN at (%d,%d); commander obj 16 " ..
      "at (%d,%d)", H.frame, H.fieldX(), H.fieldY(), objX(16), objY(16)))
    H.screenshot("cyan_defence")
  end),
  H.saveState("cyan_defence.mss"),

  -- ==================================================================== --
  -- 2. THE COMMANDER.  obj 16, parked on (33,54) by :61266-61269.  Its
  -- `battle 46` is event battle GROUP 46 = formation 409 = one $14e
  -- (event_battle_group.dat, 4 bytes/group).
  -- ==================================================================== --
  talkToObj(16, "the Imperial commander (_cb9eb5, battle 46)", 20000),
  rideUntil(function()
    return map() == 117 and sw(0x02E2) == 1 and H.hasControl()
       and H.tileAligned() and bright() >= 15
  end, "back in the camp as SABIN", 30000),
  -- STEP OFF THE TRIGGER BEFORE MINTING.  _cb0bc4 puts the party back on
  -- (36,2) and walks it DOWN 1, so it comes to rest on (36,3) -- which is
  -- _cb0c2f's own trigger tile.  CheckEventTriggers (field/event.asm:5740)
  -- has no once-per-tile latch: it re-fires every frame the party stands
  -- there, and although $02E2 now makes the script an immediate
  -- EventReturn, each firing still flips $087C to 4 for a frame or two.
  -- hasControl() therefore FLAPS -- measured, run 5: the 900-frame
  -- heartbeat read ctl=true while landedField's every-frame sample read
  -- ctl=false, and "10 consecutive settled frames" never once happened in
  -- 6,000.  (36,5) is two tiles south, off every trigger on the map and on
  -- the road the next leg takes anyway.
  H.navTo(36, 5, { maxFrames = 4000 }),
  rideUntil(landedField(117, 10), "camp control settled off the trigger", 6000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 117, "map 117 -- back in the Imperial Camp")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(inBattle(), false, "no battle")
    H.assertEq(inParty(5), true, "SABIN is the party again")
    H.assertEq(inParty(3), true, "SHADOW too")
    H.assertEq(inParty(2), false, "CYAN is out again")
    -- $02E2 is the gate scene's own latch: _cb0c2f/_cb0c47/_cb0c5e all open
    -- `if_switch $02E2=1, EventReturn` (:39786, :39797, :39807), so with it
    -- set the three gate tiles are inert and the next leg can walk south
    -- across them without replaying the interlude.
    H.assertEq(sw(0x02E2), 1, "$02E2 set -- the gate tiles are inert now")
    H.assertEq(sw(0x002B), 0, "$002B clear -- the LEO scene is still ahead")
    H.assertEq(sw(0x0044), 0, "$0044 clear -- the scenario is not done")
    H.log("[camp] battles seen: " .. table.concat(battles, " "))
    for c = 0, 15 do
      if inParty(c) then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d level=%d hp=%d/%d mp=%d/%d",
          c, H.readByte(base + 8), H.readWord(base + 9),
          H.readWord(base + 11), H.readWord(base + 13),
          H.readWord(base + 15)))
      end
    end
    H.log(string.format("[camp_intro] f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.screenshot("camp_intro")
  end),
  H.saveState("camp_intro.mss"),
  H.logStep(function()
    return string.format("camp_intro minted at frame %d", H.frame)
  end),
})
