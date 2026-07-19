-- gen_terra_caves.lua -- from terra_narshe.mss: open the secret wall Locke
-- once used and go under Narshe through the mines.
-- Mints one state:
--   terra_caves.mss  map 41 (7,33), the Narshe mines, first controllable
--                    frame inside -- the doorstep for the run to Arvis's
--                    house, and the only fixture in the chain that stands in
--                    this scenario's random-encounter pool.
--
-- ================== THE WAY ON IS AN EXAMINE, NOT A DOOR ==================
-- gen_terra_narshe leaves the party at (39,53) with the checkpoint sealed
-- behind an event that shoves it back every time.  The 231-tile southern
-- strip it is confined to holds exactly one way out, and it is not on any
-- map: EventTrigger::_20 puts _ccb133 on {15,57} (event_trigger.asm:112),
-- and _ccb133 (:104337) reads
--     if_any  $01F0=1 / $01B4=0 / $01B0=0 / $0020=0  -> _ccb154
--     _ccb154 if_any  $0019=0 / $01F0=1 / $01B4=0 / $01B0=0 -> EventReturn
-- $01B0-$01B7 ARE NOT STORY SWITCHES.  Switch N lives at bit N&7 of
-- $1E80+(N>>3), so $01B0..$01B7 alias $1EB6 -- the field engine's live
-- control-flags byte, rewritten every frame by UpdateCtrlFlags
-- (field/event.asm:5415-5432): bits 0-3 are the party's facing one-hot in
-- the engine's 0=up 1=right 2=down 3=left order, bit 4 is "A is held", bit 5
-- is the once-per-tile latch.  So
--     $01B0 = facing UP      $01B4 = A held
-- and both of those guards say the same thing: THE PARTY MUST BE STANDING ON
-- (15,57) PRESSING A WHILE IT FACES UP.  Walk onto the tile and nothing
-- happens -- the trigger runs, sees $01B4=0, and returns -- which is exactly
-- what "the scenario dead-ends outside Narshe" looks like from the outside.
-- The scenario brief predicted this reading would be needed on the river; it
-- is needed here instead, and it is the same $1EB6.
--
-- WHY THE $0020 TERM MATTERS.  _ccb133's first if_any routes on $0020: with
-- it SET the fall-through runs _ccb148 (a bare shake/sfx that just re-opens
-- the wall for the later Kefka approach, gated on $0076/$006B), and with it
-- CLEAR the branch is _ccb154, this scenario's scene -- TERRA remembering
-- Locke, EDGAR finding the switch (dlg $01AA/$01AB, :104396/:104412),
-- `call _ccb1e7` re-tiling BG1/BG2 at {14,54} 3x3 to punch the hole open
-- (:104450), and finally `switch $01F0=1 / switch $0020=1 / switch $0608=0`
-- (:104447-104449).  terra_narshe asserts both clear so the branch is not a
-- guess.
--
-- THE HOLE OPENS AT (15,56), which is map 20's short entrance to map 41
-- (7,33) -- and map 41's own (7,34) leads straight back to map 20 (15,57),
-- so the arrival tile is one step from the way home.  BFS models passability
-- and knows nothing about entrance triggers, so the walk into the mines is a
-- single deliberate held step, not a navTo that might wander back through.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/terra_narshe.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function ctrl() return H.readByte(0x1eb6) end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end

local function landed(m, n)
  local cnt, hb = 0, -600
  return function()
    local okMap = map() == m
    local ok = okMap and H.hasControl() and H.tileAligned() and bright() >= 15
           and not H.battleLoadStarted() and not H.dialogWaiting()
           and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d) f%d blocked: map=%d ctl=%s algn=%s " ..
        "bright=%d batt=%s dlg=%s at (%d,%d) ev=%s", m, H.frame, map(),
        tostring(H.hasControl()), tostring(H.tileAligned()), bright(),
        tostring(H.battleLoadStarted()), tostring(H.dialogWaiting()),
        H.fieldX(), H.fieldY(), tostring(H.eventRunning())))
    end
    return cnt >= (n or 20)
  end
end
local settleCave = landed(41)

local function where(tag)
  H.log(string.format("[%s] f%d map=%d (%d,%d) face=%d $1EB6=%02X ctl=%s " ..
    "$0019=%d $001F=%d $0020=%d $01F0=%d $0021=%d", tag, H.frame, map(),
    H.fieldX(), H.fieldY(), facing(), ctrl(), tostring(H.hasControl()),
    sw(0x0019), sw(0x001F), sw(0x0020), sw(0x01F0), sw(0x0021)))
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 20, "booted on map 20, south of the checkpoint")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(sw(0x001F), 1, "$001F set -- the townsfolk turned us away")
    H.assertEq(sw(0x0019), 1, "$0019 set -- the river was run")
    H.assertEq(sw(0x0020), 0, "$0020 clear -- _ccb133 will take the _ccb154 branch")
    H.assertEq(sw(0x01F0), 0, "$01F0 clear -- the wall is shut")
    H.assertEq(sw(0x0021), 0, "$0021 clear -- the scenario is not done")
    local p = H.bfsPath(15, 57)
    H.assertEq(p ~= nil, true, "(15,57), the wall's tile, is reachable")
    H.log(string.format("to the wall: (%d,%d) -> (15,57), %d steps",
      H.fieldX(), H.fieldY(), #p))
    where("booted")
  end),

  -- ===================================================================== --
  -- TO THE WALL, then FACE UP AND PRESS A.  Facing is set by a press into
  -- (15,56), which is still solid rock at this point -- a blocked press
  -- turns the party without moving it, the same idiom gen_narshe_escape
  -- uses to face Arvis.  Only then is A edge-pressed, and the phase ends
  -- when the scene picks up rather than after a fixed number of tries.
  -- ===================================================================== --
  H.navTo(15, 57, { maxFrames = 12000 }),
  H.release(),
  H.call(function() where("at the wall") end),
  --
  -- A MUST STAY DOWN AFTER THE TRIGGER FIRES.  $01B4 is not a latch -- it is
  -- bit 4 of $1EB6, rewritten from the live pad every frame -- and _ccb154
  -- re-reads it in its OWN guard, a couple of opcodes after _ccb133 jumped
  -- there.  A first cut ended this phase on `H.eventRunning()` and released
  -- the pad, and the measurement is unambiguous: at f739 $1EB6 read $11
  -- (facing up + A held) and the event started, then A came up, _ccb154's
  -- `if_any $01B4=0` took EventReturn, and the trigger simply re-fired and
  -- re-returned for 20,000 frames -- eventRunning() flapping true/false on
  -- alternate samples with the party standing still on (15,57) and $01F0
  -- never set.  So this phase ends on $01F0 ALONE and keeps edge-pressing A
  -- straight through the scene, where it doubles as the tap for dlg $01AA
  -- and $01AB.
  H.driveUntil(function() return sw(0x01F0) == 1 end, 8000, (function()
    local aPh = 0
    return {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.frame % 300 == 0 then
          H.log(string.format("examining: f%d (%d,%d) face=%d $1EB6=%02X " ..
            "($01B0=%d $01B4=%d) ctl=%s ev=%s dlg=%s", H.frame, H.fieldX(),
            H.fieldY(), facing(), ctrl(), sw(0x01B0), sw(0x01B4),
            tostring(H.hasControl()), tostring(H.eventRunning()),
            tostring(H.dialogWaiting())))
        end
        -- 0 = up (BitOrTbl's order, field/event.asm:5523).  UP is only
        -- pressed to TURN, and only while the party is ours to turn: (15,56)
        -- is solid rock until the scene runs, so the press turns without
        -- moving -- but once the hole is open the same press would walk the
        -- party into map 41 ahead of the asserts below.
        if H.hasControl() and H.tileAligned() and facing() ~= 0 then
          H.setPad({ "up" }); return
        end
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }
  end)(), "press A facing UP on (15,57) -- _ccb133 -> _ccb154"),
  H.release(),
  --
  -- NO SETTLE ON (15,57), AND THAT IS DELIBERATE.  The party is standing ON
  -- _ccb133's trigger tile, and with $01F0 now set the trigger re-fires and
  -- immediately EventReturns every time it is looked at -- so eventRunning()
  -- and hasControl() flap on alternate samples forever.  A settle predicate
  -- wanting 20 consecutive calm frames here never gets 2: measured as a
  -- 20,000-frame timeout with the party motionless, `ctl=false ev=true` and
  -- `ctl=true ev=false` three frames apart.  The cure is not a better
  -- predicate, it is to stop standing on the trigger -- so the asserts below
  -- are on switches (which do not flap) and the very next thing this script
  -- does is walk off the tile.
  H.waitFrames(90),
  H.call(function()
    H.assertEq(sw(0x01F0), 1, "$01F0 set -- _ccb154 ran (:104447)")
    H.assertEq(sw(0x0020), 1, "$0020 set -- and so did its companion (:104448)")
    H.assertEq(map(), 20, "still on map 20")
    where("wall open")
    H.log(string.format("   $087C=%02X $0803=%04X ev=%s ctl=%s evPC=%02X:%02X%02X",
      H.readByte(0x087c + H.readWord(0x0803)), H.readWord(0x0803),
      tostring(H.eventRunning()), tostring(H.hasControl()),
      H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5)))
    H.screenshot("terra_wall_open")
    local p = H.bfsPath(15, 56)
    H.log(string.format("the hole at (15,56) is now %s",
      p and (#p .. " steps away") or "STILL not walkable per BFS"))
  end),

  -- ===================================================================== --
  -- INTO THE MINES.  A held step, not a navTo: (15,56) is an entrance tile
  -- and map 41's arrival (7,33) sits one tile from (7,34), the way straight
  -- back out -- the same bracketed-arrival shape gen_lete and gen_returner
  -- both had to plan around.
  -- ===================================================================== --
  H.driveUntil(function() return map() ~= 20 end, 3000, {
    H.hold({ "up" }), H.waitFrames(8), H.release(), H.waitFrames(4),
  }, "step through the hole into map 41"),
  H.release(),
  H.advanceStory(settleCave, 20000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 41, "on map 41, the NARSHE MINES")
    H.assertEq(H.fieldX(), 7, "arrival tile x=7")
    H.assertEq(H.fieldY(), 33, "arrival tile y=33 (map 20 (15,56) -> map 41 (7,33))")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    H.assertEq(sw(0x0021), 0, "$0021 clear -- the scenario is not done")
    H.log(string.format("   map 41 masks $86/$87=%02X/%02X",
      H.readByte(0x0086), H.readByte(0x0087)))
    -- reconnaissance for the next link: which of map 41's exits can be
    -- reached from here?  (ShortEntrance::_41, plus its one long record)
    local EXITS = {
      { 21,  9, "-> map 20 (23,44), NORTH of the checkpoint" },
      {  7, 34, "-> map 20 (15,57), straight back out" },
      { 18, 51, "-> map 21 (36,25)" },
      { 57, 11, "-> map 43 (48,45)" },
      { 57, 21, "-> map 41 (25,58), internal warp" },
      { 25, 59, "-> map 41 (57,23), internal warp" },
      { 41,  4, "-> map 42 (22,28), long entrance" },
      { 107, 12, "-> map 21 (23,10)" },
    }
    for _, e in ipairs(EXITS) do
      local p = H.bfsPath(e[1], e[2])
      H.log(string.format("   exit (%3d,%2d) %-40s %s", e[1], e[2], e[3],
        p and (#p .. " steps") or "no path"))
    end
    where("terra_caves")
    H.screenshot("terra_caves")
  end),
  H.saveState("terra_caves.mss"),
  H.logStep(function()
    return string.format("terra_caves minted at frame %d", H.frame)
  end),
})
