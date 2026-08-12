-- gen_banon.lua -- from returner_hideout.mss (map 108, the entry hall) through
-- the Returner Hideout to the moment the party casts off for Narshe.
-- Generates one state:
--   banon_joined.mss  map 112 (7,43), TERRA + EDGAR + SABIN + BANON, $0018
--                     set: the raft is armed and the Lete River is one map
--                     away.  This is the fixture gen_lete starts from.
--
-- The hideout is a conversation graph rather than a dungeon.  There is no
-- combat and little walking; what gates progress is five NPCs talked to in a
-- partial order, each one setting a switch the next one reads.  Read out of
-- event_main.asm:
--
--   map 109 ( 9,25) greeter $0413 -> _caf68a (:36275)   the way in
--   map 110 (51,50) BANON   $041d -> _caf79c (:36439) -> _caf7dc (:36475)
--       the speech.  Sets $0011/$0012 and rebuilds the party: `party_chars
--       TERRA / char_party EDGAR,0 / char_party SABIN,0 / char_party LOCKE,0`
--       plus a delete_obj each, so TERRA is alone from here to the raft.  It
--       then `load_map 110, {21,48}` (the same map id, so a map change is
--       not an arrival signal here; $0011 is), and that load teleports the
--       party from Banon's chamber in the east of map 110 to the small room
--       in the west.  It despawns Banon ($041D=0) and spawns the three
--       friends: $041F EDGAR (52,48, east), $0420 LOCKE (27,48, west),
--       $0416 SABIN (map 109).
--   map 110 (27,48) LOCKE   $0420 -> _caf9cf (:36808)  sets $015A
--   map 109 (26,28) SABIN   $0416 -> _caf9af (:36788)  sets $015B
--   map 110 (52,48) EDGAR   $041f -> _caf9a9 (:36782)  sets $015C
--   map 109 ( 9,25) greeter again: with $0011 set _caf68a takes its first
--       branch, to _cafa67 (:36912), which is the lock: `if_any switch
--       $015A=0 / $015B=0 / $015C=0 -> _caf962`, and _caf962 is a one-line
--       brush-off ("We're a small organization now", :36737) that sets
--       nothing.  Talking to all three friends is required; skip any one
--       and the route stalls with no error.  Satisfied, it sets $0421=1,
--       which spawns Banon back on map 108 (npc_prop.asm:4325).
--   map 108 (14,49) BANON   $0421 -> _cafab8 (:36965)  the decision
--
-- Three things the tables do not say, all measured (probe_hideout):
--
-- 1. The greeter blocks the way.  Map 109's arrival vestibule reaches exactly
--    five tiles, (9,26) through (9,30), and the greeter stands on (9,25),
--    blocking the only way north.  This is the same shape as map 71's Figaro
--    guard, and the first version of this script planned straight past him
--    to a door and got "no path".  Talking to him runs the escort, which
--    walks the party to (22,21) and opens 147 tiles.
--
-- 2. Maps 109 and 110 are each partitioned, and the partition determines the
--    route.  Map 110's west room (bbox (20,46)-(29,54), 55 tiles) and its
--    east half (bbox (41,38)-(57,54), 114 tiles) do not connect to each
--    other; they connect through map 109.  So map 109's three doors to map
--    110 lead to three different destinations rather than three ways to one
--    place:
--        (11, 8) -> 110 (44,27)   east   (unreachable from the escort end)
--        (14,17) -> 110 (22,53)   west
--        (25,15) -> 110 (42,44)   east   <- the one Banon is behind
--    Banon, Edgar, the save point and the door to the river are all in the
--    east; Locke and the tile the speech parks the party on are in the west.
--    That is why this script crosses between them five times and why each
--    crossing names which half it is going to.
--
-- 3. Door C is a door tile, not a floor tile.  bfsPath says NO PATH to
--    (25,15) while reporting (25,16) directly under it 8 steps away.  This is
--    the gen_edgar finding: a door tile is a wall until CheckDoor
--    (player.asm:959) swaps the open-door tiles in, and it only does that
--    for a party pressing into it from directly below or above.  BFS cannot
--    plan through one.  So door C is crossed by staging on (25,16) and
--    holding UP, while doors B and (42,45), which are ordinary floor, are
--    crossed by a plain navTo.  Getting this wrong reads as "no path" and
--    looks like a partition bug, which is what cost the first pass.
--
-- The decision prompt, and why option 0 is safe here:
--       dlg $0131  "Will you become our last ray of hope?  0: Yes  1: No"
--       choice _cafac3, _cafc98                        (event_main.asm:36965)
--   Option 0 is Yes.  advanceStory's A-press always takes option 0, so this
--   prompt needs no special handling, but that is verified rather than
--   assumed, and $0013 afterwards is what shows the Yes branch ran.  (The
--   river's prompts are not all like this: see gen_lete.lua, where option 0
--   at the second fork is the vanilla infinite loop.)
--
-- The Yes branch does the whole departure in one scene, which is what keeps
-- this link short and is not what the NPC layout suggests.  _cafac3 falls
-- through to _cafb99 (:37120), which is
--       call _cafba6      ; despawn the hideout, set $0013
--       call _cb0080      ; the departure scene, called directly
-- so there is no "now go find everyone" step.  _cb0080 (:37934) gathers the
-- party on map 109, runs Banon's "We've no time to dilly-dally" speech at
-- _cb0106 (:38020) and ends `call _cafff0` (:37855), which puts EDGAR and
-- SABIN back in the party, drops LOCKE (he is off to South Figaro), loads
-- map 112 at (7,42), calls _cafdb9 to make BANON a real party member, and
-- sets $0018, the switch _cb059f requires before the raft will board anyone.
-- Banon is character 14 and the disassembly calls him WEDGE: const.inc:397
-- and :398 define WEDGE and BANON to the same 14 and the symbol picker took
-- the first, so `char_party WEDGE, 1` at :37457 is Banon joining, and
-- $185E rather than $1855 is the byte that records it.
--
-- One trigger this route deliberately does not assert against.  Map 109's
-- (25,23) trigger is _cb002b (:37880), the scrap-of-paper gag, and it opens
-- a choice prompt this script does not handle.  It sits 5 steps from
-- the escort's endpoint and the walks to SABIN pass near it, so pinning
-- every plan off it would be brittle.  It cannot fire on a walk-past,
-- and the reason is worth recording because the same fact governs
-- the whole Lete River (see gen_scenario.lua's header): _cb002b opens
-- `if_any switch $01B4=0 / switch $01B2=0 -> EventReturn`, and $01B0-$01B7
-- are not story switches.  Switch N lives at bit N&7 of $1E80+(N>>3), so
-- those eight alias the byte $1EB6, the field engine's control-flags byte,
-- rewritten every frame by UpdateCtrlFlags (field/event.asm:5415-5432) with
-- bits 0-3 = the party's facing direction one-hot and bit4 = "A is held".
-- So the gag's real condition is "A pressed while facing DOWN": it is an
-- examine action rather than a step trigger, and walking over the tile does
-- nothing.  Rather than rely on that, the generator asserts that $016B, the
-- flag _cb002b sets as soon as it fires, is still clear, which catches the
-- trigger by outcome whichever tile the navigator chose.
-- Issue #75, zero-write: every navigator here runs with opts.playBattles.
-- The hideout draws no random encounters, and that is now stated as a fact
-- rather than as a description of the map layout: maps 108, 109, 110 and 112
-- all have bit 7 clear in map_prop byte $0525, and CheckBattleSub tests
-- that bit and returns before it will roll anything
-- (ff6/src/field/battle.asm:332-333).  playBattles mode makes the battle
-- branch a property of the code path rather than an assumption: if a battle
-- did fire, it would be fought with real input rather than write-cleared.
--
-- THE MODE IS "tactical", and the choice is deliberate rather than a default.
-- The spelling used to be `true`, which is the blind branch: no menus, no
-- items, no flee, edge-tapped A and nothing else.  That branch is the one
-- that walked BANON's escort into a wipe at terra_clifftop while its log said
-- "navTo timeout" (ot6_field.lua's own comment at the branch says so), and it
-- has no business on this segment even when it can never run.  Between the
-- two real modes:
--
--   * "flee" means standing still while the formation takes free rounds
--     (M.FLEE_CAP's block comment).  From the speech to the departure TERRA
--     is the entire party -- Banon's script does `party_chars TERRA` and
--     deletes the other three -- so every free round lands on one character,
--     and she is the one this segment has been arriving poisoned.
--   * BANON is in the party for the last stretch, and his death is not a
--     wipe you retry: BattleEnd_03 is "banon died" and it goes to LoseBattle,
--     which sets the game-over flag (battle_main.asm:12300-12307, :16039).
--     There is no attempt 2 to spend here.
--
-- So the contingency wants the driver that reads the command table, uses
-- Edgar's Tools and Sabin's Blitz, and heals at 55% off its own item line.
-- The usual argument against tactical -- that it costs more frames per
-- encounter than a run -- does not apply to a segment that cannot roll one.
--
-- HP AND POISON.  Two care stops, one on arrival and one before the save.
-- This generator used to have none, on the reasoning that a hideout with no
-- encounters cannot cost the party anything, and that is exactly wrong for a
-- status: poison drains max HP/32 per step with a floor of 1
-- (ff6/src/field/player.asm:593-613), and this route walks a few hundred
-- steps across five crossings.  banon_joined shipped TERRA at 1 of 136 with
-- status 04 because the bit arrived with her from returner_hideout and
-- nothing here looked at it.  The arrival stop is the one that matters --
-- clearing the bit before the walking rather than after it -- and the exit
-- stop is what makes H.assertPartyStanding at the bottom a contract the
-- generator can meet rather than one it can only report.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/returner_hideout.mss.lua"

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
-- field object i's live tile.  Object number = the map's NPC record index +
-- 16, spawned or not (verified against gen_edgar's map-55 numbers: record 3
-- {24,16} is its obj 19).  Live coordinates matter here: the greeter walks
-- from (9,25) to (25,17) during his own escort.
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end
local function facing() return H.readByte(0x087f + H.readWord(0x0803)) end

local function where(tag)
  H.log(string.format("[%s] f%d map=%d (%d,%d) $0011=%d $0013=%d $0018=%d " ..
    "$015A=%d $015B=%d $015C=%d $0421=%d $016B=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0011), sw(0x0013),
    sw(0x0018), sw(0x015A), sw(0x015B), sw(0x015C), sw(0x0421), sw(0x016B)))
end

-- HP, status 1 and the poison cure, at both ends of the walk.  Status is on
-- the line because it is the whole reason this generator grew a care stop:
-- an HP-only roster reported banon_joined's TERRA as healthy at every point
-- of the route except the last one, where poison had already ground her to
-- 1 of 136.  ANTIDOTE is $F2 (ff6/src/text/item_name_en.json entry 242).
local ANTIDOTE = 0xF2
local function roster(tag)
  local out = {}
  for c = 0, 15 do
    if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
      local base = 0x1600 + 37 * c
      out[#out + 1] = string.format("c%d %d/%d hp status1=%02X", c,
        H.readWord(base + 9), H.readWord(base + 11), H.readByte(base + 20))
    end
  end
  H.log(string.format("[roster %s] %s | antidote=%d", tag,
    table.concat(out, "  "), H.invCountOf(ANTIDOTE)))
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

-- see gen_returner.lua and gen_kolts.lua: settles drive (a lingering dialog
-- or an encounter stalls a passive wait indefinitely) and do not require
-- player control ($087C&$0F alternates between 2 and 4 under any async object
-- script).
local function settleField(dstMap, maxF)
  return seq({
    H.waitFrames(90),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and (dstMap == nil or map() == dstMap)
    end), maxF or 12000, { playBattles = "tactical" }),
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
    H.navTo(tx, ty, { maxFrames = 20000, arrive = mapChanged(),
      playBattles = "tactical" }),
    H.release(),
    settleField(dstMap),
    H.call(function()
      H.assertEq(map(), dstMap, what .. ": landed on map " .. dstMap)
      where(what)
    end),
  })
end

-- a door-tile entrance: stage on the neighbour and hold into it, because
-- BFS cannot plan onto a tile that is a wall until CheckDoor opens it
local function crossDoorHold(sx, sy, dir, dstMap, what)
  local aPh = 0
  return seq({
    H.logStep(function()
      return string.format("cross %s: stage (%d,%d) hold %s -> map %d",
        what, sx, sy, dir, dstMap)
    end),
    H.navTo(sx, sy, { maxFrames = 20000, arrive = mapChanged(),
      playBattles = "tactical" }),
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

-- Talk to object `obj`, tracked by its live tile.  Two measured facts from
-- gen_edgar and gen_kolts shape the drive: CheckNPCs (player.asm:142)
-- activates whatever the object map holds one tile in the party's facing
-- direction while A is held, and a two-frame turn press does not set the
-- facing byte at all.  So the direction is held until $087F reads back the
-- wanted value, and only then is A edge-tapped (4 on / 4 off; activation is
-- edge-driven like dialog advance).  The approach tile is the first neighbour
-- BFS can currently reach, re-resolved lazily so it is correct inside
-- route().
local FACE = { up = 0, right = 1, down = 2, left = 3 }
local NEIGHBOURS = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
}
-- Half the hideout's NPCs move.  npc_prop.asm gives EDGAR ($041f) and the
-- guard at (44,14) ($041e) `set_npc_movement RANDOM`; LOCKE ($0420), SABIN
-- and BANON have no movement property and stand still.  A first version
-- latched the approach tile and the facing once and timed out on EDGAR:
-- staged at (52,46) for an Edgar who had already stepped off (52,47).  So
-- this uses gen_edgar's talkTo shape: the approach tile is re-resolved (at
-- most every 30 frames, since BFS is not free), the facing is computed from
-- the live delta every frame, and a soft round that loses him walks back
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
      playBattles = "tactical",
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
    -- rounds are written out flat: repeatN cannot replay navTo/driveUntil
    -- bodies, because their latched state carries over
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
    end, maxF or 25000, { playBattles = "tactical" }),
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
    roster("booted")
  end),

  -- The arrival care stop, and it is deliberately the first thing that
  -- happens.  Everything below this line is walking, and walking is what
  -- costs a poisoned character their HP; clearing the bit after the five
  -- crossings would restore the HP but not the hundreds of steps' worth
  -- already spent.  It is a no-op that only logs when nobody needs anything,
  -- so the cost on a clean predecessor is a few frames.
  H.fieldCare({ tag = "care on arrival", threshold = 0.85 }),

  -- ===================================================================== --
  -- Phase 1: in, past the greeter.  The vestibule on map 109 reaches five
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
  -- _caf745 does `player_ctrl_on` before it walks the greeter clear
  -- (event_main.asm:36393-36402; the obj_script is async), so control comes
  -- back while he is still moving and can still be standing in the
  -- corridor.  A first version asserted the path open as soon as the ride
  -- finished and failed on that; the probe saw it open only because its
  -- flood spent 600 frames before looking.  Wait for the path to open rather
  -- than for a frame count.
  H.waitUntil(function() return H.bfsPath(25, 16) ~= nil end, 3000,
    "the greeter walks clear of door C's approach", 10),
  H.call(function()
    H.log(string.format("greeter now at (%d,%d); (25,16) is %d steps away",
      objX(16), objY(16), #H.bfsPath(25, 16)))
    H.screenshot("banon_escorted")
  end),

  -- ===================================================================== --
  -- PHASE 2: THE SPEECH.  Door C is the only way to Banon's half of map
  -- 110, and it is a door tile, so it is staged rather than planned through.
  -- ===================================================================== --
  crossDoorHold(25, 16, "up", 110, "H2 map 109 -> map 110 EAST (door C)"),
  H.call(function()
    H.assertEq(sw(0x041D), 1, "$041D set -- BANON is here")
    H.assertEq(objX(16), 51, "BANON obj 16 at x=51")
    H.assertEq(objY(16), 50, "BANON obj 16 at y=50")
  end),
  talkToObj(16, "BANON (the speech)"),
  -- the speech reloads map 110 at (21,48): same map id, so $0011 is the
  -- only real arrival signal
  rideTo(function() return map() == 110 and sw(0x0011) == 1 end,
    "after the speech", 40000),
  H.call(function()
    H.assertEq(sw(0x0011), 1, "$0011 set -- the speech ran")
    H.assertEq(sw(0x041D), 0, "$041D clear -- BANON left map 110")
    H.assertEq(sw(0x041F), 1, "$041F set -- EDGAR is an NPC (east)")
    H.assertEq(sw(0x0420), 1, "$0420 set -- LOCKE is an NPC (west)")
    H.assertEq(sw(0x0416), 1, "$0416 set -- SABIN is an NPC on map 109")
    -- `load_map 110, {21,48}` is where the scene puts the party, but not
    -- where the scene leaves it: the movement after the load walks
    -- everyone into position and it settles a couple of tiles east (measured
    -- (23,48)).  So the assert is that the party is in the west room, stated
    -- the way the route depends on it: LOCKE has to be reachable from here.
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
  -- Phase 3: the three friends.  $015A/$015B/$015C, the lock on _cafa67.
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
  -- Phase 4: the greeter unlocks Banon.  With all three set, _caf68a's
  -- $0011 branch reaches _cafa67, which sets $0421 and puts Banon back on
  -- map 108.  Missing any of the three would take _caf962 instead, which is
  -- one line of dialog and sets no switch, and the route would stall with
  -- nothing to show for it, so $0421 is the assert that matters.
  -- Note that the greeter is back on his spawn tile (9,25): every map load
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
  -- Phase 5: the decision.  Out to 108 and answer Yes (option 0).  The Yes
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
  end, 50000, { playBattles = "tactical" }),
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
    roster("before the exit care stop")
    H.screenshot("banon_joined")
  end),

  -- The exit care stop.  The departure scene has just put EDGAR, SABIN and
  -- BANON back in the party, so this is the first moment all four records
  -- are visible to a care stop, and anything the walk cost -- or any status
  -- the three of them were carrying while the story had them out of the
  -- party -- is repairable here and nowhere later.
  H.fieldCare({ tag = "care before the raft", threshold = 0.85 }),
  H.call(function()
    roster("banon_joined exit")
    -- The exit contract: nobody dead, petrified, zombie, poisoned, or at or
    -- below max HP / 8 (H.assertPartyStanding, the same conditions
    -- tools/audit_party_hp.py applies tree-wide).  This generator had none,
    -- which is why banon_joined shipped TERRA poisoned at 1 of 136 and the
    -- audit was the thing that found it, two steps and a `make savestates`
    -- later.  Failing here instead means the fixture is never written.
    H.assertPartyStanding("banon_joined exit")
  end),
  H.saveState("banon_joined.mss"),
  H.logStep(function()
    return string.format("banon_joined generated at frame %d", H.frame)
  end),
})
