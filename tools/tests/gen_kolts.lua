-- gen_kolts.lua -- from figaro_cleared.mss (TERRA + LOCKE + EDGAR on a
-- chocobo in the Figaro desert) to the Vargas doorstep on Mt. Kolts.  The
-- last leg of rung 2's route work; everything after this is the fight.
-- Mints three states:
--   south_figaro.mss    map 75 (1,28), the town's west gate (a fixture the
--                       v0.3 Locke scenario will want)
--   kolts_doorstep.mss  map 95 (14,35), the mountain's entrance map
--   vargas_doorstep.mss map 98, party tile-aligned next to VARGAS with his
--                       approach event already run -- one interaction short
--                       of `battle 66`
--
-- THREE THINGS THIS SCRIPT HAD TO MEASURE OR DERIVE.  The entrance tables
-- give the door graph and nothing else, and all three of these are places
-- where the graph alone sends you into a wall.
--
-- 1. THE PARTY ARRIVES ON A CHOCOBO, AND THE NAVIGATOR CANNOT SEE IT.
--    figaro_cleared is minted riding one (the submerge scene's
--    `vehicle ... CHOCOBO`, event_main.asm:14330-14405).  The world module
--    then boots through InitChoco (world/init.asm:402) instead of InitWorld,
--    and InitChoco NEVER WRITES $E0/$E2 -- only InitWorld does, from $1F60
--    (init.asm:758-762).  So H.worldX/worldY read 0 from that state and
--    worldNavTo has nothing to plan from; a route that trusts them walks
--    the party off tile (0,0).  (gen_edgar asserts the zeros at its mint so
--    this stops being true loudly.)
--    THE DISMOUNT is B, and it is a whole state machine, verified frame by
--    frame in probe_dismount.lua:
--      * riding, input goes through GetChocoInput (world/ctrl.asm:451),
--        whose last branch (:562-563) is `lda $05 / bit #$0080 / jsr
--        LandAirship`.  $05 is the HELD-button low byte (bit7 = B) -- not an
--        edge -- so a plain hold is enough.
--      * LandAirship's chocobo branch (world/init.asm:1868) sets $19 = 3,
--        locks input out ($1E bit0), and converts the VEHICLE's mode-7
--        position into a tile pair at $1F60/$1F61 (:1878-1888).
--      * $19 = 3 does not exit by itself: world_start.asm:231-235 wants bit2.
--        Bit0 runs the descent (_ee1c56, move.asm:695), which only sets
--        `$19 = ($19 & $FE) | $04` once the bird is on the ground (:672-677).
--      * ExitVehicle (init.asm:1596) then does `stz $11fa` (:1616) and
--        `jmp ReloadMap` (:1620); ReloadMap re-dispatches on $11FA & 3
--        (:118-126), which is now 0, so InitWorld runs and seeds $E0/$E2.
--    Measured: B seen at +1 frame, $19 = 6 by +9, $11FA clear at +80, on
--    foot / lit / controllable at +120, standing at WoB (65,77).
--
-- 2. THE FIGARO DESERT DOES NOT REACH SOUTH FIGARO ON FOOT.  This is the
--    finding that reshaped the route, and it is not a modelling artifact:
--    the live tilemap at $7F0000 is byte-identical to world_1_tilemap.dat
--    (ModifyMap has changed nothing yet), and flood-filling it with the
--    engine's own rule -- destination property bit4 clear, `bit #$0010 /
--    branch if tile is impassable on foot`, GetPlayerInput move.asm:1013,
--    1042, and the two below them -- gives the party a 1165-tile region
--    bounded at y<=95.  South Figaro (86,111) and Mt. Kolts (102,100) sit
--    in a DIFFERENT 422-tile region.  Narshe (84,33) is in ours; they are
--    not.  A first pass planned the world leg straight there and got
--    "worldBfs: no path", which is the honest answer.
--    The link is the cave the castle's own NPC names -- "To the south
--    there's a cave that leads to South Figaro", event_main.asm:15156 --
--    and it is three field maps, not a road:
--      world (73,93) -> map 71 (10,54)          [short entrance]
--      map 71 (10,48)/(11,48) -> EVENT _ca5ef7  [event_trigger.asm _71]
--        which is `if_switch $001A=1 -> load_map 70` else `load_map 73,
--        {47,39}` (event_main.asm:14218-14224) -- 70/73 are two copies of
--        the same cave and carry IDENTICAL entrance coordinates, so the
--        route below is written once and works on either
--      map 73 (41,14) -> map 72 (4,5)           [short entrance]
--      map 72 (16,43) -> world (75,103)         [short entrance]
--    Only maps 69/72 and Mt. Kolts itself have exits landing in the south
--    region (checked by walking every record in short_entrance.dat), so
--    this cave is the only way through, exactly as the story says.
--
-- 2b. AND THE CAVE MOUTH IS GUARDED -- a wall made of NPCs, which no
--    entrance or trigger table mentions.  Map 71's lobby has exactly one
--    way north, the two floor tiles (10,49)/(11,49) (prop $02/$8F, ordinary
--    floor, all four exits) below the trigger pair, and TWO FIGARO GUARDS
--    stand on them: NPCProp::_71's third and fourth records, both spawn
--    switch $0312 (npc_prop.asm:3064-3076).  The party's object map
--    ($7E2000, bit7 set = tile free) reads occupied there, H.canStep
--    refuses the step, and BFS reports "no path (10,54)->(11,48)" -- which
--    is what the first run did.  It is not the model being shy: holding UP
--    at (10,50) for 600 frames moved the party zero tiles (measured).
--    The guards leave when TALKED TO.  The one at (10,49) runs _ca75ee
--    (event_main.asm:17853), gated `if_switch $0108=0 -> _ca7668` -- and
--    _ca7668 is the "It's closed now due to construction" brush-off
--    (:17936-17939), so $0108 is the whole difference between a cave and a
--    wall and is asserted below.  With it set, EDGAR gets recognised
--    ("Through the cave, and eastward to South Figaro", :17882), NPC_3
--    jumps clear and hides, NPC_4 rides off on its chocobo, and the scene
--    ends `switch $0312=0` (:17933) -- despawning both guards for good.
--    So the lobby is: walk under the guard, face UP, talk, then walk
--    through the tile he was standing on.
--
-- 3. TWO MORE WORLD-EXIT ROWS TO STAY OFF, the same hazard map 55's y=43
--    was for gen_edgar: BFS knows nothing about entrance triggers, so a
--    leg planned across one silently leaves the map.
--      * map 75 (South Figaro): long entrances (0,0) len $AF and (56,0)
--        len $AF are VERTICAL (the length byte's bit7 selects vertical,
--        entrance.asm CheckLongEntrance:66) -- columns x=0 and x=56, y=0..47
--        -> world (84,112)/(87,112); plus horizontal y=1 -> (85,111).  The
--        party enters at (1,28), ONE tile from the x=0 column, so the mint
--        happens on arrival and the exit is a single deliberate press.
--      * map 95 (Mt. Kolts entrance): long entrance (0,37) len $1B is
--        horizontal -- row y=37, x=0..27 -> world (102,101).  The party
--        enters at (14,35), two rows above it, and every leg on this map
--        is asserted to stay off y=37 before it is walked.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local CLEARED = "/Users/mtklein/ot6/build/states/figaro_cleared.mss.lua"

-- map compares stay MASKED: loaders ride flag bits in $1F64's high byte
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
-- event switch id -> live bit (event bitfield base $1E80, bit = id & 7)
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
-- field object i's live tile (pixel coords >> 4, block stride $29)
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end

local function where(tag)
  H.log(string.format("[%s] f%d map=%d field=(%d,%d) world=(%d,%d) " ..
    "$11FA=%02X $010A=%d bright=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), H.worldX(), H.worldY(),
    H.readByte(0x11fa), sw(0x010A), bright()))
end

-- crossDoor/seq: a bare step list cannot be spliced into a step list (Lua
-- truncates a non-final table.unpack to one value, silently dropping every
-- step but the first).  H.cond with an always-true predicate is the
-- library's public way to wrap a list into ONE step object.
local function seq(steps) return H.cond(function() return true end, steps) end

-- An `arrive` predicate that fires when the map id changes from whatever it
-- read the first time it was called.  Latching lazily (rather than at
-- script-build time) is what makes it correct inside route(), whose legs are
-- all constructed before any of them runs.
local function mapChanged()
  local m0
  return function()
    if m0 == nil then m0 = map() end
    return map() ~= m0
  end
end

-- Settle after a map load: control + alignment + a fully lit screen, held
-- for 20 CONSECUTIVE frames, then the 30-frame margin every field fixture
-- uses.  Both halves of that are load-bearing:
--   * brightness is not optional -- a cutscene can report control on a black
--     screen (gen_edgar's header documents the 5700-frame-early mint that
--     cost), so control and a lit screen have to hold SIMULTANEOUSLY;
--   * and they have to hold for a WHILE.  A first cut checked each gate once
--     with separate waitUntils and both passed instantly on the far side of
--     an entrance -- the field module still had the old map's control byte
--     and the fade had not begun -- so the crossing "settled" mid-load and
--     the next BFS ran against a half-written map.  (Measured: settle
--     satisfied after 0 + 0 frames, then brightness read 0 thirty frames
--     later.)  A consecutive-frame counter cannot be fooled by a transient.
local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

-- The settle DRIVES rather than waits: Mt. Kolts and the cave are encounter
-- territory, and an encounter that rolls on the arrival tile stalls a
-- passive waitUntil forever -- the battle holds control, the counter never
-- climbs, nobody is pressing anything (measured: map 96's arrival, 3600
-- frames, timeout).  advanceStory kill-bits whatever came up and edge-taps
-- through the victory text, and on a quiet field it holds the pad empty, so
-- it is the strictly safer settle.
-- The crossing settle does NOT wait for player control, and that is a
-- deliberate correction.  Mt. Kolts's caves each open with a glimpse of the
-- figure on the peak -- map 96's (16,22) and (14,12) triggers and map 97's
-- (34,24) run `obj_script NPC_1, ASYNC` (_ca820f/_ca8252/_ca8230,
-- event_main.asm:19739/19781/19757) -- and while an async object script is
-- live the event engine takes the party's movement-type byte ($087C&$0F)
-- from 2 to 4 for a frame at a time.  H.hasControl() reads that byte, so it
-- FLICKERS: measured on map 96, two good frames then a bad one, forever, and
-- a 20-consecutive-frame control gate sat at cnt=1..2 for 12000 frames while
-- every other term (brightness 15, aligned, right map, no battle) held
-- steady the whole time.
-- So the settle asserts what a settle is actually for -- the load landed and
-- the screen is up -- and leaves "can I step THIS frame" to navTo, which
-- already debounces control and re-plans.  The three MINTS below still
-- demand real control, explicitly, at the moment they save.
local function settleField(what, dstMap, maxF)
  return seq({
    H.waitFrames(90),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and (dstMap == nil or map() == dstMap)
    end), maxF or 12000),
    H.waitFrames(30),
  })
end

local function settleWorld(what, maxF)
  return seq({
    H.advanceStory(settled(20, function()
      return H.worldHasControl() and H.worldAligned()
    end), maxF or 12000),
    H.waitFrames(30),
  })
end

-- Walk to (tx,ty) on the current field map, expecting the map to change on
-- arrival (an entrance record fires when the party STANDS on its source
-- tile, entrance.asm CheckShortEntrance).  Mt. Kolts and the cave use plain
-- walkable floor for their entrances -- unlike Figaro's castle doors, which
-- are walls until CheckDoor -- so BFS can route straight onto them and the
-- crossing is one navTo, not a staging tile plus a hold.  Asserted after,
-- by map id, so a silently-missed crossing cannot pass for one.
local function crossTo(tx, ty, dstMap, what, maxF)
  return seq({
    H.logStep(function()
      return string.format("cross %s: (%d,%d) -> (%d,%d) -> map %d",
        what, H.fieldX(), H.fieldY(), tx, ty, dstMap)
    end),
    H.navTo(tx, ty, { maxFrames = maxF or 20000, arrive = mapChanged() }),
    H.release(),
    settleField(what, dstMap),
    H.call(function()
      H.assertEq(map(), dstMap, what .. ": landed on map " .. dstMap)
      where(what)
    end),
  })
end

-- Stand on (sx,sy), turn to face `dir`, and edge-tap A until the event
-- ENGAGES (an event script or a dialog is up).  Riding the scene out is the
-- caller's advanceStory, not this: a first cut drove until the scene's
-- closing switch instead, and hung -- once the event takes control this
-- loop's own "no control -> hands off the pad" rule stops mashing, so the
-- multi-page dlg $00AC never advanced and the switch never came.
-- Two measured facts from gen_edgar's header shape the rest: NPC activation
-- is decided by the party FACING byte ($087F through the $0803 party-object
-- offset; 0 up 1 right 2 down 3 left, player.asm:456-505) and a two-frame
-- turn press does not set it, so the direction is HELD until the byte reads
-- back; and activation is edge-driven like dialogs, so A is tapped 4 on /
-- 4 off rather than held.  (Measured here: from (10,50) already facing UP,
-- four frames of tapping engage the guard.)
local FACE = { up = 0, right = 1, down = 2, left = 3 }
local function talkAt(sx, sy, dir, what, maxF)
  local aPh, started = 0, 0
  return seq({
    H.navTo(sx, sy, { maxFrames = 20000 }),
    H.release(),
    H.driveUntil(function()
      started = (H.eventRunning() or H.dialogWaiting()) and started + 1 or 0
      return started >= 4
    end, maxF or 9000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        if H.fieldX() ~= sx or H.fieldY() ~= sy then H.setPad({}); return end
        if H.readByte(0x087f + H.readWord(0x0803)) ~= FACE[dir] then
          H.setPad({ [dir] = true })
          return
        end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, what),
    H.release(),
  })
end

-- Cross an entrance whose destination is THE SAME MAP -- map 72 is built out
-- of four of them, and `map changed` is no signal at all there.  Arrival is
-- the destination TILE instead.
local function warpTo(sx, sy, dx, dy, what, maxF)
  return seq({
    H.logStep(function()
      return string.format("warp %s: (%d,%d) -> (%d,%d) -> (%d,%d)",
        what, H.fieldX(), H.fieldY(), sx, sy, dx, dy)
    end),
    H.navTo(sx, sy, { maxFrames = maxF or 20000, arrive = function()
      return H.fieldX() == dx and H.fieldY() == dy
    end }),
    H.release(),
    settleField(what, 72),
    H.call(function()
      H.assertEq(H.fieldX(), dx, what .. ": landed at x=" .. dx)
      H.assertEq(H.fieldY(), dy, what .. ": landed at y=" .. dy)
      where(what)
    end),
  })
end

-- Assert the BFS plan to (tx,ty) exists and never touches row `badY` -- the
-- map's world-exit row.  BFS models passability, not entrance triggers, so
-- this is the only thing standing between a shortest path and a route that
-- quietly walks out of the mountain.
local function planAvoidsRow(tx, ty, badY, what)
  return H.call(function()
    local p = H.bfsPath(tx, ty)
    H.assertEq(p ~= nil, true, what .. ": a path exists")
    local x, y = H.fieldX(), H.fieldY()
    local hit = (y == badY)
    for _, d in ipairs(p) do
      local dd = ({ up = { 0, -1 }, down = { 0, 1 },
                    left = { -1, 0 }, right = { 1, 0 },
                    upleft = { -1, -1 }, upright = { 1, -1 },
                    downleft = { -1, 1 }, downright = { 1, 1 } })[d]
      x, y = x + dd[1], y + dd[2]
      if y == badY then hit = true end
    end
    H.log(string.format("%s: %d steps, touches y=%d: %s",
      what, #p, badY, tostring(hit)))
    H.assertEq(hit, false, what .. ": plan stays off the world-exit row " .. badY)
  end)
end

H.run({ maxFrames = 150000 }, {
  H.loadState(CLEARED),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(H.worldMode(), true, "booted on the world map")
    H.assertEq(H.readByte(0x11fa) & 3, 2, "booted riding the chocobo")
    where("booted")
  end),

  -- ===================================================================== --
  -- PHASE 1: GET OFF THE BIRD.  Hold B; LandAirship stages the tile into
  -- $1F60/$1F61, the descent releases the exit, ExitVehicle clears $11FA
  -- and ReloadMap comes back through InitWorld with $E0/$E2 finally live.
  -- ===================================================================== --
  H.hold({ "b" }),
  H.driveUntil(function() return H.readByte(0x11fa) & 3 == 0 end, 900, {
    H.waitFrames(1),
  }, "chocobo dismount ($11FA cleared)"),
  H.release(),
  settleWorld("dismount"),
  H.call(function()
    H.assertEq(H.readByte(0x11fa) & 3, 0, "off the chocobo")
    H.assertEq(H.worldX(), H.readByte(0x1f60), "$E0 seeded from $1F60")
    H.assertEq(H.worldY(), H.readByte(0x1f61), "$E2 seeded from $1F61")
    H.assertEq(H.worldX() ~= 0 or H.worldY() ~= 0, true,
      "world position is live (InitWorld ran, not InitChoco)")
    where("dismounted")
    H.screenshot("kolts_dismount")
  end),

  -- ===================================================================== --
  -- PHASE 2: THE SOUTH FIGARO CAVE.  The desert's only way south.  Four
  -- legs; the middle one is an event trigger, not an entrance, so it is
  -- driven as a plain navTo whose arrival is the map change.
  -- ===================================================================== --
  H.call(function()
    H.assertEq(sw(0x001A), 0,
      "$001A clear -> the cave's map-73/72 copy (event_main.asm:14219)")
  end),
  settleWorld("desert"),
  H.worldNavTo(73, 93, { maxFrames = 30000,
    arrive = function() return not H.worldMode() end }),
  H.release(),
  settleField("cave mouth", 71),
  H.call(function()
    H.assertEq(map(), 71, "world (73,93) -> map 71, the cave lobby")
    where("cave lobby")
  end),

  -- The guards first: they stand ON the only two tiles that reach the
  -- trigger.  Stage at (10,50), directly under the one with the event, face
  -- UP, talk; the scene ends by clearing their spawn switch $0312.
  H.call(function()
    H.assertEq(sw(0x0108), 1,
      "$0108 set -- the guards recognise EDGAR (else _ca7668: cave closed)")
    H.assertEq(sw(0x0312), 1, "$0312 set -- both guards are on the map")
    H.log(string.format("guards at (%d,%d) and (%d,%d)",
      objX(18), objY(18), objX(19), objY(19)))
  end),
  talkAt(10, 50, "up", "engage the cave guard (_ca75ee)"),
  H.advanceStory(function()
    return H.hasControl() and H.tileAligned() and sw(0x0312) == 0
       and map() == 71
  end, 20000),
  H.call(function()
    H.assertEq(sw(0x0312), 0, "the guards are gone ($0312 cleared)")
    where("cave opened")
    H.screenshot("kolts_cave_guards")
  end),

  -- map 71's event trigger at (10,48)/(11,48) is what actually opens the
  -- cave (_ca5ef7); the lobby has no short entrance onward at all.
  H.navTo(11, 48, { maxFrames = 20000, arrive = mapChanged() }),
  H.release(),
  settleField("cave body"),
  H.call(function()
    H.assertEq(map() == 73 or map() == 70, true,
      "map 71's trigger loaded the cave body (73 or 70), got " .. map())
    where("cave body")
  end),

  -- Map 73 offers three exits and the spawn only reaches one.  Landing at
  -- (47,39) the model reaches 50 tiles: (55,32) -> map 72 (10,3) and
  -- (47,40) -> back to the lobby, but NOT (41,14) -- that mouth belongs to
  -- a stretch of the cave this end does not connect to.  Measured, after a
  -- first pass picked (41,14) off the table and got "no path".
  crossTo(55, 32, 72, "cave body -> cave exit hall"),

  -- Map 72 is FOUR DISCONNECTED REGIONS stitched by same-map warps, and the
  -- one the party lands in does not touch the world exit.  Measured from
  -- (10,3): 276 reachable tiles, and of the map's seven entrance records
  -- only (10,2)/(4,4) back to map 73 and (17,20) are among them -- (16,43),
  -- the way out, is not.  The chain that does reach it, each hop confirmed
  -- by re-running the reachability dump on the far side:
  --   (10,3)  --walk--> (17,20) --warp--> (61,56)   [31 tiles reachable]
  --   (61,56) --walk--> (55,57) --warp--> (14,34)   [52 tiles reachable]
  --   (14,34) --walk--> (16,43) --> world (75,103)
  warpTo(17, 20, 61, 56, "cave warp A"),
  warpTo(55, 57, 14, 34, "cave warp B"),

  -- map 72 (16,43) drops onto the world at (75,103), inside the southern
  -- region.  (16,42), one tile north of it, carries a harmless b-switch
  -- event (_ca766c, event_main.asm:17941) the walk crosses on the way.
  H.logStep(function()
    return string.format("cave exit: (%d,%d) -> (16,43) -> world (75,103)",
      H.fieldX(), H.fieldY())
  end),
  H.navTo(16, 43, { maxFrames = 20000,
    arrive = function() return H.worldMode() end }),
  H.release(),
  settleWorld("south region"),
  H.call(function()
    H.assertEq(H.worldMode(), true, "back on the world, south of the range")
    where("cave cleared")
    H.screenshot("kolts_cave_out")
    local p = H.worldBfs(86, 111)
    H.assertEq(p ~= nil, true, "South Figaro is reachable from here")
    local q = H.worldBfs(102, 100)
    H.assertEq(q ~= nil, true, "Mt. Kolts is reachable from here")
    H.log(string.format("south region: S.Figaro %d steps, Kolts %d steps",
      #p, #q))
  end),

  -- ===================================================================== --
  -- PHASE 3: SOUTH FIGARO.  One world tile of the four that lead in
  -- ((86,111)/(85,112)/(86,112)/(85,113) -> map 75 (1,28)); mint on
  -- arrival, then leave by the x=0 column the party is already beside.
  -- ===================================================================== --
  H.worldNavTo(86, 111, { maxFrames = 30000,
    arrive = function() return not H.worldMode() end }),
  H.release(),
  settleField("south figaro", 75),
  H.call(function()
    H.assertEq(map(), 75, "on map 75, SOUTH FIGARO")
    H.assertEq(H.fieldX(), 1, "at the west gate x=1")
    H.assertEq(H.fieldY(), 28, "at the west gate y=28")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    where("south figaro")
    H.screenshot("south_figaro")
  end),
  H.saveState("south_figaro.mss"),
  H.logStep(function()
    return string.format("south_figaro minted at frame %d", H.frame)
  end),

  -- Out the way we came: x=0 is the vertical long entrance -> world
  -- (84,112).  One press, not a navTo: the target tile IS the trigger.
  H.driveUntil(function() return H.worldMode() end, 900, {
    H.hold({ "left" }), H.waitFrames(8),
  }, "leave South Figaro (x=0 column)"),
  H.release(),
  settleWorld("back outside"),
  H.call(function() where("left south figaro") end),

  -- ===================================================================== --
  -- PHASE 4: MT. KOLTS.  World (102,100) -> map 95 (14,35).  Map 95's own
  -- exit row y=37 is two tiles south of the spawn, so every leg here is
  -- pre-checked against it.
  -- ===================================================================== --
  H.worldNavTo(102, 100, { maxFrames = 40000,
    arrive = function() return not H.worldMode() end }),
  H.release(),
  settleField("mt kolts", 95),
  H.call(function()
    H.assertEq(map(), 95, "on map 95, MT. KOLTS")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    where("kolts doorstep")
    H.screenshot("kolts_doorstep")
  end),
  H.saveState("kolts_doorstep.mss"),
  H.logStep(function()
    return string.format("kolts_doorstep minted at frame %d", H.frame)
  end),

  -- ===================================================================== --
  -- THE MOUNTAIN.  Nine crossings, and the shape of them is the whole
  -- reason this took measuring: map 100 is not a map you walk across, it is
  -- SIX disconnected shelves, and the caves 96/97/102 are the stitching.
  -- Flooding the passability model out of every arrival tile (150 nodes per
  -- frame -- a whole flood in one Lua slice trips Mesen's script watchdog
  -- silently) partitions it exactly:
  --   F  (8,13)/(19,16)   exits (7,13)->95, (19,17)->96
  --   D  (35,7)/(44,24)/(51,33), 166 tiles -- exits (43,24)/(50,33)/(34,7)
  --                       ->96 and (56,7)->100(30,36)
  --   E  (30,36), 28 tiles -- exit (31,36)->100(57,7), i.e. back into D
  --   B  (58,46), 87 tiles -- exits (30,52)->102, (58,45)->97
  --   C  (9,36), 31 tiles  -- exits (7,29)->102, (9,37)->96
  --   A  (8,48), 60 tiles  -- exits (7,48)->98, (17,59)->101 (the east exit)
  -- and map 96 into four: P (16,22)/(21,21), R (14,12), Q (25,16),
  -- S (28,25), each with one or two exits back to a named shelf.
  -- The consequence: (7,48)->98, which the entrance table advertises as
  -- "map 100 -> Vargas's map", lives in shelf A, and NOTHING in the graph
  -- reaches A except map 98 itself.  Walking in through it is impossible;
  -- it is the way OUT, and Vargas's walk-on parks him on top of it.
  -- THE LINK THAT DOES WORK IS A LONG ENTRANCE, which is why a short-table
  -- reading of the mountain dead-ends in D: map 96 (12,8), VERTICAL, length
  -- 1 -> map 102 (51,46).  From 102 the bridge drops back onto shelf B, and
  -- B carries the summit chain 97 -> 103 -> 98.
  planAvoidsRow(11, 26, 37, "map 95 -> (11,26)"),
  crossTo(11, 26, 100, "K1 entrance -> shelf F"),
  crossTo(19, 17, 96, "K2 shelf F -> cave 96 P"),
  crossTo(22, 21, 100, "K3 cave 96 P -> shelf D"),
  crossTo(34, 7, 96, "K4 shelf D -> cave 96 R"),
  crossTo(12, 8, 102, "K5 cave 96 R -> the bridge (LONG entrance)"),
  crossTo(35, 50, 100, "K6 bridge -> shelf B"),
  crossTo(58, 45, 97, "K7 shelf B -> cave 97"),
  crossTo(55, 10, 103, "K8 cave 97 -> the summit"),
  crossTo(60, 9, 98, "K9 summit -> VARGAS's ledge"),

  -- ===================================================================== --
  -- PHASE 5: THE VARGAS DOORSTEP.  The party lands on map 98 at (11,10);
  -- the approach trigger is (10,32)/(11,32) -> _ca8267 (event_main.asm
  -- :19794, event_trigger.asm _98), gated on $010A.  It sets $010A/$031C,
  -- creates NPC_1 and runs him ASYNC from (29,35) around to (23,32) facing
  -- LEFT (:19802-19816) -- which puts him ON the tile back to map 100, so
  -- he blocks the retreat exactly the way the scene wants.  There is no
  -- player_ctrl_off in that event, so control never leaves.
  -- Then walk back east to (22,32), the tile beside him, and mint: one
  -- interaction (face RIGHT, press A -> _ca828f) short of `battle 66`.
  -- VARGAS IS OBJECT 16, not 17: object number is map-NPC index + 16 and
  -- NPCProp::_98 holds exactly one record (npc_prop.asm:4006, {23,32},
  -- spawn $031C, `set_npc_event _ca828f`), so he is index 0.  Watching 17
  -- waits forever on an object that does not exist -- measured, 20000
  -- frames of a party standing correctly at (11,32) with $010A already set.
  -- ===================================================================== --
  H.call(function()
    H.assertEq(map(), 98, "on map 98")
    H.assertEq(sw(0x010A), 0, "$010A still clear -- Vargas has not appeared")
    where("map 98 arrival")
  end),
  H.navTo(11, 32, { maxFrames = 20000,
    arrive = function() return sw(0x010A) == 1 end }),
  H.release(),
  H.advanceStory(function()
    return H.hasControl() and H.tileAligned() and sw(0x010A) == 1
       and objX(16) == 23 and objY(16) == 32
  end, 20000),
  H.call(function()
    H.assertEq(sw(0x010A), 1, "the approach trigger ran ($010A set)")
    H.assertEq(sw(0x031C), 1, "$031C set (Vargas NPC armed)")
    H.log(string.format("VARGAS (obj 16) at (%d,%d)", objX(16), objY(16)))
    where("vargas spawned")
    H.screenshot("vargas_spawn")
  end),

  H.navTo(22, 32, { maxFrames = 20000 }),
  H.release(),
  -- Face him.  NPC activation is decided by the party FACING byte ($087F
  -- through the $0803 party-object offset; 0 up 1 right 2 down 3 left, from
  -- the four movement branches at player.asm:456-505) and a two-frame turn
  -- press does not set it at all -- gen_edgar measured 1800 frames of A
  -- against a mis-faced Edgar.  So HOLD right until the byte reads 1, and
  -- leave the state facing him: the fight test then only has to press A.
  -- (Vargas occupies (23,32), so the hold cannot walk the party into him.)
  H.driveUntil(function()
    return H.readByte(0x087f + H.readWord(0x0803)) == 1
       and H.hasControl() and H.tileAligned()
       and H.fieldX() == 22 and H.fieldY() == 32
  end, 900, {
    H.hold({ "right" }), H.waitFrames(4),
  }, "face VARGAS (facing byte = 1)"),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 98, "on map 98")
    H.assertEq(H.fieldX(), 22, "party at x=22")
    H.assertEq(H.fieldY(), 32, "party at y=32")
    H.assertEq(objX(16), 23, "VARGAS at x=23, one tile east")
    H.assertEq(objY(16), 32, "VARGAS at y=32, same row")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 1, "facing RIGHT, at him")
    H.assertEq(H.battleLoadStarted(), false, "not in a battle")
    -- the tools this whole route exists to carry
    local function invCount(id)
      for i = 0, 255 do
        if H.readByte(0x1869 + i) == id then return H.readByte(0x1969 + i) end
      end
      return 0
    end
    H.assertEq(invCount(0xA4), 1, "BioBlaster still carried (the poison key)")
    H.assertEq(invCount(0xA3), 1, "NoiseBlaster still carried")
    H.assertEq(invCount(0xAA), 1, "AutoCrossbow still carried")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11)))
      end
    end
    where("vargas doorstep")
    H.screenshot("vargas_doorstep")
  end),
  H.saveState("vargas_doorstep.mss"),
  H.logStep(function()
    return string.format("vargas_doorstep minted at frame %d", H.frame)
  end),
})
