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

H.run({ maxFrames = 400000 }, {
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
