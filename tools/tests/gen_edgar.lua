-- gen_edgar.lua -- from figaro_doorstep.mss (TERRA + LOCKE at map 55
-- (28,42), the Figaro Castle gate): walk in, BUY THE TOOLS in the only
-- window the game ever offers, take the throne-room audience with EDGAR,
-- then cross the castle to the MATRON and ride her flashback -- the beat
-- that puts Edgar back on his throne and unblocks the rest of the
-- chapter.  Mints figaro_intro.mss (after the audience) and
-- figaro_matron.mss (after the flashback, $0308 set again).
--
-- SCOPE.  Stops with Edgar respawned.  The remainder (second audience ->
-- Kefka -> the confrontation -> LOCKE's regroup -> the burning night ->
-- the submerge and the chocobos) is read out of the event source below,
-- and the walking it needs is the same door/staircase machinery this
-- script already uses -- see "WHAT REMAINS" at the end of this header.
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
--   THE LINK IS A DIAGONAL STAIRCASE, and it is invisible to the model.
--   The library's passability port covers the engine's four CARDINAL
--   exits; it does not implement the diagonal branch (player.asm:378,
--   `lda $b8 / and #$c0 / bne` -- on a diagonal-movement tile ONE
--   direction press moves the party diagonally).  Every tile of such a
--   staircase therefore reads as solid wall to BFS.  Measured: on map 60
--   the party standing at (98,24) and simply HOLDING LEFT walks down the
--   stair through (97,25) and (96,26), takes that entrance, and comes out
--   on map 59 at (79,12) -- the east wing, whose door (80,18) opens onto
--   the ring at 55 (33,33).  So the route reaches the ring as
--     55 (33,24) -> 60 (103,29) -> [hold LEFT from (98,24)] -> 59 (81,11)
--       -> (80,18) -> 55 (33,33) = ring
--   and comes back the mirror way through 59 (82,10) -> 60 (97,25).
--
--   THE RING IS TWO BANDS, which is why the route takes the WEST stair
--   and not the east one:
--     east  (x >= 32), via map 60: carries the guest-wing doors
--                      (44,19)/(44,26);
--     west  (x <= 24), via 59 (66,50): carries the matron doors
--                      (12,19)/(12,26) and (23,31) -> 59 (66,49).
--   The castle block at x=24..32 separates them for y=31..42 and the one
--   row that joins them, y=43, is a map border the engine refuses to walk
--   (BFS plans straight along it; measured "edge ->left blocked in
--   reality" at both (28,43) and (32,43)).  So the matron needs the WEST
--   band, reached by the chamber staircase above, and the guest wing --
--   which the burning night needs -- takes the map-60 stair instead.
--
--   FOUR staircases are hand-held with pushUntil on this route: the
--   chamber -> west wing one, and three more inside the matron's own room
--   (its (67,27) arrival floods to FOUR tiles).  The durable fix is to
--   teach the passability model the engine's diagonal branch
--   (player.asm:378-455, tiles with $b8 & $c0, movement directions 5..8)
--   instead; that would also stop BFS routing along map borders, the other
--   way this walk failed.
--
-- WHAT REMAINS, for the pass that finishes the chapter.  Every beat is
--   already decoded above; what is left is walking and cutscene-riding:
--     * second audience: back to 58 via 55 (23,26) -> courtyard ->
--       (28,13) -> 59 (27,28) -> (27,13).  Returning from the west ring
--       means re-crossing the chamber stair the other way (59 (64,42) ->
--       (49,59)), which was not measured;
--     * Kefka's arrival leaves EDGAR alone; talk BOTH troopers (objects
--       21 and 22) then Kefka (object 20) -- $01F0/$01F1 are map-local, so
--       the gate scene's earlier $01F0 is gone;
--     * LOCKE (object 27, at (28,15)) regroups the party and arms $0313;
--     * the guest-room LOCKE is map 59 (82,45), reached via the EAST ring
--       (map-60 stair, then 55 (44,26) -> 59 (79,52));
--     * the submerge is the courtyard guard (object 19) once $01F8 is set.
--
-- DOORS.  Entrance records fire when the party STANDS on the source tile
--   (entrance.asm CheckShortEntrance), but a castle door tile is a WALL
--   until CheckDoor (player.asm:959) swaps the open-door tiles in, and it
--   only does that for a party pressing into it from directly below or
--   above.  So BFS can never plan THROUGH a door: every crossing is
--   navTo(a neighbouring tile) + one continuous hold, and crossDoor
--   derives which neighbour by BFS rather than assuming (Figaro uses all
--   four: 55 (28,38) is entered from below, 59 (27,29) from above,
--   55 (12,19) from the right).
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
--     and the hold direction are DERIVED: BFS each of the four neighbours
--     and take the first one that is actually reachable right now.
local function crossDoor(sx, sy, dm, dx, dy, what, fixed)
  local pick, startMap
  local function stage()
    if not pick then
      pick = fixed
      if not pick then
        for _, c in ipairs({ { sx, sy + 1, "up" }, { sx, sy - 1, "down" },
                             { sx - 1, sy, "right" }, { sx + 1, sy, "left" } }) do
          if H.bfsPath(c[1], c[2]) then pick = c; break end
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
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 9000 }),
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

-- Hold `dir` until pred(): the escape hatch for stretches the step model
-- cannot plan.  Figaro's staircases are DIAGONAL-movement tiles
-- (player.asm:378 branches on $b8 & $c0 and moves the party diagonally on
-- a single direction press), and the library's passability port models
-- only the four cardinal exits -- so BFS sees solid wall where the game
-- has a staircase, and half the castle reads unreachable.
local function pushUntil(dir, pred, what, budget)
  return seq({
    H.driveUntil(pred, budget or 900, {
      H.call(function() H.setPad({ [dir] = true }) end),
    }, what),
    H.release(),
    H.waitFrames(20),
    H.logStep(function()
      return string.format("%s: at map=%d (%d,%d) f%d", what, map(),
        H.fieldX(), H.fieldY(), H.frame)
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
  -- bands apart and the row that joins them, y=43, is a map border the
  -- engine refuses to walk.)
  -- ==================================================================== --
  crossDoor(102, 56, 59, 27, 15, "D7 throne room -> throne hall"),
  crossDoor(27, 29, 55, 28, 15, "D8 throne hall -> inner courtyard"),
  crossDoor(23, 24, 59, 47, 60, "D9 inner courtyard -> west chamber"),
  H.navTo(48, 58, { maxFrames = 6000 }),
  -- x>=68, not >=66: the stair's own landing tiles are still diagonal-only,
  -- and stopping the hold on the first one leaves the party on a ledge
  -- where a plain DOWN press does nothing (measured at (66,44)).  Ride the
  -- hold to the wing's floor.
  pushUntil("right", function() return map() == 59 and H.fieldX() >= 68 end,
    "D10 west chamber -> west wing (diagonal stair)", 1200),
  pushUntil("down", function() return map() == 59 and H.fieldY() >= 48 end,
    "D11 down into the west wing"),
  crossDoor(66, 50, 55, 23, 33, "D12 west wing -> WEST RING"),
  crossDoor(12, 26, 57, 67, 27, "D13 west ring -> matron's room"),
  H.call(function() where("matron's room") end),

  -- and one more stair INSIDE her room: the (67,27) arrival floods to
  -- FOUR tiles.  Up onto the landing, west along the diagonal to (60,24),
  -- up to her floor, and only then can BFS see her.
  pushUntil("up", function() return map() == 57 and H.fieldY() <= 26 end,
    "D14 matron's room: onto the landing"),
  pushUntil("left", function() return map() == 57 and H.fieldX() <= 60 end,
    "D15 matron's room: west along the stair"),
  pushUntil("up", function() return map() == 57 and H.fieldY() <= 21 end,
    "D16 matron's room: up to her floor"),

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
})
