-- gen_returner.lua -- from vargas_won.mss (TERRA + LOCKE + EDGAR + SABIN on
-- VARGAS's ledge, map 98) down the far side of Mt. Kolts and across the world
-- to the RETURNER HIDEOUT.  The first link of the rung-3 route: everything
-- from here to the scenario split runs through this door.
-- Mints one state:
--   returner_hideout.mss  map 108 (11,55), the hideout's entry hall, first
--                         controllable frame -- the fixture gen_banon starts
--                         from and the doorstep for anything that wants the
--                         hideout without replaying the mountain.
--
-- THE ROUTE, and the three places the tables alone would strand you.
--
-- 1. THE WAY OUT OF MAP 98 IS THE TILE VARGAS WAS STANDING ON.  Map 98 holds
--    exactly two entrance records (short_entrance.dat, ShortEntrance::_98):
--    (10,10) -> map 103 (59,9), the summit the party came in by, and
--    (23,32) -> map 100 (8,48).  (23,32) is NPCProp::_98's only record --
--    Vargas's own spawn tile (npc_prop.asm:4006) -- so before the fight it
--    is a wall of NPC and after it is the road.  _ca828f's reunion ends
--    `hide_obj SLOT_2..4 / update_party / player_ctrl_on` via _cacb95
--    (event_main.asm:31276-31283) and never moves Vargas's object out of the
--    way; it is `switch $031C=0` at :20147 that despawns him.  So the exit is
--    only walkable BECAUSE the fight was won, and $031C is asserted clear
--    below before the leg is planned.
--
-- 2. MAP 100 LANDS THE PARTY ONE TILE FROM THE WAY BACK.  The arrival tile is
--    (8,48) and (7,48) -- its immediate west neighbour -- is the entrance
--    straight back to map 98.  This is the same hazard shape gen_kolts
--    documented for South Figaro's x=0 column and map 95's y=37 row, and BFS
--    cannot see it: entrance triggers are not passability.  Shelf A is 60
--    tiles and the target (17,59) is well east of the spawn, so the shortest
--    path has no reason to touch (7,48) -- but "no reason to" is not a
--    guarantee, and planAvoids() below turns it into one.
--
-- 3. THE MOUNTAIN'S NORTH DOOR IS A LONG ENTRANCE, AND IT IS GUARDED LATER.
--    Map 101 is entered at (10,49) from map 100 (17,59) and left by its long
--    entrance (5,57), HORIZONTAL, length $12 -- row y=57, x=5..22 -> world
--    (98,93) (long_entrance.dat, LongEntrance::_101).  Its other long record,
--    (10,48) length 1, goes straight back to map 100 (17,58), and (10,48) is
--    the tile DIRECTLY NORTH of the spawn -- so this map is bracketed by
--    exits the way map 100 is, and the walk south is asserted off it.
--    NPCProp::_101 also puts two imperial SOLDIERs on (10,49)/(11,50), both
--    spawn switch $031d, the second running _ca8473 ("Scum!  You're
--    Returners!", event_main.asm:20159/20166) which throws the party back out
--    to world (98,93).  ONE of them spawns on the arrival tile itself.  They
--    are not a problem on THIS pass and cannot be: $031D is set by the
--    hideout -- _caf68a's walk-in at :36300 and Banon's speech _caf7dc at
--    :36712 -- both of which are still ahead of us.  Asserted clear on
--    arrival, so if that ordering ever changes this fails loudly instead of
--    walking into a scene.
--
-- 4. THE HIDEOUT'S WORLD TILE IS (104,64) AND IT IS A LONG WALK NORTH.
--    World (104,64) -> map 108 (11,55) (ShortEntrance::_0); map 108's own way
--    back is the long entrance (6,57) length $11 -> world (104,65).  From the
--    mountain's north door at (98,93) that is a long stretch of overworld,
--    and the world leg is planned by worldBfs and asserted to exist before it
--    is walked rather than discovered by holding a direction.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local WON = "/Users/mtklein/ot6/build/states/vargas_won.mss.lua"

-- map compares stay MASKED: loaders ride flag bits in $1F64's high byte
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
-- event switch id -> live bit (event bitfield base $1E80, bit = id & 7)
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end

local function where(tag)
  H.log(string.format("[%s] f%d map=%d field=(%d,%d) world=(%d,%d) " ..
    "$031C=%d $031D=%d $0011=%d bright=%d ctl=%s",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), H.worldX(), H.worldY(),
    sw(0x031C), sw(0x031D), sw(0x0011), bright(), tostring(H.hasControl())))
end

-- a bare step list cannot be spliced into a step list (Lua truncates a
-- non-final table.unpack to one value, silently dropping every step but the
-- first).  H.cond with an always-true predicate wraps a list into ONE step.
local function seq(steps) return H.cond(function() return true end, steps) end

local function mapChanged()
  local m0
  return function()
    if m0 == nil then m0 = map() end
    return map() ~= m0
  end
end

-- Settle after a map load: a fully lit screen plus whatever `extra` demands,
-- held for n CONSECUTIVE frames.  Both halves are load-bearing and both cost
-- a previous agent a bad mint -- see gen_kolts.lua's header: a cutscene can
-- report control on a black screen, and a single-shot check passes mid-load
-- while the field module still holds the OLD map's control byte.
local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

-- The settle DRIVES rather than waits, for the reason gen_kolts measured on
-- map 96: this is encounter territory, and a battle rolled on the arrival
-- tile stalls a passive waitUntil forever.  advanceStory kill-bits whatever
-- came up and edge-taps the victory text; on a quiet field it holds the pad
-- empty.  It also deliberately does NOT require player control -- $087C&$0F
-- flickers 2<->4 while any async object script is live -- and leaves "can I
-- step THIS frame" to navTo, which debounces control itself.
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

local function settleWorld(maxF)
  return seq({
    H.advanceStory(settled(20, function()
      return H.worldHasControl() and H.worldAligned()
    end), maxF or 12000),
    H.waitFrames(30),
  })
end

-- Walk to (tx,ty) expecting an entrance to fire there.  Mt. Kolts uses plain
-- walkable floor for its entrances (unlike Figaro's castle doors, which are
-- walls until CheckDoor), so BFS routes straight onto them and the crossing
-- is one navTo, not a staging tile plus a hold.  Asserted after by map id.
local function crossTo(tx, ty, dstMap, what, maxF)
  return seq({
    H.logStep(function()
      return string.format("cross %s: (%d,%d) -> (%d,%d) -> map %d",
        what, H.fieldX(), H.fieldY(), tx, ty, dstMap)
    end),
    H.navTo(tx, ty, { maxFrames = maxF or 20000, arrive = mapChanged() }),
    H.release(),
    settleField(dstMap),
    H.call(function()
      H.assertEq(map(), dstMap, what .. ": landed on map " .. dstMap)
      where(what)
    end),
  })
end

-- Assert the BFS plan to (tx,ty) exists and never steps on any tile in
-- `bad` -- this map's OTHER entrance records.  BFS models passability, not
-- entrance triggers, so this is the only thing between a shortest path and a
-- route that quietly leaves the map.  (gen_kolts's planAvoidsRow, generalised
-- from a row to a tile set: map 98's neighbours are point exits, not rows.)
local function planAvoids(tx, ty, bad, what)
  return H.call(function()
    local p = H.bfsPath(tx, ty)
    H.assertEq(p ~= nil, true, what .. ": a path exists")
    local DD = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 },
                 right = { 1, 0 }, upleft = { -1, -1 }, upright = { 1, -1 },
                 downleft = { -1, 1 }, downright = { 1, 1 } }
    local x, y = H.fieldX(), H.fieldY()
    local hit = nil
    for _, b in ipairs(bad) do
      if x == b[1] and y == b[2] then hit = b end
    end
    for _, d in ipairs(p) do
      x, y = x + DD[d][1], y + DD[d][2]
      for _, b in ipairs(bad) do
        if x == b[1] and y == b[2] then hit = b end
      end
    end
    H.log(string.format("%s: %d steps, avoids %d exit tiles: %s",
      what, #p, #bad, tostring(hit == nil)))
    H.assertEq(hit == nil, true, what .. ": plan stays off this map's " ..
      "other entrance tiles" ..
      (hit and string.format(" (hit %d,%d)", hit[1], hit[2]) or ""))
  end)
end

H.run({ maxFrames = 120000 }, {
  H.loadState(WON),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 98, "booted on map 98, VARGAS's ledge")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    -- the fight is what opens the road: $031C despawns Vargas's object, and
    -- his spawn tile (23,32) IS the exit to map 100
    H.assertEq(sw(0x031C), 0, "$031C clear -- VARGAS despawned, (23,32) walkable")
    H.assertEq((H.readByte(0x1855) & 0x07) ~= 0, true, "SABIN in the party")
    where("booted")
  end),

  -- ===================================================================== --
  -- PHASE 1: OFF THE MOUNTAIN.  98 -> 100 (shelf A) -> 101 -> world.
  -- ===================================================================== --
  -- (10,10) is the other exit on this map (back up to the summit, map 103);
  -- keep the plan off it as well.
  planAvoids(23, 32, { { 10, 10 } }, "map 98 -> the ledge exit"),
  crossTo(23, 32, 100, "M1 VARGAS's ledge -> map 100 shelf A"),

  H.call(function()
    H.assertEq(H.fieldX(), 8, "landed at x=8 on shelf A")
    H.assertEq(H.fieldY(), 48, "landed at y=48 on shelf A")
  end),
  -- (7,48) is one tile west and goes straight back to map 98
  planAvoids(17, 59, { { 7, 48 } }, "shelf A -> the north door"),
  crossTo(17, 59, 101, "M2 shelf A -> map 101, the north gatehouse"),

  H.call(function()
    -- the imperial pair belongs to a scene the hideout arms, not this pass
    H.assertEq(sw(0x031D), 0,
      "$031D clear -- no imperial soldiers on map 101 yet (_ca8473)")
    where("north gatehouse")
    H.screenshot("returner_gatehouse")
  end),
  -- out by the long entrance row y=57 (x=5..22).  (10,48), one tile north of
  -- the spawn, is the record back to map 100 -- stay off it.
  planAvoids(10, 57, { { 10, 48 } }, "map 101 -> the world door"),
  H.logStep(function()
    return string.format("cross M3: (%d,%d) -> (10,57) -> world (98,93)",
      H.fieldX(), H.fieldY())
  end),
  H.navTo(10, 57, { maxFrames = 20000,
    arrive = function() return H.worldMode() end }),
  H.release(),
  settleWorld(),
  H.call(function()
    H.assertEq(H.worldMode(), true, "out of the mountain, on the world map")
    where("north of Mt. Kolts")
    H.screenshot("returner_worldout")
  end),

  -- ===================================================================== --
  -- PHASE 2: THE WORLD LEG.  (98,93) -> (104,64), the hideout's door.
  -- Asserted reachable before it is walked: worldBfs answering nil here
  -- would mean the north door does not open into the hideout's region, and
  -- that is worth failing on rather than holding UP and hoping.
  -- ===================================================================== --
  H.call(function()
    local p = H.worldBfs(104, 64)
    H.assertEq(p ~= nil, true, "the Returner Hideout is reachable from here")
    H.log(string.format("world leg: (%d,%d) -> (104,64), %d steps",
      H.worldX(), H.worldY(), #p))
  end),
  H.worldNavTo(104, 64, { maxFrames = 40000,
    arrive = function() return not H.worldMode() end }),
  H.release(),
  settleField(108),
  H.call(function()
    H.assertEq(map(), 108, "on map 108, the RETURNER HIDEOUT")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    -- the story has not started here yet
    H.assertEq(sw(0x0011), 0, "$0011 clear -- Banon's speech has not run")
    H.assertEq(sw(0x0013), 0, "$0013 clear -- no decision made")
    H.assertEq(sw(0x0018), 0, "$0018 clear -- the raft is not armed")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11)))
      end
    end
    where("returner hideout")
    H.screenshot("returner_hideout")
  end),
  H.saveState("returner_hideout.mss"),
  H.logStep(function()
    return string.format("returner_hideout minted at frame %d", H.frame)
  end),
})
