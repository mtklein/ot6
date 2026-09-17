-- @suite savestate=worldmap_narshe
-- battle_fold: boost folds tiered spells.  Terra casting with pending BP
-- executes the spell a tier up (queued as the -ra/-ga id in CreateAction,
-- so name, animation, and power are the higher tier's own), is charged
-- that tier's own MP, and tier-family spells never take the generic
-- damage multiplier.
--
-- On worldmap_narshe Terra owns Magic (row 2) with Fire ($00, 4 MP) and
-- Cure ($2D, 5 MP), cast through the live menu.  Her pool is 29 MP, which
-- pays Fire 2's 20 once and cannot pay it twice, so the fold under test is
-- pending 1, Fire -> Fire 2 ($00 -> $05, Ot6FoldTbl row 0), priced at
-- Fire 2's own 20.  Ot6InitBP grants 1 opening bp and pending caps at bp,
-- so one R edge arms the fold.
--
--   asserts: $3410 sees the folded tier id at execution, the tier's own
--   mp cost is both queued ($3620 page, Ot6QueueFold -> Ot6SpellMP) and
--   spent (pool delta == 20 exactly), the damage lands in
--   tier-2-potency-without-multiplier bounds, the boost is consumed with
--   regen skipped, and the leftover pool cannot pay the tier again.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/worldmap_narshe.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_MAGIC, ST_TGT, ST_TRANS = 0x05, 0x0E, 0x38, 0x01
local CMD_MAGIC = 0x02
local FIRE, FIRE2, FIRE2_MP = 0x00, 0x05, 20
local CURE, CURE2_MP = 0x2D, 25          -- the other family head she knows
local FIRE_MP, CURE_MP = 4, 5            -- their own base prices
local SPELL_PTR = { [0] = 0x0000, [1] = 0x013C, [2] = 0x0278, [3] = 0x03B4 }

local function pend(slot) return H.readByte(0x3e9d + slot*2) end
local function bp(slot) return H.readByte(0x3e9c + slot*2) end
local function mp(slot) return H.readWord(0x3c08 + slot*2) end
local function cmdRow(slot, cmd)
  for r = 0, 3 do
    if H.readByte(0x202E + slot*12 + r*3) == cmd then return r end
  end
  return nil
end
local function spellIndexOf(slot, id)
  for i = 0, 53 do
    local a = 0x2092 + SPELL_PTR[slot] + i*4
    if H.readByte(a) == id and (H.readByte(a + 1) & 0x80) == 0 then return i end
  end
  return nil
end
-- the whole cost column of a caster's list: 79 rows (the esper row plus 54
-- spells and 24 lores), entry+3, the one cell the number, the grey, the
-- confirm and the charge all read.  Ot6FoldPrices rewrites this column on
-- every recheck, so a snapshot before and after the boost edge says exactly
-- which rows the walk touched.
local LIST_ROWS = 79
local function costColumn(slot)
  local t = {}
  for i = 0, LIST_ROWS - 1 do
    local a = 0x208E + SPELL_PTR[slot] + i*4
    t[i] = { id = H.readByte(a), cost = H.readByte(a + 3) }
  end
  return t
end
local function rowOfSpell(slot, id)
  for i = 0, LIST_ROWS - 1 do
    local a = 0x208E + SPELL_PTR[slot] + i*4
    if i > 0 and H.readByte(a) == id then return i end
  end
  return nil
end
local function worldReady()
  return (H.readWord(0x1f64) & 0x03ff) < 3
     and H.readByte(0x0019) == 0
     and (H.readByte(0x00e7) & 0x01) == 0
end
local function monsterHp()
  local t = 0
  for s = 0, 5 do t = t + H.readWord(0x3bfc + s*2) end
  return t
end

local terra, mp0, mhp0
local spells, queued = {}, {}
-- the computed per-target damage, from $33D0,y, the pre-HP-clamp "damage
-- taken" cell (ApplyDmg caps at 9999).  Monsters are entities 4..9 ->
-- $33D8 + slot*2; $FFFF = no damage, $4000 = the miss flag.  The cell is
-- written and consumed within a frame, so this is a write watch; the
-- 16-bit sta arrives as lo,hi byte pairs.
local maxDmg, dmgSeen, lastLo = 0, {}, {}
local function armDamageWatch()
  emu.addMemoryCallback(function(addr, value)
    local a = addr - 0x7e0000
    if a % 2 == 0 then lastLo[a] = value; return end
    local w = (lastLo[a - 1] or 0) | (value << 8)
    if w ~= 0xFFFF and (w & 0x4000) == 0 and w < 10000 and w > 0 then
      dmgSeen[#dmgSeen + 1] = w
      if w > maxDmg then maxDmg = w end
    end
  end, emu.callbackType.write, 0x7e33d8, 0x7e33e3)
end
local function sawQueuedCost(want)
  for _, v in ipairs(queued) do if v == want then return true end end
  return false
end

-- the per-frame menu policy: Locke defers with X, Terra arms one R edge
-- and casts Fire through her live list.
local mf = 0
local function decide()
  if H.readByte(MENU) == 0 then
    return (H.frame % 8 < 4) and { a = true } or {}
  end
  mf = mf + 1
  if (mf - 1) % 8 >= 4 then return {} end
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  if st == ST_TRANS then return {} end
  local btn
  if act ~= terra then
    btn = (st == ST_CMD) and "x" or "b"
  elseif st == ST_CMD then
    if pend(terra) < 1 then btn = "r"            -- the one real boost edge
    else
      local want = cmdRow(terra, CMD_MAGIC)
      local cur = H.readByte(CMDROW + terra) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    end
  elseif st == ST_MAGIC then
    local i = spellIndexOf(terra, FIRE)
    if i == nil then error("terra's list lost Fire", 0) end
    local wantRow, wantCol = i // 2, i % 2
    local absRow = H.readByte(0x8913 + terra) + H.readByte(0x891B + terra)
    local col = H.readByte(0x8917 + terra)
    btn = "a"
    if absRow ~= wantRow then btn = (absRow < wantRow) and "down" or "up"
    elseif col ~= wantCol then btn = (col < wantCol) and "right" or "left" end
  elseif st == ST_TGT then
    btn = "a"                                    -- default monster target
  else
    btn = "b"
  end
  if btn and (mf - 1) % 8 == 0 then
    H.log(string.format("fold: f%d st=%02x act=%d press %s (pend=%d mp=%d)",
      H.frame, st, act, btn, pend(terra), mp(terra)))
  end
  return btn and { [btn] = true } or {}
end

local plan, idx, goal = nil, 1, { 82, 56 }

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(worldReady, 500, "world-map control", 5),
  H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(function()
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then plan = nil; H.setPad({}); return end
      if not H.worldAligned() then return end
      if not plan or idx > #plan then
        if H.worldX() == goal[1] and H.worldY() == goal[2] then
          goal = (goal[2] == 56) and { 82, 50 } or { 82, 56 }
        end
        plan = H.worldBfs(goal[1], goal[2]); idx = 1
        if not plan or #plan == 0 then plan = nil; H.setPad({}); return end
      end
      local dir = plan[idx]; idx = idx + 1
      if not dir then H.setPad({}); return end
      H.setPad({ [dir] = true })
    end),
  }, "grass-area encounter"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(90),
  H.call(function()
    for slot = 0, 3 do
      if H.readByte(0x3ED8 + slot*2) == 0x00 then terra = slot end
    end
    H.assertEq(terra ~= nil, true, "TERRA is really in this party")
    H.assertEq(cmdRow(terra, CMD_MAGIC) ~= nil, true,
      "her real Magic command exists")
    H.assertEq(spellIndexOf(terra, FIRE) ~= nil, true,
      "and her real list holds Fire")
    mp0 = mp(terra)
    mhp0 = monsterHp()
    H.log(string.format("terra slot %d: bp=%d mp=%d, monsters open at %d hp",
      terra, bp(terra), mp0, mhp0))
    H.assertEq(bp(terra), 1, "she opens with the 1 bp Ot6InitBP grants")
    H.assertEq(mp0 >= FIRE2_MP, true, "the real pool pays Fire 2 once...")
    H.assertEq(mp0 < 2 * FIRE2_MP, true, "...but could not pay it twice")
    H.assertEq(mp0 < 51, true, "...and never pays Fire 3 (preview's arm)")
    emu.addMemoryCallback(function(addr, value)
      spells[#spells + 1] = value
    end, emu.callbackType.write, 0x7e3410, 0x7e3410)
    emu.addMemoryCallback(function(_, value)
      queued[#queued + 1] = value
    end, emu.callbackType.write, 0x7e3620, 0x7e371f)
    armDamageWatch()
    _G.__col0 = costColumn(terra)
    _G.__fireRow = rowOfSpell(terra, FIRE)
    _G.__cureRow = rowOfSpell(terra, CURE)
    H.assertEq(_G.__fireRow ~= nil and _G.__cureRow ~= nil, true,
      "her list really holds rows for Fire and Cure, the two family heads "
      .. "the boost below re-prices")
    H.log(string.format("unboosted column: Fire row %d = %d MP, Cure row "
      .. "%d = %d MP", _G.__fireRow, _G.__col0[_G.__fireRow].cost,
      _G.__cureRow, _G.__col0[_G.__cureRow].cost))
    H.assertEq(_G.__col0[_G.__fireRow].cost, FIRE_MP,
      "Fire's row opens at its own 4")
    H.assertEq(_G.__col0[_G.__cureRow].cost, CURE_MP,
      "Cure's row opens at its own 5")
  end),

  -- The price column, across the R edge.  Ot6FoldPrices walks all 79 rows
  -- since #219 (it has to: a spell outside a tier family now escalates
  -- x2.5 per boost rather than folding), so the regression this guards is
  -- the walk itself -- a column that moved a row it had no business
  -- moving, or missed one it did.  Exactly two rows may change here,
  -- because Fire and Cure are the only spells this party knows and both
  -- are family heads: they go to their folded tiers' own prices, and the
  -- other 77 rows stay byte-for-byte where battle init left them.
  H.driveUntil(function() return pend(terra) >= 1 end, 8000, {
    H.call(function() H.setPad(decide()) end),
  }, "one real R edge arms the boost"),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    local col1 = costColumn(terra)
    local moved = {}
    for i = 0, LIST_ROWS - 1 do
      if col1[i].cost ~= _G.__col0[i].cost then
        moved[#moved + 1] = string.format("row %d ($%02x) %d -> %d",
          i, col1[i].id, _G.__col0[i].cost, col1[i].cost)
      end
    end
    H.log("rows the boost re-priced: " .. table.concat(moved, ", "))
    H.assertEq(#moved, 2, "exactly two rows moved -- the 79-row walk touched "
      .. "Fire's and Cure's and nothing else")
    H.assertEq(col1[_G.__fireRow].cost, FIRE2_MP,
      "Fire's row now carries Fire 2's own 20 -- the number, the grey and "
      .. "the confirm read this cell, so all three follow the fold")
    H.assertEq(col1[_G.__cureRow].cost, CURE2_MP,
      "Cure's row now carries Cure 2's own 25.  A tier family does NOT take "
      .. "#219's 2.5x escalation: the fold IS its escalation")
  end),
  -- One real R edge arms pending 1; the live list then queues the fold.
  -- The drive stops once the cast is charged (mp changed) rather than once
  -- the fold's id appears in $3410, since the charge lands strictly later.
  H.driveUntil(function() return mp(terra) ~= mp0 end, 16000, {
    H.call(function() H.setPad(decide()) end),
  }, "the boosted cast was charged"),
  H.waitUntil(function() return pend(terra) == 0 end, 900,
    "folded cast resolves", 10),
  H.waitFrames(120),
  H.call(function()
    H.setPad({})
    local vals = {}
    for _, v in ipairs(spells) do vals[#vals + 1] = string.format("%02x", v) end
    H.log("spells executed: " .. table.concat(vals, " "))
    local fold2 = false
    for _, v in ipairs(spells) do if v == FIRE2 then fold2 = true end end
    H.assertEq(fold2, true, "the base Fire folded to its next tier ($05)")
    -- Ot6QueueFold re-prices $3620,y off MagicProp after the fold rewrites
    -- $3a7b, so a 20 in this strip is unambiguous: base Fire is 4, Cure is
    -- 5, and nothing else this party can queue costs 20.
    local qv = {}
    for _, v in ipairs(queued) do qv[#qv + 1] = tostring(v) end
    H.log("costs queued: " .. table.concat(qv, " "))
    H.assertEq(sawQueuedCost(FIRE2_MP), true,
      "Fire 2 was QUEUED at its own 20 MP -- boost buys the tempo, not the "
      .. "magnitude (#64)")
    local mp1 = mp(terra)
    H.log(string.format("mp %d -> %d = %d spent", mp0, mp1, mp0 - mp1))
    H.assertEq(mp0 - mp1, FIRE2_MP,
      "and the pool really paid it: exactly Fire 2's 20")
    H.assertEq(mp1 < FIRE2_MP, true,
      "the real wallet after one fold cannot buy a second (#64's economy)")
    -- potency: the fold executed the tier's own record against the
    -- monsters.  The computed damage (numeral cell $33D0,y, pre-HP-clamp)
    -- is the check, because the trash's low HP saturates any HP-drop bound.
    local dv = {}
    for _, v in ipairs(dmgSeen) do dv[#dv + 1] = tostring(v) end
    H.log(string.format("monsters %d -> %d hp; computed damage seen: %s",
      mhp0, monsterHp(), table.concat(dv, " ")))
    H.assertEq(maxDmg >= 150, true, "tier-2 potency applied (not base fire)")
    H.assertEq(maxDmg <= 700, true, "no single-target multiplier double-dip")
    H.assertEq(pend(terra), 0, "pending consumed")
    H.assertEq(bp(terra), 0, "the 1-bp bank is spent, boosted turn regens nothing")
    H.screenshot("fold_cast")
  end),
})
