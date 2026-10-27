-- gen_wor_desert.lua -- the Cactrot desert, the second of the two grinds before Kefka's Tower
-- (docs/design/route-wor-side-trips.md): Continue the `wor-dino-v1` battery (SHADOW, CELES, CYAN and TERRA on foot
-- beside the Falcon by the dinosaur forest), check what the plan depends on, fly back to the Falcon's tile by
-- Maranda (69,183), where the line left it, walk the seven steps south onto the desert (world group 111: Hoover,
-- Cactrot), fight there for DESERT_FIGHTS battles, walk back to the Falcon, and save on its tile: the
-- `wor-desert-v1` battery, Kefka's Tower's boot.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
local POTION, FENIX, REMEDY, TINCTURE = 0xE9, 0xF0, 0xF5, 0xEB
local NAMES = { [TERRA] = "TERRA", [LOCKE] = "LOCKE", [CYAN] = "CYAN", [SHADOW] = "SHADOW", [EDGAR] = "EDGAR",
  [SABIN] = "SABIN", [CELES] = "CELES", [STRAGO] = "STRAGO", [RELM] = "RELM", [SETZER] = "SETZER", [MOG] = "MOG",
  [GAU] = "GAU", [GOGO] = "GOGO", [UMARO] = "UMARO" }
local FIGHT = {}
H.NAV_REFIRE_HOLD = true
-- the Cactrot (3 HP under evade 250 and MBlock 250, so a Fight or a spell misses, and 0 while it shields): a
-- thrown skean cannot be dodged (MagicProp $51-$53), and the Water Edge is its weakness, so SHADOW throws it,
-- reading the weakness as a player who knows the Cactrot does (the driver otherwise waits for a reveal that a
-- miss never makes); the Hoover is weak to ice too, and whoever holds Ice casts it while one stands
-- (route-wor-side-trips.md section 3: Fight alone, the Cactrot wiped the party, and Ice missed it)
local CACTROT, HOOVER = 0x04C, 0x03E
-- the care between battles casts first, as the forest's does (TERRA's Cure is 1 MP under the Economizer)
H.careMagic, H.careCastFirst = true, true
FIGHT.throwRead = function() return H.formationHas({ [CACTROT] = true }) end
FIGHT.nuke = function()
  if H.formationHas({ [HOOVER] = true }) then return { 0x01 } end
  return nil
end
-- without a Water Edge in the bag or SHADOW standing to throw it, nothing the party holds can touch the Cactrot,
-- and a player runs from it (it pays no experience): read as each battle opens
local WATER_EDGE = 0xAC
local function cactrotRun()
  local up = (H.readByte(0x1850 + SHADOW) & 7) == 1 and H.readWord(0x1600 + 37 * SHADOW + 0x09) > 0
  if up and H.invCountOf(WATER_EDGE) > 0 then return {} end
  if not H.formationHas({ [CACTROT] = true }) then return { CACTROT } end
  H.log(string.format("[desert] no throw for the Cactrot (SHADOW %s, %d Water Edge): running from it",
    up and "standing" or "down", H.invCountOf(WATER_EDGE)))
  return { CACTROT }
end

local LINKS = {}
local K = H.worLegKit({ fight = FIGHT, links = LINKS, names = NAMES })
local map, sw, c, lv, settled = K.map, K.sw, K.c, K.lv, K.settled
local say, kitLine, board, watches = K.say, K.kitLine, K.board, K.watches
local regroup, liftOff, landNear, partyOf = K.regroup, K.liftOff, K.landNear, K.partyOf
local kohlingenStop = K.kohlingenStop

local FOUR = { SHADOW, CELES, CYAN, TERRA }
local DESERT = 111                                   -- WorldBattleGroup: Hoover (237), Cactrot (221)
local DESERT_NEAR = { 70, 187 }                      -- one step south of the landing tile (70,186)
local MARANDA_TILE = { 69, 183 }                     -- the Falcon's tile by Maranda (wor-colosseum-v1's)
local MARANDA_WORLD = { { 69, 184 }, { 70, 184 } }   -- Maranda's door: the walks step round it
-- a while in the desert, as a player at the pinata spends it: eight battles (route-wor-side-trips.md section 3)
local DESERT_FIGHTS, n0 = 8, 0

-- the world tile nearest (nx, ny) whose own zone deals `group` on its own background, with a passable
-- neighbour that does too (the zone is the saved position, which every battle sets to its own tile:
-- M.worldEncounterGroup), so pacing between them rolls only that group
local function inGroup(group)
  return function(x, y) return H.worldPassable(x, y) and H.worldEncounterGroup(x, y, x, y) == group end
end
local function groupTile(group, nx, ny, what)
  local ok, best, bd = inGroup(group), nil, 1e9
  for dy = -8, 8 do
    for dx = -8, 8 do
      local x, y = nx + dx, ny + dy
      if ok(x, y) and (ok(x + 1, y) or ok(x - 1, y) or ok(x, y + 1) or ok(x, y - 1)) then
        local d = dx * dx + dy * dy
        if d < bd and H.worldBfs(H.worldX(), H.worldY(), nil, x, y) then best, bd = { x, y }, d end
      end
    end
  end
  H.assertEq(best ~= nil, true, string.format("%s: a tile of world group %d near (%d,%d) with a walk to it", what,
    group, nx, ny))
  H.log(string.format("[zone] %s: world group %d at (%d,%d)", what, group, best[1], best[2]))
  return best
end
local function seated()
  for _, ch in ipairs(FOUR) do if partyOf(ch) ~= 1 then return false end end
  return true
end
local function potionsShort()
  return H.invCountOf(POTION) < math.min(99, H.careStockPotions(H.activeTopLevel(), { spend = 30 }))
    or H.invCountOf(FENIX) < math.min(20, H.activeTopLevel())
end
local DT = nil
-- the most a top-up at Kohlingen's counter spends: 99 Potions, 20 Remedies, 20 Fenix Downs at the World of Ruin's
-- prices (shop 67), rounded up
local GIL_FLOOR = 60000

H.run({ maxFrames = 1600000 }, {
  H.bootCheckpoint("wor-dino-v1"),
  watches(),
  -- ---- 0. what the plan depends on (#480) -------------------------------------------------------------------
  -- The entry contract (lib/ot6_contract.lua) already holds the story: SHADOW recruited ($02F3, gen_wor_colosseum;
  -- his Throw is the one hit that lands on the Cactrot) and the Falcon parked beside the party.  Hard, and asserted
  -- here: gil for Kohlingen's counter should the bag be short (the line's purse).  Soft, fixed in the leg as a
  -- player would: who is seated (the cabin), the bag's Potions and Fenix Downs (Kohlingen's counter), the Water
  -- Edges (without one, the Cactrot is run from) and HP (the field care).
  H.call(function()
    say("wor", "boot")
    H.log("[kit] " .. kitLine(FOUR))
    H.assertEq(H.gil() >= GIL_FLOOR, true, string.format("gil for Kohlingen's top-up: %d GP, the floor %d (the "
      .. "line's purse)", H.gil(), GIL_FLOOR))
  end),
  -- @@setup-end

  -- @@stage ready
  -- on foot onto the Falcon's tile, A: the pilot's controls; the cabin only when the four are not seated
  H.cond(function() return not seated() end, { regroup(FOUR), liftOff() }, { board() }),
  H.cond(potionsShort, { kohlingenStop("the top-up before the desert") }, {}),
  -- down on the tile by Maranda the line left the Falcon on (wor-colosseum-v1), seven steps north of the desert
  H.waitUntil(function() return H.airshipControl() end, 3000, "the pilot's controls", 5),
  H.lazy(function() return H.flyTo(MARANDA_TILE[1], MARANDA_TILE[2], { what = "the Falcon back by Maranda",
    fight = FIGHT }) end),
  H.call(function()
    for _, ch in ipairs(FOUR) do H.assertEq(partyOf(ch), 1, NAMES[ch] .. " is seated") end
  end),
  H.fieldCare({ threshold = 1.0, tag = "before the desert" }),

  -- ---- 1. the desert --------------------------------------------------------------------------------------
  -- @@stage desert
  H.lazy(function()
    DT = groupTile(DESERT, DESERT_NEAR[1], DESERT_NEAR[2], "the Cactrot desert")
    return H.worldNavTo(DT[1], DT[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
      avoid = MARANDA_WORLD })
  end),
  H.call(function() n0 = #H.outcomes; say("wor", "on the desert") end),
  K.pace(function() return #H.outcomes - n0 >= DESERT_FIGHTS end, DESERT_FIGHTS + 1, "the Cactrot desert", nil,
    { pick = inGroup(DESERT), flee = cactrotRun }),
  H.call(function()
    local t = {}
    for i = n0 + 1, #H.outcomes do t[H.outcomes[i].kind] = (t[H.outcomes[i].kind] or 0) + 1 end
    say("wor", string.format("after the desert: %d battles, %d won, %d run from, %d lost", #H.outcomes - n0,
      t["won"] or 0, t["party left"] or 0, t["lost"] or 0))
    H.log("[kit] " .. kitLine(FOUR))
  end),

  -- ---- 2. back to the Falcon, and the save --------------------------------------------------------------
  -- @@stage save
  H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
    { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, avoid = MARANDA_WORLD }),
  -- the Hoovers' Sand Storms empty the bag (the line's play: 97 Potions in, 4 out), and the save is Kefka's
  -- Tower's boot: a player restocks before it, at Kohlingen's counter, and comes back to the Falcon's tile
  H.cond(potionsShort, {
    board(),
    kohlingenStop("the restock after the desert"),
    H.waitUntil(function() return H.airshipControl() end, 3000, "the pilot's controls", 5),
    H.lazy(function() return H.flyTo(MARANDA_TILE[1], MARANDA_TILE[2], { what = "the Falcon back by Maranda",
      fight = FIGHT }) end),
  }, {}),
  H.fieldCare({ threshold = 1.0, tag = "on the Falcon's tile" }),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "settled on the save tile", 5),
  H.call(function()
    for _, ch in ipairs(FOUR) do H.assertEq(partyOf(ch), 1, NAMES[ch] .. " is seated") end
    say("wor", "on the save tile")
    H.log("[kit] " .. kitLine(FOUR))
  end),
  H.saveAtCheckpoint("wor-desert-v1"),
  H.saveState("wor_desert.mss"),
  H.logStep(function()
    return string.format("wor_desert generated: SHADOW L%d, CELES L%d, CYAN L%d and TERRA L%d beside the Falcon, "
      .. "world (%d,%d), saved in slot 3", lv(SHADOW), lv(CELES), lv(CYAN), lv(TERRA), H.worldX(), H.worldY())
  end),
})
