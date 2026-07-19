-- gen_edgar.lua -- THE WHOLE FIGARO CHAPTER, from figaro_doorstep.mss
-- (TERRA + LOCKE at map 55 (28,42), the castle gate) to the world map
-- outside the sand.  Walk in, BUY THE TOOLS in the only window the game
-- ever offers, take the throne-room audience with EDGAR, cross the castle
-- to the MATRON and ride her flashback (the beat that puts Edgar back on
-- his throne), take the second audience into KEFKA's arrival, work the
-- confrontation, LOCKE's regroup and the burning night, and finally let
-- the castle submerge and ride the chocobos out.  Mints three states:
--   figaro_intro.mss    after the first audience ($0004 set)
--   figaro_matron.mss   after the flashback ($0308 set again)
--   figaro_cleared.mss  first controllable frame on the world map,
--                       TERRA + LOCKE + EDGAR, tools carried
--
-- ROUTING IS DONE FROM THE ENTRANCE TABLES, not by exploring: every
-- crossDoor below names a real record in ff6/src/field/trigger/
-- short_entrance.dat (6-byte records, srcX/srcY/map/flags/dstX/dstY per
-- field/short_entrance.inc), indexed per map by the _N offsets in that
-- .inc.  The castle's whole door graph is 12 records on map 55, 23 on 59,
-- 2 each on 57 and 60, and one 2-tile LONG entrance out of the throne
-- room -- which is what makes the "disconnected regions" note below
-- checkable rather than folklore.
--
-- THE MECHANISM (why "talk to Edgar twice" is not the story; every line
-- number is ff6/src/event/event_main.asm unless said otherwise):
--   * The throne Edgar NPC (map 58 (101,42), spawn switch $0308,
--     npc_prop.asm:2625) runs _ca6623, which forks on $0004 (:15211).
--     With $0004=0 that is the intro flirt scene -- it hands over the
--     AutoCrossbow and opens `name_menu EDGAR` (:15312-15313) -- and it
--     ENDS by setting `$0004=1 / $0308=0 / $030D=0 / $030E=1 / $0315=1`
--     (:15446-15450).  $0308=0 despawns Edgar: the throne room is empty
--     and nothing on maps 55/58/59 brings him back.
--   * The respawn lives on MAP 57: the matron (OLD_WOMAN at (58,21),
--     spawn $030F, npc_prop.asm:2602) runs _ca6c85.  It is gated
--     `if_switch $0049=1 -> _ca6d5f` / `if_switch $0005=1 -> _ca6d5b`,
--     so it only fires fresh while both are clear, and its first four
--     commands are `$0308=1 / $0316=1 / $01CC=1 / $0005=1` (:16226-16229).
--     :16226 is the ONLY `switch $0308=1` in the bank.  Then the Sabin
--     coin-toss flashback plays (map 60, `name_menu SABIN` :16330) and
--     drops the party back at map 57 (59,21) (:16338).
--   * Back on the throne with $0004=1, _ca6623 branches to _ca6d63
--     (:16367): Kefka arrives, `$0311=1 / $03FE=1 / $0315=0 / $01CC=1`
--     (:16392-16395), the party becomes EDGAR alone (:16396-16407) and
--     control returns in the courtyard with `player_ctrl_on / $0308=0`
--     (:16638-16639).
--   * The confrontation needs BOTH trooper switches: _ca6f02 bails unless
--     $01F0 and $01F1 are set (:16659-16663), so BOTH troopers get talked
--     to (_ca6ee6 -> $01F0 :16646, _ca6ef2 -> $01F1 :16656).  The gate
--     scene _ca714c also sets $01F0 on the way in (:17081) -- but that is
--     worthless here, see the map-local switches note below.  Kefka's
--     scene then ends `player_ctrl_on / $03FE=0 / $0006=1` (:16722-25).
--
-- MAP-LOCAL SWITCHES (measured this run, and the reason a first attempt
--   asserted a set $01F0 and read 0): LoadMap zeroes $1EBE/$1EBF on every
--   load of a DIFFERENT map -- `stz $1ebe ; unused` / `stz $1ebf`,
--   ff6/src/field/init.asm:470-471, guarded by $58 (re-load of the same
--   map).  Those two bytes are event switches $01F0..$01FF, so that whole
--   range is per-map scratch, not story state.  The gate scene's $01F0
--   therefore dies at the very next door, and the Kefka gate has to be
--   satisfied from inside map 55 -- both troopers, after his arrival.
--   ($01F8, the burning-night marker, is safe for the opposite reason:
--   _ca700e sets it AFTER its last load_map, and the guard we then talk
--   to is on that same map.)
--   * LOCKE at (28,15) (_ca6f60, needs $0006=1) brings TERRA back and
--     ends `$0311=0 / $0313=1 / $0315=1 / $01FF=1 / $0008=1` (:16842-46).
--     $0313 arms the guest-room LOCKE at map 59 (82,45)
--     (npc_prop.asm:2693) whose talk (_ca700e) runs the whole burning
--     night: the party becomes EDGAR alone again, map 55 reloads at night
--     with STARTUP_EVENT, and it ends `$01F8=1 / player_ctrl_on` (:17071).
--   * The submerge is NOT a trigger: it is the courtyard guard at (24,16)
--     (spawn $0315, npc_prop.asm:2372) whose event _ca5f9f forks on
--     $01F8 (:14288) into _ca5fba -- "EDGAR: Get ready…!", the three
--     chocobos (`vehicle ... CHOCOBO` :14330-14405) and finally
--     `load_map 0, {64,76}` (:14731), the world map outside the sand.
--
-- THE SHOP (bought here, in the only window that exists): the tool
--   merchant at map 59 (44,15) (npc_prop.asm:2737) opens `shop_menu 82`
--   (:15496) -- but _ca67c0 opens `set_case PARTY_CHARS / case EDGAR ->
--   _ca67de` (:15489-15492), so once EDGAR (or SABIN) is in the party the
--   merchant refuses ("I can't take money from the King!") and no shop
--   ever opens.  EDGAR joins in the Kefka scene, so the purchase has to
--   happen before it -- i.e. on the FIRST trip up, while the party is
--   still TERRA + LOCKE.  Shop 82 stocks AutoCrossbow $AA / NoiseBlaster
--   $A3 / BioBlaster $A4 (shop_prop.dat record 82 = 33 aa a3 a4 ff...);
--   the AutoCrossbow arrives free in the intro (`give_item AUTOCROSSBOW`
--   :15310), so the gil goes on the BioBlaster (750, the rung-2 poison
--   key) and the NoiseBlaster (500).
--
-- THE CASTLE IS NOT ONE WALKABLE PLACE.  This is the part that cost the
--   most measuring, and no amount of reading short_entrance.dat gives it
--   to you: a Figaro "map" is several DISCONNECTED walking regions that
--   only reach each other through doors.  Map 55 alone has three --
--     * the gate pocket, 13 tiles: (27..29, 39..43) plus the door
--       (28,38).  That is all figaro_doorstep can walk to.  Its south
--       edge y=43 is map 55's world-exit border (long entrance
--       (0,43) len 63 -> the world), so BFS happily plans through it and
--       a walker who trusts BFS leaves the castle;
--     * the inner courtyard (y 13..32, x 21..35), whose only doors are
--       (28,32), (28,13), (23,24) and (33,24);
--     * the outer ring, 1781 tiles around the whole castle, which is the
--       ONLY region carrying the west tower doors (12,19)/(12,26) into
--       the matron's map 57 and the east tower doors (44,19)/(44,26)
--       into the guest wing.
--   Nothing on map 55 connects the courtyard to the ring, and the door
--   graph alone does not either: a DFS that BFS-probed every door of every
--   map it landed on visited 14 rooms without once reaching the ring.  The
--   throne hall's tower stair 59 (23,9) -> (120,14) -> (123,8) drops you
--   on map 55 (29,7), which is an 11-tile roof platform, not the ring;
--   55 (23,24) -> 59 (47,60) is a dead-end chamber.
--
--   THE LINK IS A DIAGONAL STAIRCASE.  Every Figaro staircase is built from
--   tiles whose property byte has $c0 set, where a LEFT or RIGHT press moves
--   the party diagonally (player.asm:379-453).  The library's passability
--   port used to model only the four CARDINAL exits, so those tiles read as
--   solid wall and half the castle was unreachable; the model now ports
--   that branch too (lib/ot6.lua, "true passability model"), and BFS plans
--   and verifies diagonal steps like any other -- validated tile by tile in
--   probe_canstep part 2.  Measured: on map 60 the party standing at
--   (98,24) and simply HOLDING LEFT walks down the stair through (97,25)
--   and (96,26), takes that entrance, and comes out on map 59 at (79,12) --
--   the east wing, whose door (80,18) opens onto the ring at 55 (33,33).
--   So the ring is reachable as
--     55 (33,24) -> 60 (103,29) -> [LEFT from (98,24)] -> 59 (81,11)
--       -> (80,18) -> 55 (33,33) = ring
--   and comes back the mirror way through 59 (82,10) -> 60 (97,25).
--
--   THE RING IS TWO BANDS, which is why the route takes the WEST stair
--   and not the east one:
--     east  (x >= 32), via map 60: carries the guest-wing doors
--                      (44,19)/(44,26);
--     west  (x <= 24), via 59 (66,50): carries the matron doors
--                      (12,19)/(12,26) and (23,31) -> 59 (66,49).
--   The castle block at x=24..32 separates them for y=31..42, and the one
--   row that joins them, y=43, CANNOT BE WALKED ACROSS -- but not for the
--   reason an earlier pass here recorded ("a map border the engine
--   refuses").  Map 55 is 64x64 ($86/$87 = $3f/$3f, map_prop.dat record
--   33*55+23 = $aa), so y=43 is nowhere near an edge, and every tile along
--   it reads p1=$02 / p2=$8f -- ordinary floor, all four exits.  y=43 is
--   map 55's WORLD-EXIT ROW: the long entrance (0,43) length 63 fires on
--   arrival (entrance.asm CheckLongEntrance), and a walker that steps onto
--   it is on the world map a second later.  Measured from figaro_doorstep:
--   one DOWN press from (28,42) lands (28,43), and 84 frames later the
--   party is outside the castle.  What the earlier pass logged as "edge
--   (28,43)->left blocked in reality" was navTo holding a direction during
--   that map load.  So: the matron needs the WEST band, reached by the
--   chamber staircase above, and the guest wing -- which the burning night
--   needs -- takes the map-60 stair instead.  BFS still does not know about
--   entrance triggers; keep route legs off y=43.
--
-- THE ROSTER CHANGES FOUR TIMES, so nothing may read a fixed character
--   slot.  LOCKE leaves during the first audience; the Kefka scene makes
--   the party EDGAR ALONE (`char_party EDGAR, 1 / party_chars EDGAR /
--   char_party TERRA, 0 / delete_obj TERRA`, :16401-16407); LOCKE's
--   regroup hands it back to TERRA alone and DELETES Edgar again
--   (`char_party EDGAR, 0 / delete_obj EDGAR` :16813-16814,
--   `party_chars TERRA` :16818); the burning night makes it EDGAR alone
--   once more (:16944-16949).  Only after the submerge are all three in
--   the party at once (asserted at the mint, by party byte not by slot).
--   Every position read in this script goes through the $0803 party-object
--   offset (H.fieldX/fieldY), which is what makes that survivable.
--
-- OBJECT NUMBERS are map-NPC index + 16, in npc_prop.asm order.  Map 55:
--   19 courtyard guard {24,16} $0315 -> _ca5f9f (the submerge), 20 KEFKA
--   {28,57} $03FE -> _ca6f02, 21/22 the two troopers {27,58}/{29,58}
--   $03FE -> _ca6ee6/_ca6ef2, 27 LOCKE {28,15} $0311 -> _ca6f60.  Map 58:
--   16 is the throne EDGAR.  Map 59: 19 the guest-room LOCKE {82,45}
--   $0313 -> _ca700e, 25 the tool merchant.  The table positions are only
--   where they SPAWN -- Kefka and the troopers walk up from y=57/58 during
--   his scene and are at (28,28)/(29,27)/(27,27) when control returns --
--   so talkTo tracks them by their live object coords, never these.
--
-- DOORS.  Entrance records fire when the party STANDS on the source tile
--   (entrance.asm CheckShortEntrance), but a castle door tile is a WALL
--   until CheckDoor (player.asm:959) swaps the open-door tiles in, and it
--   only does that for a party pressing into it from directly below or
--   above.  So BFS can never plan THROUGH a door: every crossing is
--   navTo(a neighbouring tile) + one continuous hold, and crossDoor
--   derives which neighbour by BFS rather than assuming (Figaro uses all
--   four: 55 (28,38) is entered from below, 59 (27,29) from above,
--   55 (12,19) from the right).  A STAIRCASE entrance is the other kind:
--   its tile is ordinary walkable floor, so BFS routes straight over it
--   and the crossing can happen before the hold ever starts -- crossDoor
--   treats a map change during its approach as arrival for that reason.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/figaro_doorstep.mss.lua"

-- event switch id -> live bit (event bitfield base $1E80, bit = id & 7)
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
-- field object i's live tile (pixel coords >> 4, block stride $29)
local function objX(i) return H.readWord(0x086a + 0x29 * i) >> 4 end
local function objY(i) return H.readWord(0x086d + 0x29 * i) >> 4 end
-- map compares stay MASKED: loaders ride flag bits in $1F64's high byte
local function map() return H.mapId() & 0x1ff end
local function gil()
  return H.readByte(0x1860) + H.readByte(0x1861) * 256 + H.readByte(0x1862) * 65536
end
local function invCount(id)
  for i = 0, 255 do
    if H.readByte(0x1869 + i) == id then return H.readByte(0x1969 + i) end
  end
  return 0
end
-- a menu module owns the CPU (the field's own "menu opening" flag; safe
-- here because no battle happens anywhere in the castle to alias it --
-- the caveat gen_moogle documents)
local function menuUp() return H.readByte(0x0059) ~= 0 end

local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

-- calm()'s world-module twin, for after the submerge: the overworld is a
-- separate engine with its own position and control registers, and every
-- field predicate above reads meaningless RAM there (docs/research/
-- world-map-nav.md).
--
-- THE BRIGHTNESS TERM IS LOAD-BEARING, and n is 120 rather than 30.  The
-- submerge cutscene VISITS the world map in the middle of itself --
-- `load_map 0, {64,76}` (event_main.asm:14731) is the shot of the castle
-- going under, and sixteen frames later :14737 loads map 55 straight back.
-- During that visit the world module is up, no world event is running yet
-- and $19/$E8 are clear, so worldHasControl() is TRUE for ~56 frames on a
-- fully black screen (measured: brightness 0 throughout, then the event
-- engine takes $E7 bit0 at +56 and the screen only lights afterwards).
-- A 30-frame calm window latched onto exactly that and minted a state
-- 5700 frames early.  Requiring control and a lit screen SIMULTANEOUSLY
-- rejects it, because the two never overlap during the transient.
local function worldCalm(n)
  local cnt = 0
  return function()
    local ok = H.worldMode() and H.worldHasControl() and H.worldAligned()
      and (emu.getState()["ppu.screenBrightness"] or 0) >= 15
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

local function where(tag)
  H.log(string.format(
    "[%s] f%d map=%d (%d,%d) $0004=%d $0005=%d $0006=%d $0308=%d $0311=%d " ..
    "$0313=%d $0315=%d $01F0=%d $01F1=%d $01F8=%d gil=%d party=%d%d%d%d%d%d",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0004), sw(0x0005),
    sw(0x0006), sw(0x0308), sw(0x0311), sw(0x0313), sw(0x0315), sw(0x01F0),
    sw(0x01F1), sw(0x01F8), gil(),
    H.readByte(0x1850) & 7, H.readByte(0x1851) & 7, H.readByte(0x1852) & 7,
    H.readByte(0x1853) & 7, H.readByte(0x1854) & 7, H.readByte(0x1855) & 7))
end

-- crossDoor/talkTo/buy expand to SEVERAL steps, and a bare list cannot be
-- spliced into a step list -- Lua truncates a non-final table.unpack to one
-- value, which silently drops every step but the first (measured: run 1
-- walked to a staging tile and then navigated map-59 coords on map 55).
-- H.cond with an always-true predicate is the library's public way to wrap
-- a step list into ONE step object.
local function seq(steps) return H.cond(function() return true end, steps) end

local aPhase = 0

-- Cross the entrance whose SOURCE tile is (sx,sy), landing on map dm at
-- (dx,dy).  Two measured facts shape this:
--   * the door tile is a WALL until CheckDoor opens it, so BFS can never
--     plan through it -- the crossing is navTo(a neighbouring tile) plus
--     one continuous hold into the door;
--   * WHICH neighbour is the staging tile cannot be read off the entrance
--     table.  Figaro's doors are entered from below, above and from the
--     side in roughly equal measure (55 (28,38) from below, 59 (27,29)
--     from above, 55 (12,19) from the right), and a first attempt that
--     assumed "always from below" walked into walls.  So the staging tile
--     and the hold direction are DERIVED: BFS each neighbour and take the
--     first one that is actually reachable right now.
-- The neighbour set is all EIGHT, not four: a door at the head of a
-- staircase can only be entered diagonally.  59 (64,42), the west wing's
-- way back into the chamber, is the worked example -- it sits on the "\"
-- stair (64,42)/(65,43)/(66,44) and its only approach is up-left from
-- (65,43), i.e. a LEFT press.  With four candidates crossDoor fell through
-- to its own default and navTo then spent 20 retries proving there is no
-- path to it.  A diagonal candidate has to clear one extra test: the move
-- must be one the engine would actually produce there (H.canStep), since
-- a left press only goes up-left on a tile that says so.
local DIAGSTAGE = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { -1, 1, "upright" }, { -1, -1, "downright" },
  { 1, -1, "downleft" }, { 1, 1, "upleft" },
}
local function crossDoor(sx, sy, dm, dx, dy, what, fixed)
  local pick, startMap
  local function stage()
    if not pick then
      pick = fixed
      if not pick then
        for _, c in ipairs(DIAGSTAGE) do
          local cx, cy, move = sx + c[1], sy + c[2], c[3]
          local press = H.movePress(move)
          if H.bfsPath(cx, cy)
             and (press == move or H.canStep(cx, cy, move)) then
            pick = { cx, cy, press }; break
          end
        end
      end
      pick = pick or { sx, sy + 1, "up" }
      H.log(string.format("%s: staging (%d,%d), hold %s into (%d,%d)",
        what, pick[1], pick[2], pick[3], sx, sy))
    end
    return pick
  end
  local settled = calm(20)
  return seq({
    H.call(function() pick, startMap = nil, map() end),
    -- The walk to the staging tile can TAKE THE DOOR BY ITSELF.  A
    -- staircase entrance sits on an ordinary walkable tile (unlike a
    -- castle door, which is a wall until CheckDoor opens it), BFS knows
    -- nothing about entrance triggers, and it will happily route across
    -- one: approaching 60 (96,26) from (103,29), the plan crossed the
    -- entrance tile itself and the party was on map 59 before the hold
    -- ever started -- navTo then burned 20 retries looking for a tile on
    -- a map it had already left.  A map change IS arrival; the far-side
    -- assert below still checks it was the right one.
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 9000,
        arrive = function() return map() ~= startMap end }),
    H.driveUntil(function()
      return map() ~= startMap or (H.fieldX() == dx and H.fieldY() == dy)
    end, 1800, {
      H.call(function()
        aPhase = (aPhase + 1) % 8
        if H.dialogWaiting() then H.setPad(aPhase < 4 and { "a" } or {}); return end
        H.setPad({ [stage()[3]] = true })
      end),
    }, what),
    H.release(),
    H.waitUntil(settled, 1800, what .. ": far-side control"),
    H.waitUntil(function()
      return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
    end, 900, what .. ": fade-in", 10),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(map(), dm, what .. ": landed on the right map")
      H.log(string.format("%s: DONE (%d,%d) frame=%d", what,
        H.fieldX(), H.fieldY(), H.frame))
    end),
  })
end

-- Talk to object `obj`.  CheckNPCs (player.asm:142) activates whatever the
-- object map holds ONE TILE IN THE PARTY'S FACING DIRECTION ($087F,y) while
-- A is held ($06 bit7) -- so facing is the entire trick, and it is the part
-- a first attempt got wrong: a 2-frame directional tap does not turn the
-- party at all (measured at the throne, 1800 frames of A pressed while
-- facing LEFT at an Edgar standing NORTH), while a 30-frame hold turns it
-- and the very next A fires the event.  So the drive HOLDS the direction
-- until the facing byte actually reads the wanted value, and only then
-- edge-taps A (4 on / 4 off -- activation is edge-driven like dialogs).
-- Facing encoding, from the four movement branches at player.asm:456-505:
-- 0 up, 1 right, 2 down, 3 left.
local FACE = { up = 0, right = 1, down = 2, left = 3 }

local function talkTo(obj, what, maxFrames)
  local engaged = false
  local function objAt() return objX(obj), objY(obj) end
  local function adjacent()
    local ox, oy = objAt()
    return math.abs(ox - H.fieldX()) + math.abs(oy - H.fieldY()) == 1
  end
  local function facing()
    return H.readByte(0x087f + H.readWord(0x0803))
  end
  -- first adjacent tile BFS can currently reach; re-resolved at most every
  -- 30 frames because NPCs wander (the gen_moogle marshalApproach idiom)
  local apFrame, apPick = -1000, nil
  local function approach()
    if H.frame - apFrame >= 30 then
      apFrame = H.frame
      local ox, oy = objAt()
      local cand = { { ox, oy + 1 }, { ox, oy - 1 }, { ox - 1, oy }, { ox + 1, oy } }
      apPick = cand[1]
      for _, c in ipairs(cand) do
        if H.bfsPath(c[1], c[2], NAV.blocked) then apPick = c; break end
      end
    end
    return apPick
  end
  local function walkStep()
    return H.navTo(function() return approach()[1] end,
                   function() return approach()[2] end, {
      arrive = function()
        return engaged or (adjacent() and H.hasControl() and H.tileAligned())
      end,
      maxFrames = maxFrames or 9000,
    })
  end
  -- One activation attempt.  Soft rounds give up quietly (the NPC wandered
  -- off; walk back and try again); the last round is hard and raises.
  local function pokeStep(round, budget, hard)
    local started, waited, aPh = 0, 0, 0
    return H.driveUntil(function()
      started = (H.eventRunning() or H.dialogWaiting() or menuUp())
        and started + 1 or 0
      if started >= 8 then engaged = true; return true end
      waited = waited + 1
      return not hard and waited > budget
    end, budget + 120, {
      H.call(function()
        aPh = (aPh + 1) % 8
        if waited % 300 == 0 then
          local ox, oy = objAt()
          H.log(string.format("  %s: f%d me=(%d,%d) npc=(%d,%d) adj=%s ctl=%s face=%d",
            what, H.frame, H.fieldX(), H.fieldY(), ox, oy, tostring(adjacent()),
            tostring(H.hasControl()), facing()))
        end
        if not (H.hasControl() and adjacent()) then H.setPad({}); return end
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
    H.logStep(function()
      local ox, oy = objAt()
      return string.format("%s: object %d at (%d,%d); party at (%d,%d) f%d",
        what, obj, ox, oy, H.fieldX(), H.fieldY(), H.frame)
    end),
    walkStep(), pokeStep(1, 600, false),
    -- round 2, written out FLAT: repeatN cannot replay navTo/driveUntil
    -- bodies (their latched state carries over)
    H.cond(function() return not engaged end,
      { walkStep(), pokeStep(2, 900, true) }, {}),
    H.logStep(function()
      return string.format("%s: engaged at frame %d", what, H.frame)
    end),
  })
end

-- A naming menu (name_menu EDGAR :15313, name_menu SABIN :16330) is the one
-- beat advanceStory cannot tap: it suspends the field module entirely.
-- START commits the default name (name_change.asm exits on START unless the
-- name is blank), pressed on repeat until the event engine resumes --  a
-- single press during the menu's own fade would simply vanish.
local function commitName(tag)
  local running = 0
  return seq({
    H.advanceStory(menuUp, 20000),
    H.waitFrames(180),
    H.call(function()
      H.log(string.format("%s: naming menu open at f%d ($59=%d, menu state $%02X)",
        tag, H.frame, H.readByte(0x0059), H.readByte(0x0026)))
      H.screenshot(tag)
    end),
    H.driveUntil(function()
      running = (H.eventRunning() and not menuUp()) and running + 1 or 0
      return running >= 10
    end, 1800, {
      H.pressButtons({ "start" }, 8),
      H.waitFrames(12),
    }, tag .. ": name committed, event resumed"),
  })
end

-- ------------------------------------------------------------------ shop --
-- Every press waits for the menu state it expects: blind timed taps
-- desynced on the second purchase (measured -- the post-buy "Thank you"
-- wait state $28 swallowed them).  States (src/menu/shop.asm): $25
-- options, $26 buy list, $27 quantity, $28 post-buy wait -> $26.  The
-- cursor row is $4B ($53*$4e+$4d, CalcShortListIndex); row r's item id is
-- $7E9D89+r and its price $7E9F09+2r (both filled entering the buy list).
local function mstate() return H.readByte(0x0026) end
local function shopRow() return H.readByte(0x004b) end
local function rowItem(r) return H.readByte(0x9d89 + r) end
local function inState(s) return function() return mstate() == s end end

local function shopPress(btn, pred, what)
  return seq({
    H.pressButtons({ btn }, 6),
    H.waitUntil(pred, 900, "shop: " .. what, 2),
  })
end

local function buyItem(id, fromRow, toRow, price)
  local before = 0
  local steps = {}
  local stride = toRow > fromRow and 1 or -1
  for r = fromRow + stride, toRow, stride do
    steps[#steps + 1] = shopPress(stride > 0 and "down" or "up",
      (function(rr) return function() return shopRow() == rr end end)(r),
      string.format("cursor -> row %d", r))
  end
  steps[#steps + 1] = H.call(function()
    before = gil()
    H.assertEq(rowItem(shopRow()), id,
      string.format("shop cursor on item $%02X (row %d)", id, shopRow()))
  end)
  steps[#steps + 1] = shopPress("a", inState(0x27), "quantity window")
  steps[#steps + 1] = shopPress("a", function() return gil() < before end,
    string.format("purchase $%02X", id))
  steps[#steps + 1] = H.waitUntil(inState(0x26), 900, "shop: back to buy list", 2)
  steps[#steps + 1] = H.call(function()
    H.assertEq(before - gil(), price, string.format("$%02X cost", id))
    H.assertEq(invCount(id) >= 1, true, string.format("$%02X in inventory", id))
  end)
  return seq(steps)
end

H.run({ maxFrames = 120000 }, {
  H.loadState(DOOR),
  H.waitFrames(10),
  H.waitUntil(calm(10), 600, "doorstep control", 5),
  H.call(function()
    H.assertEq(map(), 55, "boot map is the Figaro courtyard (55)")
    H.assertEq(H.fieldX() == 28 and H.fieldY() == 42, true, "at the gate (28,42)")
    H.assertEq(sw(0x0004), 0, "$0004 clear (Edgar intro unseen)")
    H.assertEq(sw(0x0308), 1, "$0308 set (throne Edgar spawned)")
    H.assertEq(sw(0x030F), 1, "$030F set (matron spawned)")
    H.assertEq(sw(0x0005), 0, "$0005 clear (flashback unseen)")
    H.assertEq(sw(0x0049), 0, "$0049 clear (matron's later branch dark)")
    where("start")
  end),

  -- ==================================================================== --
  -- PHASE 1: gate -> entrance hall -> throne wing.  The first step north
  -- fires the gate scene (_ca714c): it parks the guard NPC on (28,40), the
  -- only northward tile, for the length of its two dialogs -- navTo's
  -- no-path patience is exactly what rides that out.
  -- ==================================================================== --
  crossDoor(28, 38, 59, 12, 49, "D1 gate -> gatehouse"),
  crossDoor(12, 41, 55, 28, 31, "D2 gatehouse -> inner courtyard"),
  crossDoor(28, 13, 59, 27, 28, "D3 inner courtyard -> throne hall"),
  H.call(function() where("throne hall") end),

  -- ==================================================================== --
  -- PHASE 2: the shop, in its only window (TERRA + LOCKE, pre-Edgar).
  -- ==================================================================== --
  crossDoor(32, 21, 59, 44, 18, "D4 throne hall -> shop alcove"),
  talkTo(25, "tool merchant", 6000),
  H.waitUntil(inState(0x25), 900, "shop: options menu", 2),
  H.call(function() H.screenshot("edgar_shop") end),
  shopPress("a", inState(0x26), "buy list open"),
  H.call(function()
    local rows = {}
    for r = 0, 4 do
      rows[#rows + 1] = string.format("%d:$%02X@%d", r, rowItem(r),
        H.readWord(0x9f09 + r * 2))
    end
    H.log("shop 82 stock: " .. table.concat(rows, " "))
    H.assertEq(rowItem(0), 0xAA, "row 0 is AutoCrossbow")
    H.assertEq(rowItem(1), 0xA3, "row 1 is NoiseBlaster")
    H.assertEq(rowItem(2), 0xA4, "row 2 is BioBlaster")
  end),
  buyItem(0xA4, 0, 2, 750),               -- BioBlaster: the poison key
  buyItem(0xA3, 2, 1, 500),               -- NoiseBlaster
  shopPress("b", inState(0x25), "back to options"),
  shopPress("b", function() return H.hasControl() end, "shop closed"),
  H.call(function()
    H.assertEq(invCount(0xA4), 1, "BioBlaster bought")
    H.assertEq(invCount(0xA3), 1, "NoiseBlaster bought")
    where("shop done")
  end),
  crossDoor(44, 19, 59, 32, 23, "D5 shop alcove -> throne hall"),

  -- ==================================================================== --
  -- PHASE 3: the throne room, first talk -- the flirt intro, the free
  -- AutoCrossbow and `name_menu EDGAR`.  Done when $0004 flips.
  -- ==================================================================== --
  crossDoor(27, 13, 58, 102, 55, "D6 throne hall -> THRONE ROOM"),
  talkTo(16, "EDGAR (intro)", 9000),
  commitName("edgar_naming"),
  H.advanceStory(calm(30, function() return sw(0x0004) == 1 end), 20000),
  H.call(function()
    H.assertEq(sw(0x0004), 1, "intro ran ($0004 set)")
    H.assertEq(sw(0x0308), 0, "throne Edgar despawned ($0308 clear)")
    H.assertEq(invCount(0xAA), 1, "AutoCrossbow handed over by the intro")
    where("intro done")
    H.screenshot("edgar_intro_done")
  end),

  -- ==================================================================== --
  -- PHASE 4: assert the far side and mint.
  -- ==================================================================== --
  H.call(function()
    H.assertEq(map(), 58, "still in the throne room")
    H.assertEq(sw(0x0004), 1, "$0004 set")
    H.assertEq(sw(0x0308), 0, "$0308 clear")
    H.assertEq(sw(0x0315), 1, "$0315 set (the courtyard guard is armed)")
    H.assertEq(invCount(0xA4), 1, "BioBlaster carried")
    H.assertEq(invCount(0xA3), 1, "NoiseBlaster carried")
    H.assertEq(invCount(0xAA), 1, "AutoCrossbow carried")
    H.assertEq(gil(), 3974, "gil after the two purchases")
    for c = 0, 5 do
      local base = 0x1600 + 37 * c
      H.log(string.format("char %d: actor=%02X level=%d hp=%d/%d party=%d",
        c, H.readByte(base), H.readByte(base + 8), H.readWord(base + 9),
        H.readWord(base + 11) & 0x3fff, H.readByte(0x1850 + c) & 7))
    end
    H.screenshot("figaro_intro")
  end),
  H.saveState("figaro_intro.mss"),
  H.logStep(function()
    return string.format("figaro_intro minted at frame %d", H.frame)
  end),

  -- ==================================================================== --
  -- PHASE 5: THE MATRON -- the beat both earlier attempts died on.  Her
  -- room (map 57) hangs off the castle's WEST ring, and the only way onto
  -- that ring is the chamber behind 55 (23,24): its floor reaches (48,58)
  -- and from there one continuous RIGHT walks a diagonal staircase through
  -- (49,59)/(50,60), takes 59 (50,60) -> 59 (65,43) and carries on into
  -- the west wing.  The wing's door (66,50) is the ring's west band.
  -- (The EAST ring, reached the mirror way through map 60, carries the
  -- guest-wing doors instead; the castle block at x=24..32 keeps the two
  -- bands apart and the row that joins them, y=43, is map 55's world-exit
  -- trigger row -- see the header.)
  -- ==================================================================== --
  crossDoor(102, 56, 59, 27, 15, "D7 throne room -> throne hall"),
  crossDoor(27, 29, 55, 28, 15, "D8 throne hall -> inner courtyard"),
  crossDoor(23, 24, 59, 47, 60, "D9 inner courtyard -> west chamber"),
  -- D10 is the chamber's diagonal staircase, and with the model reading
  -- the engine's diagonal branch it is an ordinary door crossing: BFS
  -- walks (48,58)->(49,59) itself and crossDoor's staging search finds
  -- the diagonal approach on its own.
  crossDoor(50, 60, 59, 65, 43, "D10 west chamber -> west wing"),
  crossDoor(66, 50, 55, 23, 33, "D12 west wing -> WEST RING"),
  crossDoor(12, 26, 57, 67, 27, "D13 west ring -> matron's room"),
  H.call(function() where("matron's room") end),

  -- Her room's own staircase (the "\" tiles (66,26)/(65,25)/(64,24)) needed
  -- three more hand-holds before the fix -- the (67,27) arrival flooded to
  -- FOUR tiles.  talkTo's own navTo crosses it now: BFS finds an 11-step
  -- plan from (67,27) to her doorstep, two of them diagonal (probe_canstep).
  talkTo(17, "MATRON", 9000),
  commitName("sabin_naming"),
  H.advanceStory(calm(30, function()
    return map() == 57 and sw(0x0005) == 1
  end), 30000),
  H.call(function()
    H.assertEq(sw(0x0005), 1, "flashback ran ($0005 set)")
    H.assertEq(sw(0x0308), 1, "EDGAR RESPAWNED on the throne ($0308 set)")
    H.assertEq(sw(0x0316), 1, "$0316 set (chancellor armed)")
    H.assertEq(map(), 57, "back in the matron's room")
    where("flashback done")
    H.screenshot("figaro_matron")
  end),
  H.saveState("figaro_matron.mss"),
  H.logStep(function()
    return string.format("figaro_matron minted at frame %d", H.frame)
  end),

  -- ==================================================================== --
  -- PHASE 6: back to the throne for the SECOND AUDIENCE.  The west band
  -- is a cul-de-sac: its only way out is the wing door 55 (23,31), so the
  -- return re-crosses the chamber staircase from the other side.  That
  -- one is D-K3 below and it is the door the four-neighbour staging
  -- search could not find: 59 (64,42) sits on the "\" stair
  -- (64,42)/(65,43)/(66,44) and is reachable ONLY up-left from (65,43).
  -- ==================================================================== --
  crossDoor(67, 28, 55, 12, 28, "K1 matron's room -> WEST RING"),
  crossDoor(23, 31, 59, 66, 49, "K2 west ring -> west wing"),
  crossDoor(64, 42, 59, 49, 59, "K3 west wing -> west chamber (stair)"),
  crossDoor(47, 61, 55, 23, 26, "K4 west chamber -> inner courtyard"),
  crossDoor(28, 13, 59, 27, 28, "K5 inner courtyard -> throne hall"),
  crossDoor(27, 13, 58, 102, 55, "K6 throne hall -> THRONE ROOM"),
  H.call(function() where("second audience") end),

  -- ==================================================================== --
  -- PHASE 7: KEFKA.  With $0004=1 the throne Edgar's _ca6623 forks to
  -- _ca6d63 (:16367): the messenger, Kefka's arrival, $0311=1 / $03FE=1 /
  -- $0315=0 (:16392-16394), the party becomes EDGAR alone and control
  -- returns out in the courtyard (`player_ctrl_on / $0308=0`, :16638).
  -- ==================================================================== --
  talkTo(16, "EDGAR (second audience)", 9000),
  H.advanceStory(calm(30, function()
    return map() == 55 and sw(0x0311) == 1
  end), 30000),
  H.call(function()
    H.assertEq(sw(0x0311), 1, "Kefka scene ran ($0311 set)")
    H.assertEq(sw(0x0315), 0, "$0315 cleared by the scene")
    H.assertEq(map(), 55, "control returns in the courtyard")
    where("Kefka arrived")
    H.screenshot("figaro_kefka")
  end),

  -- ==================================================================== --
  -- PHASE 8: the confrontation, then LOCKE's regroup.  _ca6f02 returns
  -- immediately unless BOTH $01F0 and $01F1 are set (:16659-16663), and
  -- those are the two troopers' own switches.  They live in the MAP-LOCAL
  -- $01F0..$01FF range, so the gate scene's $01F0 from Phase 1 died at the
  -- first door and both troopers have to be talked to here, after Kefka
  -- arrives -- talking only one leaves Kefka a no-op with no diagnostic.
  -- ==================================================================== --
  talkTo(21, "trooper east", 9000),
  H.advanceStory(calm(20, function() return sw(0x01F0) == 1 end), 9000),
  H.call(function() H.assertEq(sw(0x01F0), 1, "$01F0 set (east trooper)") end),
  talkTo(22, "trooper west", 9000),
  H.advanceStory(calm(20, function() return sw(0x01F1) == 1 end), 9000),
  H.call(function() H.assertEq(sw(0x01F1), 1, "$01F1 set (west trooper)") end),
  talkTo(20, "KEFKA", 9000),
  H.advanceStory(calm(30, function()
    return map() == 55 and sw(0x0006) == 1
  end), 30000),
  H.call(function()
    H.assertEq(sw(0x0006), 1, "confrontation done ($0006 set)")
    where("Kefka done")
  end),
  talkTo(27, "LOCKE (regroup)", 9000),
  H.advanceStory(calm(30, function()
    return map() == 55 and sw(0x0313) == 1
  end), 30000),
  H.call(function()
    H.assertEq(sw(0x0313), 1, "$0313 set (guest-room LOCKE armed)")
    H.assertEq(sw(0x0315), 1, "$0315 set (courtyard guard re-armed)")
    H.assertEq(sw(0x01FF), 1, "$01FF set (regroup done)")
    where("regrouped")
  end),

  -- ==================================================================== --
  -- PHASE 9: the burning night.  The guest-room LOCKE (map 59 (82,45),
  -- spawn $0313) runs _ca700e, which is the whole night: the party becomes
  -- EDGAR alone again, map 55 reloads at night with STARTUP_EVENT, and it
  -- ends `$01F8=1 / player_ctrl_on` (:17070-17071).  He hangs off the EAST
  -- band, so this is the map-60 crossing the west route never needed.
  -- ==================================================================== --
  crossDoor(33, 24, 60, 103, 29, "K7 inner courtyard -> map 60"),
  crossDoor(96, 26, 59, 81, 11, "K8 map 60 -> east wing (diagonal stair)"),
  crossDoor(80, 18, 55, 33, 33, "K9 east wing -> EAST RING"),
  crossDoor(44, 26, 59, 79, 52, "K10 east ring -> guest wing"),
  talkTo(19, "LOCKE (guest room)", 9000),
  H.advanceStory(calm(30, function()
    return map() == 55 and sw(0x01F8) == 1
  end), 40000),
  H.call(function()
    H.assertEq(sw(0x01F8), 1, "the burning night ran ($01F8 set)")
    H.assertEq(map(), 55, "back on map 55, at night")
    where("burning night")
    H.screenshot("figaro_night")
  end),

  -- ==================================================================== --
  -- PHASE 10: THE SUBMERGE.  Not a trigger: the courtyard guard (object
  -- 19, spawn $0315) forks _ca5f9f on $01F8 (:14288) into _ca5fba -- the
  -- chocobos (:14330-14405) and finally `load_map 0, {64,76}` (:14731),
  -- the world map outside the sand.  From there it is world-module RAM,
  -- not field RAM, so the settle predicate switches too.
  -- ==================================================================== --
  talkTo(19, "courtyard guard (submerge)", 9000),
  H.advanceStory(worldCalm(120), 90000),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "on the world map")
    H.assertEq(H.worldId(), 0, "World of Balance")
    H.assertEq(H.worldHasControl(), true, "and controllable")
    -- roster: TERRA + LOCKE + EDGAR, by party byte, not by slot index
    local inParty = {}
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then inParty[c] = true end
    end
    H.assertEq(inParty[4] or false, true, "EDGAR in the party ($1854)")
    H.assertEq(inParty[0] or false, true, "TERRA in the party ($1850)")
    H.assertEq(inParty[1] or false, true, "LOCKE in the party ($1851)")
    -- the shop survived the chapter: this whole route exists so that it can
    H.assertEq(invCount(0xA4), 1, "BioBlaster still carried")
    H.assertEq(invCount(0xA3), 1, "NoiseBlaster still carried")
    H.assertEq(invCount(0xAA), 1, "AutoCrossbow still carried")
    -- THE PARTY LANDS ON A CHOCOBO ($11FA&3 = 2 selects InitChoco,
    -- world/init.asm:95-102), and that matters to whoever navigates from
    -- this state: InitChoco (init.asm:402) never initialises the world
    -- tile-position registers $E0/$E2 -- only InitWorld does, from $1F60
    -- (init.asm:758-762) -- so H.worldX/worldY read 0 here and
    -- H.worldNavTo cannot be used until the party is off the bird.  The
    -- state itself is fine: control is live, the minimap draws, and the
    -- screenshot shows the party in the desert.  Asserted, not assumed,
    -- so this stops being true loudly rather than quietly.
    H.assertEq(H.readByte(0x11fa) & 3, 2, "riding a chocobo ($11FA&3=2)")
    H.log(string.format(
      "world id=%d $E0/$E2=(%d,%d) [zero: chocobo, see above] " ..
      "chars=$1EDC=%04X gil=%d",
      H.worldId(), H.worldX(), H.worldY(), H.readWord(0x1edc), gil()))
    for c = 0, 15 do
      if inParty[c] then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d party-byte=%02X",
          c, H.readByte(base), H.readByte(base + 8), H.readWord(base + 9),
          H.readByte(0x1850 + c)))
      end
    end
    H.screenshot("figaro_cleared")
  end),
  H.saveState("figaro_cleared.mss"),
  H.logStep(function()
    return string.format("figaro_cleared minted at frame %d", H.frame)
  end),
})
