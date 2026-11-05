-- gen_wor_bench.lua -- the bench's training before Kefka's Tower (#496, docs/design/route-wor-tower-prep.md):
-- Continue the `wor-desert-v1` battery (SHADOW, CELES, CYAN and TERRA beside the Falcon by Maranda), check what
-- the plan depends on, then rotate the bench through the plain by Maranda (world group 49, the World of Ruin's
-- grind), two at a time beside two of the line's strong members, until each stands at its goal (GOALS): the tower's
-- three parties each carry two or three of them, and the tower's first map is lethal to a carried member under
-- about L40 (the lab: route-wor-tower-prep.md section 2).  Kohlingen's counter when the bag runs short (its gear stop
-- dresses whoever is seated, the trainees among them); the line's four back in the cabin, and the save on the
-- Falcon's tile: the `wor-bench-v1` battery, Kefka's Tower's boot.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, CYAN, SHADOW, EDGAR, SABIN, CELES, STRAGO, RELM, SETZER, MOG, GAU, GOGO, UMARO =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13
local POTION, FENIX = 0xE9, 0xF0
local NAMES = H.SPLIT_NAMES
local FIGHT = {}
H.NAV_REFIRE_HOLD = true
-- the care between battles tops everyone up to full, and casts before it reaches for the bag (the forest's and the
-- desert's care): a trainee at L32 meets the plain's L54 bodies at about a third of their HP
H.careThreshold = 1.0
H.careMagic, H.careCastFirst = true, true
-- the plain's Crawler is weak to ice (gen_wor_dino's): whoever holds Ice casts it while one stands
FIGHT.nuke = function()
  if H.formationHas({ [0x05B] = true }) then return { 0x01 } end
  return nil
end

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, c, lv, settled = K.map, K.c, K.lv, K.settled
local say, kitLine, board, watches = K.say, K.kitLine, K.board, K.watches
local regroup, liftOff, partyOf = K.regroup, K.liftOff, K.partyOf
local kohlingenStop = K.kohlingenStop

local FOUR = { SHADOW, CELES, CYAN, TERRA }
-- the two who carry the trainees: the line's two at L53, not TERRA and CELES at L63-64, so the training raises the
-- average and leaves the top where it is (#496: "raise the party average while keeping the max down")
local CARRIERS = { SHADOW, CYAN }
-- each trainee's goal.  The carried (route-wor-tower-prep.md section 2: the bench's best four, L38-44, won the
-- tower's first map with no carrier; the four weakest, L32-37, lost it five times in six): L40.  SABIN and GOGO, the
-- two who join the six at L53-64 as strong members of the tower's third party: L48.
local GOALS = { [SETZER] = 40, [GAU] = 40, [EDGAR] = 40, [UMARO] = 40, [MOG] = 40, [LOCKE] = 40,
  [SABIN] = 48, [GOGO] = 48 }
local TRAINEES = { SETZER, GAU, EDGAR, UMARO, MOG, LOCKE, SABIN, GOGO }
local PLAIN = 49                                     -- WorldBattleGroup: the plain by Maranda (gen_wor_dino's)
local MARANDA_TILE = { 69, 183 }                     -- the Falcon's tile by Maranda (wor-desert-v1's)
local MARANDA_WORLD = { { 69, 184 }, { 70, 184 } }   -- Maranda's door: the walks step round it
local ROTATION_BUDGET, ROTATIONS = 60, 12
local GIL_FLOOR = 60000                              -- a top-up at Kohlingen's counter (gen_wor_dino's)

-- the experience a trainee still needs for its goal (LevelUpExp x8, field/event.asm; the ROM's own table)
local function xpOf(ch) return H.readByte(c(ch, 0x11)) | H.readByte(c(ch, 0x12)) << 8 | H.readByte(c(ch, 0x13)) << 16 end
local function xpFor(level)
  local base, t = H.sym("LevelUpExp") & 0x3FFFFF, 0
  for l = 1, level - 1 do t = t + 8 * (H.readRomByte(base + 2 * (l - 1)) | H.readRomByte(base + 2 * (l - 1) + 1) << 8) end
  return t
end
local function short(ch) return math.max(0, xpFor(GOALS[ch]) - xpOf(ch)) end
local function allDone()
  for _, ch in ipairs(TRAINEES) do if lv(ch) < GOALS[ch] then return false end end
  return true
end
-- the two who still need the most
local PAIR, UNDER = nil, {}
local function pickPair()
  local t = {}
  for _, ch in ipairs(TRAINEES) do if lv(ch) < GOALS[ch] then t[#t + 1] = ch end end
  table.sort(t, function(a, b) return short(a) > short(b) end)
  PAIR = { t[1], t[2] }
  if PAIR[2] == nil then
    -- one left: the next-lowest beside it, who rides along
    local best = nil
    for _, ch in ipairs(TRAINEES) do
      if ch ~= PAIR[1] and (best == nil or lv(ch) < lv(best)) then best = ch end
    end
    PAIR[2] = best
  end
  UNDER = {}
  for _, ch in ipairs(PAIR) do UNDER[ch] = lv(ch) < GOALS[ch] end
  return PAIR
end
-- a rotation ends when one of the pair who sat under its goal reaches it, and the next rotation re-pairs.  A rider
-- (seated beside the last trainee, already at its goal) does not end it: counting the rider ended every rotation
-- at once, and four runs of six in the first sweep spent their last rotations on 0 battles with one trainee a
-- level short (bsweep/b_k2_s0: "rotation 7: 0 battles" .. "rotation 12: 0 battles", MOG L39/40).  Waiting for
-- both instead let the quicker one run on (SETZER, whose Exp. Egg doubles his share, to L50 beside SABIN: 81
-- battles where 63 did, bsweep2)
local function pairDone()
  for _, ch in ipairs(PAIR) do
    if UNDER[ch] and lv(ch) >= GOALS[ch] then return true end
  end
  return false
end
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
  return best
end
local function onWorld()
  return H.worldMode() and H.worldSettled() and H.worldAligned() and not H.battleLoadStarted()
end
local function bagShort()
  local top = H.activeTopLevel()
  return H.invCountOf(POTION) < math.min(99, H.careStockPotions(top, { spend = 30 })) // 2
    or H.invCountOf(FENIX) < math.min(20, top) // 2
end
local function benchLine()
  local t = {}
  for _, ch in ipairs(TRAINEES) do t[#t + 1] = string.format("%s L%d/%d", NAMES[ch], lv(ch), GOALS[ch]) end
  for _, ch in ipairs(FOUR) do t[#t + 1] = string.format("%s L%d", NAMES[ch], lv(ch)) end
  return table.concat(t, ", ")
end
local n0, r0, rot = 0, 0, 0
local function tally(from, what)
  local t, keys = {}, {}
  for i = from + 1, #H.outcomes do
    local o = H.outcomes[i]
    local k = string.format("%s %03X", o.kind, o.form & 0x3FF)
    t[k] = (t[k] or 0) + 1
  end
  for k, v in pairs(t) do keys[#keys + 1] = string.format("%s x%d", k, v) end
  table.sort(keys)
  say("bench", string.format("%s: %d battles (%s); %s", what, #H.outcomes - from, table.concat(keys, ", "),
    benchLine()))
end

-- one rotation: the pair seated beside the carriers in the cabin, the Falcon down on its tile by Maranda, the plain
-- until one of the pair stands at its goal (or the bag runs short), back on the Falcon's tile
local function rotation()
  return H.lazy(function()
    local four = { CARRIERS[1], CARRIERS[2], PAIR[1], PAIR[2] }
    rot = rot + 1
    H.log(string.format("[bench] rotation %d: %s and %s beside %s and %s; %s", rot, NAMES[PAIR[1]], NAMES[PAIR[2]],
      NAMES[CARRIERS[1]], NAMES[CARRIERS[2]], benchLine()))
    return H.seqStep({
      regroup(four),
      liftOff(),
      H.cond(bagShort, { kohlingenStop("the bag short on the bench's training") }, {}),
      H.waitUntil(function() return H.airshipControl() end, 3000, "the pilot's controls", 5),
      H.flyTo(MARANDA_TILE[1], MARANDA_TILE[2], { what = "the Falcon down by Maranda", fight = FIGHT }),
      H.fieldCare({ threshold = 1.0, tag = "before the plain" }),
      H.lazy(function()
        local t = groupTile(PLAIN, H.worldX(), H.worldY(), "the plain by Maranda")
        return H.worldNavTo(t[1], t[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
          avoid = MARANDA_WORLD })
      end),
      H.call(function() r0 = #H.outcomes end),
      K.pace(function() return onWorld() and (pairDone() or bagShort()) end, ROTATION_BUDGET,
        "the plain by Maranda", nil, { pick = inGroup(PLAIN) }),
      H.call(function() tally(r0, string.format("rotation %d", rot)) end),
      H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
        { maxFrames = 6000, playBattles = "tactical", fight = FIGHT, avoid = MARANDA_WORLD }),
    })
  end)
end

H.run({ maxFrames = 4000000 }, {
  H.bootCheckpoint("wor-desert-v1"),
  watches(),
  -- ---- 0. what the plan depends on (#480) -------------------------------------------------------------------
  -- The entry contract holds the story (SHADOW recruited, the Falcon parked by Maranda).  Hard, and asserted here:
  -- every trainee and carrier recruited (the party menu's mask, $1EDE: gen_wor_gogo's GOGO, gen_wor_narshe's UMARO
  -- and the arcs before them), and gil for Kohlingen's counter (the line's purse).  Soft, fixed in the leg: who is
  -- seated (the cabin), the bag (Kohlingen), HP (the care) and the trainees' gear (Kohlingen's gear stop).
  H.call(function()
    say("bench", "boot; " .. benchLine())
    local mask = H.readByte(0x1EDE) | H.readByte(0x1EDF) << 8
    local missing = {}
    for _, ch in ipairs(TRAINEES) do if (mask >> ch) & 1 == 0 then missing[#missing + 1] = NAMES[ch] end end
    for _, ch in ipairs(CARRIERS) do if (mask >> ch) & 1 == 0 then missing[#missing + 1] = NAMES[ch] end end
    H.log("[deps] recruited mask $" .. string.format("%04X", mask) .. "; missing: "
      .. (#missing > 0 and table.concat(missing, ", ") or "none"))
    H.assertEq(#missing, 0, "every trainee and carrier recruited ($1EDE: the arcs up to gen_wor_colosseum)")
    -- the experience table read off the ROM agrees with each trainee's own level (a misread table would train to
    -- the wrong goal)
    for _, ch in ipairs(TRAINEES) do
      H.assertEq(xpFor(lv(ch)) <= xpOf(ch) and xpOf(ch) < xpFor(lv(ch) + 1), true, string.format(
        "%s's experience %d lies between LevelUpExp's L%d (%d) and L%d (%d)", NAMES[ch], xpOf(ch), lv(ch),
        xpFor(lv(ch)), lv(ch) + 1, xpFor(lv(ch) + 1)))
    end
    H.assertEq(H.gil() >= GIL_FLOOR, true, string.format("gil for Kohlingen's top-ups: %d GP, the floor %d (the "
      .. "line's purse)", H.gil(), GIL_FLOOR))
  end),
  -- @@setup-end

  -- ---- 1. the rotations --------------------------------------------------------------------------------------
  -- @@stage bench
  H.call(function() n0 = #H.outcomes end),
  H.repeatN(ROTATIONS, {
    H.cond(function() return not allDone() end, {
      H.call(function() pickPair() end),
      rotation(),
    }, {}),
  }),
  H.call(function()
    H.assertEq(allDone(), true, string.format("every trainee at its goal within %d rotations (%s)", ROTATIONS,
      benchLine()))
    tally(n0, "the bench's training")
  end),

  -- ---- 2. the line's four back, and the save ------------------------------------------------------------------
  -- @@stage save
  regroup(FOUR),
  liftOff(),
  H.cond(bagShort, { kohlingenStop("the restock after the bench's training") }, {}),
  H.waitUntil(function() return H.airshipControl() end, 3000, "the pilot's controls", 5),
  H.flyTo(MARANDA_TILE[1], MARANDA_TILE[2], { what = "the Falcon down by Maranda", fight = FIGHT }),
  H.fieldCare({ threshold = 1.0, tag = "on the Falcon's tile" }),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "settled on the save tile", 5),
  H.call(function()
    for _, ch in ipairs(FOUR) do H.assertEq(partyOf(ch), 1, NAMES[ch] .. " is seated") end
    say("bench", "on the save tile; " .. benchLine())
    H.log("[kit] " .. kitLine(FOUR))
  end),
  H.saveAtCheckpoint("wor-bench-v1"),
  H.saveState("wor_bench.mss"),
  H.logStep(function()
    return string.format("wor_bench generated: %s; beside the Falcon, world (%d,%d), saved in slot 3", benchLine(),
      H.worldX(), H.worldY())
  end),
})
