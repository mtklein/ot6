-- gen_sabin_escape.lua -- leg 5 of SABIN's scenario: the Doma courtyard
-- defence -- three fights, CYAN joins, everyone mounts Magitek.  Mints one
-- state:
--   doma_defended.mss  map 119 at (14,30), SABIN + CYAN mounted on Magitek,
--                      controllable -- the starting line of the escape to
--                      the overworld
--
-- SCOPE NOTE: this leg stops at the moment the escape hands the player
-- control, NOT at the overworld.  The escape's walk from (14,30) to the
-- world exit is a fight/scripted-interlude/fight sequence whose interlude
-- holds the party in an obj-script a plain navTo never sees end (measured;
-- see the long comment at the mint below).  That walk is the next leg.
--
-- THE DEFENCE IS THREE TALKS TO CYAN, AND THE TALK DETECTOR IS THE WHOLE
-- TRICK.  SABIN arrives at (8,29) on map 119 with CYAN (the warrior NPC,
-- object carrying event _cb1483, npc_prop.asm:4712) fighting off Imperial
-- troops.  Facing CYAN and pressing A runs _cb1483, which chains on the
-- fight-count switches (event_main.asm):
--   $0034=0 -> _cb1483 body      :41201  battle 13, then $0034=1
--   $0034=1 -> _cb152c           :41313  battle 13, then $0035=1
--   $0035=1 -> _cb15d9           :41435  battle 14, CYAN joins, $0036=1
-- After each fight CYAN walks to a new spot and the next wave's soldiers are
-- placed beside him (:41255-41312).
--
-- WHY A PLAIN talkToObj FAILS HERE, measured over a dozen probe runs.  The
-- whole courtyard floor (y 19..29) is paved with _cb13b9 triggers
-- (event_trigger.asm) that fire a soldier-jump animation as SABIN walks.
-- gen_banon's talkToObj declares "engaged" as soon as `eventRunning() or
-- dialogWaiting()` holds for six frames -- which a floor trigger satisfies
-- -- so it walks up to CYAN, clips a floor tile, mistakes THAT for the talk,
-- and moves on having fought nothing.  The fix is a talk whose success test
-- is the FIGHT SWITCH ITSELF (or a battle actually loading), not "some event
-- ran": walk cleanly onto a tile adjacent to CYAN, then hold a tight
-- face-then-edge-A loop -- no re-planning, no bfs mid-poke -- until the
-- wanted switch flips.  Measured: from (9,26) that loop reaches _cb152c
-- (event PC $CB154D) in ~150 frames; a re-planning driver never did.
--
-- $01B5 IS NOT A WAVE LATCH -- it is a live control-flag bit, exactly the
-- trap the survey flagged.  _cb13b9 writes `switch $01B5=1` and reads it
-- back to fire each soldier-jump only once, and it is NEVER cleared by any
-- `switch $01B5=0`, because it is bit 5 of $1EB6, the party control-flags
-- byte UpdateCtrlFlags rewrites every frame (field/event.asm:5416).  Reading
-- it as "the wave is blocked" is how a probe convinced itself the defence
-- had deadlocked when it had not; the fights never consult it.
--
-- THE MAGITEK ESCAPE IS ONE LONG AUTOMATIC CUTSCENE.  After CYAN joins
-- there is exactly ONE player_ctrl_on in the whole escape, at its very end
-- (:42253), right before `load_map 0, {179,71}, LEFT` + `set_script_mode
-- WORLD` (:42254-42255).  Everything between -- the mount (`vehicle SABIN/
-- CYAN/SHADOW, {MAGITEK, SHOW_RIDER}`, :41654-41735) and the four soldier
-- fights (battle 15/16/17 at _cb1955/_cb19af/_cb19e6/_cb1985, :42025-42094)
-- -- runs on obj_scripts with control OFF.  So the escape is RIDDEN, not
-- walked: kill-bit the fights, tap the dialogs, hands off otherwise, until
-- the world map appears.  (This confirms, on this map, the survey's note
-- that the raft's `vehicle` opcodes are cosmetic sprite swaps on an ordinary
-- field map -- the Magitek "mode" here is likewise just a sprite the escape
-- cutscene drives, not a separate engine mode; $087C stays event-controlled
-- throughout and no MAGITEK-specific movement code ever runs.)
--
-- THE EXIT LANDS ON THE CAMP-ENTRY TRIGGER.  World (179,71) is the very
-- tile whose trigger _cb0bb7 (:39715) loaded the camp -- but it now opens
-- `if_switch $0037=1, WorldReturn`, and the escape has set $0037, so
-- re-stepping it returns instead of re-entering.  The mint is taken on the
-- first settled world frame, before any walk, so the fixture is unambiguous.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/camp_cleared.mss.lua"

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
        H.log(string.format("escape f%d map=%d (%d,%d) face=%d ctl=%s dlg=%s " ..
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
            error(string.format("escape: unexpected choice prompt (%d options) " ..
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
          H.log(string.format("escape: battle up f%d map=%d present=%d " ..
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
            H.log(string.format("escape: NAME MENU #%d at f%d (map %d) -- START",
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

-- TALK TO CYAN UNTIL A FIGHT SWITCH FLIPS.  cx/cy are thunks (CYAN moves
-- between waves).  The success test is the FIGHT SWITCH ITSELF, never "an
-- event ran" -- the courtyard's floor triggers make the latter fire
-- spuriously (see the header).  ONE flap-tolerant driver: hold bfsPath's
-- first step toward CYAN until adjacent, then face-and-A until the switch.
-- This replaced a navTo-per-round loop that hard-timed-out on the stacked
-- (s2_) boot -- navTo drops its plan on the courtyard flap, and its
-- timeout RAISES, so one unlucky boot phase killed the whole run.  The two
-- real fixes are in the driver below: the ungated A-drive, and the
-- bfsPath-hold approach.
local function talkForFight(cx, cy, wantSw, what, budget)
  local function cxr() return type(cx) == "function" and cx() or cx end
  local function cyr() return type(cy) == "function" and cy() or cy end
  local function adjacentToCyan()
    return math.abs(cxr() - H.fieldX()) + math.abs(cyr() - H.fieldY()) == 1
  end
  -- pick the nearest reachable CYAN-neighbour and the FIRST step toward it,
  -- via bfsPath -- a PURE function of the passability map (no control
  -- needed), so it routes around the courtyard walls the way navTo would
  -- while staying readable through the floor-trigger flap.
  local function stepToward()
    local x, y = cxr(), cyr()
    local best, bd = nil, nil
    for _, d in ipairs({ { 0, 1 }, { -1, 0 }, { 1, 0 }, { 0, -1 } }) do
      local p = H.bfsPath(x + d[1], y + d[2])
      if p and (not bd or #p < bd) then best, bd = p, #p end
    end
    return best and best[1] or nil        -- a MOVES name, or nil if adjacent
  end
  -- APPROACH IS FLAP-TOLERANT, not navTo.  The courtyard is paved with
  -- re-firing floor triggers (the header's _cb13b9) that seize $087C ~1
  -- frame in 3; navTo drops its plan on every control loss (lib navTo) and
  -- thrashes -- caught CYAN on one boot's phase, hard-timed-out on another
  -- (the s2_ stack).  So take bfsPath's first step and HOLD it through the
  -- flap: a step begins on each clean frame and un-aligns the party off the
  -- trigger, the magitek leg's fix.  Kill-bit any wave that fires mid-walk.
  local function approachStep(phase)
    if inBattle() then
      for s = 0, 5 do
        if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
          H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
        end
      end
      H.setPad(phase < 4 and { "a" } or {}); return
    end
    if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
    local mv = stepToward()
    -- movePress maps the four diagonals a $c0 tile makes to a cardinal; the
    -- courtyard is plain floor, so mv is already a cardinal in practice
    H.setPad(mv and { [H.movePress(mv)] = true } or {})
  end
  -- ONE flap-tolerant driver, no navTo: when not adjacent to CYAN, hold
  -- the approach axis; when adjacent, run the face-then-dense-A poke.  The
  -- success test is the FIGHT SWITCH ITSELF (or a battle loading), never
  -- "an event ran" -- the floor triggers make the latter fire spuriously.
  local phase = 0
  local steps = {
    H.logStep(function()
      return string.format("escape: talk CYAN(%d,%d) from (%d,%d) for %s",
        cxr(), cyr(), H.fieldX(), H.fieldY(), what)
    end),
    H.driveUntil(function() return sw(wantSw) == 1 end, budget or 14000, {
      H.call(function()
        phase = (phase + 1) % 8
        if not adjacentToCyan() then approachStep(phase); return end
        -- adjacent: face + dense A (see the cadence note below)
        if inBattle() then
          for s = 0, 5 do
            if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
              H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
            end
          end
          H.setPad(phase < 4 and { "a" } or {}); return
        end
        if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
        local dx, dy = cxr() - H.fieldX(), cyr() - H.fieldY()
        local dir = dx == 1 and "right" or dx == -1 and "left"
                 or dy == 1 and "down" or "up"
        -- adjacency/facing are read off the LIVE object map (valid even
        -- while the floor-trigger flap owns $087C), so the A-drive is NOT
        -- gated on hasControl: the flap steals control ~1 frame in 3 and
        -- setPad only lands at the next poll, so an A-edge gated on
        -- "controllable now" usually presses on a frame the flap has since
        -- taken -- why a phase-locked 4-on/4-off caught the talk on one
        -- boot and starved 14 pokes on another (same control ratio,
        -- different phase).  A tight 2-frame A cadence puts a fresh
        -- off->on edge every other frame; one is polled clean within a few.
        if facing() ~= FACE[dir] then H.setPad({ [dir] = true })
        else H.setPad(phase < 4 and { "a" } or {}) end
      end),
    }, what),
    H.call(function()
      H.assertEq(sw(wantSw), 1, what .. " -- switch set")
    end),
  }
  return H.cond(function() return true end, steps)
end

-- CYAN's live tile (object carrying _cb1483).  It is obj 18 on entry and
-- stays obj 18 across the waves (measured: it walks (4,23)->(10,26)).
local function cyanX() return objX(18) end
local function cyanY() return objY(18) end

H.run({ maxFrames = 90000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 119, "booted on map 119, the Doma gate")
    H.assertEq(inParty(5), true, "SABIN in the party")
    H.assertEq(sw(0x0033), 1, "$0033 set -- the defence is underway")
    H.assertEq(sw(0x0034), 0, "$0034 clear -- no wave fought yet")
    H.log(string.format("[escape] f%d SABIN(%d,%d) CYAN obj18 (%d,%d)",
      H.frame, H.fieldX(), H.fieldY(), cyanX(), cyanY()))
  end),

  -- 1. the three waves.  CYAN moves between them, so his tile is a thunk.
  talkForFight(cyanX, cyanY, 0x0034, "wave 1 (battle 13, $0034)", 14000),
  talkForFight(cyanX, cyanY, 0x0035, "wave 2 (battle 13, $0035)", 14000),
  talkForFight(cyanX, cyanY, 0x0036, "wave 3 (battle 14, CYAN joins, $0036)",
    14000),
  H.call(function()
    H.assertEq(sw(0x0036), 1, "$0036 set -- all three waves fought")
    H.assertEq(inParty(2), true, "CYAN has joined the party")
    H.log(string.format("[escape] CYAN joined at f%d; battles: %s",
      H.frame, table.concat(battles, " ")))
  end),

  -- 2. THE ESCAPE HANDS CONTROL TO THE PLAYER AT (14,30), and that is the
  -- deliberate end of this leg.  After CYAN joins, the mount sequence
  -- auto-walks the party (obj_scripts, control off) up through the castle
  -- and back down, then returns USER control -- measured, a pure hands-off
  -- ride from here idles at exactly (14,30), $087C=02, ev=false,
  -- indefinitely (probe_ride).  That is the Magitek escape's starting line.
  --
  -- WHY THE LEG STOPS HERE, stated so the next agent does not rediscover it.
  -- The escape from (14,30) to the world exit (36,14) is NOT a plain walk:
  -- it is fight / scripted-interlude / fight.  Walking onto (24,28) fires
  -- `battle 15` (_cb1955, :42014); the fight is WON (the tail runs past
  -- `call _ca5ea9` -- GameOver's gate -- and sets $01F4=1), but control does
  -- NOT come back: the party sits on (24,28) with $087C=04 (event-
  -- controlled) and eventRunning() true for as long as the run lasts
  -- (measured 7,000+ frames, probe_esc).  So _cb1955's tail leaves the
  -- party inside an obj-script interlude that a plain navTo (which only
  -- hands off and waits when control is lost) never sees end.  Driving the
  -- escape needs a fight/interlude/fight state machine, or the interlude's
  -- own exit condition decoded, and that is scoped as the next leg rather
  -- than thrashed here.  doma_defended is the clean, reproducible doorstep
  -- it should build from.
  rideUntil(function()
    return map() == 119 and H.fieldX() == 14 and H.fieldY() == 30
       and H.hasControl() and H.tileAligned() and bright() >= 15
  end, "control back at the escape's starting line (14,30)", 25000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 119, "map 119 -- the Doma courtyard")
    H.assertEq(H.fieldX(), 14, "at x=14, the escape's starting line")
    H.assertEq(H.fieldY(), 30, "at y=30")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(inParty(5), true, "SABIN in the party")
    H.assertEq(inParty(2), true, "CYAN in the party")
    H.assertEq(sw(0x0036), 1, "$0036 set -- the courtyard defence is won")
    H.assertEq(sw(0x0044), 0, "$0044 clear -- the scenario is not done")
    -- SABIN and CYAN are mounted on Magitek here -- a cosmetic sprite the
    -- field walks normally.  $087C reads 2 (user-controlled), NOT a vehicle
    -- movement type, confirming on this map the survey's raft note: the
    -- `vehicle … MAGITEK` opcodes are sprite swaps, not an engine mode.
    for c = 0, 15 do
      if inParty(c) then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d level=%d hp=%d/%d mp=%d/%d",
          c, H.readByte(base + 8), H.readWord(base + 9),
          H.readWord(base + 11), H.readWord(base + 13), H.readWord(base + 15)))
      end
    end
    H.log(string.format("[doma_defended] f%d map=%d (%d,%d) $087C=%02X",
      H.frame, map(), H.fieldX(), H.fieldY(),
      H.readByte(0x087c + H.readWord(0x0803))))
    H.screenshot("doma_defended")
  end),
  H.saveState("doma_defended.mss"),
  H.logStep(function()
    return string.format("doma_defended minted at frame %d", H.frame)
  end),
})
