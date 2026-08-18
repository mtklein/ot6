-- gen_kolts.lua -- from figaro_cleared.mss (TERRA + LOCKE + EDGAR on a
-- chocobo in the Figaro desert) to the Vargas entry point on Mt. Kolts.  The
-- last step of tier 2's route work; everything after this is the fight.
-- Generates three states:
--   south_figaro.mss    map 75 (1,28), the town's west gate (a fixture the
--                       v0.3 Locke scenario will want)
--   kolts_entry.mss  map 95 (14,35), the mountain's entrance map
--   vargas_entry.mss map 98, party tile-aligned next to VARGAS with his
--                       approach event already run, one interaction short
--                       of `battle 66`
--
-- Three things this script had to measure or derive.  The entrance tables
-- give the door graph and nothing else, and in all three of these the graph
-- alone is not enough to reach the destination.
--
-- 1. The party arrives on a chocobo, and the world navigator cannot read its
--    position.  figaro_cleared is generated riding one (the submerge scene's
--    `vehicle ... CHOCOBO`, event_main.asm:14330-14405).  The world module
--    then boots through InitChoco (world/init.asm:402) instead of InitWorld,
--    and InitChoco never writes $E0/$E2; only InitWorld does, from $1F60
--    (init.asm:758-762).  So H.worldX/worldY read 0 from that state and
--    worldNavTo has nothing to plan from; a route that trusts them walks
--    the party off tile (0,0).  (gen_edgar asserts the zeros when it
--    generates its state, so a change here would fail there.)  The dismount
--    button is B, and the dismount itself is a state machine, verified frame
--    by frame in probe_dismount.lua:
--      * riding, input goes through GetChocoInput (world/ctrl.asm:451),
--        whose last branch (:562-563) is `lda $05 / bit #$0080 / jsr
--        LandAirship`.  $05 is the held-button low byte (bit7 = B) rather
--        than an edge, so a plain hold is enough.
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
-- 2. The Figaro desert does not reach South Figaro on foot.  This is a
--    property of the map data, not of the passability model:
--    the live tilemap at $7F0000 is byte-identical to world_1_tilemap.dat
--    (ModifyMap has changed nothing yet), and flood-filling it with the
--    engine's own rule (destination property bit4 clear, `bit #$0010 /
--    branch if tile is impassable on foot`, GetPlayerInput move.asm:1013,
--    1042, and the two below them) gives the party a 1165-tile region
--    bounded at y<=95.  South Figaro (86,111) and Mt. Kolts (102,100) sit
--    in a different 422-tile region.  Narshe (84,33) is in the party's
--    region; those two are not.  A first pass planned the world step
--    straight there and got "worldBfs: no path", which is correct.
--    The link is the cave the castle's own NPC names ("To the south
--    there's a cave that leads to South Figaro", event_main.asm:15156),
--    and it is three field maps rather than a road:
--      world (73,93) -> map 71 (10,54)          [short entrance]
--      map 71 (10,48)/(11,48) -> EVENT _ca5ef7  [event_trigger.asm _71]
--        which is `if_switch $001A=1 -> load_map 70` else `load_map 73,
--        {47,39}` (event_main.asm:14218-14224).  70 and 73 are two copies of
--        the same cave and carry identical entrance coordinates, so the
--        route below is written once and works on either
--      map 73 (41,14) -> map 72 (4,5)           [short entrance]
--      map 72 (16,43) -> world (75,103)         [short entrance]
--    Only maps 69/72 and Mt. Kolts itself have exits landing in the south
--    region (checked by walking every record in short_entrance.dat), so
--    this cave is the only way through.
--
-- 2b. The cave mouth is guarded by NPCs, which no
--    entrance or trigger table mentions.  Map 71's lobby has exactly one
--    way north, the two floor tiles (10,49)/(11,49) (prop $02/$8F, ordinary
--    floor, all four exits) below the trigger pair, and two Figaro guards
--    stand on them: NPCProp::_71's third and fourth records, both spawn
--    switch $0312 (npc_prop.asm:3064-3076).  The party's object map
--    ($7E2000, bit7 set = tile free) reads occupied there, H.canStep
--    refuses the step, and BFS reports "no path (10,54)->(11,48)", which
--    is what the first run did.  The model is not being conservative here:
--    holding UP at (10,50) for 600 frames moved the party zero tiles
--    (measured).
--    The guards leave when talked to.  The one at (10,49) runs _ca75ee
--    (event_main.asm:17853), gated `if_switch $0108=0 -> _ca7668`, and
--    _ca7668 is the "It's closed now due to construction" brush-off
--    (:17936-17939), so $0108 decides whether the cave is open, and it is
--    asserted below.  With it set, EDGAR gets recognised
--    ("Through the cave, and eastward to South Figaro", :17882), NPC_3
--    jumps clear and hides, NPC_4 rides off on its chocobo, and the scene
--    ends `switch $0312=0` (:17933), despawning both guards permanently.
--    So the lobby is: walk under the guard, face UP, talk, then walk
--    through the tile he was standing on.
--
-- 3. Two more world-exit rows to stay off, the same hazard map 55's y=43
--    was for gen_edgar: BFS knows nothing about entrance triggers, so a
--    step planned across one silently leaves the map.
--      * map 75 (South Figaro): long entrances (0,0) len $AF and (56,0)
--        len $AF are vertical (the length byte's bit7 selects vertical,
--        entrance.asm CheckLongEntrance:66): columns x=0 and x=56, y=0..47
--        -> world (84,112)/(87,112); plus horizontal y=1 -> (85,111).  The
--        party enters at (1,28), one tile from the x=0 column, so the
--        generation happens on arrival and the exit is a single deliberate
--        press.
--      * map 95 (Mt. Kolts entrance): long entrance (0,37) len $1B is
--        horizontal: row y=37, x=0..27 -> world (102,101).  The party
--        enters at (14,35), two rows above it, and every step on this map
--        is asserted to stay off y=37 before it is walked.
--
-- Encounter policy (issue #75, the input-driven test conversion).  There are
-- no state writes on this route: the battle-clear write is gone, and
-- every encounter is answered by the pad.  Which answer is used varies by
-- region, and each is measured:
--
--   * the cave, the town and the world steps run, playBattles="flee",
--     using L+R, the engine's own mechanic.  They are cheap; the cave cost
--     the party ten hit points end to end.
--   * Mt. Kolts and map 98 are fought, playBattles="tactical", using the real
--     command menus, EDGAR's Tools, boosted Fights, and the fight driver's
--     own Potion medic line.  The first input-driven version of this route
--     fled the mountain too.  Fleeing costs hit points, because the party
--     stands still while the formation takes free rounds.  Measured
--     2026-08-09, three runs: fled, the party reached VARGAS with TERRA dead
--     and EDGAR on 1 hp, and lost the fight four times; fled with a healing
--     layer, it reached him with LOCKE dead on the final fifty-three steps;
--     fought, everyone arrived alive and two levels up.  A player crossing
--     Mt. Kolts kills Triliums, which is where the levels for VARGAS come
--     from, so the fought version is both the input-driven one and the one
--     that works.
--
-- A formation that will not release the party inside M.FLEE_CAP frames is
-- fought out by the same tactical driver.  The cap exists because a
-- 90-second hold wiped a full-health party here once.
--
-- The care layer that goes with it is below: every crossing ends with a check
-- of the party's hit points, and the route stops at the shop in South Figaro.
local H = dofile("tools/tests/lib/ot6.lua")
local CLEARED = "build/states/figaro_cleared.mss.lua"

-- map compares stay masked: loaders leave flag bits in $1F64's high byte
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
-- event switch id -> live bit (event bitfield base $1E80, bit = id & 7)
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
-- field object i's live tile (pixel coords >> 4, block stride $29)
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end

-- field inventory: ids at $1869+i, counts at $1969+i (256 slots)
local function invCount(id)
  for i = 0, 255 do
    if H.readByte(0x1869 + i) == id then return H.readByte(0x1969 + i) end
  end
  return 0
end
local function gil()
  return H.readByte(0x1860) + (H.readByte(0x1861) << 8)
       + (H.readByte(0x1862) << 16)
end

-- Roster line, printed by every `where` so the damage profile of the route
-- is legible step by step rather than only at generation time.  The risk on
-- this route is arriving at VARGAS with a party that cannot fight: the
-- input-driven 2026-08-06 chain reached his ledge with TERRA dead and EDGAR
-- on 1 hp, and lost four straight attempts (issue #75).  Who is hurt and
-- where it happened is the measurement this generator needs to emit.
-- $1600 + 37*c: +8 level, +9/+11 cur/max hp, +13/+15 cur/max mp; a character
-- is in the party when $1850+c has a low nibble bit set.
local function rosterLine()
  local out = {}
  for c = 0, 15 do
    if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
      local b = 0x1600 + 37 * c
      out[#out + 1] = string.format("c%d L%d %d/%d hp %d/%d mp", c,
        H.readByte(b + 8), H.readWord(b + 9), H.readWord(b + 11),
        H.readWord(b + 13), H.readWord(b + 15))
    end
  end
  return string.format("%s | gil=%d tonic=%d potion=%d fenix=%d",
    table.concat(out, " | "), gil(),
    invCount(0xE8), invCount(0xE9), invCount(0xF0))
end

local function where(tag)
  H.log(string.format("[%s] f%d map=%d field=(%d,%d) world=(%d,%d) " ..
    "$11FA=%02X $010A=%d bright=%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), H.worldX(), H.worldY(),
    H.readByte(0x11fa), sw(0x010A), bright()))
  H.log(string.format("[%s] %s", tag, rosterLine()))
end

-- The care layer (issue #75, 2026-08-09).  Running from encounters costs hit
-- points, because the party takes a round or two every time the run roll
-- fails, and this route used to walk the whole mountain without ever opening
-- the item menu.  Measured: TERRA left the cave at 84/94, reached the
-- mountain at 65/94, arrived on map 98 at 39/94 and was dead by the entry
-- point, with EDGAR on 1/145 beside her, while seven Potions and five Tonics
-- sat unused in the bag; the four input-driven VARGAS attempts that followed
-- all wiped.  So every crossing now ends the way a player's would: check the
-- party, and if anyone is meaningfully hurt, heal them through the real
-- Item windows (H.fieldCare writes no state, and does not open the menu when
-- nobody needs it).
--
-- The Potion reserve is the other half of the contract: gen_vargas's medic
-- line spends Potions inside the fight, so the walk may only spend down to
-- three of them and uses Tonics for small holes.
--
-- mpFloor is the third.  Casting stays on; what changes is how much of the
-- caster's pool this segment is allowed to spend, because a quarter-of-max
-- floor is an idle-corridor number and this corridor ends at a boss.
--
-- The argument for casting is in H.fieldCare's header and it is sound: OT6
-- refills HP and MP on level up (ot6_progression.asm:3-6), so MP spent in a
-- corridor is refunded and a Tonic drunk in one is gone.  The clause it
-- assumes is a level up between the spending and the next fight.  Nothing
-- levels up between the last care stop on this mountain and battle 66, and
-- TERRA is the only member of this party who knows Cure -- LOCKE's and
-- EDGAR's pools pay for their own abilities, since in OT6 every ability
-- costs MP -- so on this segment her pool is not a renewable healing budget
-- at all.  It is the boss's healing, being spent early.
--
-- What the fight needs, measured.  gen_vargas's medic spends TERRA from her
-- entry MP down to 6 in every winning run on record, so the fight consumes
-- whatever she brings.  Read straight out of five worktrees' vargas_entry.mss
-- on 2026-08-11, with the battle 66 result each one led to:
--     wt/multihit, wt/bpwindow  46/46 mp   won
--     wt/ladder, wt/restage     31/46 mp   won
--     an earlier chain on the v0.10 tip  26/46 mp   LOST -- VARGAS left at
--         11065 of 11600, short of even his first script gate, TERRA out of
--         MP by frame 13283 (wt/restage's own failed run of that step)
--     wt/healpolicy             21/46 mp   not run
-- So the fight's threshold sits between 26 and 31, and the entry contract
-- below asks for two thirds of her maximum (31 of 46) on that basis.
--
-- The floor is set above the contract, not equal to it, so a normal run has
-- headroom and the contract only fires when something has actually changed:
-- 0.75 of her maximum is 34, and fieldCare stops casting when a cast would
-- break the floor, so she arrives between 34 and 38.  That still buys this
-- climb two or three Cures, which is where the item saving comes from; what
-- it does not buy is the eight or nine casts a quarter-floor allowed.
local POTION = 0xE9
local function care(tag, threshold)
  return H.fieldCare({ tag = "care " .. tag, threshold = threshold or 0.85,
                       reserve = { [POTION] = 5 }, mpFloor = 0.75 })
end

-- crossDoor/seq: a bare step list cannot be spliced into a step list (Lua
-- truncates a non-final table.unpack to one value, silently dropping every
-- step but the first).  H.cond with an always-true predicate is the
-- library's public way to wrap a list into a single step object.
local function seq(steps) return H.cond(function() return true end, steps) end

-- An `arrive` predicate that fires when the map id changes from whatever it
-- read the first time it was called.  Latching lazily (rather than at
-- script-build time) is what makes it correct inside route(), whose steps are
-- all constructed before any of them runs.
local function mapChanged()
  local m0
  return function()
    if m0 == nil then m0 = map() end
    return map() ~= m0
  end
end

-- Settle after a map load: control + alignment + a fully lit screen, held
-- for 20 consecutive frames, then the 30-frame margin every field fixture
-- uses.  Both halves are needed:
--   * brightness is checked because a cutscene can report control on a black
--     screen (gen_edgar's header documents the 5700-frame-early generation
--     that caused), so control and a lit screen have to hold at the same
--     time;
--   * and they have to hold for a stretch of frames.  A first cut checked
--     each gate once with separate waitUntils and both passed immediately on
--     the far side of an entrance, because the field module still had the old
--     map's control byte and the fade had not begun.  The crossing settled
--     mid-load and the next BFS ran against a half-written map.  (Measured:
--     settle satisfied after 0 + 0 frames, then brightness read 0 thirty
--     frames later.)  A consecutive-frame counter is not satisfied by a
--     transient.
local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

-- The settle drives rather than waits.  Mt. Kolts and the cave have
-- encounters, and an encounter that rolls on the arrival tile stalls a
-- passive waitUntil indefinitely: the battle holds control, the counter never
-- climbs, and nothing is pressing the pad (measured: map 96's arrival, 3600
-- frames, timeout).  advanceStory write-clears whatever came up and edge-taps
-- through the victory text, and on a quiet field it holds the pad empty, so
-- it is the safer settle.
-- The crossing settle does not wait for player control.  Mt. Kolts's caves
-- each open with a view of the figure on the peak: map 96's (16,22) and
-- (14,12) triggers and map 97's (34,24) run `obj_script NPC_1, ASYNC`
-- (_ca820f/_ca8252/_ca8230, event_main.asm:19739/19781/19757).  While an
-- async object script is live the event engine takes the party's
-- movement-type byte ($087C&$0F) from 2 to 4 for a frame at a time.
-- H.hasControl() reads that byte, so it flickers: measured on map 96, two
-- good frames then a bad one, repeating, and a 20-consecutive-frame control
-- gate sat at cnt=1..2 for 12000 frames while every other term (brightness
-- 15, aligned, right map, no battle) held steady the whole time.
-- So the settle checks that the load landed and the screen is up, and leaves
-- "can I step this frame" to navTo, which already debounces control and
-- re-plans.  The three states generated below still assert real control at
-- the moment they save.
local function settleField(what, dstMap, maxF, mode)
  return seq({
    H.waitFrames(90),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and (dstMap == nil or map() == dstMap)
    end), maxF or 24000, { playBattles = mode or "flee" }),
    H.waitFrames(30),
  })
end

local function settleWorld(what, maxF)
  return seq({
    H.advanceStory(settled(20, function()
      return H.worldHasControl() and H.worldAligned()
    end), maxF or 12000, { playBattles = "flee" }),
    H.waitFrames(30),
  })
end

-- Walk to (tx,ty) on the current field map, expecting the map to change on
-- arrival (an entrance record fires when the party stands on its source
-- tile, entrance.asm CheckShortEntrance).  Mt. Kolts and the cave use plain
-- walkable floor for their entrances, unlike Figaro's castle doors, which are
-- walls until CheckDoor, so BFS can route straight onto them and the crossing
-- is one navTo rather than a staging tile plus a hold.  The map id is
-- asserted afterwards, so a missed crossing cannot pass for one.
local function crossTo(tx, ty, dstMap, what, mode, maxF)
  return seq({
    H.logStep(function()
      return string.format("cross %s: (%d,%d) -> (%d,%d) -> map %d [%s]",
        what, H.fieldX(), H.fieldY(), tx, ty, dstMap, mode or "flee")
    end),
    H.navTo(tx, ty, { maxFrames = maxF or 40000, arrive = mapChanged(),
             playBattles = mode or "flee", reserve = { [POTION] = 5 } }),
    H.release(),
    settleField(what, dstMap, nil, mode),
    H.call(function()
      H.assertEq(map(), dstMap, what .. ": landed on map " .. dstMap)
      where(what)
    end),
    care(what),
  })
end

-- Stand on (sx,sy), turn to face `dir`, and edge-tap A until the event
-- engages (an event script or a dialog is up).  Running the scene out is the
-- caller's advanceStory, not this.  A first cut drove until the scene's
-- closing switch instead and hung: once the event takes control, this loop's
-- own "no control -> hands off the pad" rule stops tapping, so the multi-page
-- dlg $00AC never advanced and the switch never came.
-- Two measured facts from gen_edgar's header shape the rest.  NPC activation
-- is decided by the party facing byte ($087F through the $0803 party-object
-- offset; 0 up 1 right 2 down 3 left, player.asm:456-505) and a two-frame
-- turn press does not set it, so the direction is held until the byte reads
-- back.  Activation is edge-driven like dialogs, so A is tapped 4 on / 4 off
-- rather than held.  (Measured here: from (10,50) already facing up, four
-- frames of tapping engage the guard.)
local FACE = { up = 0, right = 1, down = 2, left = 3 }
local function talkAt(sx, sy, dir, what, maxF)
  local aPh, started = 0, 0
  return seq({
    H.navTo(sx, sy, { maxFrames = 20000, playBattles = "flee" }),
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

-- Cross an entrance whose destination is the same map.  Map 72 is built out
-- of four of them, so `map changed` is no signal there.  Arrival is the
-- destination tile instead.
local function warpTo(sx, sy, dx, dy, what, maxF)
  return seq({
    H.logStep(function()
      return string.format("warp %s: (%d,%d) -> (%d,%d) -> (%d,%d)",
        what, H.fieldX(), H.fieldY(), sx, sy, dx, dy)
    end),
    H.navTo(sx, sy, { maxFrames = maxF or 20000, playBattles = "flee",
                      arrive = function()
      return H.fieldX() == dx and H.fieldY() == dy
    end }),
    H.release(),
    settleField(what, 72),
    H.call(function()
      H.assertEq(H.fieldX(), dx, what .. ": landed at x=" .. dx)
      H.assertEq(H.fieldY(), dy, what .. ": landed at y=" .. dy)
      where(what)
    end),
    care(what),
  })
end

-- Assert the BFS plan to (tx,ty) exists and never touches row `badY`, the
-- map's world-exit row.  BFS models passability, not entrance triggers, so
-- this check is what keeps a shortest path from walking out of the mountain.
local function planAvoidsRow(tx, ty, badY, what)
  -- Poll before asserting (the gen_terra_clifftop fix, 2026-08-18): a
  -- transient NPC in a corridor fails a single-sample BFS pre-check.
  return H.cond(function() return true end, {
    H.waitUntil(function() return H.bfsPath(tx, ty) ~= nil end,
                900, what .. ": a path exists (45f poll)", 45),
    H.call(function()
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
  end),
  })
end

-- ------------------------------------------------------------- the shop --
-- Menu states (src/menu/shop.asm, and gen_edgar's already-proven drive of
-- them): $25 options, $26 buy list, $27 quantity, $28 post-buy wait -> $26.
-- The list row is $4B; row r's item id is $7E9D89+r.  The quantity widget
-- is zSelIndex, DP $28 -- RIGHT +1, LEFT -1, UP +10, DOWN -10, gil-clamped
-- by the handler.  Both cells are read and steered toward a target, never
-- press-counted: menu auto-repeat overshoots (gen_sabin_train bought 25
-- Tonics on a counted hold that asked for 14).
--
-- The five map-75 short entrances a BFS would route through.  Four of them
-- are far from this walk.  (8..10,32) is sixteen steps from the spawn, in the
-- quadrant the shop walk crosses.
local M75_AVOID = {
  { 8, 32 }, { 9, 32 }, { 10, 32 },        -- -> map 80
  { 18, 55 }, { 19, 55 }, { 20, 55 },      -- -> map 91
  { 48, 37 }, { 34, 35 }, { 22, 14 },
}

local function mstate() return H.readByte(0x0026) end
local function shopRow() return H.readByte(0x004b) end
local function shopQty() return H.readByte(0x0028) end
local function rowItem(r) return H.readByte(0x9d89 + r) end
local function inState(v) return function() return mstate() == v end end

local function tapUntil(btn, pred, what, maxF)
  return H.driveUntil(pred, maxF or 1800, {
    H.call(function() H.setPad((H.frame % 10 < 4) and { btn } or {}) end),
  }, what)
end

-- Walk off the current map by holding each direction in turn until the map
-- id changes.  This is not H.stepOff, whose battle branch still sets the kill
-- bit; nothing on this route may write game state (issue #75), and maps 75/85
-- have no encounters for it to answer.
local function leaveTo(dstMap, dirs, what, maxF)
  local n = 0
  return seq({
    H.driveUntil(function() return map() == dstMap end, maxF or 3000, {
      H.call(function()
        n = n + 1
        H.setPad({ [dirs[((n // 40) % #dirs) + 1]] = true })
      end),
    }, what),
    H.release(),
  })
end

-- Buy up to `target` of item `id`, sitting on buy-list row `row`.  Every step
-- is checked: the row is verified to hold the expected item before any money
-- moves, the quantity is steered to the number we want and read back, and the
-- purchase is confirmed by gil falling by quantity x price.  With too little
-- gil it buys what it can and logs the count.
local function buyTo(id, row, target, unit, name)
  local want, before = 0, 0
  return seq({
    H.driveUntil(function() return shopRow() == row end, 3000, {
      H.call(function()
        local cur = shopRow()
        H.setPad((H.frame % 10 < 4)
          and { [cur < row and "down" or "up"] = true } or {})
      end),
    }, "shop: cursor -> row " .. row),
    H.release(), H.waitFrames(20),
    H.call(function()
      H.assertEq(rowItem(row), id,
        string.format("shop row %d really is item $%02X", row, id))
      before = gil()
      want = target - invCount(id)
      local afford = before // unit
      if want > afford then want = afford end
      H.log(string.format("[shop] %s: have %d, buying %d at %d gp (gil %d)",
        name, invCount(id), want, unit, before))
    end),
    H.cond(function() return want >= 1 end, {
      tapUntil("a", inState(0x27), "shop: quantity window"),
      H.driveUntil(function() return shopQty() == want end, 3000, {
        H.call(function()
          local q = shopQty()
          local btn = (q < want) and ((want - q >= 10) and "up" or "right")
                                 or ((q - want >= 10) and "down" or "left")
          H.setPad((H.frame % 8 < 3) and { [btn] = true } or {})
        end),
      }, "shop: quantity steered to the wanted count"),
      H.release(), H.waitFrames(20),
      tapUntil("a", function() return gil() < before end,
        "shop: purchase goes through"),
      H.release(),
      H.waitUntil(inState(0x26), 2400, "shop: back to the buy list", 2),
      H.call(function()
        H.assertEq(before - gil(), want * unit,
          string.format("%s cost %d x %d gp", name, want, unit))
      end),
    }, {}),
  })
end

local function shopTrip()
  return seq({
    H.logStep(function()
      return string.format("[shop] heading in: gil=%d tonic=%d potion=%d " ..
        "fenix=%d", gil(), invCount(0xE8), invCount(0xE9), invCount(0xF0))
    end),
    H.navTo(44, 32, { maxFrames = 30000, playBattles = "flee", avoid = M75_AVOID }),
    H.release(), H.waitFrames(20),
    H.call(function()
      H.assertEq(H.fieldX(), 44, "on the shop's door mat, x=44")
      H.assertEq(H.fieldY(), 32, "on the shop's door mat, y=32")
    end),
    -- (44,30) is a bump door: a wall until CheckDoor runs, so this is a
    -- held press, never a navTo whose goal it is
    H.driveUntil(function() return map() == 85 end, 1200, {
      H.hold({ "up" }), H.waitFrames(8),
    }, "into the item shop (the bump door at (44,30))"),
    H.release(),
    settleField("item shop", 85),
    H.call(function()
      H.assertEq(map(), 85, "inside the item shop, map 85")
      where("item shop")
    end),
    H.navTo(106, 54, { maxFrames = 20000, playBattles = "flee" }),
    H.release(), H.waitFrames(20),
    -- Counter talk: the merchant is at (106,52) with the counter tile
    -- (106,53) between him and the party, and CheckNPCs reaches through it
    -- (player.asm:188-200).  UP is held until the facing byte reads back,
    -- because a two-frame turn press does not set it, and (106,53) is
    -- impassable, so the hold cannot walk anyone into the counter.
    H.driveUntil(inState(0x25), 6000, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        if H.fieldX() ~= 106 or H.fieldY() ~= 54 then H.setPad({}); return end
        if H.readByte(0x087f + H.readWord(0x0803)) ~= FACE.up then
          H.setPad({ up = true }); return
        end
        H.setPad((H.frame % 8 < 4) and { "a" } or {})
      end),
    }, "open the item shop (counter talk -> shop_menu 8)"),
    H.release(),
    H.call(function() H.screenshot("sfigaro_shop") end),
    tapUntil("a", inState(0x26), "shop: the buy list opens"),
    H.release(), H.waitFrames(20),
    H.call(function()
      local rows = {}
      for r = 0, 7 do rows[#rows + 1] = string.format("%02X", rowItem(r)) end
      H.log("[shop] stock: " .. table.concat(rows, " "))
    end),
    -- Five Fenix Downs, not three.  Measured 2026-08-09: with three, the
    -- mountain's own fights spent every one of them before the summit and the
    -- party stood on VARGAS's ledge with no way to answer a death, and
    -- gen_vargas needs one after the fight to raise TERRA.  The gil is
    -- available, and the mountain returns more than that on the way up.
    -- The mix is measured.  A death costs a Fenix Down (500 gil); not dying
    -- costs a Tonic (50).  The first pass bought three revives and spent all
    -- three; the second bought five and spent all five, every one of them on
    -- map 98.  So most of the gil goes on Tonics and the driver heals earlier
    -- (M.setRows' sibling change: playBattles="tactical" now heals at 55%,
    -- not 35%), with five revives as the minimum because gen_vargas needs one
    -- after the fight to raise TERRA and the entry-point contract below
    -- refuses to generate without it.
    buyTo(0xF0, 5, 5, 500, "FENIX DOWN to 5"),
    -- Three Antidotes, and this shop is the only reason the route can answer
    -- poison at all.  Measured here 2026-08-12: the map-98 approach fight
    -- put status 04 on TERRA, the care stop before VARGAS cast her back to
    -- 136/136 and left the bit standing, and it rode her through gen_vargas
    -- and gen_returner into the hideout, where poison drains max HP/32 on
    -- every step with a floor of 1 (ff6/src/field/player.asm:593-613).  Five
    -- crossings later banon_joined shipped her at 1 of 136, and lete_river
    -- and the whole Lete River inherited it.
    --
    -- This counter is the last one before the damage: the route from here is
    -- the world map, Mt. Kolts, VARGAS, the world map again and the Returner
    -- Hideout, and there is no shop anywhere on it.  Eight of the 128 shop
    -- records stock $F2, but which towns they belong to is not established
    -- here -- event_main.asm is a dump of separately-addressed scripts and
    -- adjacency in it means nothing -- so the claim is only the one the
    -- route makes: nothing between this counter and the hideout sells an
    -- Antidote.  No owned esper grants a status cure either (genju_prop.asm),
    -- so a party that walks out of here without one carries the bit until
    -- the next town that has them.
    --
    -- Row 1: shop 8's stock is Tonic, Antidote, Soft, Eyedrop, $FB, Fenix
    -- Down, Sleeping Bag, Tent (menu/shop_prop.dat record 8), and buyTo
    -- checks the row really holds $F2 before any money moves.
    --
    -- Three at 50 gil each is 150, against 2500 on the Fenix Downs above, so
    -- this is not a real claim on the purse -- but it is placed before the
    -- Tonics deliberately, because the Tonic line is the marginal one that
    -- clamps to whatever gil is left, and a poisoned character loses every
    -- point of HP a Tonic would have bought them.  Three rather than one
    -- because the mountain can poison more than once and the count has to
    -- survive gen_vargas, gen_returner and gen_banon's own care stops.
    buyTo(0xF2, 1, 3, 50, "ANTIDOTE to 3"),
    -- This is also the common party's last provision stop before the
    -- scenario split.  Two Softs answer Petrify on the long branches; the
    -- need was measured on the Phantom Train, where a forced corridor fight
    -- petrified SHADOW before a clean boss win.  Soft is row 2 and costs 200
    -- gil.  The first measured run bought two and spent both before even
    -- reaching Mt. Kolts when the party had no immunity.  The relic stop
    -- below now gives all three Jewel Rings, so these two are recovery for
    -- an exceptional hit rather than the primary defense.  Buy them before
    -- the marginal Tonic line so the party keeps an answer instead of more
    -- 50-HP heals.
    buyTo(0xF4, 2, 2, 200, "SOFT to 2"),
    buyTo(0xE8, 0, 25, 50, "TONIC to 25"),
    tapUntil("b", inState(0x25), "shop: back to the options window"),
    tapUntil("b", function() return H.hasControl() and map() == 85 end,
      "shop: closed"),
    H.release(), H.waitFrames(30),
    H.call(function()
      H.log(string.format(
        "[shop] done: gil=%d tonic=%d potion=%d fenix=%d antidote=%d",
        gil(), invCount(0xE8), invCount(0xE9), invCount(0xF0),
        invCount(0xF2)))
      H.assertEq(invCount(0xF0) >= 3, true,
        "the party leaves with Fenix Downs -- a death is answerable now")
      H.assertEq(invCount(0xE8) >= 10, true, "Tonics restocked for the climb")
      H.assertEq(invCount(0xF2) >= 2, true,
        "the party leaves with Antidotes -- poison is answerable now, and " ..
        "there is no other counter between here and the Returner Hideout")
      H.assertEq(invCount(0xF4) >= 2, true,
        "the party leaves with two Softs -- Petrify recovery backs up the " ..
        "route, not merely the next encounter")
    end),
    H.navTo(104, 57, { maxFrames = 20000, playBattles = "flee" }),
    H.release(), H.waitFrames(20),
    leaveTo(75, { "down", "left", "right", "up" }, "out of the item shop"),
    settleField("back in town", 75),
    H.call(function()
      H.assertEq(map(), 75, "back on map 75 with the shopping done")
      where("shop done")
    end),
  })
end

-- ================================================================ the stop --
-- Everything below is the South Figaro stop as a player would take it:
-- fight the ground outside the gate for a while, then spend what that paid
-- on the four shops and a night at the inn.  It was written and driven in
-- probe_sfiggrind.lua and probe_sfigshops.lua first, because this file's own
-- run is minutes long and a mis-derived coordinate here costs all of them.
--
-- Why the stop is here at all: `docs/design/wob-route.md` §2 -- the route
-- plays casual -- and LOCKE's level, which is fixed from `banon_joined`
-- onward because he leaves the party there.  Mt Kolts through the Returner
-- Hideout is the only window in which it can still move, and the world map
-- outside this town is the earliest encounter-bearing ground in it.

-- ------------------------------------------------------------ the grind --
-- The corridor, derived from world_1_tilemap.dat + WorldTileProp and then
-- walked in probe_sfiggrind.lua:
--   * the southern walkable region is 422 tiles (the same figure this
--     file's header records for the cave crossing), 371 of them battle-bg 0
--     and 51 bg 3.  Sector (86,111) is `WorldBattleRate[26] = $00`, so every
--     tile in it draws at the normal rate; bg 0 selects
--     `WorldBattleGroup[104] = 3` -- GreaseMonk / Rhodox / Rhinotaur, an
--     expected 358 xp and 720 gil a fight once OT6's `Ot6RewardMulW = $0020`
--     doubling is applied (ot6_break.asm:693-696).
--   * the per-step danger increment is HALVED by the same pair of knobs
--     (`Ot6DangerMulW = $0008`), so the world's vanilla $00C0 becomes $0060
--     and a fight is expected about every 37 steps.
--   * leaving town by the x=0 column lands at world (84,112), and (85,112)
--     and (86,112) are two of South Figaro's own four entrance tiles.  A
--     plan straight east from there walks onto them and back into the town:
--     the 23-step shortest path (84,112) -> (100,105) has both on it.  So
--     the first hop is NORTH to (84,108), and worldNavTo has no `avoid`
--     option to fix it with afterwards.
--   * the lap is (100,105) <-> (87,105), 13 steps each way on row 105, with
--     no world entrance or event trigger on it.  The whole grind stays on
--     the world map, because the danger counter is zeroed by every battle
--     and every map load, so a lap that ducks into town throws away
--     whatever it had accumulated.
--
-- Measured 2026-08-12, 16 laps from `south_figaro`, ~31000 frames:
-- gil 3974 -> 12782, TERRA L5 -> L8, LOCKE L6 -> L8 (814 -> 2036 xp),
-- EDGAR L7 -> L9, nobody below half hp at any lap boundary.  So a lap is
-- worth roughly 550 gil and 75 LOCKE experience.
local LOCKE = 1
local function expOf(c)
  local b = 0x1600 + 37 * c + 0x11        -- 3 bytes
  return H.readByte(b) + (H.readByte(b + 1) << 8) + (H.readByte(b + 2) << 16)
end
local function levelOf(c) return H.readByte(0x1600 + 37 * c + 8) end

-- The target is LOCKE's TOTAL experience at the end of the grind, not a
-- level, because the level he reaches his own scenario with is this number
-- plus whatever Mt Kolts, VARGAS and the hideout add: measured at +943 on
-- the chain of 2026-08-12 (814 at south_figaro, 1757 at banon_joined).
-- Level 10 is 2976 total and level 11 is 3936 (8 * sum(LevelUpExp[2..L]),
-- CalcLevelExpTotal, ff6/src/menu/status.asm:580-605), so 2250 here lands
-- him at level 10 with about 220 to spare -- two levels above the 8 he has
-- had for every measurement of the gate soldier so far, and the "a level up
-- or two" the owner asked for rather than an open-ended grind.
local EXP_TARGET = 2250
-- The gil floor is the other half of the grind's contract, added 2026-08-17.
-- The grind used to stop on the experience target alone, and the town's
-- whole shopping list leaned on the gil that many laps happened to pay:
-- gearTrip is 1800, the item top-up runs to about 1300, the relic counter
-- is 4500 and the inn is 80, about 7680 end to end.  When the upstream
-- chain started delivering LOCKE with more experience (the Narshe mines
-- chest pickups, #84, plus the progression rework), the same target was met
-- in 14 laps instead of 16 and the route reached the relic counter 534 gil
-- short: measured 2026-08-17, grind end at 7146 gil, Star Pendants bought,
-- and only two of the three Jewel Rings affordable -- the exact-count
-- contract below the relic buys caught it.  So the grind now runs until
-- BOTH targets hold.  8000 covers the measured 7680 with margin for the
-- item top-up's variable Tonic line; at the measured 400-800 gil a lap the
-- floor costs one or two extra laps, whose experience (about 115 a lap)
-- stays well inside the level-11 boundary the EXP_TARGET comment derives.
local GIL_TARGET = 8300   -- +250: the second Plumed Hat (#84 wave)
local grindLaps = 0
local function grindDone()
  return expOf(LOCKE) >= EXP_TARGET and gil() >= GIL_TARGET
end
local function lap(n)
  return H.cond(function() return not grindDone() end, {
    H.logStep(function()
      return string.format("grind lap %d: LOCKE L%d xp=%d/%d gil=%d f%d", n,
        levelOf(LOCKE), expOf(LOCKE), EXP_TARGET, gil(), H.frame)
    end),
    H.worldNavTo(100, 105, { maxFrames = 40000, playBattles = "tactical",
                             reserve = { [POTION] = 3 } }),
    H.release(),
    H.worldNavTo(87, 105, { maxFrames = 40000, playBattles = "tactical",
                            reserve = { [POTION] = 3 } }),
    H.release(),
    H.call(function() grindLaps = n; where("grind lap " .. n) end),
    care("grind lap " .. n, 0.85),
  }, {})
end

local function grindTrip()
  return seq({
    -- out of town by the x=0 column -> world (84,112)
    H.navTo(1, 28, { maxFrames = 30000, playBattles = "flee",
                     avoid = M75_AVOID }),
    H.release(), H.waitFrames(30),
    H.driveUntil(function() return H.worldMode() end, 900, {
      H.hold({ "left" }), H.waitFrames(8),
    }, "leave South Figaro for the grind (x=0 column)"),
    H.release(),
    settleWorld("outside the gate"),
    H.worldNavTo(84, 108, { maxFrames = 20000, playBattles = "tactical" }),
    H.release(),
    H.call(function()
      H.assertEq(H.worldMode(), true,
        "still outside -- the town's own entrance tiles were stepped around")
      H.assertEq(H.worldX(), 84, "staged north of the gate, x=84")
      H.assertEq(H.worldY(), 108, "staged north of the gate, y=108")
      where("grind start")
    end),
    lap(1), lap(2), lap(3), lap(4), lap(5), lap(6), lap(7), lap(8), lap(9),
    lap(10), lap(11), lap(12), lap(13), lap(14), lap(15), lap(16), lap(17),
    lap(18), lap(19), lap(20), lap(21), lap(22), lap(23), lap(24),
    H.call(function()
      H.log(string.format(
        "[grind] %d laps: LOCKE L%d xp=%d (target %d), gil=%d",
        grindLaps, levelOf(LOCKE), expOf(LOCKE), EXP_TARGET, gil()))
      H.assertEq(expOf(LOCKE) >= EXP_TARGET, true,
        string.format("the grind reached its experience target in %d laps " ..
          "(LOCKE %d of %d)", grindLaps, expOf(LOCKE), EXP_TARGET))
      H.assertEq(gil() >= GIL_TARGET, true,
        string.format("the grind paid for the town's whole shopping list " ..
          "(%d of %d gil)", gil(), GIL_TARGET))
    end),
    -- back in at (86,111) -> map 75 (1,28)
    H.worldNavTo(86, 111, { maxFrames = 40000, playBattles = "tactical",
      arrive = function() return not H.worldMode() end }),
    H.release(),
    settleField("back in town", 75),
    H.call(function()
      H.assertEq(map(), 75, "back inside South Figaro after the grind")
      where("grind done")
      H.screenshot("sfigaro_grind_done")
    end),
  })
end

-- ------------------------------------------------- the other three shops --
-- Doorsteps, merchants and talk spots are docs/research/
-- south-figaro-shop-route.md §10 (§5 for the inn), derived statically there
-- and walked here.  All three doors are $F7 bump doors, so the door tile can
-- never be the goal of a navTo: CheckDoor opens the $05/$15 pair only for a
-- party standing directly below it (field/player.asm:958-1010).
local function enterDoor(mx, my, dstMap, what)
  return seq({
    H.logStep(function()
      return string.format("%s: doormat (%d,%d) -> map %d", what, mx, my, dstMap)
    end),
    H.navTo(mx, my, { maxFrames = 30000, playBattles = "flee",
                      avoid = M75_AVOID }),
    H.release(), H.waitFrames(20),
    H.call(function()
      H.assertEq(H.fieldX(), mx, what .. ": on the doormat, x=" .. mx)
      H.assertEq(H.fieldY(), my, what .. ": on the doormat, y=" .. my)
    end),
    H.driveUntil(function() return map() == dstMap end, 1800, {
      H.hold({ "up" }), H.waitFrames(8),
    }, what .. ": hold UP into the door"),
    H.release(),
    settleField(what, dstMap),
    H.call(function()
      H.assertEq(map(), dstMap, what .. ": inside map " .. dstMap)
      where(what)
    end),
  })
end

-- Leave an interior by walking back onto its arrival tile and holding DOWN
-- through the door under it.
local function leaveDoor(ax, ay, what)
  return seq({
    H.navTo(ax, ay, { maxFrames = 20000, playBattles = "flee" }),
    H.release(), H.waitFrames(20),
    H.driveUntil(function() return map() == 75 end, 1800, {
      H.hold({ "down" }), H.waitFrames(8),
    }, what .. ": back out to the town"),
    H.release(),
    settleField("back in town", 75),
  })
end

-- Stand on (sx,sy), face UP, tap A until the shop options window is up.
-- CheckNPCs reaches one tile past a counter (p1 & 7 == 7,
-- field/player.asm:188-200), which is why these talk spots are two tiles
-- below the merchant rather than adjacent to him.
local function counterShop(sx, sy, what)
  return seq({
    H.navTo(sx, sy, { maxFrames = 20000, playBattles = "flee" }),
    H.release(), H.waitFrames(20),
    H.driveUntil(inState(0x25), 6000, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        if H.fieldX() ~= sx or H.fieldY() ~= sy then H.setPad({}); return end
        if H.readByte(0x087f + H.readWord(0x0803)) ~= FACE.up then
          H.setPad({ up = true }); return
        end
        H.setPad((H.frame % 8 < 4) and { "a" } or {})
      end),
    }, what .. ": counter talk opens the shop"),
    H.release(),
    tapUntil("a", inState(0x26), what .. ": the buy list opens"),
    H.release(), H.waitFrames(20),
    H.call(function()
      local rows = {}
      for r = 0, 7 do rows[#rows + 1] = string.format("%02X", rowItem(r)) end
      H.log("[shop] " .. what .. " stock: " .. table.concat(rows, " "))
    end),
  })
end

local function closeShop(onMap, what)
  return seq({
    tapUntil("b", inState(0x25), what .. ": back to the options window"),
    tapUntil("b", function() return H.hasControl() and map() == onMap end,
      what .. ": closed"),
    H.release(), H.waitFrames(30),
  })
end

-- ------------------------------------------------------------ the equips --
-- Two menus, not one.  Equip (main menu row 2) reaches R-Hand / L-Hand /
-- Head / Body and nothing else: `EquipSlotCursorProp` is `{1, 4}`, four rows
-- (ff6/src/menu/equip.asm:76-77).  Relics have their own menu (main row 3)
-- with a two-slot cursor (`RelicSlotCursorProp` `{1, 2}`, :200-201) and its
-- own state chain $59 -> $5a -> $5b.  A first draft drove relics through the
-- Equip menu and would have hunted a fifth slot that does not exist.
-- Main menu rows are Item / Skills / Equip / Relic / Status / Config / Save
-- (`SelectMainMenuOptionTbl`, ff6/src/menu/field_menu.asm:3420-3427).
local ZM, CUR = 0x26, 0x4b
local ST_MAIN, ST_CHAR = 0x05, 0x06
local ST_EQOPT, ST_EQSLOT, ST_EQITEM = 0x36, 0x55, 0x57
local ST_RLOPT, ST_RLSLOT, ST_RLITEM = 0x59, 0x5a, 0x5b

-- char-select position of a character id, answered from $1850 rather than
-- from the menu's own $69+slot copy, which is stale on the field.  It is
-- resolved lazily because every step in an H.run list is CONSTRUCTED before
-- the boot state is loaded.
local function posOf(c)
  return function()
    for i, m in ipairs(H.partyMembers()) do
      if m == c then return i - 1 end
    end
    return 0
  end
end

local function menuEquip(mainRow, pos, slot, slotState, itemState, itemId, tag)
  local optState = (slotState == ST_EQSLOT) and ST_EQOPT or ST_RLOPT
  local ph = 0
  local function tap(btn) ph = (ph + 1) % 12; H.setPad(ph < 4 and { btn } or {}) end
  local function st() return H.readByte(ZM) end
  local function seek(state, wantIn, back, fwd, label)
    local function want()
      return type(wantIn) == "function" and wantIn() or wantIn
    end
    return H.driveUntil(function()
      return st() == state and H.readByte(CUR) == want()
    end, 1800, {
      H.call(function()
        if st() ~= state then H.setPad({}); return end
        local cur = H.readByte(CUR)
        ph = (ph + 1) % 12
        H.setPad(ph < 4 and { [cur < want() and fwd or back] = true } or {})
      end),
    }, tag .. ": " .. label)
  end
  local function press(state, label)
    return seq({
      H.driveUntil(function() return st() == state end, 1800, {
        H.call(function() tap("a") end),
      }, tag .. ": " .. label),
      H.release(), H.waitFrames(10),
    })
  end
  return seq({
    H.driveUntil(function() return st() == ST_MAIN end, 1800, {
      H.call(function() tap("x") end),
    }, tag .. ": main menu"),
    H.release(), H.waitFrames(10),
    seek(ST_MAIN, mainRow, "up", "down", "main cursor"),
    H.release(), H.waitFrames(10),
    press(ST_CHAR, "character select"),
    seek(ST_CHAR, pos, "up", "down", "character cursor"),
    H.release(), H.waitFrames(10),
    press(optState, "options row"),
    seek(optState, 0, "left", "right", "cursor on Equip"),
    H.release(), H.waitFrames(10),
    press(slotState, "slot select"),
    seek(slotState, slot, "up", "down", "slot cursor"),
    H.release(), H.waitFrames(10),
    press(itemState, "item list"),
    -- the list rows at $7e9d8a are bag indexes into $1869, so this compares
    -- the item id under the cursor rather than counting rows; the list is
    -- pre-filtered by GetValidEquip, so an un-equippable item makes the seek
    -- time out rather than equip something else
    H.driveUntil(function()
      return st() == itemState
         and H.readByte(0x1869 + H.readByte(0x9d8a + H.readByte(CUR))) == itemId
    end, 3000, {
      H.call(function()
        if st() ~= itemState then H.setPad({}); return end
        tap("down")
      end),
    }, tag .. ": list cursor on the item"),
    H.release(), H.waitFrames(10),
    H.driveUntil(function() return st() == slotState end, 1800, {
      H.call(function() tap("a") end),
    }, tag .. ": equipped, back on the slot list"),
    H.release(),
    H.driveUntil(function() return H.hasControl() end, 2400, {
      H.call(function() tap("b") end),
    }, tag .. ": back out to the field"),
    H.release(), H.waitFrames(20),
  })
end
local function equipGear(pos, slot, itemId, tag)
  return menuEquip(2, pos, slot, ST_EQSLOT, ST_EQITEM, itemId, tag)
end
local function equipRelic(pos, slot, itemId, tag)
  return menuEquip(3, pos, slot, ST_RLSLOT, ST_RLITEM, itemId, tag)
end

-- -------------------------------------------------- the relic shop + inn --
-- Both are on map 76, which is two disjoint regions joined by a same-map
-- short entrance: region A (the relic shop) is where map 75's door lands,
-- and (48,3) -> (69,10) is the only way to region B (the inn).
--
-- The relic demonstrator (NPC index 4 = object 20, spawn switch $0358)
-- stands on (51,11), the only tile the shopkeeper at {51,9} can be
-- counter-talked from.  His own scene ends `switch $0358=0`
-- (event_main.asm:18394) and he walks off, so he is talked to first.
local function talkOut(obj, done, what, budget)
  local calm, ph = 0, 0
  return seq({
    H.talkToObj(obj, what),
    H.driveUntil(function()
      local ok = H.hasControl() and H.tileAligned() and bright() >= 15
             and not H.dialogWaiting() and not H.eventRunning()
             and not H.battleLoadStarted() and done()
      calm = ok and calm + 1 or 0
      return calm >= 30
    end, budget or 20000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.hasControl() and not H.dialogWaiting() then H.setPad({}); return end
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, what .. ": ride it out"),
    H.release(),
  })
end

-- The 80 GP is paid on purpose.  Every player-invocable rest in the script
-- goes through `_cacd3c`/`_cacd31`, which both end in `_cacf67` ->
-- `_cacfbd`, so every rest in the game restores the same thing and a free
-- one would be strictly better.  There is not one on this road.  Of the
-- fifteen call sites, twelve take gil, one takes 1, and the three free ones
-- are Figaro Castle's bed (`EventTrigger::_59` {47,52}), map 123's, and the
-- Returner Hideout's own NPCs on maps 109/111 -- none reachable from here.
-- Duncan's house is real and is map 86, INSIDE the town (map_prop byte 0 =
-- $1C -> map_title_en 28, "DUNCAN'S HOUSE"; his wife is NPCProp::_86's
-- OLD_WOMAN at {54,51}), and `EventTrigger::_86`'s eight triggers are all
-- exit redirects -- no bed.  The hut on the road at world (90,99) -> map 93
-- is where SABIN was staying, and `EventTrigger::_93` is empty, so there is
-- nothing on it to sleep in either.  At 434 gil a lap the inn costs about a
-- fifth of one lap, once.
--
-- `dlg $0B89` is "80 GP per night! Well?  0: Yes  1: No", and `take_gil 80`
-- sets $01BE when the party cannot pay, in which case the script says
-- "……Not enough money." and does not rest -- so the gold is asserted before
-- the talk rather than the rest being assumed.  What it restores is
-- `and_status {MAGITEK, INTERCEPTOR}` + `max_hp` + `max_mp` on all four
-- slots (_cacfbd, event_main.asm:31862-31875): full HP, full MP, and every
-- other persistent status bit cleared -- KO and poison included.  That last
-- part is why this stop is the right place to end the town visit: TERRA
-- walks out of it with the full Cure line the VARGAS entry contract asks
-- for, whatever the grind spent.
local CH_SEL, CH_MAX = 0x056E, 0x056F
local function innRest(what)
  local ph, ci, calm = 0, 0, 0
  local inChoice = false
  return seq({
    H.call(function()
      H.assertEq(gil() >= 80, true, what .. ": the party can pay the 80 GP")
    end),
    H.navTo(81, 19, { maxFrames = 20000, playBattles = "flee" }),
    H.release(), H.waitFrames(20),
    H.call(function()
      H.assertEq(H.fieldX(), 81, what .. ": on the innkeeper's talk spot x=81")
      H.assertEq(H.fieldY(), 19, what .. ": on the innkeeper's talk spot y=19")
    end),
    H.driveUntil(function()
      return H.eventRunning() or H.dialogWaiting()
    end, 6000, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        if H.readByte(0x087f + H.readWord(0x0803)) ~= FACE.up then
          H.setPad({ up = true }); return
        end
        H.setPad((H.frame % 8 < 4) and { "a" } or {})
      end),
    }, what .. ": engage the innkeeper"),
    H.release(),
    H.driveUntil(function()
      local ok = H.hasControl() and H.tileAligned() and bright() >= 15
             and not H.dialogWaiting() and not H.eventRunning()
      calm = ok and calm + 1 or 0
      return calm >= 30
    end, 30000, {
      H.call(function()
        ph = (ph + 1) % 8
        local chMax = (not H.battleLoadStarted()) and H.readByte(CH_MAX) or 0
        if chMax >= 2 then
          if not H.dialogWaiting() then H.setPad({}); return end
          if not inChoice then
            inChoice = true; ci = ci + 1
            H.log(string.format(
              "%s: choice #%d up (%d options) -- taking 0 (Yes)",
              what, ci, chMax))
          end
          if H.readByte(CH_SEL) > 0 then H.setPad(ph < 4 and { "up" } or {})
          else H.setPad(ph < 4 and { "a" } or {}) end
          return
        end
        inChoice = false
        if H.hasControl() and not H.dialogWaiting() then H.setPad({}); return end
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, what .. ": the night passes"),
    H.release(), H.waitFrames(30),
  })
end

-- The gear pass.  LOCKE's own Dirk is power 26 and pierce; the MithrilBlade
-- is power 38 and slash, and it is the best thing in shop 5 he can hold
-- (RegalCutlass is 54 but its equip mask is $8051 -- TERRA, EDGAR, CELES).
-- He BUYS one rather than taking EDGAR's, which was the cheaper idea and is
-- wrong: LOCKE carries exactly one weapon into his solo scenario, because
-- the Returner Hideout's `remove_equip` returns only what he is WEARING to
-- the bag, and TunnelArmr is `5, OT6_PIERCE` (ot6_hud.asm:1943).  Buying
-- leaves his Dirk unequipped in the shared bag, which does ride to the
-- split, so his scenario has both classes.  The gate soldier's HeavyArmor is
-- `3, OT6_SLASH|OT6_PIERCE` (:2013), so the blade breaks it either way.
--
-- Two Heavy Shlds and a Plumed Hat are the other half.  LOCKE is the only member of this
-- party with an EMPTY left hand (measured at south_figaro -- TERRA and EDGAR
-- both carry Bucklers already), so one is a straight +22 defense / +14 magic
-- defense on him for 400 gil.  The second stays in the common bag for
-- CYAN's Phantom Train loadout.  That spare matters when LOCKE's scenario is
-- completed first: CELES keeps his branch's shield equipped while the player
-- switches to SABIN, so one purchased shield cannot serve both parties.
-- The hat is the same scenario-order provision for SHADOW: CELES retains the
-- common route's Leather Hat on LOCKE's branch, while the Plumed Hat remains
-- in the bag and fits everyone.
--
-- A MithrilKnife is bought as well and nobody equips it here (issue #106).
-- It is row 1 of the same shop, 300 gil out of a five-figure purse, power 30
-- and OT6_PIERCE (ot6_class.asm:49).  It is bought for a fight three links
-- past the scenario split: the Returner Hideout now hands the party a Genji
-- Glove, which lets LOCKE hold two weapons at once, and TunnelArmr is
-- `5, OT6_PIERCE`, so two PIERCE weapons chip two shields a swing instead of
-- one.  What carries it there is the bag, by the same fact the Dirk
-- paragraph above rests on: an unequipped item rides the split.
--
-- It is also what keeps CELES armed.  Without this purchase the Locke
-- scenario holds exactly two weapons, so arming LOCKE with both hands leaves
-- her with nothing, and tools/audit_equipment.py refuses a fixture that
-- ships a bare-handed party member.  One extra knife is what lets LOCKE
-- dual-wield pierce and CELES hold the MithrilBlade.
--
-- And it is what a player does at the last counter before the mountain:
-- docs/design/wob-route.md section 2, buy what the next stretch needs.
local MITHRILBLADE, HEAVYSHLD, PLUMEDHAT, STARPENDANT = 0x0A, 0x5B, 0x6B, 0xB1
local JEWELRING = 0xB5
local MITHRILKNIFE = 0x01

local function gearTrip()
  return seq({
    enterDoor(29, 19, 77, "weapon shop"),
    counterShop(103, 11, "shop 5 (weapon)"),
    buyTo(MITHRILBLADE, 2, 1, 450, "MITHRILBLADE to 1"),
    buyTo(MITHRILKNIFE, 1, 1, 300, "MITHRILKNIFE to 1"),
    closeShop(77, "shop 5"),
    leaveDoor(103, 16, "shop 5"),
    enterDoor(35, 19, 77, "armor shop"),
    counterShop(114, 12, "shop 6 (armor)"),
    buyTo(HEAVYSHLD, 1, 2, 400, "HEAVY SHLD to 2"),
    buyTo(PLUMEDHAT, 3, 2, 250, "PLUMED HAT to 2 -- one per scenario order, the Heavy Shld precedent: the Locke lineage wears one onto a head before the split hands the bag to SABIN's train"),
    closeShop(77, "shop 6"),
    leaveDoor(114, 16, "shop 6"),
    H.call(function()
      H.assertEq(invCount(MITHRILBLADE) >= 1, true,
        "the MithrilBlade is in the bag")
      H.assertEq(invCount(HEAVYSHLD) >= 2, true,
        "two Heavy Shlds cover both scenario orders")
      H.assertEq(invCount(PLUMEDHAT) >= 2, true,
        "two Plumed Hats cover SHADOW in either scenario order (#84 wave: "
        .. "one hat was worn by the Locke lineage and s2_train found the bag "
        .. "empty)")
      H.assertEq(invCount(MITHRILKNIFE) >= 1, true,
        "a spare MithrilKnife is in the bag -- nobody wears it here; it is " ..
        "LOCKE's second PIERCE weapon at TunnelArmr, past the split")
    end),
    equipGear(posOf(1), 0, MITHRILBLADE, "locke blade"),
    equipGear(posOf(1), 1, HEAVYSHLD, "locke shield"),
    H.call(function()
      H.assertEq(H.readByte(0x1600 + 37 * 1 + 0x1f), MITHRILBLADE,
        "LOCKE holds the MithrilBlade")
      H.assertEq(H.readByte(0x1600 + 37 * 1 + 0x20), HEAVYSHLD,
        "LOCKE holds the Heavy Shld")
      H.assertEq(invCount(HEAVYSHLD) >= 1, true,
        "a second Heavy Shld remains in the common bag for CYAN")
      H.assertEq(invCount(0x00) >= 1, true,
        "and his own Dirk is unequipped in the shared bag, which is what " ..
        "carries a pierce weapon into his solo scenario for TunnelArmr")
      where("locke armed")
    end),
  })
end

-- The relic pass and the night.  Three Star Pendants are `+$06 = $04` into
-- $11D2, the status 1 and 2 protection word (CalcEquipEffect,
-- battle_main.asm:2513-2517), and STATUS1::POISON is BIT_2
-- (ff6/include/const.inc:1491), so they are poison immunity for the whole
-- party.  That is the thing wob-route.md §2 names: the route used to buy
-- Antidotes and then walk a poisoned character down to 1 hp, because
-- DoPoisonDmg takes max HP/32 on every step with a floor of 1
-- (field/player.asm:593-613).  The Antidotes stay bought as well; they cost
-- 150 against a purse the grind put five figures into, and nothing has yet
-- measured a poisoned party member on this route WITH the pendants on.
--
-- Three Jewel Rings fill the free second relic slots.  Their same +$06 byte
-- is $40, STATUS1::PETRIFY, so the party prevents the condition instead of
-- routinely spending Softs after it.  The first recovery-only attempt bought
-- two Softs and consumed both before Mt. Kolts; immunity preserves that small
-- backup for the scenario branches.  The relic shop is after the gil grind,
-- so the 3000 GP does not compete with the item shop's Fenix/Tonic budget.
local function relicTrip()
  return seq({
    enterDoor(15, 39, 76, "the relic shop and the inn"),
    H.call(function()
      H.assertEq(sw(0x0358), 1,
        "$0358 set -- the relic demonstrator is standing on the talk spot")
      H.log(string.format("demonstrator (obj 20) at (%d,%d)",
        objX(20), objY(20)))
    end),
    talkOut(20, function() return sw(0x0358) == 0 end,
      "the relic demonstrator (_ca78dc)"),
    H.call(function()
      H.assertEq(sw(0x0358), 0, "the demonstrator has gone ($0358 cleared)")
    end),
    counterShop(51, 11, "shop 7 (relics)"),
    buyTo(STARPENDANT, 2, 3, 500, "STAR PENDANT to 3"),
    buyTo(JEWELRING, 3, 3, 1000, "JEWEL RING to 3"),
    closeShop(76, "shop 7"),
    H.call(function()
      H.assertEq(invCount(STARPENDANT), 3, "three Star Pendants in the bag")
      H.assertEq(invCount(JEWELRING), 3, "three Jewel Rings in the bag")
    end),
    equipRelic(posOf(0), 0, STARPENDANT, "terra pendant"),
    equipRelic(posOf(1), 0, STARPENDANT, "locke pendant"),
    equipRelic(posOf(4), 0, STARPENDANT, "edgar pendant"),
    equipRelic(posOf(0), 1, JEWELRING, "terra jewel ring"),
    equipRelic(posOf(1), 1, JEWELRING, "locke jewel ring"),
    equipRelic(posOf(4), 1, JEWELRING, "edgar jewel ring"),
    H.call(function()
      for _, c in ipairs({ 0, 1, 4 }) do
        H.assertEq(H.readByte(0x1600 + 37 * c + 0x23) == STARPENDANT
                or H.readByte(0x1600 + 37 * c + 0x24) == STARPENDANT, true,
          string.format("char %d wears a Star Pendant -- Mt Kolts cannot " ..
            "poison this party", c))
        H.assertEq(H.readByte(0x1600 + 37 * c + 0x23) == JEWELRING
                or H.readByte(0x1600 + 37 * c + 0x24) == JEWELRING, true,
          string.format("char %d wears a Jewel Ring -- Mt Kolts cannot " ..
            "petrify this party", c))
      end
      where("pendants on")
    end),
    -- region A -> region B, the inn wing
    H.navTo(48, 3, { maxFrames = 20000, playBattles = "flee",
      arrive = function() return H.fieldX() == 69 and H.fieldY() == 10 end }),
    H.release(),
    settleField("inn wing", 76),
    H.call(function()
      H.assertEq(H.fieldX(), 69, "through the staircase warp, x=69")
      H.assertEq(H.fieldY(), 10, "through the staircase warp, y=10")
    end),
    innRest("the inn"),
    H.call(function()
      where("after the night")
      for _, c in ipairs(H.partyMembers()) do
        H.assertEq(H.charHp(c), H.charMaxHp(c),
          string.format("char %d woke at full hp", c))
        H.assertEq(H.charMp(c), H.charMaxMp(c),
          string.format("char %d woke at full mp", c))
      end
      H.screenshot("sfigaro_inn")
    end),
    -- back out: region B -> region A -> map 75
    H.navTo(70, 11, { maxFrames = 20000, playBattles = "flee",
      arrive = function() return H.fieldX() == 49 and H.fieldY() == 4 end }),
    H.release(),
    settleField("relic wing", 76),
    leaveDoor(52, 14, "the inn's building"),
    H.call(function()
      H.assertEq(map(), 75, "back on map 75 with the shopping done")
      where("town stop done")
    end),
  })
end

H.run({ maxFrames = 700000 }, {
  H.loadState(CLEARED),
  H.waitFrames(20),
  H.call(function()
    H.assertEq(H.worldMode(), true, "booted on the world map")
    H.assertEq(H.readByte(0x11fa) & 3, 2, "booted riding the chocobo")
    where("booted")
  end),

  -- ===================================================================== --
  -- PHASE 1: get off the chocobo.  Hold B; LandAirship stages the tile into
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
  -- PHASE 2: the South Figaro cave, the desert's only way south.  Four
  -- steps; the middle one is an event trigger, not an entrance, so it is
  -- driven as a plain navTo whose arrival is the map change.
  -- ===================================================================== --
  H.call(function()
    H.assertEq(sw(0x001A), 0,
      "$001A clear -> the cave's map-73/72 copy (event_main.asm:14219)")
  end),
  settleWorld("desert"),
  H.worldNavTo(73, 93, { maxFrames = 30000, playBattles = "flee",
    arrive = function() return not H.worldMode() end }),
  H.release(),
  settleField("cave mouth", 71),
  H.call(function()
    H.assertEq(map(), 71, "world (73,93) -> map 71, the cave lobby")
    where("cave lobby")
  end),
  care("cave lobby"),

  -- The guards first: they stand on the only two tiles that reach the
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
  end, 20000, { playBattles = "flee" }),
  H.call(function()
    H.assertEq(sw(0x0312), 0, "the guards are gone ($0312 cleared)")
    where("cave opened")
    H.screenshot("kolts_cave_guards")
  end),

  -- map 71's event trigger at (10,48)/(11,48) opens the cave (_ca5ef7); the
  -- lobby has no short entrance onward.
  H.navTo(11, 48, { maxFrames = 20000, arrive = mapChanged(),
           playBattles = "flee" }),
  H.release(),
  settleField("cave body"),
  H.call(function()
    H.assertEq(map() == 73 or map() == 70, true,
      "map 71's trigger loaded the cave body (73 or 70), got " .. map())
    where("cave body")
  end),
  care("cave body"),

  -- Map 73 offers three exits and the spawn only reaches one.  Landing at
  -- (47,39) the model reaches 50 tiles: (55,32) -> map 72 (10,3) and
  -- (47,40) -> back to the lobby, but not (41,14), which belongs to a stretch
  -- of the cave this end does not connect to.  This was measured after a
  -- first pass picked (41,14) off the table and got "no path".
  crossTo(55, 32, 72, "cave body -> cave exit hall"),

  -- Map 72 is four disconnected regions stitched together by same-map warps,
  -- and the one the party lands in does not touch the world exit.  Measured
  -- from (10,3): 276 reachable tiles, and of the map's seven entrance records
  -- only (10,2)/(4,4) back to map 73 and (17,20) are among them.  (16,43),
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
  H.navTo(16, 43, { maxFrames = 20000, playBattles = "flee",
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
  -- PHASE 3: South Figaro.  One world tile of the four that lead in
  -- ((86,111)/(85,112)/(86,112)/(85,113) -> map 75 (1,28)); generate on
  -- arrival, then leave by the x=0 column the party is already beside.
  -- ===================================================================== --
  H.worldNavTo(86, 111, { maxFrames = 30000, playBattles = "flee",
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
  end),
  care("south figaro"),
  H.call(function() H.screenshot("south_figaro") end),
  H.saveState("south_figaro.mss"),
  H.logStep(function()
    return string.format("south_figaro generated at frame %d", H.frame)
  end),

  -- The town's seven visible chests (#84), all on map 75, opened in walk
  -- order from the gate toward the item shop door at (44,32).  Maps 75/85
  -- have no encounters, so every pickup walk matches the neighbouring navTo
  -- calls (playBattles="flee") and avoids the same short entrances the shop
  -- walk does.  Every stand/face pair below was measured from south_figaro
  -- in probe_kolts_chests.lua before it was inserted here; stand-below-face-
  -- up only holds for three of the seven, because South Figaro shelves its
  -- chests: the tile below the Tonic at (6,31) and the Green Cherry at
  -- (14,28) is not reachable (walkability dumps in the probe run), so both
  -- open from the side.  (These pickups all run after the saveState above,
  -- so south_figaro.mss itself does not carry the treasure bits; kolts_entry
  -- and vargas_entry do.)
  -- #84: Tonic, visible on the walk
  H.openChest{ stand = {5, 31}, face = "right", bit = 24, what = "Tonic",
               item = 0xE8, nav = { playBattles = "flee", avoid = M75_AVOID } },
  -- #84: Green Cherry, visible on the walk
  H.openChest{ stand = {13, 28}, face = "right", bit = 25,
               what = "Green Cherry",
               nav = { playBattles = "flee", avoid = M75_AVOID } },
  -- #84: Warp Stone, visible on the walk
  H.openChest{ stand = {11, 24}, face = "up", bit = 231, what = "Warp Stone",
               nav = { playBattles = "flee", avoid = M75_AVOID } },

  -- #84: Fenix Down, visible on the walk.  Its yard at (22..25,15..19) is
  -- fenced off the street -- measured: BFS reaches no tile beside the chest
  -- from the party's region -- and the way in is through the house between
  -- them, the classic South Figaro back door: doormat (15,20), bump door up
  -- into map 81 at (4,16); inside, (16,16) -> map 75 (23,17) opens in the
  -- yard (short_entrance.dat maps 75/81).  The interior walks avoid the
  -- house's other exit tile so a shortest path cannot warp out early.
  enterDoor(15, 20, 81, "chest yard house"),
  H.navTo(16, 15, { maxFrames = 20000, playBattles = "flee",
                    avoid = { { 4, 17 }, { 16, 16 } } }),
  H.release(), H.waitFrames(20),
  H.driveUntil(function() return map() == 75 end, 1800, {
    H.hold({ "down" }), H.waitFrames(8),
  }, "chest yard: out the back door onto (23,17)"),
  H.release(),
  settleField("chest yard", 75),
  H.call(function()
    H.assertEq(map(), 75, "in the chest yard, back on map 75")
  end),
  H.openChest{ stand = {22, 19}, face = "up", bit = 20, what = "Fenix Down",
               item = 0xF0, nav = { playBattles = "flee" } },
  enterDoor(23, 17, 81, "chest yard house, back through"),
  H.navTo(4, 16, { maxFrames = 20000, playBattles = "flee",
                   avoid = { { 16, 16 }, { 4, 17 } } }),
  H.release(), H.waitFrames(20),
  H.driveUntil(function() return map() == 75 end, 1800, {
    H.hold({ "down" }), H.waitFrames(8),
  }, "chest yard: back out to the street"),
  H.release(),
  settleField("back in town", 75),
  H.call(function()
    H.assertEq(map(), 75, "back on the street with the Fenix Down")
  end),

  -- #84: Tonic, visible on the walk (the stand/face pair probe_openchest.lua
  -- measured)
  H.openChest{ stand = {32, 17}, face = "up", bit = 21, what = "Tonic",
               item = 0xE8, nav = { playBattles = "flee", avoid = M75_AVOID } },

  -- ===================================================================== --
  -- PHASE 3b: the item shop.  The party walks through a town on the way to a
  -- boss carrying a bag that cannot answer a death, and until now it walked
  -- straight back out again.  Measured 2026-08-09: with the care layer in and
  -- map 98 fought rather than fled, everyone reached VARGAS alive, but the
  -- Tonics were gone and the Potions were down to the reserve, and the run
  -- before that lost LOCKE outright with no Fenix Down to raise him.  Running
  -- out of supplies is a real finding, and the shop is thirty seconds off the
  -- path.  The same argument brought the Antidote line in on 2026-08-12: the
  -- bag could not answer poison either, and unlike a death, poison is not
  -- something the mountain finishes with you -- it rides out of the fight and
  -- costs max HP/32 on every step from here to Narshe.
  --
  -- The route is derived in docs/research/south-figaro-shop-route.md and
  -- the hazards it names are handled here:
  --   * shop 8 (event_main.asm:18308), not 15; the shop ids at :21595
  --     belong to another town.  Its stock is Tonic / Antidote /
  --     Soft / Eyedrop / Echo Screen / Fenix Down / Sleeping Bag / Tent,
  --     rows 0..7, and it does not sell Potions.  Shop 63, the $00A4
  --     alternate, is the only South Figaro record that sells them, and
  --     $00A4 is set inside the Locke/Celes escape, chapters from here.
  --     So Tonics are the refill and Fenix Downs are the insurance.
  --   * map 75 has five short entrances a BFS would route through, and
  --     (8..10,32) sits sixteen steps from the spawn in the quadrant this
  --     walk crosses.  They are passed to navTo as `avoid`.
  --   * (44,30) is a bump door ($F7): a wall until CheckDoor opens it, so
  --     BFS cannot plan onto it and the crossing is navTo(44,32) plus one
  --     held UP, the same shape gen_edgar's crossDoor uses for Figaro.
  --   * the merchant is a counter talk.  He stands at (106,52); the party
  --     stands at (106,54) and faces UP, and CheckNPCs reaches the tile
  --     beyond the counter at (106,53) (player.asm:188-200).  The counter
  --     is in the way, so the party cannot stand next to him.
  --   * maps 75 and 85 have no encounters (map_prop byte 5 = 0), so this
  --     detour is walked, not fought.
  shopTrip(),

  -- The grind, then the rest of the shopping it pays for, then a night at
  -- the inn.  The order is deliberate: shop 8 above is the insurance (the
  -- party crosses the cave and reaches this counter with ZERO Fenix Downs,
  -- measured), the grind is what turns 324 gil into five figures, and the
  -- inn is last so the party leaves town at full hp and full mp whatever
  -- the grind spent.
  grindTrip(),
  gearTrip(),

  -- Back to the item shop with the grind's money.  The first visit could
  -- only afford 5 revives and 25 Tonics out of 3974; the mountain is nine
  -- crossings and the map-98 approach on top, and this is still the last
  -- counter before the Returner Hideout.  Seven revives and thirty Tonics
  -- leave a generous field-care reserve while preserving 4580 GP for the
  -- three Star Pendants, three Jewel Rings, and the 80 GP inn stay below.
  enterDoor(44, 32, 85, "item shop (second visit)"),
  counterShop(106, 54, "shop 8 (item, top-up)"),
  buyTo(0xF0, 5, 7, 500, "FENIX DOWN to 7"),
  buyTo(0xE8, 0, 30, 50, "TONIC to 30"),
  closeShop(85, "shop 8"),
  leaveDoor(104, 57, "the item shop"),
  H.call(function()
    H.assertEq(invCount(0xF0) >= 6, true,
      "the mountain is walked with real revives now")
    where("restocked")
  end),

  -- The two chests in the south yard, six tiles below the relic shop's door
  -- at (15,39), picked up on the walk to it.  They stack on one column:
  -- Antidote at (15,45), Eyedrop at (15,47), and the tile between them,
  -- (15,46), is the one walkable stand (the tile below the Eyedrop is not;
  -- probe_kolts_chests.lua's walkability dump).  So both open from (15,46),
  -- facing opposite ways.
  -- #84: Antidote, visible on the walk
  H.openChest{ stand = {15, 46}, face = "up", bit = 22, what = "Antidote",
               item = 0xF2, nav = { playBattles = "flee", avoid = M75_AVOID } },
  -- #84: Eyedrop, visible on the walk
  H.openChest{ stand = {15, 46}, face = "down", bit = 23, what = "Eyedrop",
               nav = { playBattles = "flee", avoid = M75_AVOID } },

  relicTrip(),

  -- The rows are set once, here, and they carry in the save from here to the
  -- end of the chain (the bit is $1850+c bit $20, party state, not battle
  -- state).  Owner note, 2026-08-09: "a lot of ranged attackers can just sit
  -- in the back row forever at no cost."  In this ROM the exemption is wider
  -- than that: ExecCmd sets $B3 = $FF for every command and only the weapon
  -- swing clears the "ignore attacker row" bit, so Tools, Magic, Blitz,
  -- SwdTech, Throw and Steal are all exempt (battle_main.asm:3131-3133,
  -- :7127-7133).  EDGAR fights this arc with Tools and TERRA with Magic, so
  -- the back row halves the physical damage they take at no cost.  LOCKE
  -- stays in front: Steal deals no damage, so Fight is his only damage, and
  -- the Dirk carries no BACK_ROW flag.  docs/research/row-menu.md has the
  -- citations.
  H.setRows({ [0] = true, [1] = false, [4] = true }, { tag = "rows" }),

  -- Out the way we came: x=0 is the vertical long entrance -> world
  -- (84,112).  One press, not a navTo, because the target tile is the
  -- trigger.
  H.navTo(1, 28, { maxFrames = 20000, playBattles = "flee", avoid = M75_AVOID }),
  H.release(),
  H.waitFrames(30),
  H.driveUntil(function() return H.worldMode() end, 900, {
    H.hold({ "left" }), H.waitFrames(8),
  }, "leave South Figaro (x=0 column)"),
  H.release(),
  settleWorld("back outside"),
  H.call(function() where("left south figaro") end),

  -- ===================================================================== --
  -- PHASE 4: Mt. Kolts.  World (102,100) -> map 95 (14,35).  Map 95's own
  -- exit row y=37 is two tiles south of the spawn, so every step here is
  -- pre-checked against it.
  -- ===================================================================== --
  H.worldNavTo(102, 100, { maxFrames = 40000, playBattles = "flee",
    arrive = function() return not H.worldMode() end }),
  H.release(),
  settleField("mt kolts", 95),
  H.call(function()
    H.assertEq(map(), 95, "on map 95, MT. KOLTS")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    where("kolts entry point")
  end),
  care("kolts entry point"),
  H.call(function()
    H.assertEq(invCount(0xF4) >= 2, true,
      "at least two Softs survive the South Figaro-to-Kolts journey -- " ..
      "the scenario branches still have a Petrify answer")
  end),
  H.call(function() H.screenshot("kolts_entry") end),
  H.saveState("kolts_entry.mss"),
  H.logStep(function()
    return string.format("kolts_entry generated at frame %d", H.frame)
  end),

  -- ===================================================================== --
  -- The mountain.  Nine crossings.  Map 100 cannot be walked across: it is
  -- six disconnected shelves, and the caves 96/97/102 connect them.
  -- Flooding the passability model out of every arrival tile (150 nodes per
  -- frame, because a whole flood in one Lua slice trips Mesen's script
  -- watchdog silently) partitions it as:
  --   F  (8,13)/(19,16)   exits (7,13)->95, (19,17)->96
  --   D  (35,7)/(44,24)/(51,33), 166 tiles -- exits (43,24)/(50,33)/(34,7)
  --                       ->96 and (56,7)->100(30,36)
  --   E  (30,36), 28 tiles -- exit (31,36)->100(57,7), i.e. back into D
  --   B  (58,46), 87 tiles -- exits (30,52)->102, (58,45)->97
  --   C  (9,36), 31 tiles  -- exits (7,29)->102, (9,37)->96
  --   A  (8,48), 60 tiles  -- exits (7,48)->98, (17,59)->101 (the east exit)
  -- and map 96 into four: P (16,22)/(21,21), R (14,12), Q (25,16),
  -- S (28,25), each with one or two exits back to a named shelf.
  -- So (7,48)->98, which the entrance table lists as "map 100 -> Vargas's
  -- map", lives in shelf A, and nothing in the graph reaches A except map 98
  -- itself.  Walking in through it is impossible; it is the way out, and
  -- Vargas's walk-on parks him on top of it.
  -- The link that does work is a long entrance, which is why reading only the
  -- short table dead-ends the mountain in D: map 96 (12,8), vertical, length
  -- 1 -> map 102 (51,46).  From 102 the bridge drops back onto shelf B, and
  -- B carries the summit chain 97 -> 103 -> 98.
  planAvoidsRow(11, 26, 37, "map 95 -> (11,26)"),
  crossTo(11, 26, 100, "K1 entrance -> shelf F", "tactical"),
  crossTo(19, 17, 96, "K2 shelf F -> cave 96 P", "tactical"),
  crossTo(22, 21, 100, "K3 cave 96 P -> shelf D", "tactical"),
  crossTo(34, 7, 96, "K4 shelf D -> cave 96 R", "tactical"),
  crossTo(12, 8, 102, "K5 cave 96 R -> the bridge (LONG entrance)", "tactical"),
  crossTo(35, 50, 100, "K6 bridge -> shelf B", "tactical"),
  crossTo(58, 45, 97, "K7 shelf B -> cave 97", "tactical"),
  crossTo(55, 10, 103, "K8 cave 97 -> the summit", "tactical"),
  crossTo(60, 9, 98, "K9 summit -> VARGAS's ledge", "tactical"),

  -- ===================================================================== --
  -- PHASE 5: the Vargas entry point.  The party lands on map 98 at (11,10);
  -- the approach trigger is (10,32)/(11,32) -> _ca8267 (event_main.asm
  -- :19794, event_trigger.asm _98), gated on $010A.  It sets $010A/$031C,
  -- creates NPC_1 and runs him ASYNC from (29,35) around to (23,32) facing
  -- left (:19802-19816), which puts him on the tile back to map 100, so he
  -- blocks the retreat.  There is no player_ctrl_off in that event, so
  -- control never leaves.
  -- Then walk back east to (22,32), the tile beside him, and generate: one
  -- interaction (face right, press A -> _ca828f) short of `battle 66`.
  -- Vargas is object 16, not 17: object number is map-NPC index + 16 and
  -- NPCProp::_98 holds exactly one record (npc_prop.asm:4006, {23,32},
  -- spawn $031C, `set_npc_event _ca828f`), so he is index 0.  Watching 17
  -- waits on an object that does not exist; that was measured as 20000
  -- frames of a party standing correctly at (11,32) with $010A already set.
  -- ===================================================================== --
  H.call(function()
    H.assertEq(map(), 98, "on map 98")
    H.assertEq(sw(0x010A), 0, "$010A still clear -- Vargas has not appeared")
    where("map 98 arrival")
  end),
  care("map 98 arrival"),
  -- Map 98 is fought, not fled, and that is a measured decision.  Its
  -- encounter group is 62 (Trilium pairs, and Trilium + Tusker + two
  -- Cirpius), and the approach is 96 steps followed by another 53, the
  -- longest unbroken walk on the route.  Running from those formations means
  -- standing still and being hit for as many rounds as the run roll takes:
  -- measured 2026-08-09, the party crossed the whole mountain at full hp
  -- under the care layer and then lost LOCKE outright (122 -> 0) on the
  -- final 53 steps, and with no Fenix Down in the bag no amount of care can
  -- answer that.  A player walking this ledge kills Triliums, which are weak
  -- enemies with two shields.  So these three steps run
  -- playBattles="tactical", using the real command menus, EDGAR's Tools,
  -- boosted Fights, and the fight driver's own Potion medic line at 35%, and
  -- the party arrives having fought the mountain rather than absorbed it.
  H.navTo(11, 32, { maxFrames = 40000, playBattles = "tactical",
    reserve = { [POTION] = 5 },
    arrive = function() return sw(0x010A) == 1 end }),
  H.release(),
  H.advanceStory(function()
    return H.hasControl() and H.tileAligned() and sw(0x010A) == 1
       and objX(16) == 23 and objY(16) == 32
  end, 20000, { playBattles = "tactical", reserve = { [POTION] = 5 } }),
  H.call(function()
    H.assertEq(sw(0x010A), 1, "the approach trigger ran ($010A set)")
    H.assertEq(sw(0x031C), 1, "$031C set (Vargas NPC armed)")
    H.log(string.format("VARGAS (obj 16) at (%d,%d)", objX(16), objY(16)))
    where("vargas spawned")
    H.screenshot("vargas_spawn")
  end),
  care("vargas spawned"),

  H.navTo(22, 32, { maxFrames = 40000, playBattles = "tactical",
                    reserve = { [POTION] = 5 } }),
  H.release(),
  -- Face him.  NPC activation is decided by the party facing byte ($087F
  -- through the $0803 party-object offset; 0 up 1 right 2 down 3 left, from
  -- the four movement branches at player.asm:456-505) and a two-frame turn
  -- press does not set it; gen_edgar measured 1800 frames of A against a
  -- mis-faced Edgar.  So hold right until the byte reads 1, and leave the
  -- state facing him, so the fight test only has to press A.
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

  -- The last care stop, and the one the fight depends on: the walk from the
  -- approach trigger to his tile is 53 steps through Trilium/Tusker
  -- encounters, and is where TERRA died on the 2026-08-06 chain.  Heal here,
  -- then re-establish the facing.  The menu visit should not have changed it,
  -- but the fixture's contract checks rather than assumes.
  care("vargas entry point", 0.95),
  H.driveUntil(function()
    return H.readByte(0x087f + H.readWord(0x0803)) == 1
       and H.hasControl() and H.tileAligned()
       and H.fieldX() == 22 and H.fieldY() == 32
  end, 900, {
    H.hold({ "right" }), H.waitFrames(4),
  }, "face VARGAS again after the care stop"),
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
    -- the tools this route carries to the fight
    H.assertEq(invCount(0xA4), 1, "BioBlaster still carried (the poison key)")
    H.assertEq(invCount(0xA3), 1, "NoiseBlaster still carried")
    H.assertEq(invCount(0xAA), 1, "AutoCrossbow still carried")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d mp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11),
          H.readWord(base + 13), H.readWord(base + 15)))
      end
    end
    -- The entry point contract (issue #75).  A fixture that hands gen_vargas
    -- a dead character and a one-hit-point EDGAR has already lost the fight.
    -- The 2026-08-06 chain shipped that and the four losses were attributed
    -- to the fight instead.  So the walk has to deliver a party that can
    -- fight, and check it here rather than three edges downstream: everyone
    -- alive, and nobody below half hp.  A failure here means the route ran
    -- out of supplies, which is worth knowing and is not a reason to widen
    -- the bound.
    for _, c in ipairs(H.partyMembers()) do
      H.assertEq(H.charHp(c) > 0, true,
        string.format("char %d reached VARGAS alive", c))
      H.assertEq(H.charHp(c) * 2 >= H.charMaxHp(c), true,
        string.format("char %d is at or above half hp (%d/%d)",
          c, H.charHp(c), H.charMaxHp(c)))
    end
    -- MP is part of the same contract, and it was the half nobody wrote
    -- down.  HP was checked here and MP was not, so a chain that arrived
    -- with TERRA at 21 of 46 MP passed this gate and lost battle 66 three
    -- edges later, where it read as a hard fight rather than as a route
    -- that had spent the fight's healing on the walk to it.
    --
    -- The bar is TERRA's, because she is the only member of this party who
    -- knows Cure and therefore the fight's only healer once the Potions thin
    -- out.  It is two thirds of her own maximum rather than an absolute so it
    -- survives her levelling, and two thirds is where the measured win/loss
    -- boundary is: 26 of 46 lost battle 66, 31 and 46 won, and two thirds of
    -- 46 is 31.  The care stops above ration to a 0.75 floor, deliberately
    -- above this bar, so a healthy run clears it with room and this fires
    -- only when the segment's MP budget has actually moved.  If it fires,
    -- the answer is to stop spending her MP on the climb, not to lower the
    -- number.
    local terra = 0
    H.assertEq(H.charMaxMp(terra) > 0, true, "TERRA has an MP pool to check")
    H.assertEq(H.charMp(terra) * 3 >= H.charMaxMp(terra) * 2, true,
      string.format("TERRA reaches VARGAS with her Cure line intact " ..
        "(%d/%d mp)", H.charMp(terra), H.charMaxMp(terra)))
    -- The party also still has a way to answer a death.  gen_vargas raises
    -- TERRA after the fight; an entry point with an empty bag makes that
    -- impossible, and the failure would surface an edge later.
    H.assertEq(invCount(0xF0) >= 1, true,
      string.format("a Fenix Down is still in reserve for the fight (%d)",
        invCount(0xF0)))
    -- the rows the shop stop set are still set (nothing on this mountain
    -- rearranges the party, and if something did we want to know here)
    H.assertEq((H.readByte(0x1850 + 0) & 0x20) ~= 0, true, "TERRA back row")
    H.assertEq((H.readByte(0x1854 + 0) & 0x20) ~= 0, true, "EDGAR back row")
    H.assertEq((H.readByte(0x1851 + 0) & 0x20) == 0, true, "LOCKE front row")
    where("vargas entry point")
    H.screenshot("vargas_entry")
  end),
  H.saveState("vargas_entry.mss"),
  H.logStep(function()
    return string.format("vargas_entry generated at frame %d", H.frame)
  end),
})
