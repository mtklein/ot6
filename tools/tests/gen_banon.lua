-- gen_banon.lua -- from returner_hideout.mss (map 108, the entry hall) through
-- the RETURNER HIDEOUT to the moment the party casts off for Narshe.
-- Mints one state:
--   banon_joined.mss  map 112 (7,43), TERRA + EDGAR + SABIN + BANON, $0018
--                     set -- the raft is armed and the Lete River is one map
--                     away.  This is the fixture gen_lete starts from.
--
-- THE HIDEOUT IS A CONVERSATION GRAPH, NOT A DUNGEON.  There is no combat and
-- little walking; what gates progress is five NPCs talked to in a partial
-- order, each one a switch the next one reads.  Read out of event_main.asm:
--
--   map 109 ( 9,25) greeter $0413 -> _caf68a (:36275)   THE WAY IN
--   map 110 (51,50) BANON   $041d -> _caf79c (:36439) -> _caf7dc (:36475)
--       the speech.  Sets $0011/$0012 and REBUILDS THE PARTY: `party_chars
--       TERRA / char_party EDGAR,0 / char_party SABIN,0 / char_party LOCKE,0`
--       plus a delete_obj each -- TERRA IS ALONE from here to the raft.  It
--       then `load_map 110, {21,48}` (the SAME map id, so "the map changed"
--       is no arrival signal here -- $0011 is), and that load teleports the
--       party from Banon's chamber in the EAST of map 110 to the small room
--       in the WEST.  It despawns Banon ($041D=0) and spawns the three
--       friends: $041F EDGAR (52,48, east), $0420 LOCKE (27,48, west),
--       $0416 SABIN (map 109).
--   map 110 (27,48) LOCKE   $0420 -> _caf9cf (:36808)  sets $015A
--   map 109 (26,28) SABIN   $0416 -> _caf9af (:36788)  sets $015B
--   map 110 (52,48) EDGAR   $041f -> _caf9a9 (:36782)  sets $015C
--   map 109 ( 9,25) greeter again: with $0011 set _caf68a takes its FIRST
--       branch, to _cafa67 (:36912), and that is the lock -- `if_any switch
--       $015A=0 / $015B=0 / $015C=0 -> _caf962`, and _caf962 is a one-line
--       brush-off ("We're a small organization now", :36737) that sets
--       nothing.  Talking to all three friends is not flavour; skip any one
--       and the route stalls with no error.  Satisfied, it sets $0421=1 --
--       which spawns BANON BACK ON MAP 108 (npc_prop.asm:4325).
--   map 108 (14,49) BANON   $0421 -> _cafab8 (:36965)  the decision
--
-- THREE THINGS THE TABLES DO NOT SAY, ALL OF THEM MEASURED (probe_hideout):
--
-- 1. THE GREETER IS A WALL.  Map 109's arrival vestibule reaches exactly
--    FIVE tiles -- (9,26) through (9,30) -- and the greeter stands on (9,25)
--    plugging the only way north.  This is map 71's Figaro-guard shape all
--    over again, and the first cut of this script planned straight past him
--    to a door and got "no path".  Talking to him runs the escort, which
--    walks the party to (22,21) and opens 147 tiles.
--
-- 2. MAPS 109 AND 110 ARE EACH PARTITIONED, AND THE PARTITION IS THE ROUTE.
--    Map 110's west room (bbox (20,46)-(29,54), 55 tiles) and its east half
--    (bbox (41,38)-(57,54), 114 tiles) DO NOT CONNECT to each other -- they
--    connect through map 109.  So "map 109 has three doors to map 110" is
--    three different destinations, not three ways to one place:
--        (11, 8) -> 110 (44,27)   east   -- unreachable from the escort end
--        (14,17) -> 110 (22,53)   WEST
--        (25,15) -> 110 (42,44)   EAST   <- the one Banon is behind
--    Banon, Edgar, the save point and the door to the river are ALL in the
--    east; Locke and the tile the speech parks the party on are in the west.
--    That is why this script crosses between them five times and why each
--    crossing names which half it is going to.
--
-- 3. DOOR C IS A DOOR TILE, NOT A FLOOR TILE.  bfsPath says NO PATH to
--    (25,15) while reporting (25,16) directly under it 8 steps away -- the
--    gen_edgar finding exactly: a door tile is a WALL until CheckDoor
--    (player.asm:959) swaps the open-door tiles in, and it only does that
--    for a party pressing into it from directly below or above.  BFS can
--    never plan THROUGH one.  So door C is crossed by staging on (25,16) and
--    HOLDING UP, while doors B and (42,45) -- ordinary floor -- are crossed
--    by a plain navTo.  Getting this wrong reads as "no path" and looks like
--    a partition bug, which is what cost the first pass.
--
-- THE DECISION PROMPT, AND WHY OPTION 0 IS SAFE HERE:
--       dlg $0131  "Will you become our last ray of hope?  0: Yes  1: No"
--       choice _cafac3, _cafc98                        (event_main.asm:36965)
--   Option 0 is Yes.  advanceStory's A-press always takes option 0, so this
--   prompt needs no special handling -- but that is verified, not assumed,
--   and $0013 afterwards is what proves the Yes branch ran.  (The river's
--   prompts are NOT all like this: see gen_lete.lua, where option 0 at the
--   second fork is the vanilla infinite loop.)
--
-- AND THE YES BRANCH DOES THE WHOLE DEPARTURE IN ONE SCENE -- the thing that
-- kept this link short, and not what the NPC layout suggests.  _cafac3 falls
-- through to _cafb99 (:37120), which is
--       call _cafba6      ; despawn the hideout, set $0013
--       call _cb0080      ; THE DEPARTURE SCENE, called directly
-- so there is no "now go find everyone" leg.  _cb0080 (:37934) gathers the
-- party on map 109, runs Banon's "We've no time to dilly-dally" speech at
-- _cb0106 (:38020) and ends `call _cafff0` (:37855) -- which puts EDGAR and
-- SABIN back in the party, drops LOCKE (he is off to South Figaro), loads
-- map 112 at (7,42), calls _cafdb9 to make BANON a real party member, and
-- sets $0018, the switch _cb059f demands before the raft will board anyone.
-- BANON IS CHARACTER 14 AND THE DISASSEMBLY CALLS HIM WEDGE: const.inc:397
-- and :398 define WEDGE and BANON to the same 14 and the symbol picker took
-- the first, so `char_party WEDGE, 1` at :37457 IS Banon joining -- and
-- $185E, not $1855, is the byte that proves it.
--
-- ONE TRIGGER THIS ROUTE DOES NOT ASSERT AGAINST, DELIBERATELY.  Map 109's
-- (25,23) trigger is _cb002b (:37880), the scrap-of-paper gag, and it opens
-- a CHOICE PROMPT this script never reasoned about.  It sits 5 steps from
-- the escort's endpoint and the walks to SABIN pass near it, so pinning
-- every plan off it would be brittle.  It cannot fire on a walk-past,
-- though, and the reason is worth writing down because the same fact runs
-- the whole Lete River (see gen_scenario.lua's header): _cb002b opens
-- `if_any switch $01B4=0 / switch $01B2=0 -> EventReturn`, and $01B0-$01B7
-- ARE NOT STORY SWITCHES.  Switch N lives at bit N&7 of $1E80+(N>>3), so
-- those eight alias the byte $1EB6 -- the field engine's control-flags byte,
-- rewritten every frame by UpdateCtrlFlags (field/event.asm:5415-5432) with
-- bits 0-3 = the party's facing direction one-hot and bit4 = "A is held".
-- So the gag's real condition is "A pressed while facing DOWN": it is an
-- EXAMINE, not a step trigger, and walking over the tile does nothing.
-- Rather than trust even that, the mint asserts $016B -- the flag _cb002b
-- sets the instant it fires -- is still clear, which catches it by outcome
-- no matter which tile the navigator chose.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/returner_hideout.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
-- field object i's live tile.  Object number = the map's NPC RECORD index +
-- 16, spawned or not (verified against gen_edgar's map-55 numbers: record 3
-- {24,16} is its obj 19).  LIVE coords matter here and not just in principle
-- -- the greeter walks from (9,25) to (25,17) during his own escort.
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end

local function where(tag)
  H.log(string.format("[%s] f%d map=%d (%d,%d) $0011=%d $0013=%d $0018=%d " ..
    "$015A=%d $015B=%d $015C=%d $0421=%d $016B=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0011), sw(0x0013),
    sw(0x0018), sw(0x015A), sw(0x015B), sw(0x015C), sw(0x0421), sw(0x016B)))
end

local function seq(steps) return H.cond(function() return true end, steps) end

local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

-- see gen_returner.lua / gen_kolts.lua: settles DRIVE (a lingering dialog or
-- an encounter stalls a passive wait forever) and do NOT require player
-- control ($087C&$0F flickers 2<->4 under any async object script).
local function settleField(dstMap, maxF)
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

local function mapChanged()
  local m0
  return function()
    if m0 == nil then m0 = map() end
    return map() ~= m0
  end
end

-- an ordinary floor-tile entrance: BFS routes straight onto it
local function crossTo(tx, ty, dstMap, what)
  return seq({
    H.logStep(function()
      return string.format("cross %s: (%d,%d) -> (%d,%d) -> map %d",
        what, H.fieldX(), H.fieldY(), tx, ty, dstMap)
    end),
    H.navTo(tx, ty, { maxFrames = 20000, arrive = mapChanged() }),
    H.release(),
    settleField(dstMap),
    H.call(function()
      H.assertEq(map(), dstMap, what .. ": landed on map " .. dstMap)
      where(what)
    end),
  })
end

-- a DOOR-tile entrance: stage on the neighbour and hold into it, because
-- BFS cannot plan onto a tile that is a wall until CheckDoor opens it
local function crossDoorHold(sx, sy, dir, dstMap, what)
  local aPh = 0
  return seq({
    H.logStep(function()
      return string.format("cross %s: stage (%d,%d) hold %s -> map %d",
        what, sx, sy, dir, dstMap)
    end),
    H.navTo(sx, sy, { maxFrames = 20000, arrive = mapChanged() }),
    H.release(),
    H.driveUntil(function() return map() ~= 109 and map() ~= 110
                            or map() == dstMap end, 1800, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if H.dialogWaiting() then H.setPad(aPh < 4 and { "a" } or {}); return end
        H.setPad({ [dir] = true })
      end),
    }, what),
    H.release(),
    settleField(dstMap),
    H.call(function()
      H.assertEq(map(), dstMap, what .. ": landed on map " .. dstMap)
      where(what)
    end),
  })
end

-- Talk to object `obj`, tracked by its LIVE tile.  Two measured facts from
-- gen_edgar/gen_kolts shape the drive: CheckNPCs (player.asm:142) activates
-- whatever the object map holds ONE TILE IN THE PARTY'S FACING DIRECTION
-- while A is held, and a two-frame turn press does not set the facing byte at
-- all -- so the direction is HELD until $087F reads back the wanted value,
-- and only then is A edge-tapped (4 on / 4 off; activation is edge-driven
-- exactly like dialog advance).  The approach tile is the first neighbour BFS
-- can currently reach, re-resolved lazily so it is correct inside route().
local FACE = { up = 0, right = 1, down = 2, left = 3 }
local NEIGHBOURS = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
}
-- HALF THE HIDEOUT WANDERS.  npc_prop.asm gives EDGAR ($041f) and the
-- guard at (44,14) ($041e) `set_npc_movement RANDOM`; LOCKE ($0420), SABIN
-- and BANON have no movement property and stand still.  A first cut latched
-- the approach tile and the facing once and timed out on EDGAR alone --
-- staged at (52,46) for an Edgar who had already stepped off (52,47).  So
-- this is gen_edgar's talkTo shape: the approach tile is re-resolved (at
-- most every 30 frames -- BFS is not free), the facing is computed from the
-- LIVE delta every frame, and a soft round that loses him just walks back
-- and tries again before the hard round raises.
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
        if waited % 300 == 0 then
          local ox, oy = objAt()
          H.log(string.format("  %s: f%d me=(%d,%d) npc=(%d,%d) adj=%s " ..
            "ctl=%s face=%d", what, H.frame, H.fieldX(), H.fieldY(), ox, oy,
            tostring(adjacent()), tostring(H.hasControl()), facing()))
        end
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
    H.logStep(function()
      local ox, oy = objAt()
      return string.format("%s: obj %d at (%d,%d); party at (%d,%d)",
        what, obj, ox, oy, H.fieldX(), H.fieldY())
    end),
    walkStep(), pokeStep(1, 600, false),
    -- rounds are written out FLAT: repeatN cannot replay navTo/driveUntil
    -- bodies, their latched state carries over
    H.cond(function() return not engaged end,
      { walkStep(), pokeStep(2, 900, false) }, {}),
    H.cond(function() return not engaged end,
      { walkStep(), pokeStep(3, 1200, true) }, {}),
    H.release(),
  })
end

-- ride whatever scene just started until `pred` holds on a settled field
local function rideTo(pred, what, maxF)
  return seq({
    H.advanceStory(function()
      return pred() and H.hasControl() and H.tileAligned() and bright() >= 15
         and not H.battleLoadStarted()
    end, maxF or 25000),
    H.waitFrames(20),
    H.call(function() where(what) end),
  })
end

H.run({ maxFrames = 200000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 108, "booted on map 108, the hideout entry hall")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(sw(0x0011), 0, "$0011 clear -- the speech has not run")
    where("booted")
  end),

  -- ===================================================================== --
  -- PHASE 1: IN, PAST THE GREETER.  The vestibule on map 109 reaches five
  -- tiles and he is standing on the sixth; the escort is the only way out
  -- of it, and it ends with the party at (22,21).
  -- ===================================================================== --
  crossTo(10, 48, 109, "H1 entry hall -> map 109"),
  H.call(function()
    H.assertEq(sw(0x01F0), 0, "$01F0 clear -- the escort has not run")
    H.assertEq(sw(0x0413), 1, "$0413 set -- the greeter is on the map")
    local p = H.bfsPath(25, 16)
    H.assertEq(p, nil,
      "the vestibule cannot reach door C yet -- the greeter is the wall")
  end),
  talkToObj(16, "the greeter (the escort)"),
  rideTo(function() return map() == 109 and sw(0x01F0) == 1 end,
    "escorted in"),
  H.call(function()
    H.assertEq(sw(0x01F0), 1, "$01F0 set -- the escort ran")
  end),
  -- _caf745 does `player_ctrl_on` BEFORE it walks the greeter clear
  -- (event_main.asm:36393-36402, the obj_script is ASYNC), so control comes
  -- back while he is still in transit and can still be standing in the
  -- corridor.  A first cut asserted the path open the instant the ride
  -- finished and failed on exactly that -- the probe only ever saw it open
  -- because its flood spent 600 frames before looking.  Wait for the fact
  -- rather than for a frame count.
  H.waitUntil(function() return H.bfsPath(25, 16) ~= nil end, 3000,
    "the greeter walks clear of door C's approach", 10),
  H.call(function()
    H.log(string.format("greeter now at (%d,%d); (25,16) is %d steps away",
      objX(16), objY(16), #H.bfsPath(25, 16)))
    H.screenshot("banon_escorted")
  end),

  -- ===================================================================== --
  -- PHASE 2: THE SPEECH.  Door C is the only way to Banon's half of map
  -- 110, and it is a door tile -- staged, not planned through.
  -- ===================================================================== --
  crossDoorHold(25, 16, "up", 110, "H2 map 109 -> map 110 EAST (door C)"),
  H.call(function()
    H.assertEq(sw(0x041D), 1, "$041D set -- BANON is here")
    H.assertEq(objX(16), 51, "BANON obj 16 at x=51")
    H.assertEq(objY(16), 50, "BANON obj 16 at y=50")
  end),
  talkToObj(16, "BANON (the speech)"),
  -- the speech reloads map 110 at (21,48): same map id, so $0011 is the
  -- only honest arrival signal
  rideTo(function() return map() == 110 and sw(0x0011) == 1 end,
    "after the speech", 40000),
  H.call(function()
    H.assertEq(sw(0x0011), 1, "$0011 set -- the speech ran")
    H.assertEq(sw(0x041D), 0, "$041D clear -- BANON left map 110")
    H.assertEq(sw(0x041F), 1, "$041F set -- EDGAR is an NPC (east)")
    H.assertEq(sw(0x0420), 1, "$0420 set -- LOCKE is an NPC (west)")
    H.assertEq(sw(0x0416), 1, "$0416 set -- SABIN is an NPC on map 109")
    -- `load_map 110, {21,48}` is where the scene PUTS the party, but it is
    -- not where the scene LEAVES it -- the choreography after the load walks
    -- everyone into position and it settles a couple of tiles east (measured
    -- (23,48)).  So the assert is "we are in the west room", stated the way
    -- the route actually depends on it: LOCKE has to be reachable from here.
    H.log(string.format("the speech left the party at (%d,%d); " ..
      "LOCKE obj 19 at (%d,%d)", H.fieldX(), H.fieldY(), objX(19), objY(19)))
    for _, c in ipairs({ { 27, 49 }, { 27, 47 }, { 26, 48 }, { 28, 48 } }) do
      local p = H.bfsPath(c[1], c[2])
      H.log(string.format("  approach (%d,%d): %s", c[1], c[2],
        p and (#p .. " steps") or "NO PATH"))
    end
    -- TERRA alone: char 0 in, 1/4/5 out
    H.assertEq((H.readByte(0x1850) & 0x07) ~= 0, true, "TERRA in the party")
    H.assertEq((H.readByte(0x1851) & 0x07) ~= 0, false, "LOCKE out")
    H.assertEq((H.readByte(0x1854) & 0x07) ~= 0, false, "EDGAR out")
    H.assertEq((H.readByte(0x1855) & 0x07) ~= 0, false, "SABIN out")
    H.screenshot("banon_speech")
  end),

  -- ===================================================================== --
  -- PHASE 3: THE THREE FRIENDS.  $015A/$015B/$015C, the lock on _cafa67.
  -- LOCKE is in this room; SABIN is on map 109; EDGAR is back across door C.
  -- ===================================================================== --
  talkToObj(19, "LOCKE ($015A)"),
  rideTo(function() return sw(0x015A) == 1 end, "locke done"),
  H.call(function() H.assertEq(sw(0x015A), 1, "$015A set (LOCKE)") end),

  -- west room -> map 109 by the floor-tile door (22,54)
  crossTo(22, 54, 109, "H3 map 110 WEST -> map 109 (for SABIN)"),
  talkToObj(19, "SABIN ($015B)"),
  rideTo(function() return sw(0x015B) == 1 end, "sabin done"),
  H.call(function() H.assertEq(sw(0x015B), 1, "$015B set (SABIN)") end),

  -- back through door C for EDGAR
  crossDoorHold(25, 16, "up", 110, "H4 map 109 -> map 110 EAST (for EDGAR)"),
  talkToObj(18, "EDGAR ($015C)"),
  rideTo(function() return sw(0x015C) == 1 end, "edgar done"),
  H.call(function()
    H.assertEq(sw(0x015C), 1, "$015C set (EDGAR)")
    where("three of three")
  end),

  -- ===================================================================== --
  -- PHASE 4: THE GREETER UNLOCKS BANON.  With all three set, _caf68a's
  -- $0011 branch reaches _cafa67, which sets $0421 and puts Banon back on
  -- map 108.  Missing any of the three would take _caf962 instead -- one
  -- line of flavour, no switch -- and the route would stall with nothing to
  -- show for it, so $0421 is the assert that matters.
  -- NB the greeter is back on his SPAWN tile (9,25): every map load
  -- re-inits NPCs from npc_prop, so his escort walk to (25,17) is undone.
  -- talkToObj tracks him live either way.
  -- ===================================================================== --
  crossTo(42, 45, 109, "H5 map 110 EAST -> map 109 (for the greeter)"),
  talkToObj(16, "the greeter (unlock BANON)"),
  rideTo(function() return sw(0x0421) == 1 end, "banon unlocked"),
  H.call(function()
    H.assertEq(sw(0x0421), 1, "$0421 set -- BANON is waiting on map 108")
  end),

  -- ===================================================================== --
  -- PHASE 5: THE DECISION.  Out to 108 and answer YES (option 0).  The Yes
  -- branch runs the entire departure without another input: _cafb99 calls
  -- _cafba6 then _cb0080 directly, and _cb0080 ends in _cafff0, which lands
  -- the party on map 112 with BANON aboard and $0018 set.
  -- ===================================================================== --
  crossTo(9, 30, 108, "H6 map 109 -> map 108 (to BANON)"),
  H.call(function()
    H.assertEq(objX(16), 14, "BANON obj 16 at x=14")
    H.assertEq(objY(16), 49, "BANON obj 16 at y=49")
  end),
  talkToObj(16, "BANON (the decision, option 0 = Yes)"),
  H.advanceStory(function()
    return map() == 112 and sw(0x0018) == 1 and H.hasControl()
       and H.tileAligned() and bright() >= 15 and not H.battleLoadStarted()
  end, 50000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 112, "on map 112 -- the passage to the Lete River")
    H.assertEq(sw(0x0013), 1, "$0013 set -- the YES branch ran (_cafac3)")
    H.assertEq(sw(0x0018), 1, "$0018 set -- _cb059f will let the raft board")
    H.assertEq(sw(0x016B), 0,
      "$016B clear -- the scrap-of-paper prompt never fired")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    -- the raft party: TERRA + EDGAR + SABIN + BANON (char 14, aka WEDGE)
    H.assertEq((H.readByte(0x1850) & 0x07) ~= 0, true, "TERRA in the party")
    H.assertEq((H.readByte(0x1854) & 0x07) ~= 0, true, "EDGAR back")
    H.assertEq((H.readByte(0x1855) & 0x07) ~= 0, true, "SABIN back")
    H.assertEq((H.readByte(0x185e) & 0x07) ~= 0, true,
      "BANON joined (char 14 -- const.inc calls 14 both WEDGE and BANON)")
    H.assertEq((H.readByte(0x1851) & 0x07) ~= 0, false,
      "LOCKE left (he is off to South Figaro)")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11)))
      end
    end
    where("banon joined")
    H.screenshot("banon_joined")
  end),
  H.saveState("banon_joined.mss"),
  H.logStep(function()
    return string.format("banon_joined minted at frame %d", H.frame)
  end),
})
