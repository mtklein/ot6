-- @suite frontier=worldmap_narshe
-- battle_fold: boost folds tiered spells — Terra casting with pending BP
-- executes the spell a tier up (queued as the -ra/-ga id in CreateAction,
-- so name, animation, and power are the higher tier's own), is CHARGED
-- THAT TIER'S OWN MP (issue #64), and tier-family spells never take the
-- generic damage multiplier.
--
-- Issue #75 conversion.  The old apparatus lived on battle_doorstep,
-- where TERRA has no Magic command: it rewrote her $202E rows, cleared
-- her magitek bit, MUDDLED her to force menu-less casts, pinned guards
-- at 3000 HP / stopped them, handed her bp:=3/pending:=2, and pumped her
-- pool to 300 so a folded tier-3 could be observed at all.  On
-- worldmap_narshe she really owns Magic (row 2) with Fire ($00, 4 MP)
-- and Cure ($2D, 5 MP), so the cast goes through the LIVE MENU and every
-- write drops out.  The wallet is real too, and that moves the tier under
-- observation: her measured pool is 29 MP, which pays Fire 2's 20 once
-- and can never pay Fire 3's 51 -- so the fold this test watches is the
-- one a player at this point in the game can actually buy: pending 1,
-- Fire -> Fire 2 ($00 -> $05, Ot6FoldTbl row 0), priced at Fire 2's own
-- 20.  "She can afford it once and not twice" is asserted against the
-- real pool; the tier-3 grey/refusal on this same wallet is
-- battle_preview's arm.  The boost is the OPENING bp (Ot6InitBP gives 1;
-- pending caps at bp), so no banking turns are needed: one real R edge
-- at her window arms the fold.
--
--   asserts: $3410 sees the folded tier id at execution, the TIER's own
--   mp cost is both queued ($3620 page, Ot6QueueFold -> Ot6SpellMP) and
--   spent (pool delta == 20, exact -- no muddle noise anymore), the
--   damage lands in tier-2-potency-without-multiplier bounds, the boost
--   is consumed with regen skipped, and the leftover pool cannot pay the
--   tier again.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/worldmap_narshe.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_MAGIC, ST_TGT, ST_TRANS = 0x05, 0x0E, 0x38, 0x01
local CMD_MAGIC = 0x02
local FIRE, FIRE2, FIRE2_MP = 0x00, 0x05, 20
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
-- the computed per-target damage, from $33D0,y -- the pre-HP-clamp
-- "damage taken" cell ApplyDmg caps at 9999 (battle_main.asm:1965-1975).
-- The grass trash opens at ~33 total HP (measured), so an HP-drop bound
-- SATURATES on a kill; the numeral cell does not.  Monsters are entities
-- 4..9 -> $33D8 + slot*2; $FFFF = no damage, $4000 = the miss flag.
-- The cell is written and consumed within a frame (measured: a per-frame
-- poll saw nothing while 33 hp of damage demonstrably landed), so this is
-- a WRITE WATCH; the 16-bit sta arrives as lo,hi byte pairs.
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

H.run({ maxFrames = 45000 }, {
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
  }, "grass-band encounter"),
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
    -- the wallet facts every price assert below leans on: she can pay the
    -- one-tier fold, and could never pay the two-tier one
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
  end),
  -- one real R edge arms pending 1; the live list then queues the fold
  H.driveUntil(function()
    for _, v in ipairs(spells) do if v == FIRE2 then return true end end
    return false
  end, 16000, {
    H.call(function() H.setPad(decide()) end),
  }, "the boosted cast folded"),
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
    -- THE PROPERTY UNDER TEST (#64): the folded tier's own MP is charged.
    -- (a) THE MECHANISM, exactly.  Ot6QueueFold re-prices $3620,y off
    --     MagicProp after the fold rewrites $3a7b, so a 20 in this strip is
    --     unambiguous: base Fire is 4, Cure is 5, and nothing else this
    --     party can queue costs 20.
    local qv = {}
    for _, v in ipairs(queued) do qv[#qv + 1] = tostring(v) end
    H.log("costs queued: " .. table.concat(qv, " "))
    H.assertEq(sawQueuedCost(FIRE2_MP), true,
      "Fire 2 was QUEUED at its own 20 MP -- boost buys the tempo, not the "
      .. "magnitude (#64)")
    -- (b) THE EFFECT.  The pool really moved by exactly that much: with the
    --     muddle apparatus gone there is no trailing-cast noise, so the old
    --     >= bound sharpens to equality.
    local mp1 = mp(terra)
    H.log(string.format("mp %d -> %d = %d spent", mp0, mp1, mp0 - mp1))
    H.assertEq(mp0 - mp1, FIRE2_MP,
      "and the pool really paid it: exactly Fire 2's 20")
    H.assertEq(mp1 < FIRE2_MP, true,
      "the real wallet after one fold cannot buy a second (#64's economy)")
    -- potency: the fold executed the tier's own record against the
    -- monsters.  The COMPUTED damage (numeral cell $33D0,y, pre-HP-clamp)
    -- is the witness, because the trash's ~33 HP saturates any HP-drop
    -- bound.  MEASURED 2026-08-10: the folded Fire 2 computes 234 here.
    -- Base Fire (power 21 vs Fire 2's 60) would land near 234*21/60 ~ 82,
    -- so the floor is 150 -- above any base-fire roll, half the tier-2
    -- measurement.  A x4 double-dip would compute ~936, over the 700 cap.
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
