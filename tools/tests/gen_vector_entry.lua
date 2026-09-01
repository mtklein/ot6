-- gen_vector_entry.lua -- v0.6 step 1: cold Continue from the versioned
-- post-Opera battery checkpoint, validate its semantic contract, then walk
-- the world to the VECTOR event trigger and generate the real v0.6 entry
-- point.

-- Unlike the tactical chain of generated savestates, this starts from
-- power-on and lets Mesen load an ordinary .srm from its private save
-- directory.  The checkpoint contains one valid game in slot 3.

-- How Vector is entered.  Not by an entrance record: there
-- is no entrance anywhere in the game whose destination is map 242 or 253.
-- Vector is a world event trigger:

--   ff6/src/event/event_trigger.asm:36-37
--       make_event_trigger {120, 187}, _ca5ecf
--       make_event_trigger {121, 187}, _ca5ecf
--   ff6/src/event/event_main.asm:14196-14200
--       _ca5ecf: set_script_mode WORLD
--                if_switch $0079=1, _ca5edc          ; post-story Vector (253)
--                load_map 242, {32,61}, UP, {Z_UPPER, SHOW_TITLE, ...}

-- $0079 is set only at event_main.asm:46316/:97003/:99716, all after v0.6,
-- so on this route the trigger loads map 242 at (32,61) facing UP.  The
-- v0.6 opening is therefore an ordinary on-foot world walk rather than an
-- airship sequence: no vehicle/airship_pos opcode is involved.

-- Why worldGrind and not worldNavTo.  The 31-step walk from the checkpoint
-- tile (137,203) to (122,187) runs entirely inside the random-battle area
-- (world tile prop bit6 $40 on every tile of the path).  A battle snapshots
-- and restores the party to the same tile (move.asm:916-921 /
-- world_start.asm :465-482), which worldNavTo's verified-step loop reads as
-- the press not having moved the party; it condemns the edge, and with the
-- whole area battle-enabled it condemns them all.  That is the failure that
-- broke gen_opera1; the same grind-and-replan walker is used here (see
-- gen_opera1_entry.lua:47-76).

-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
local function sw(id)
  return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1
end
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

-- The map name the engine would print for the map it is standing on.
-- $0520 is map_prop byte 0, copied by LoadMapProp (field/map.asm:143-157);
-- ShowMapTitle (field/text.asm:112-119) uses it exactly this way.  HiROM
-- file offset = cpu & $3FFFFF, so MapTitlePtrs $E68400 -> $268400 and
-- MapTitle $CEF100 -> $0EF100.  Font encoding: $20-$39 A-Z, $3A-$53 a-z,
-- $54-$5D 0-9, $65 '.', $7F space.
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

-- ------------------------------------------------- LOCKE's and CELES's kit --
-- The checkpoint boots them holding nothing at all: `post-opera-v1` reads
-- LOCKE `FF FF FF FF FF` and CELES the same, with LOCKE's own Guardian
-- sitting in the bag.  That is the story's doing -- the opera strips CELES
-- (`remove_equip CELES`, event_main.asm:27273/:27785) and nothing in the
-- chain ever put either kit back -- and until this stop it rode all the way
-- through the Magitek Research Facility, whose maps 262, 263 and 264 all
-- draw random battles (map_prop.dat +$05 bit 7 set, the flag
-- CheckRandomBattle tests at field/battle.asm:332).  Two characters
-- punching that arc is exactly the fixture bug tools/audit_equipment.py
-- exists to catch.

-- Equipped by item, never through Optimum (wob-route.md section 2).  What
-- the checkpoint's bag holds, and who gets it:
--   LOCKE  $02 Guardian (power 59, and LOCKE is the only actor whose equip
--          mask claims it), $5A Buckler, $69 Leather Hat, $84 LeatherArmor
--   CELES  $01 MithrilKnife (power 30; the Dirk's 26 is the only other
--          weapon in the bag she can hold), the second $5A Buckler,
--          $6A Hair Band, $84 LeatherArmor
-- Both weapons are OT6_PIERCE (ot6_class.asm:48-50), which is deliberate:
-- EDGAR and SABIN arrive holding $0A and $53, both OT6_SLASH (:59, :140),
-- so the party covers both classes across the arc's two set-piece espers --
-- Ifrit is pierce and Shiva is slash (wob-route.md section 1).  The bag has
-- no slash weapon either of these two can hold, so there is no better
-- split available here.

-- The relic rows are left alone on purpose.  The bag's spare relics are a
-- Gauntlet, a Peace Ring and a Black Belt, and equipping a Gauntlet makes
-- the game run its own Optimum when the Relic screen is backed out
-- (CheckReequipRelics, equip.asm:2843-2850), which is the thing this route
-- is not allowed to do.
local EMPTY = 0xFF
local CH_LOCKE, CH_CELES = 1, 6
local function gear(c, off) return H.readByte(0x1600 + 37 * c + off) end
local function ordOf(c) return (H.readByte(0x1850 + c) >> 3) & 0x03 end

-- Fill one empty gear slot from the bag.  Both guards matter, for
-- gen_tunnelarmr's fillSlot reasons: H.equipWeapon's list seek walks the
-- menu's pre-filtered rows, so an item the bag does not hold makes it time
-- out rather than fail cleanly, and a slot that already holds something
-- does not want overwriting.  Slot n's byte is +$1F+n (R-Hand, L-Hand,
-- Helmet, Armor, Relic 1, Relic 2; ff6/notes/field-ram.txt:905-923).
local function fill(c, pos, slot, id, tag)
  return H.cond(function()
    return gear(c, 0x1F + slot) == EMPTY and H.invCountOf(id) > 0
  end, { H.equipWeapon(pos, id, { slot = slot, tag = tag }) }, {})
end

-- Robust world walk to (tx,ty): re-plan a worldBfs each time the plan runs
-- out, press the next step, and flee any random encounter with the game's
-- L+R run mechanic.  No edge is ever
-- condemned, so a battle-restored tile is simply retried until a step
-- lands.  Arrives at (tx,ty) or when the party leaves the world map.
local function worldGrind(tx, ty, what)
  local plan, idx = nil, 1
  return H.driveUntil(function()
    return (not H.worldMode()) or (H.worldX() == tx and H.worldY() == ty
      and H.worldHasControl() and H.worldAligned())
  end, 60000, {
    H.call(function()
      if H.battleLoadStarted() then
        plan = nil; H.setPad({ l = true, r = true }); return
      end
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then plan = nil; H.setPad({}); return end
      if not H.worldAligned() then return end
      if not plan or idx > #plan then plan = H.worldBfs(tx, ty); idx = 1 end
      if not plan then H.setPad({}); return end
      local dir = plan[idx]; idx = idx + 1
      H.setPad({ [dir] = true })
    end),
  }, what or string.format("worldGrind (%d,%d)", tx, ty))
end

H.run({ maxFrames = 160000 }, {
  H.waitFrames(350),
  -- Title -> New Game/Continue -> Continue -> the sole valid slot (3) ->
  -- "This data?" -> field.  Repeated edge presses tolerate title animation
  -- timing while the semantic checks below prevent a false landing.
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function()
    return (H.mapId() & 0x1ff) == 0 and H.worldHasControl()
      and H.worldAligned()
  end, 3000, "cold Continue to post-Opera world entry point", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "cold Continue fade-in", 10),
  H.call(function()
    -- The roster diagnostic stays a log line; the contract is the check.
    local t = {}
    for c = 0, 13 do t[#t + 1] = string.format("%02X", H.readByte(0x1850 + c)) end
    H.log("[roster] $1850+0..13 = " .. table.concat(t, " ")
      .. string.format("  $1EDE=%02X $1EDF=%02X $1A6D=%02X",
        H.readByte(0x1EDE), H.readByte(0x1EDF), H.readByte(0x1A6D)))
    H.assertEntryContract("post-opera-v1")
  end),

  -- CELES wears RAMUH for the whole facility arc: bolt is the area's own
  -- language (break-coverage-vector.md 6.3 -- seven of the ten random
  -- species carry vanilla bolt), and the L15-16 party otherwise fields no
  -- bolt at all.  A phase reroll proved the cost: the Pipsqueak
  -- five-stack ground a boltless party down over 20k frames.  Guarded so
  -- an already-worn stone is not toggled OFF (A on a worn esper removes
  -- it).
  H.cond(function()
    return H.readByte(0x1600 + 37 * 6 + 0x1E) ~= 0x00
  end, {
    H.equipEsper(function() return (H.readByte(0x1856) >> 3) & 3 end, 0x00,
      { tag = "RAMUH -> CELES (the facility's bolt)" }),
  }, {}),

  -- Positive control, part 1: check that mapTitleHere() reads the
  -- engine's live title and is not returning "" for everything.  Step
  -- east into the Albrook gate the way the retired generator did,
  -- read the name the game itself would print, and require "ALBROOK",
  -- the string the old fixture was standing on.  Then walk back
  -- out of town so the real step starts from the checkpoint tile.
  H.driveUntil(function() return map() == 323 end, 1200, {
    H.hold({ "right" }),
  }, "step RIGHT into the ALBROOK gate (control probe)"),
  H.release(),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end,
    1200, "Albrook control", 5),
  H.call(function()
    H.assertEq(map(), 323, "control probe: map 323")
    H.assertEq(mapTitleHere(), "ALBROOK",
      "CONTROL: map 323's own title reads ALBROOK -- this is the town the "
      .. "retired vector_arrival fixture was standing in")
    H.log(string.format("[control] map=%d title=%q at (%d,%d)",
      map(), mapTitleHere(), H.fieldX(), H.fieldY()))
    H.screenshot("v06_control_albrook")
  end),

  -- ---- the equip stop, in Albrook -----------------------------------------
  -- Here, and not on the world map the checkpoint boots onto: H.equipWeapon
  -- ends by driving back to H.hasControl(), which reads the field party
  -- object's movement type ($087c+$0803 low nibble = 2, lib/ot6.lua:1580-1587)
  -- and is a field-mode answer.  Albrook is the first field map the step
  -- stands on, the party is already standing in it for the control probe
  -- above, and it is a town, which is where a player would open the menu
  -- anyway.  Everything after this is the world walk and then Vector.

  -- The char-select rows are asserted rather than assumed: H.equipWeapon
  -- seeks the cursor to a fixed row and the row is the party's order field
  -- ($1850 bits 3-4), so a reordered party would dress the wrong character.
  H.call(function()
    H.assertEq(ordOf(CH_LOCKE), 2, "LOCKE is char-select row 2")
    H.assertEq(ordOf(CH_CELES), 3, "CELES is char-select row 3")
    for _, c in ipairs({ CH_LOCKE, CH_CELES }) do
      H.log(string.format("[kit] char %d gear before: %02X %02X %02X %02X",
        c, gear(c, 0x1F), gear(c, 0x20), gear(c, 0x21), gear(c, 0x22)))
    end
  end),
  fill(CH_LOCKE, 2, 0, 0x02, "LOCKE Guardian"),
  fill(CH_LOCKE, 2, 1, 0x5A, "LOCKE Buckler"),
  fill(CH_LOCKE, 2, 2, 0x69, "LOCKE Leather Hat"),
  fill(CH_LOCKE, 2, 3, 0x84, "LOCKE LeatherArmor"),
  fill(CH_CELES, 3, 0, 0x01, "CELES MithrilKnife"),
  fill(CH_CELES, 3, 1, 0x5A, "CELES Buckler"),
  fill(CH_CELES, 3, 2, 0x6A, "CELES Hair Band"),
  fill(CH_CELES, 3, 3, 0x84, "CELES LeatherArmor"),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end,
    1200, "Albrook control back after the equip stop", 5),
  H.call(function()
    -- The exit contract for the kit.  Without it an equip stop that
    -- silently did nothing and one that worked report the same green.
    H.assertEq(gear(CH_LOCKE, 0x1F) ~= EMPTY, true, "LOCKE holds a weapon")
    H.assertEq(gear(CH_CELES, 0x1F) ~= EMPTY, true, "CELES holds a weapon")
    for _, c in ipairs({ CH_LOCKE, CH_CELES }) do
      H.log(string.format("[kit] char %d gear after:  %02X %02X %02X %02X",
        c, gear(c, 0x1F), gear(c, 0x20), gear(c, 0x21), gear(c, 0x22)))
    end
  end),

  -- Back out.  Map 323's world exits are LONG entrances on its west and
  -- north edges (decoded from LongEntrance, $EDF480/$EDF882): a vertical
  -- run at x=0, y=0..29 -> world (137,203), and two horizontal runs at
  -- y=0 and y=1, x=0..31 -> world (138,202).  The party lands at (2,17),
  -- so LEFT reaches the column and UP reaches the rows; alternate the two
  -- rather than assume which lane is open from this tile.
  (function() local hb = 0
    return H.driveUntil(function() return H.worldMode() end, 8000, {
      H.call(function() hb = hb + 1
        if H.battleLoadStarted() then
          H.setPad({ l = true, r = true }); return
        end
        if H.dialogWaiting() then
          H.setPad(hb % 8 < 4 and { "a" } or {}); return
        end
        H.setPad(hb % 240 < 120 and { left = true } or { up = true })
      end) }, "back out of Albrook to the world") end)(),
  -- $E0/$E2 read (0,0) for tens of frames after the exit fires: world
  -- control and full brightness both come back before InitWorld has
  -- written the position from $1F60.  Gate on the destination tile itself
  -- (the x=0 column's LongEntrance DestPos) so the log and the step below
  -- both start from a real coordinate.
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
       and H.worldX() == 137 and H.worldY() == 203
  end, 2400, "back on the world at (137,203), the checkpoint tile", 5),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldX(), 137, "back on the world: x")
    H.assertEq(H.worldY(), 203, "back on the world: y")
  end),

  -- Step 1: the world walk.  29 steps, every tile battle-enabled.

  --   f3508 (122,188) aligned, 1-step plan UP pressed  -> f3510 (121,188)
  --   f3524 (121,188) aligned, 2-step plan pressed     -> f3526 (121,187)
  --   f3541 world control drops; the trigger has fired; map 242 loads

  -- Two effects combine there.  worldGrind holds a direction continuously
  -- and only chooses the next one on an aligned frame, but the world
  -- engine latches input at the tile boundary, so a direction issued on
  -- the arrival frame arrives one poll late and the previous direction
  -- takes one more step, landing the party one tile west of the goal.  And
  -- from that overshoot tile (121,188) the shortest path back to (122,187)
  -- runs (121,188) -> (121,187) -> (122,187), straight through the
  -- trigger.  So the walker fires the map load itself, worldGrind exits on
  -- its `not worldMode()` arm, and the wait for world control that follows
  -- cannot be satisfied, giving "timeout after 2400 frames waiting for at
  -- the Vector trigger approach".

  worldGrind(124, 187, "world walk -> the Vector trigger approach (124,187)"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned()
  end, 2400, "at the Vector trigger approach", 5),
  H.call(function()
    H.assertEq(H.worldX(), 124, "trigger approach x")
    H.assertEq(H.worldY(), 187, "trigger approach y")
    H.log(string.format("[world] at the Vector trigger approach (%d,%d)",
      H.worldX(), H.worldY()))
  end),

  -- hold LEFT along row 187; the step onto (121,187) fires _ca5ecf ->
  -- load_map 242 {32,61}
  (function() local hb = 0
    return H.driveUntil(function() return not H.worldMode() and map() == 242 end,
      6000, {
      H.call(function() hb = hb + 1
        if H.battleLoadStarted() then
          H.setPad({ l = true, r = true }); return
        end
        H.setPad({ left = true })
      end) }, "hold LEFT onto (121,187) -> the Vector trigger") end)(),
  H.waitUntil(function()
    return map() == 242 and H.hasControl() and H.tileAligned()
      and bright() >= 15 and not H.dialogWaiting()
  end, 6000, "Vector control", 5),
  H.waitFrames(120),

  H.call(function()
    H.assertEq(mapTitleHere(), "VECTOR",
      "the map the party is standing on calls itself VECTOR")
    H.assertEq(map(), 242, "Vector town is map 242")
    H.assertEq(H.fieldX(), 32, "Vector arrival x (_ca5ecf load_map 242 {32,61})")
    H.assertEq(H.fieldY(), 61, "Vector arrival y")
    H.assertEq(sw(0x01F0), 0, "$01F0 CLEAR -- the old man's distraction has not run")
    H.assertEq(sw(0x062B), 1, "$062B SET -- the three gate guards are present")
    H.assertEq(sw(0x063B), 1, "$063B SET -- the Returner sympathizer is present")
    H.assertEq(sw(0x006B), 0, "$006B CLEAR -- the factory escape has not happened")
    local cur = H.readByte(0x1A6D)
    for c = 0, 13 do
      local p = H.readByte(0x1850 + c)
      if p ~= 0 and (p & 0x07) == cur then
        H.assertEq(H.readWord(0x1609 + 37 * c) > 0, true,
          string.format("active character %d is standing at the Vector generation point", c))
      end
    end
    H.log(string.format("[vector_entry] f%d map=%d title=%q (%d,%d)",
      H.frame, map(), mapTitleHere(), H.fieldX(), H.fieldY()))
    H.screenshot("vector_entry")
  end),
  H.saveState("vector_entry.mss"),
  H.logStep(function()
    return string.format(
      "cold battery Continue walked the world into VECTOR (map 242, %q) "
      .. "and generated vector_entry at frame %d", mapTitleHere(), H.frame)
  end),
})
