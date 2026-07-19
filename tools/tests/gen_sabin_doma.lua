-- gen_sabin_doma.lua -- leg 4 of SABIN's scenario: CYAN's run home through
-- Doma Castle, the family scene, and the handoff back to SABIN.  Mints one
-- state:
--   camp_cleared.mss  map 119 (DOMA CASTLE), SABIN alone, controllable,
--                     with CYAN's defence of the gate already underway
--
-- THE WALK IS THREE MAPS AND ONE OF THEM IS A TRAP DOOR.  From map 121 the
-- route is (short_entrance.dat, map 121):
--   121 (37,11) -> 123 (17,38)     the castle interior
--   123 (16,32) -> 124 (28,36)     Cyan's quarters
-- and (28,36) on map 124 is `make_event_trigger {28,36}, _cb1283`
-- (event_trigger.asm:597) -- the family scene (event_main.asm:40863).  Its
-- tail is `_cb1337` (:40991): `char_party CYAN, 0 / char_party SABIN, 1 /
-- party_chars SABIN` and `load_map 119, {8,25}, RIGHT` (:41001), then the
-- arrival scene that introduces CYAN to SABIN, sets $0033 and ends in
-- `player_ctrl_on` (:41067-41068).
--
-- THE TRAP DOOR: map 123 (17,39) goes straight back to map 121, and it is
-- one tile south of where this leg ARRIVES on map 123.  The field BFS knows
-- tile passability and nothing about doorways, so any plan that clips that
-- tile silently un-does the leg.  fieldLeg() below is the field twin of
-- gen_sabin_world's worldLeg: it names the map the leg is allowed to end on
-- and fails loudly on any other, instead of leaving a walker to idle out
-- its budget on the wrong map.
--
-- WHAT IS *NOT* REQUIRED, checked rather than assumed.  Map 123 carries two
-- more scene triggers -- (4,34) _cba29f (:62120, the King) and (42,8)
-- _cba395 (:62307, "Here, too...") -- and neither gates the family scene:
-- _cb1283 opens `if_switch $007D=1, EventReturn` and nothing else, so the
-- only thing between CYAN and his house is walking there.  Both are skipped.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/kefka_done.mss.lua"

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
        H.log(string.format("doma f%d map=%d (%d,%d) face=%d ctl=%s dlg=%s " ..
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
            error(string.format("doma: unexpected choice prompt (%d options) " ..
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
          H.log(string.format("doma: battle up f%d map=%d present=%d " ..
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
            H.log(string.format("doma: NAME MENU #%d at f%d (map %d) -- START",
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

-- Every short entrance whose SOURCE is on map 123 (from short_entrance.dat,
-- decoded offline).  source (x,y) -> a human label for the destination.
local DOORS123 = {
  { 51, 31, "121" }, { 10, 50, "121" }, { 17, 39, "121" },
  { 16, 32, "124 FAMILY" }, { 25, 18, "123 10,36" }, { 10, 34, "123 25,17" },
  { 4, 14, "123 42,9" }, { 42, 7, "123 4,13" }, { 40, 7, "123 56,53" },
  { 6, 24, "123 49,27" }, { 48, 28, "123 5,25" }, { 40, 12, "123 5,45" },
  { 5, 43, "123 40,11" }, { 49, 12, "123 15,45" }, { 15, 43, "123 49,11" },
  { 56, 54, "123 40,9" }, { 28, 55, "285" },
}

-- Crawl the map-123 room maze to the door at (gx,gy), which leads to map
-- `dest`.  One H.cond per potential hop (a fixed, generous bound on how
-- many rooms the maze is deep); each fires only while still on map 123 and
-- not yet on the goal door's room, picks the reachable unused door nearest
-- the goal, and walks through it.  Bailing OUT of map 123 is the success
-- exit and every later hop then no-ops.
local function crawl123(gx, gy, dest)
  local used = {}
  local function keyOf(d) return d[1] .. "," .. d[2] end
  local function pickDoor()
    -- the goal door first if we can reach it; else nearest unused reachable
    if H.bfsPath(gx, gy) then return { gx, gy, "GOAL" } end
    local best, bd = nil, 1e9
    for _, d in ipairs(DOORS123) do
      if not used[keyOf(d)] and H.bfsPath(d[1], d[2]) then
        local dist = math.abs(d[1] - gx) + math.abs(d[2] - gy)
        if dist < bd then best, bd = d, dist end
      end
    end
    return best
  end
  local steps = {}
  for i = 1, 14 do
    local target, transiting
    steps[#steps + 1] = H.cond(function() return map() == 123 end, {
      H.call(function()
        transiting = false
        for _, d in ipairs(DOORS123) do   -- standing on a door = used
          if math.abs(d[1] - H.fieldX()) + math.abs(d[2] - H.fieldY()) <= 1 then
            used[keyOf(d)] = true
          end
        end
        target = pickDoor()
        if target then used[keyOf(target)] = true end
        H.log(string.format("crawl hop %d: map 123 (%d,%d) -> door %s",
          i, H.fieldX(), H.fieldY(),
          target and string.format("(%d,%d) %s", target[1], target[2],
            target[3]) or "NONE REACHABLE"))
        if not target then
          error(string.format("crawl123: no unused reachable door from " ..
            "(%d,%d); the maze model is incomplete", H.fieldX(),
            H.fieldY()), 0)
        end
      end),
      H.navTo(function() return target[1] end, function() return target[2] end, {
        maxFrames = 9000,
        -- A DOOR FIRES THE MOMENT THE PARTY STEPS ON IT, WHISKING IT AWAY --
        -- so navTo never rests on the door tile and its own terminator
        -- (on the tile, with control) can never fire.  For an inner door
        -- the map even STAYS 123, so `map ~= 123` misses it too and the
        -- walker would path endlessly back toward a tile it no longer
        -- occupies (the crawl thrash, measured).  The real signal is the
        -- transition itself: CheckShortEntrance's DoEntrance does
        -- `lda #1 / sta $84` before FadeOut (field/entrance.asm), and $0084
        -- is 0 during ordinary control (hasControl() folds it in).  Latch a
        -- rising $0084, and the hop ends when the door fires whether the
        -- destination is another room or another map.
        arrive = function()
          if H.readByte(0x0084) ~= 0 then transiting = true end
          return transiting or map() ~= 123
        end,
      }),
      -- Ride out whatever the hop landed in until control is back.  This is
      -- a rideUntil, not a bare waitUntil, because the BFS is blind to
      -- TRIGGER tiles and can route a hop straight across one: the path from
      -- (5,25) to the family door clips (4,34), which fires the King scene
      -- _cba29f (:62120) -- a full cutscene that reloads map 123 at (25,17)
      -- and only then returns control (measured, run 3).  A waitUntil would
      -- sit through its dialogs doing nothing; rideUntil taps them.  It ends
      -- the instant we are off map 123 (the family door won, into the
      -- _cb1283 cutscene that never gives control back on map 124), or once
      -- control is genuinely back on 123 for the next pickDoor.
      rideUntil(function()
        return map() ~= 123
            or (H.hasControl() and H.tileAligned() and bright() >= 15)
      end, "crawl hop " .. i .. " settle", 20000),
      H.waitFrames(20),
    }, {})
  end
  steps[#steps + 1] = H.call(function()
    H.assertEq(map(), dest, "crawl123 arrived on the destination map")
  end)
  return H.cond(function() return true end, steps)
end

-- navTo with a WRONG-MAP GUARD, the field twin of gen_sabin_world's
-- worldLeg.  `want` is the map this leg is allowed to end on; landing
-- anywhere else is a doorway the BFS did not know was a doorway, and it
-- fails here rather than 20,000 frames later.
local function fieldLeg(tx, ty, from, want, what, budget)
  return H.navTo(tx, ty, {
    maxFrames = budget or 15000,
    arrive = function()
      local m = map()
      if m == from then return false end            -- still walking
      if m == want then return true end
      if H.readByte(0x0084) == 0 and bright() >= 15 then
        error(string.format("%s: walked onto map %d at (%d,%d), wanted %d",
          what, m, H.fieldX(), H.fieldY(), want), 0)
      end
      return false
    end,
  })
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 121, "booted on map 121, the Doma Castle grounds")
    H.assertEq(inParty(2), true, "CYAN is the party")
    H.assertEq(sw(0x0155), 1, "$0155 set -- the camp is behind us")
    H.assertEq(sw(0x007D), 0, "$007D clear -- the family scene has not played")
    H.log(string.format("[doma] f%d CYAN at (%d,%d)",
      H.frame, H.fieldX(), H.fieldY()))
  end),

  -- 1. into the castle.  From CYAN's spawn on map 121 the only forward door
  --    the field BFS can reach is (28,12) -> map 123 at (51,30); the
  --    survey's (37,11) is walled off from this spawn (measured, probe_121).
  fieldLeg(28, 12, 121, 123, "121 -> 123 (the castle interior)", 15000),
  rideUntil(landedField(123, 10), "inside Doma Castle (map 123)", 8000),
  H.waitFrames(30),

  -- 2. THROUGH THE ROOM MAZE TO CYAN'S QUARTERS.  Doma Castle's interior is
  --    ONE field map (123) built out of a dozen rooms wired to each other
  --    by internal short entrances -- (48,28)->(5,25), (6,24)->(49,27), and
  --    so on (short_entrance.dat, map 123).  The lib's BFS is per-room: it
  --    can only reach doors in the room the party currently stands in, so a
  --    single navTo to the family door (16,32) fails "no path" from every
  --    room but its own.  crawl123() hops room to room, each hop walking to
  --    the reachable UNUSED door nearest (Manhattan) to the family door,
  --    until the family door itself is reachable and it walks through onto
  --    map 124.  "Used" is keyed on the door's SOURCE tile, so the maze
  --    cannot ping-pong the party back through the door it just took.
  crawl123(16, 32, 124),

  -- 3. the family scene (_cb1283, trigger (28,36) on map 124) runs itself,
  --    hands the party back to SABIN, and drops him into Doma's gate map.
  rideUntil(landedField(119, 10), "SABIN at DOMA's gate (map 119)", 30000),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end,
    900, "a genuinely controllable frame to mint on"),
  H.call(function()
    H.assertEq(map(), 119, "map 119 -- DOMA CASTLE, the gate")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(inBattle(), false, "no battle")
    H.assertEq(inParty(5), true, "SABIN is the party again")
    H.assertEq(inParty(2), false, "CYAN is an NPC here, not a party member")
    H.assertEq(sw(0x007D), 0, "$007D still clear (the scene's own latch)")
    H.assertEq(sw(0x0033), 1, "$0033 set -- CYAN's defence is underway")
    H.assertEq(sw(0x0044), 0, "$0044 clear -- the scenario is not done")
    H.log("[doma] battles seen: " .. table.concat(battles, " "))
    H.log(string.format("[doma] CYAN NPC obj 18 at (%d,%d)", objX(18), objY(18)))
    for c = 0, 15 do
      if inParty(c) then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d level=%d hp=%d/%d mp=%d/%d",
          c, H.readByte(base + 8), H.readWord(base + 9),
          H.readWord(base + 11), H.readWord(base + 13),
          H.readWord(base + 15)))
      end
    end
    H.log(string.format("[camp_cleared] f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    H.screenshot("camp_cleared")
  end),
  H.saveState("camp_cleared.mss"),
  H.logStep(function()
    return string.format("camp_cleared minted at frame %d", H.frame)
  end),
})
