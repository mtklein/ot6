-- gen_vector_doorstep.lua -- v0.6 leg 1: cold Continue from the versioned
-- post-Opera battery anchor, validate its semantic contract, then walk the
-- world to the VECTOR event trigger and mint the real v0.6 doorstep.
--
-- Unlike the tactical frontier chain, this starts from power-on and lets
-- Mesen load an ordinary .srm from its private save directory.  The anchor
-- contains one valid game in slot 3.
--
-- WHAT THIS REPLACES (issue #17).  The previous version of this generator
-- held RIGHT off the anchor tile until `(mapId & 0x1ff) == 323`, asserted
-- field (2,17), and minted `vector_arrival.mss` logging "entered Vector".
-- **Map 323 is ALBROOK.**  `ff6/src/field/map_prop.dat` is 33 bytes x 415
-- records and byte 0 is the map-title index (`LoadMapProp`,
-- `ff6/src/field/map.asm:143-157`, copies the record to $0520..$0540;
-- `ShowMapTitle`, `ff6/src/field/text.asm:112-119`, indexes MapTitlePtrs
-- with $0520).  Map 323 -> title 53 -> "ALBROOK"; maps 242 and 253 ->
-- title 49 -> "VECTOR".  The east step off the anchor lands in the Albrook
-- short-entrance record at world (138,203)/(139,203), which is why the old
-- assertions were green while standing in the wrong town, and why nothing
-- downstream of it could ever have reached the Magitek Research Facility --
-- map 323's only exits are the four Albrook shops, maps 330/332, and the
-- long entrance back to the world.
--
-- HOW VECTOR IS ACTUALLY ENTERED.  Not by an entrance record at all: there
-- is no entrance anywhere in the game whose destination is map 242 or 253.
-- Vector is a world EVENT TRIGGER --
--
--   ff6/src/event/event_trigger.asm:36-37
--       make_event_trigger {120, 187}, _ca5ecf
--       make_event_trigger {121, 187}, _ca5ecf
--   ff6/src/event/event_main.asm:14196-14200
--       _ca5ecf: set_script_mode WORLD
--                if_switch $0079=1, _ca5edc          ; post-story Vector (253)
--                load_map 242, {32,61}, UP, {Z_UPPER, SHOW_TITLE, ...}
--
-- $0079 is set only at event_main.asm:46316/:97003/:99716, all after v0.6,
-- so on this route the trigger loads map 242 at (32,61) facing UP.  The
-- v0.6 opening is therefore an ordinary ON-FOOT WORLD WALK, not an airship
-- sequence: no vehicle/airship_pos opcode is involved.
--
-- WHY worldGrind AND NOT worldNavTo.  The 31-step walk from the anchor tile
-- (137,203) to (122,187) runs entirely inside the random-battle band (world
-- tile prop bit6 $40 on every tile of the path).  A battle snapshots and
-- restores the party to the same tile (move.asm:916-921 / world_start.asm
-- :465-482), which worldNavTo's verified-step loop reads as "the press
-- never moved us"; it condemns the edge, and with the whole band hot it
-- condemns them all.  That is the failure that broke gen_opera1; the same
-- grind-and-replan walker is used here (see gen_opera1_doorstep.lua:47-76).
--
-- THE POSITIVE CONTROL.  Issue #17's acceptance criterion is that this
-- fixture must fail loudly if the party is on the wrong map, rather than
-- pass because a hard-coded map id matched a constant that was chosen
-- wrong -- which is exactly how the Albrook bug stayed green.  So the
-- landing is checked through the game's OWN map-title machinery: read the
-- live title index the engine loaded into $0520, follow MapTitlePtrs
-- ($E68400) into MapTitle ($CEF100), decode it, and require the string
-- "VECTOR".  A wrong turn now reports the name of the town it is actually
-- standing in.  mapTitleHere() is exercised on the Albrook gate FIRST --
-- the exact step the retired generator took -- so the control cannot pass
-- by returning "" for everything.
--
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
-- ^ the persistent-SRAM layout this leg understands (issue #25).  run.sh
--   reads the marker line above and refuses -- BEFORE the emulator boots,
--   naming both strings -- any OT6_SRAM_ANCHOR whose manifest.json declares
--   a different persistent_layout.  An SRAM schema change bumps the layout
--   string in new anchor manifests, and every leg then refuses the old
--   anchors until it is deliberately migrated to declare the new string
--   (leg-fixtures.md, "Costs, named").
local H = dofile("tools/tests/lib/ot6.lua")
local function sw(id)
  return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1
end
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

-- The map name the ENGINE would print for the map it is standing on.
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
  end, 3000, "cold Continue to post-Opera world doorstep", 10),
  H.waitUntil(function()
    return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
  end, 900, "cold Continue fade-in", 10),
  -- THE ENTRY CONTRACT (issue #25).  Everything this leg requires of the
  -- post-Opera boundary -- save slot, story switches, world tile, the #21
  -- party count and roster, and the bank-$31 codex witnesses -- is declared
  -- as DATA in tools/tests/lib/ot6_contract.lua under "post-opera-v1", the
  -- same table a predecessor leg will someday assert as its EXIT contract.
  -- A stale or wrong anchor fails here by NAMING WHAT DIFFERED, one
  -- "CONTRACT DIFF" line per field (expected vs read), never by timing out
  -- somewhere downstream.  This SUBSUMES the #21 party-count control that
  -- used to live inline: the contract COUNTS the $1850 assignments and
  -- requires all four named members -- see the #21 narrative beside the
  -- contract declaration for why the count, not the roster log, is the
  -- check that catches a chain silently running two characters.
  H.call(function()
    -- The roster diagnostic stays a log line -- the CONTRACT is the check.
    local t = {}
    for c = 0, 13 do t[#t + 1] = string.format("%02X", H.readByte(0x1850 + c)) end
    H.log("[roster] $1850+0..13 = " .. table.concat(t, " ")
      .. string.format("  $1EDE=%02X $1EDF=%02X $1A6D=%02X",
        H.readByte(0x1EDE), H.readByte(0x1EDF), H.readByte(0x1A6D)))
    H.assertEntryContract("post-opera-v1")
  end),

  -- POSITIVE CONTROL, part 1: prove mapTitleHere() actually reads the
  -- engine's live title and is not just returning "" for everything.  Step
  -- east into the Albrook gate exactly the way the retired generator did,
  -- read the name the game itself would print, and require "ALBROOK" --
  -- the string the old fixture was silently standing on.  Then walk back
  -- out of town so the real leg starts from the anchor tile.
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
  -- $E0/$E2 read (0,0) for tens of frames after the exit fires -- world
  -- control and full brightness both come back BEFORE InitWorld has
  -- written the position from $1F60.  Gate on the destination tile itself
  -- (the x=0 column's LongEntrance DestPos) so the log and the leg below
  -- both start from a real coordinate.
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
       and H.worldX() == 137 and H.worldY() == 203
  end, 2400, "back on the world at (137,203), the anchor tile", 5),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldX(), 137, "back on the world: x")
    H.assertEq(H.worldY(), 203, "back on the world: y")
  end),

  -- LEG 1: the world walk.  29 steps, every tile battle-enabled.
  --
  -- THE WALK STOPS THREE TILES EAST OF THE TRIGGER, NOT ONE.  It used to
  -- aim at (122,187), the tile the trigger is stepped onto FROM, and that
  -- put the walker's own slop right on top of (121,187).  Measured per
  -- frame on the re-minted anchor:
  --
  --   f3508 (122,188) aligned, 1-step plan UP pressed  -> f3510 (121,188)
  --   f3524 (121,188) aligned, 2-step plan pressed     -> f3526 (121,187)
  --   f3541 world control drops; the trigger has fired; map 242 loads
  --
  -- Two things compose there.  worldGrind holds a direction continuously
  -- and only chooses the next one on an aligned frame, but the world
  -- engine latches input at the tile boundary, so a direction issued on
  -- the arrival frame arrives one poll late and the previous direction
  -- takes one more step -- the party lands one tile WEST of the goal.  And
  -- from that overshoot tile (121,188) the shortest path back to (122,187)
  -- runs (121,188) -> (121,187) -> (122,187), straight through the
  -- trigger.  So the walker fires the map load itself, worldGrind exits on
  -- its `not worldMode()` arm, and the wait for world control that follows
  -- can never be satisfied -- "timeout after 2400 frames waiting for at
  -- the Vector trigger approach".
  --
  -- This is the same lesson 56901e9 recorded for navTo (#22) and is why
  -- the fix is not a smarter walker: A TILE THAT TAKES THE PARTY AWAY IS
  -- ENTERED WITH A HELD PRESS, NOT WITH A WALKER AIMED NEXT TO IT.  Row
  -- 187 is passable for x=116..130 (measured), so aiming at (124,187)
  -- leaves the whole +-1 slop window on safe tiles and puts no shortest
  -- path anywhere near x=121; the held-LEFT leg below then covers the last
  -- three tiles, which is what it already did for the last one.
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
    -- POSITIVE CONTROL, part 2: the same live title read that returned
    -- "ALBROOK" above must now return "VECTOR".  This is the assertion
    -- issue #17 asks for -- it names the town the party is standing in
    -- rather than agreeing with a constant.
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
          string.format("active character %d is standing at the Vector mint", c))
      end
    end
    H.log(string.format("[vector_doorstep] f%d map=%d title=%q (%d,%d)",
      H.frame, map(), mapTitleHere(), H.fieldX(), H.fieldY()))
    H.screenshot("vector_doorstep")
  end),
  H.saveState("vector_doorstep.mss"),
  H.logStep(function()
    return string.format(
      "cold battery Continue walked the world into VECTOR (map 242, %q) "
      .. "and minted vector_doorstep at frame %d", mapTitleHere(), H.frame)
  end),
})
