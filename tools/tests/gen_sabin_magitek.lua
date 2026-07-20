-- gen_sabin_magitek.lua -- leg 6 of SABIN's scenario: the Magitek escape from
-- the Imperial Camp.  From doma_defended (map 119 at (14,30), SABIN+CYAN(+
-- SHADOW) mounted on Magitek), ride the camp's fight/interlude gauntlet out to
-- the World of Balance.  Mints:
--   camp_escaped.mss   world map (179,71), on foot toward the Phantom Forest,
--                      $0037=1 (the escape is done).
--
-- THE BLOCKER YOUR PREDECESSOR HIT, SOLVED -- and the fix is geometric, not a
-- state machine.  The escape is a wall of event triggers (event_trigger.asm
-- :564-573): battle 15 at the x=24 column (24,28)-(24,31)+(23,32) (_cb1955),
-- battle 16 at (33,29)/(33,30) (_cb19af), battle 17 at (36,22) (_cb19e6), and
-- the world-exit finale on the y=14 row (35/36/37,14) (_cb1a23, :42119 ->
-- player_ctrl_on + load_map 0 {179,71} + set_script_mode WORLD, :42253-42255).
-- Between them the party WALKS with real user control ($087C nibble 2) -- the
-- escape is walked, not ridden.  Three facts, all measured (probe_esc):
--
--  1. EACH BATTLE MUST BE WON BY TAP-A, NEVER KILL-BIT.  _cb1955's tail
--     (event_main.asm:42026) is `call _ca5ea9`, which is `if_b_switch $40,
--     ...; call GameOver` (:14171): a battle that exits WITHOUT the win bit
--     $40 -- which is exactly what kill-bitting during load produces -- calls
--     GameOver and parks the event forever.  That silent park is the
--     "$CB1955 forever" the predecessor measured.  Auto-battle (edge-tap A)
--     lets the Magitek party win cleanly; then the teardown sets $01F4=1 and
--     control returns a few frames after fade-in.
--
--  2. THE TRIGGER RE-FIRES EVERY ALIGNED FRAME (CheckEventTriggers has no
--     once-per-tile latch, field/event.asm:5740-5786; its guard fires
--     whenever the party is tile-aligned AND $087C nibble==2 AND no event
--     runs).  So while the party STANDS aligned on a fired trigger tile the
--     guarded re-fire (`if_switch $01F4=1, EventReturn`) grabs $087C for ~3 of
--     every 4 frames -- control flaps at ~25% duty.  navTo reads that as
--     "control lost" and DROPS its plan every cycle (lib line ~1042), so it
--     thrashes in place and never completes a step.  This is the whole reason
--     a plain navTo could not leave (24,30).
--
--  3. YOU LEAVE A TRIGGER BY HOLDING A *WALKABLE* DIRECTION PERSISTENTLY.
--     The corridor runs along y=28, not the start row y=30.  (24,30) has NO
--     right exit (a wall -- canStep proved it); (24,28) DOES.  Holding the
--     corridor-forward direction through the flap, a step begins on each clean
--     frame, un-aligns the party, and the re-fire (which needs alignment)
--     stops -- the step completes and the party is off the trigger.  navTo's
--     give-up is the bug; a hold that never gives up is the fix.
--
-- So the drive is: navTo the CLEAN segment up to each trigger's near side
-- (navTo works perfectly off the triggers), then holdCross the trigger itself
-- (persistent hold of the corridor direction + tap-A the fight), landing on
-- the clean far side.  Repeat for battles 15/16/17, then holdCross UP into the
-- finale row and ride the dismount cutscene (tap-A its dialogs) onto the world
-- map.  NPC_16's touch-battle _cb1985 (battle 17 again, npc_prop.asm:4809) is
-- optional and off the corridor; if it ever fires, holdCross taps-A it too.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/doma_defended.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local function monCount()
  local n = 0
  for i = 0, 5 do if monPresent(i) then n = n + 1 end end
  return n
end
-- slot-agnostic, table-validated battle detector (CYAN/SABIN can fight from
-- any slot; a loaded party table only ever holds real HP or 0/$FFFF)
local function inBattle()
  for i = 0, 3 do
    local hp = H.readWord(0x3bf4 + i * 2)
    if hp == 0xFFFF or hp == 0 then
    elseif hp < 10000 then return true
    else return false end
  end
  return false
end

-- FLAP-TOLERANT PERSISTENT HOLD.  Hold `dir` every field frame; edge-tap A
-- (4 on / 4 off) through any battle or dialog, NEVER kill-bit; never give up
-- on control loss.  On each clean frame the held direction begins a step into
-- the walkable corridor tile, un-aligning the party off the re-firing trigger.
local battles = {}
local function holdCross(dir, donePred, what, budget)
  local phase, hb, battN, dlgN = 0, -900, 0, 0
  return H.driveUntil(donePred, budget or 25000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.frame - hb >= 600 then
        hb = H.frame
        H.log(string.format("cross[%s] f%d map=%d (%d,%d) face=%d ctl=%s "..
          "ev=%s batt=%s mon=%d br=%d $01F4=%d $01F5=%d $01F6=%d $0037=%d",
          dir, H.frame, map(), H.fieldX(), H.fieldY(), facing(),
          tostring(H.hasControl()), tostring(H.eventRunning()),
          tostring(inBattle()), monCount(), bright(), sw(0x01F4), sw(0x01F5),
          sw(0x01F6), sw(0x0037)))
      end
      battN = inBattle() and battN + 1 or 0
      dlgN  = H.dialogWaiting() and dlgN + 1 or 0
      if battN >= 3 then
        if battN == 3 then
          local w = H.formationWords()
          battles[#battles + 1] = string.format("(%d,%d):%04X/%d",
            H.fieldX(), H.fieldY(), w[5] ~= 0xFFFF and w[5] or w[1], monCount())
          H.log(string.format("cross: BATTLE up f%d (%d,%d) mon=%d "..
            "form=(%04X %04X %04X %04X %04X %04X)", H.frame, H.fieldX(),
            H.fieldY(), monCount(), w[1], w[2], w[3], w[4], w[5], w[6]))
        end
        H.setPad(phase < 4 and { "a" } or {})   -- tap-A, never kill-bit
        return
      end
      if dlgN >= 3 then H.setPad(phase < 4 and { "a" } or {}); return end
      if battN > 0 or dlgN > 0 then H.setPad({}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

-- a clean-segment nav that refuses to kill-bit an escape fight (species
-- $0042): if one ever fires mid-segment it hands off and we notice via the
-- budget, rather than corrupting a teardown.  The segments are chosen off the
-- triggers, where control does not flap and navTo is reliable.
local IMP = 0x0042
local function seg(tx, ty, what)
  return H.cond(function() return true end, {
    H.logStep(function()
      return string.format("[magitek] navTo (%d,%d) for %s from (%d,%d) f%d",
        tx, ty, what, H.fieldX(), H.fieldY(), H.frame)
    end),
    H.navTo(tx, ty, { maxFrames = 14000, spare = { IMP }, arrive = function()
      return map() == 119 and H.fieldX() == tx and H.fieldY() == ty
         and H.hasControl() and H.tileAligned()
    end }),
  }, {})
end

H.run({ maxFrames = 120000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 119, "booted on map 119, the Doma courtyard")
    H.assertEq(H.fieldX(), 14, "start x=14"); H.assertEq(H.fieldY(), 30, "y=30")
    H.assertEq(inParty(5), true, "SABIN in the party")
    H.assertEq(inParty(2), true, "CYAN in the party")
    H.assertEq(sw(0x0044), 0, "$0044 clear -- scenario not done")
    H.log(string.format("[magitek] start f%d (%d,%d) ctl=%s",
      H.frame, H.fieldX(), H.fieldY(), tostring(H.hasControl())))
  end),

  -- BATTLE 15: cross the x=24 wall at y=28 (its right exit is open).
  seg(23, 28, "b15 approach"),
  holdCross("right", function()
    return map() == 119 and H.fieldX() >= 27 and H.fieldY() == 28
       and H.hasControl() and H.tileAligned() and not inBattle()
  end, "cross battle 15 (24,28) -> east", 30000),
  H.call(function()
    H.assertEq(sw(0x01F4), 1, "$01F4 set -- battle 15 won")
    H.log(string.format("[magitek] past b15 at (%d,%d) f%d", H.fieldX(),
      H.fieldY(), H.frame))
  end),

  -- BATTLE 16: corridor turns down at x=32; cross (33,29) holding right.
  seg(32, 29, "b16 approach"),
  holdCross("right", function()
    return map() == 119 and H.fieldX() >= 35 and H.fieldY() == 29
       and H.hasControl() and H.tileAligned() and not inBattle()
  end, "cross battle 16 (33,29) -> east", 30000),
  H.call(function()
    H.assertEq(sw(0x01F5), 1, "$01F5 set -- battle 16 won")
    H.log(string.format("[magitek] past b16 at (%d,%d) f%d", H.fieldX(),
      H.fieldY(), H.frame))
  end),

  -- BATTLE 17: up the east side; cross (36,22) holding up.
  seg(36, 23, "b17 approach"),
  holdCross("up", function()
    return map() == 119 and H.fieldY() <= 21 and H.fieldX() == 36
       and H.hasControl() and H.tileAligned() and not inBattle()
  end, "cross battle 17 (36,22) -> north", 30000),
  H.call(function()
    H.assertEq(sw(0x01F6), 1, "$01F6 set -- battle 17 won")
    H.log(string.format("[magitek] past b17 at (%d,%d) f%d", H.fieldX(),
      H.fieldY(), H.frame))
  end),

  -- FINALE: up the x=37 column into the y=14 row -> _cb1a23 dismount cutscene
  -- -> world (179,71).  holdCross UP rides it (tap-A the dialogs) onto the
  -- world map; done when the world module owns the party.
  seg(37, 16, "finale approach"),
  holdCross("up", function()
    return H.worldMode() and H.worldHasControl()
  end, "ride the finale cutscene onto the world map", 40000),

  -- settle on the world map: control + full brightness + 30f margin
  H.waitUntil(function() return H.worldHasControl() and H.worldAligned() end,
    3000, "world control", 5),
  H.waitUntil(function() return bright() >= 15 end, 1200, "world fade-in", 10),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "on the World of Balance")
    H.assertEq(sw(0x0037), 1, "$0037 set -- the escape is done")
    H.assertEq(sw(0x0044), 0, "$0044 clear -- scenario not done yet")
    H.assertEq(inParty(5), true, "SABIN still in the party")
    H.assertEq(inParty(2), true, "CYAN still in the party")
    H.log(string.format("[camp_escaped] f%d world (%d,%d) worldId=%d br=%d "..
      "battles: %s", H.frame, H.worldX(), H.worldY(), H.worldId(), bright(),
      table.concat(battles, " ")))
    H.screenshot("camp_escaped")
  end),
  H.saveState("camp_escaped.mss"),
  H.logStep(function()
    return string.format("camp_escaped minted at frame %d world (%d,%d)",
      H.frame, H.worldX(), H.worldY())
  end),
})
