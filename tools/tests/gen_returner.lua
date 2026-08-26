-- gen_returner.lua -- from vargas_won.mss (TERRA + LOCKE + EDGAR + SABIN on
-- VARGAS's ledge, map 98) down the far side of Mt. Kolts and across the world
-- to the Returner Hideout.  This is the first link of the tier-3 route:
-- everything from here to the scenario split runs through this door.
-- Generates one state:
--   returner_hideout.mss  map 108 (11,55), the hideout's entry hall, first
--                         controllable frame.  This is the fixture gen_banon
--                         starts from and the entry point for anything that
--                         wants the hideout without replaying the mountain.

-- The route, and the three places the tables alone would leave you stuck.

-- 1. The way out of map 98 is the tile Vargas was standing on.  Map 98 holds
--    exactly two entrance records (short_entrance.dat, ShortEntrance::_98):
--    (10,10) -> map 103 (59,9), the summit the party came in by, and
--    (23,32) -> map 100 (8,48).  (23,32) is NPCProp::_98's only record,
--    Vargas's own spawn tile (npc_prop.asm:4006), so before the fight it
--    is blocked by his object and after it is walkable.  _ca828f's reunion
--    ends `hide_obj SLOT_2..4 / update_party / player_ctrl_on` via _cacb95
--    (event_main.asm:31276-31283) and never moves Vargas's object out of the
--    way; it is `switch $031C=0` at :20147 that despawns him.  So the exit is
--    walkable only because the fight was won, and $031C is asserted clear
--    below before the step is planned.

-- 2. Map 100 lands the party one tile from the way back.  The arrival tile is
--    (8,48), and (7,48), its immediate west neighbour, is the entrance
--    straight back to map 98.  This is the same hazard shape gen_kolts
--    documented for South Figaro's x=0 column and map 95's y=37 row, and BFS
--    cannot see it: entrance triggers are not passability.  Shelf A is 60
--    tiles and the target (17,59) is well east of the spawn, so the shortest
--    path is unlikely to touch (7,48), and planAvoids() below makes that a
--    guarantee.

-- 4. The hideout's world tile is (104,64), and it is a long walk north.
--    World (104,64) -> map 108 (11,55) (ShortEntrance::_0); map 108's own way
--    back is the long entrance (6,57) length $11 -> world (104,65).  From the
--    mountain's north door at (98,93) that is a long stretch of overworld,
--    and the world step is planned by worldBfs and asserted to exist before
--    it is walked rather than discovered by holding a direction.

local H = dofile("tools/tests/lib/ot6.lua")
local WON = "build/states/vargas_won.mss.lua"

-- map compares stay masked: loaders leave flag bits in $1F64's high byte
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
-- first).  H.cond with an always-true predicate wraps a list into one step.
local function seq(steps) return H.cond(function() return true end, steps) end

local function mapChanged()
  local m0
  return function()
    if m0 == nil then m0 = map() end
    return map() ~= m0
  end
end

-- Settle after a map load: a fully lit screen plus whatever `extra` requires,
-- held for n consecutive frames.  Both halves are needed, and both caused a
-- bad generated state in an earlier pass; see gen_kolts.lua's header.  A
-- cutscene can report control on a black screen, and a single-shot check
-- passes mid-load while the field module still holds the previous map's
-- control byte.
local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

local function settleField(dstMap, maxF)
  return seq({
    H.waitFrames(90),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and (dstMap == nil or map() == dstMap)
    end), maxF or 12000, { playBattles = true }),
    H.waitFrames(30),
  })
end

local function settleWorld(maxF)
  return seq({
    H.advanceStory(settled(20, function()
      return H.worldHasControl() and H.worldAligned()
    end), maxF or 12000, { playBattles = true }),
    H.waitFrames(30),
  })
end

-- Walk to (tx,ty) expecting an entrance to fire there.  Mt. Kolts uses plain
-- walkable floor for its entrances (unlike Figaro's castle doors, which are
-- walls until CheckDoor), so BFS routes straight onto them and the crossing
-- is one navTo rather than a staging tile plus a hold.  The map id is
-- asserted afterwards.
local function crossTo(tx, ty, dstMap, what, maxF)
  return seq({
    H.logStep(function()
      return string.format("cross %s: (%d,%d) -> (%d,%d) -> map %d",
        what, H.fieldX(), H.fieldY(), tx, ty, dstMap)
    end),
    H.navTo(tx, ty, { maxFrames = maxF or 20000, arrive = mapChanged(),
      playBattles = true }),
    H.release(),
    settleField(dstMap),
    H.call(function()
      H.assertEq(map(), dstMap, what .. ": landed on map " .. dstMap)
      where(what)
    end),
  })
end

-- H.fieldCare revives from the bag before it heals, so one call answers both,
-- and it does not open the menu at all when nobody needs anything, which is
-- why it can sit after every fight without costing a quiet route any frames.
local function care(tag)
  return H.fieldCare({ tag = "care " .. tag, threshold = 0.85 })
end

local function battlePending()
  return (H.readByte(0x00e8) & 0x20) ~= 0 or H.battleLoadStarted()
end
local function worldRound(n, tx, ty)
  return H.cond(function() return H.worldMode() end, {
    -- playBattles = "tactical" is the backstop, not the plan: arrive fires
    -- on the battle-pending bit frames before the navigator's own 3-frame
    -- debounce could act, so the option should never be consulted here.  It
    -- is set anyway so that the day the flag write goes, a missed arrive
    -- shows up as a fought battle rather than a silently killed one, and
    -- "tactical" because this file fights its encounters on purpose (see the
    -- header) rather than fleeing them.
    H.worldNavTo(tx, ty, { maxFrames = 40000, playBattles = "tactical",
      arrive = function() return battlePending() or not H.worldMode() end }),
    H.cond(battlePending, {
      H.logStep(function()
        return string.format("world segment round %d: encounter roll won at " ..
          "(%d,%d) f%d -- fighting it", n, H.worldX(), H.worldY(),
          H.frame)
      end),
      H.waitUntil(function() return H.battleLoadStarted() end, 1800,
        "the rolled encounter loads", 5),
      H.fightBattle(20000),
      H.driveUntil(function()
        return H.worldMode() and H.worldHasControl() and H.worldAligned()
      end, 8000, { H.release() }, "world reload after the fight"),
      H.call(function()
        H.log(string.format("world segment round %d: fight done, reloaded at " ..
          "(%d,%d) f%d", n, H.worldX(), H.worldY(), H.frame))
      end),
      -- and patch the party up before walking into the next roll.  A death
      -- answered here costs one Fenix Down; a death carried to the hideout
      -- is the fixture defect above.
      care(string.format("world round %d", n)),
    }, {}),
  }, {})
end

-- Assert the BFS plan to (tx,ty) exists and never steps on any tile in
-- `bad`, this map's other entrance records.  BFS models passability, not
-- entrance triggers, so this check is the only thing stopping a shortest path
-- from becoming a route that leaves the map.  (gen_kolts's planAvoidsRow,
-- generalised from a row to a tile set: map 98's neighbours are point exits
-- rather than rows.)
local function planAvoids(tx, ty, bad, what)
  return H.cond(function() return true end, {
    H.waitUntil(function() return H.bfsPath(tx, ty) ~= nil end,
                900, what .. ": a path exists (45f poll)", 45),
    H.call(function()
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
  end),
  })
end

-- 120000 was the battle-clear-write budget; input-driven fights spend real
-- ATB rounds, so the limit carries headroom for every encounter the route
-- can roll
H.run({ maxFrames = 220000 }, {
  H.loadState(WON),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 98, "booted on map 98, VARGAS's ledge")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    -- the fight is what opens the route: $031C despawns Vargas's object, and
    -- his spawn tile (23,32) is the exit to map 100
    H.assertEq(sw(0x031C), 0, "$031C clear -- VARGAS despawned, (23,32) walkable")
    H.assertEq((H.readByte(0x1855) & 0x07) ~= 0, true, "SABIN in the party")
    where("booted")
  end),

  -- ===================================================================== --
  -- Phase 1: off the mountain.  98 -> 100 (shelf A) -> 101 -> world.
  -- ===================================================================== --
  -- (10,10) is the other exit on this map (back up to the summit, map 103);
  -- keep the plan off it as well.
  planAvoids(23, 32, { { 10, 10 } }, "map 98 -> the ledge exit"),
  crossTo(23, 32, 100, "M1 VARGAS's ledge -> map 100 shelf A"),

  H.call(function()
    H.assertEq(H.fieldX(), 8, "landed at x=8 on shelf A")
    H.assertEq(H.fieldY(), 48, "landed at y=48 on shelf A")
  end),
  planAvoids(8, 53, { { 7, 48 } }, "shelf A -> the Tent chest"),
  H.openChest{ stand = { 8, 53 }, face = "up", bit = 40, what = "Tent",
               nav = { playBattles = true } },
  care("after the Tent chest"),
  -- (7,48) is one tile west and goes straight back to map 98
  planAvoids(17, 59, { { 7, 48 } }, "shelf A -> the north door"),
  crossTo(17, 59, 101, "M2 shelf A -> map 101, the north gatehouse"),

  H.call(function()
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
  H.navTo(10, 57, { maxFrames = 20000, playBattles = true,
    arrive = function() return H.worldMode() end }),
  H.release(),
  settleWorld(),
  H.call(function()
    H.assertEq(H.worldMode(), true, "out of the mountain, on the world map")
    where("north of Mt. Kolts")
    H.screenshot("returner_worldout")
  end),
  -- The mountain's own encounters are behind the party now; the overworld's
  -- are ahead.  Care here rather than only at the far end, so the world walk
  -- starts from a whole party instead of carrying the descent's casualties
  -- through twelve more rolls.
  care("off the mountain"),

  -- ===================================================================== --
  -- Phase 2: the world step.  (98,93) -> (104,64), the hideout's door.
  -- It is asserted reachable before it is walked: worldBfs answering nil here
  -- would mean the north door does not open into the hideout's region, which
  -- should fail rather than be worked around by holding UP.
  -- ===================================================================== --
  H.call(function()
    local p = H.worldBfs(104, 64)
    H.assertEq(p ~= nil, true, "the Returner Hideout is reachable from here")
    H.log(string.format("world segment: (%d,%d) -> (104,64), %d steps",
      H.worldX(), H.worldY(), #p))
  end),
  -- Twelve input-driven rounds: ~45 tiles of encounter territory has not
  -- rolled more than a handful of fights, and a spent round costs nothing
  -- (its cond sees the world already left).  A 13th battle would show up
  -- as the settle below timing out on map 108.
  worldRound(1, 104, 64), worldRound(2, 104, 64), worldRound(3, 104, 64),
  worldRound(4, 104, 64), worldRound(5, 104, 64), worldRound(6, 104, 64),
  worldRound(7, 104, 64), worldRound(8, 104, 64), worldRound(9, 104, 64),
  worldRound(10, 104, 64), worldRound(11, 104, 64), worldRound(12, 104, 64),
  H.release(),
  settleField(108),
  -- The hideout has no encounters of its own, so this is the last chance to
  -- put the party back together before the fixture is written.
  care("at the hideout"),
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
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d mp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11),
          H.readWord(base + 13), H.readWord(base + 15)))
      end
    end

    -- Half HP is the same bar gen_kolts uses.  A failure here means the
    -- descent and the world walk cost more than the bag could answer, which
    -- is a finding about supplies and not a reason to lower the bar.
    for _, c in ipairs(H.partyMembers()) do
      H.assertEq(H.charHp(c) > 0, true,
        string.format("char %d reached the hideout alive", c))
      H.assertEq(H.charHp(c) * 2 >= H.charMaxHp(c), true,
        string.format("char %d is at or above half hp (%d/%d)",
          c, H.charHp(c), H.charMaxHp(c)))
    end
    where("returner hideout")
    H.screenshot("returner_hideout")
  end),
  H.saveState("returner_hideout.mss"),
  H.logStep(function()
    return string.format("returner_hideout generated at frame %d", H.frame)
  end),
})
