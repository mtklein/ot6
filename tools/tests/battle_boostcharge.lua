-- @suite savestate=n024_entry
-- battle_boostcharge.lua -- #226: a boosted SUMMON and a boosted NON-TIER
-- spell, queued and charged through the real battle menu, with the pool's
-- own movement as the measurement.
--
-- #219 gave non-tier magic and summons the same escalating price leaf as
-- Blitz and Tools: Ot6MagicPrice sends anything Ot6InFoldTbl does not claim
-- through Ot6BoostPriceFor, and anything it does claim through Ot6FoldTier
-- to be priced as the tier it folded into.  Until this file, that arm had
-- no measured charge behind it -- only the price table (battle_costtable),
-- the lore rows of battle_fold's column check, and battle_boostprice's
-- Blitz.  No fixture had a caster who knew a non-tier spell they could
-- actually cast, so nothing had ever watched the MP leave the pool.
--
-- The v0.19 release notes state a number to players -- "A boosted Ifrit
-- costs 26 normally, 65 at one pip and 99 at two" -- so this file measures
-- exactly that, plus the other half of the rule beside it.  On ONE caster,
-- LOCKE wearing the Ifrit magicite, whose granted kit (GenjuProp) carries
-- both a non-tier spell (Drain) and a tier-family head (Fire):
--
--   1. the SUMMON, boost 1.  Inferno ($37, MagicProp record esper+$36) is
--      queued at min(99, floor(26 * 2.5 + 0.5)) = 65 and the pool loses 65.
--   2. the SUMMON, boost 2, in a second boot of the same fixture (a divine
--      is once per battle, $3f2e): 99, the ceiling, and the pool loses 99.
--   3. a NON-TIER spell, boost 1.  Drain ($04) is in no row of Ot6FoldTbl,
--      so it takes the 2.5x: 15 -> 38.
--   4. the TIER-FAMILY CONTRAST, the other half of the rule and the likelier
--      place for a regression to hide: a boosted family head folds up a tier
--      and pays THAT TIER'S OWN vanilla MP, not 2.5x on top of its own.
--      Fire ($00) at boost 1 is queued as Fire 2 ($05) and charged Fire 2's
--      20 -- not 4, and not the 10 the escalation would have charged.  Its
--      unboosted cast (4) runs in the same battle as the control.
--
-- Every expected number is DERIVED, never written down: the bases come out
-- of the built ROM's MagicProp+5, the families out of its own Ot6FoldTbl,
-- and the ladder from a local recomputation of the integer identity
-- Ot6BoostPriceFor implements.  Each assertion also names the number it must
-- NOT be -- the base for the escalating arm, the 2.5x for the folding one --
-- and refuses to run if those two happen to coincide, so the file cannot
-- pass under the wrong rule and cannot pass vacuously.
--
-- Why n024_entry.  It is the fixture where the magicite run lives
-- (battle_magicite runs here), its party carries both stones, and LOCKE
-- arrives with a 172-MP pool -- deep enough to pay 65 + 4 + 38 + 20 in one
-- battle and 99 in another, which no earlier fixture's caster can.  The
-- battle is its boss, battle 72, entered the way a player enters it: one
-- step up and one A at the park.  Nothing here needs the boss to die or
-- even to be hurt; the file measures a pool, so it leaves when its
-- measurements are in and boots the fixture again for the second pip.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/n024_entry.mss.lua"

-- ---------------------------------------------------------------- the RAM --
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F
local ST_TRANS, ST_CMD, ST_ITEM, ST_MAGIC, ST_ESPER, ST_TGT, ST_DEF =
  0x01, 0x05, 0x0A, 0x0E, 0x16, 0x38, 0x27
local CMD_FIGHT, CMD_ITEM, CMD_MAGIC, CMD_SUMMON = 0x00, 0x01, 0x02, 0x19
local MLISTPTR = 0x302C                  -- per-slot pointer to the spell list
local MSCROLL, MCOL, MROW = 0x8913, 0x8917, 0x891B
local SUMMONED = 0x3F2E                  -- the once-per-battle divine latch
local RELIC2 = 0x3C45                    -- relic effects 2: $40 economizer,
local RELIC_MP = 0x60                    --   $20 gold hairpin

local LOCKE, IFRIT = 0x01, 0x01          -- character id; GenjuProp index
local INFERNO = 0x37                     -- IFRIT's MagicProp record (idx+$36)
local FIRE, DRAIN = 0x00, 0x04           -- the granted kit's head and non-tier
local ANCHOR = 99                        -- the two-digit display ceiling

local function bp(s) return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function mp(s) return H.readWord(0x3C08 + s * 2) end
local function hp(s) return H.readWord(0x3BF4 + s * 2) end
local function maxHp(s) return H.readWord(0x3C1C + s * 2) end
local function alive(s) return maxHp(s) > 0 and hp(s) > 0 end
local function charPos(c) return (H.readByte(0x1850 + c) >> 3) & 0x03 end

-- ---------------------------------------------------------------- the ROM --
-- The price rule, recomputed here rather than copied from the library or
-- from the ROM's own arithmetic: Ot6BoostPriceFor computes
-- (base * 5^n + 2^(n-1)) >> n capped at 99, which is exactly
-- min(99, floor(base * 2.5^n + 1/2)) for n = 0..3, floored at the base so
-- the cap can never make a boost cheaper than not boosting.
local function boosted(base, n)
  if n == 0 then return base end
  local x = base
  for _ = 1, n do x = x * 5 end
  x = (x + (1 << (n - 1))) >> n
  return math.max(base, math.min(ANCHOR, x))
end

local magicProp, foldTbl
local function baseMp(id) return H.readRomByte(magicProp + id * 14 + 5) end
-- Ot6FoldTbl, read out of the built ROM: 8 rows of [base, +1, +2].  Returns
-- the id `steps` tiers above `id`, or nil when the id is in no family (which
-- is exactly the test Ot6InFoldTbl makes, byte for byte).
local function foldTo(id, steps)
  for r = 0, 7 do
    if H.readRomByte(foldTbl + r * 3) == id then
      return H.readRomByte(foldTbl + r * 3 + steps)
    end
  end
  return nil
end

-- ------------------------------------------------------------- the lists --
local function listBase(s) return H.readWord(MLISTPTR + s * 2) end
local function recCost(s, n) return H.readByte(listBase(s) + n * 4 + 3) end
local function recId(s, n) return H.readByte(listBase(s) + n * 4) end
local function recEnabled(s, n) return H.readByte(listBase(s) + n * 4 + 1) < 0x80 end
local function recOf(s, id)
  for n = 1, 78 do if recId(s, n) == id then return n end end
  return nil
end
local function cmdCellOf(s, cmd)
  for i = 0, 3 do
    if H.readByte(CMDTBL + s * 12 + i * 3) == cmd then return i end
  end
  return nil
end

-- ----------------------------------------------------------- the charge --
-- One write watch on the mp-cost queue.  CreateAction banks vanilla's
-- GetMPCost answer into $3620,y (battle_main.asm:13270) and Ot6QueueFold
-- then re-derives the price and stores it again, so one queued action can
-- leave more than one store behind: measured on this ROM, the boosted Drain
-- and the boosted Fire each left two ({38,38} and {20,20}) and the boosted
-- summon left one ({65}).  The watch keeps every store and takes the LAST,
-- which is what the queue carries into CalcAttackEffect either way -- and
-- the pool's own movement below is the check on that reading.  X is the
-- attacker entity at that instruction (Ot6AbilityCost's and Ot6QueueFold's
-- own site contract), which is what keeps a monster's queued action, or
-- another party member's, out of the measurement.
local rec = nil
local function armWatch()
  emu.addMemoryCallback(function(_, v)
    if rec == nil or rec.spent ~= nil then return end
    if (emu.getState()["cpu.x"] & 0xffff) ~= rec.slot * 2 then return end
    if H.readByte(0x3A7A) ~= rec.cmd then return end
    rec.stores[#rec.stores + 1] = v
    rec.qcost, rec.atk = v, H.readByte(0x3A7B)
    if not rec.queued then
      rec.queued = true
      -- the pool AT QUEUE TIME, read inside the live battle: the charge
      -- lands later, at CalcAttackEffect, and $3C08 reads $FFFF once a
      -- battle tears down (battle_boostprice measured that as "spent
      -- -65466"), so both ends are sampled while the battle is up
      rec.mp0 = mp(rec.slot)
    end
  end, emu.callbackType.write, 0x7E3620, 0x7E3620 + 0xFE)
end
local function charged()
  if rec.spent == nil and H.battleActive() and rec.mp0 then
    local m = mp(rec.slot)
    if m < 0x8000 and m < rec.mp0 then rec.spent = rec.mp0 - m end
  end
  return rec.spent ~= nil
end

-- ------------------------------------------------------------ the driver --
local locke                               -- LOCKE's battle slot this boot
local want = { slot = nil, bank = 0, pend = 0, mode = "idle", spell = nil }
local armed = false                       -- this target window is ours
local ph, hbF = 0, -900
local tc = H.targetCursor({ mask = 0x7B7D,
                            dirs = { "down", "up", "left", "right" } })

local TONIC, POTION, XPOTION, FENIX = 0xE8, 0xE9, 0xEA, 0xF0
local HEAL_PCT = 55
local function bagIdxOf(id)
  for i = 0, 251 do
    if H.readByte(0x2686 + i * 5) == id and H.readByte(0x2686 + i * 5 + 3) > 0 then
      return i
    end
  end
  return nil
end
-- The bench: keep everyone standing and DO NOT hurry the boss along.  A
-- character with nothing to heal takes a real Defend (RIGHT opens the Def.
-- window $27, A commits it), which spends the turn, halves what the boss
-- lands, and leaves battle 72's HP alone -- this file needs turns, not a
-- corpse, and a bench that plain-Fights can end the battle out from under a
-- measurement that has not been taken yet.  Healing comes first: a deferring
-- bench is what wiped battle_magicite's party on this same fixture.
local function carePlan()
  for s = 0, 3 do
    if maxHp(s) > 0 and hp(s) == 0 and bagIdxOf(FENIX) then
      return { item = FENIX, target = s, why = "down" }
    end
  end
  local worst, wpct = nil, 101
  for s = 0, 3 do
    if alive(s) then
      local pct = hp(s) * 100 // maxHp(s)
      if pct < wpct then worst, wpct = s, pct end
    end
  end
  if worst and wpct < HEAL_PCT then
    local item = (wpct < 25 and bagIdxOf(XPOTION) and XPOTION)
              or (bagIdxOf(POTION) and POTION)
              or (bagIdxOf(TONIC) and TONIC) or nil
    if item then
      return { item = item, target = worst,
               why = string.format("at %d%%", wpct) }
    end
  end
  return nil
end

local plans, planKey, steerBails = {}, {}, 0
local function safeSteer(act, target)
  local ok, r = pcall(tc.steer, target, ph)
  if ok then return r end
  steerBails = steerBails + 1
  H.log(string.format("[steer f%d] actor=%d bail %d: %s", H.frame, act,
    steerBails, tostring(r)))
  if steerBails >= 3 then error(r, 0) end
  plans[act], planKey[act] = nil, nil
  return "b"
end

local function benchTurn(a, st)
  local btn
  if st == ST_CMD then
    local p = carePlan()
    local key = p and string.format("%02X/%d", p.item, p.target) or "-"
    if key ~= planKey[a] then
      planKey[a] = key
      if p then
        H.log(string.format("[bench f%d] actor=%d item $%02X on slot %d (%s) "
          .. "-- hp %d/%d/%d/%d", H.frame, a, p.item, p.target, p.why,
          hp(0), hp(1), hp(2), hp(3)))
      end
    end
    plans[a] = p
    if p then
      local cell = cmdCellOf(a, CMD_ITEM)
      if cell == nil then btn = "right" else
        local cur = H.readByte(CMDROW + a) & 3
        btn = (cur == cell) and "a" or ((cur < cell) and "down" or "up")
      end
    else
      btn = "right"                       -- open the Def. window
    end
  elseif st == ST_DEF then
    btn = "a"                             -- commit the Defend
  elseif st == ST_ITEM then
    local p = plans[a]
    local wantIdx = p and bagIdxOf(p.item)
    if wantIdx == nil then btn = "b" else
      local cur = H.readByte(0x8947 + a) + H.readByte(0x894F + a)
      if cur < wantIdx then btn = "down"
      elseif cur > wantIdx then btn = "up"
      else btn = "a" end
    end
  elseif st == ST_TGT then
    local p = plans[a]
    if p == nil then btn = "b" else btn = safeSteer(a, p.target) end
  else
    btn = nil
  end
  H.setPad(btn and { [btn] = true } or {})
end

local function heartbeat()
  if H.frame - hbF < 900 then return end
  hbF = H.frame
  H.log(string.format("[hb f%d] mode=%s pend=%s bank=%s mp=%s | menu=%02x "
    .. "actor=%s st=%02x | hp %d/%d/%d/%d | $3f2e=%04x", H.frame, want.mode,
    want.slot and pend(want.slot) or "?", want.slot and bp(want.slot) or "?",
    want.slot and mp(want.slot) or "?", H.readByte(MENU),
    tostring(H.readByte(ACTOR)), H.readByte(MSTATE),
    hp(0), hp(1), hp(2), hp(3), H.readWord(SUMMONED)))
end

-- The per-frame driver.  Off-battle it pages dialogs; in battle the bench
-- runs above and the measuring character is driven to `want`.  The three
-- wants are ordered and the order matters: a pending boost is LOWERED first
-- (banking is real unboosted actions, and an action taken with a pending
-- live is charged the pip), then the bank is filled, then the pending is
-- raised to exactly what the arm asked for -- exactly, because the price
-- under test is a function of it.
local function pulse()
  ph = ph + 1
  heartbeat()
  if not H.battleLoadStarted() then
    H.setPad(ph % 8 < 4 and { a = true } or {})
    return
  end
  if H.readByte(MENU) == 0 then
    H.setPad(ph % 8 < 4 and { a = true } or {})
    return
  end
  tc.observe()
  if ph % 10 >= 5 then H.setPad({}); return end
  local a, st = H.readByte(ACTOR) & 3, H.readByte(MSTATE)
  if st == ST_TRANS then H.setPad({}); return end
  if want.slot == nil or a ~= want.slot then return benchTurn(a, st) end

  local btn
  if st == ST_CMD then armed = false end
  if pend(a) > want.pend then
    btn = (st == ST_CMD) and "l" or "b"
  elseif bp(a) < want.bank then
    if st == ST_CMD then
      -- a plain, unboosted Fight is what banks a pip (Ot6ActionEnd)
      local cell = cmdCellOf(a, CMD_FIGHT) or 0
      local cur = H.readByte(CMDROW + a) & 3
      btn = (cur == cell) and "a" or ((cur < cell) and "down" or "up")
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
  elseif pend(a) < want.pend then
    btn = (st == ST_CMD) and "r" or "b"
  elseif want.mode == "idle" then
    if st == ST_CMD then btn = "x"        -- defer: the next window sooner
    elseif st == ST_TGT or st == ST_MAGIC or st == ST_ESPER then btn = "b"
    else btn = nil end
  elseif st == ST_CMD then
    local cell = cmdCellOf(a, CMD_MAGIC)
    assert(cell, "the measuring character's command list carries Magic")
    local cur = H.readByte(CMDROW + a) & 3
    btn = (cur == cell) and "a" or ((cur < cell) and "down" or "up")
  elseif st == ST_MAGIC then
    if want.mode == "summon" then
      btn = "up"                          -- UP off row 0 opens the esper window
    else
      local n = recOf(a, want.spell)
      if n == nil then btn = "b" else
        local wr, wc = (n - 1) // 2, (n - 1) % 2
        local ar = H.readByte(MSCROLL + a) + H.readByte(MROW + a)
        local col = H.readByte(MCOL + a)
        if ar < wr then btn = "down"
        elseif ar > wr then btn = "up"
        elseif col < wc then btn = "right"
        elseif col > wc then btn = "left"
        else
          -- the number the player is looking at, latched at the confirm
          rec.drawn, armed = recCost(a, n), true
          btn = "a"
        end
      end
    end
  elseif st == ST_ESPER then
    if want.mode == "summon" then
      rec.drawn, armed = recCost(a, 0), true
      btn = "a"
    else btn = "b" end
  elseif st == ST_TGT then
    btn = armed and "a" or "b"
  else
    btn = "b"
  end
  H.setPad(btn and { [btn] = true } or {})
end

local function step(what, cond, budget)
  return H.driveUntil(cond, budget or 30000,
    { H.call(pulse), H.waitFrames(1) }, what)
end

-- ------------------------------------------------------- one measurement --
local measured = {}
-- Arm the want, watch the queue take a price, watch the pool lose it, and
-- assert both against a number derived from the ROM -- and against the
-- number the OTHER rule would have produced, so the arm cannot pass under
-- the wrong one.
local function measure(spec)
  return H.repeatN(1, {
    H.call(function()
      local base = baseMp(spec.id)
      local price, notIt, why = spec.price(base)
      H.assertEq(price ~= notIt, true, string.format(
        "[%s] premise: the price under test (%d) and the price the other "
        .. "rule would charge (%d) must be different numbers, or this arm "
        .. "asserts nothing", spec.tag, price, notIt))
      H.assertEq(mp(locke) >= price, true, string.format(
        "[%s] premise: LOCKE's real pool (%d) covers the %d this costs -- an "
        .. "unaffordable boost is greyed and refused at the confirm (#219 "
        .. "ruling 2), which is a different measurement", spec.tag,
        mp(locke), price))
      rec = { slot = locke, cmd = spec.cmd, stores = {}, queued = false,
              want = price, notIt = notIt, why = why, tag = spec.tag,
              base = base, id = spec.id, pend = spec.pend }
      armed = false
      want.slot, want.bank, want.pend = locke, spec.pend, spec.pend
      want.mode, want.spell = spec.mode, spec.id
      H.log(string.format("[%s] arming: %s at boost %d -- base %d, the rule "
        .. "says %d, the other rule would say %d; pool %d, bank %d, pending %d",
        spec.tag, spec.name, spec.pend, base, price, notIt, mp(locke),
        bp(locke), pend(locke)))
    end),
    step("[" .. spec.tag .. "] the action reaches the queue",
      function() return rec.queued end),
    H.call(function()
      H.log(string.format("[%s] drawn %s, queue stores {%s} -> %d, attack "
        .. "$%02X, pool at queue %d", spec.tag, tostring(rec.drawn),
        table.concat(rec.stores, ","), rec.qcost, rec.atk, rec.mp0))
      H.assertEq(rec.drawn, rec.want, string.format(
        "[%s] the number the list DREW beside %s at boost %d is %d -- %s",
        spec.tag, spec.name, spec.pend, rec.want, rec.why))
      H.assertEq(rec.qcost, rec.want, string.format(
        "[%s] ...and the queue took the same %d, not the %d the other rule "
        .. "would have charged (#219 ruling 3: one arithmetic authority)",
        spec.tag, rec.want, rec.notIt))
      if spec.queuedAs then
        H.assertEq(rec.atk, spec.queuedAs, string.format(
          "[%s] the queue carries attack $%02X -- %s", spec.tag,
          spec.queuedAs, spec.queuedAsWhy))
      end
    end),
    step("[" .. spec.tag .. "] the action resolves and the pool moves",
      charged, 20000),
    H.call(function()
      H.log(string.format("[%s] CHARGE: LOCKE MP %d -> %d, spent %d (rule %d, "
        .. "other rule %d, base %d)", spec.tag, rec.mp0, rec.mp0 - rec.spent,
        rec.spent, rec.want, rec.notIt, rec.base))
      H.assertEq(rec.spent, rec.want, string.format(
        "[%s] %s at boost %d took exactly %d MP out of the pool -- %s.  It is "
        .. "NOT %d, which is what %s would have charged", spec.tag, spec.name,
        spec.pend, rec.want, rec.why, rec.notIt, spec.otherRule))
      want.mode = "idle"
      measured[#measured + 1] = string.format("%s@%d=%d", spec.name,
        spec.pend, rec.spent)
    end),
  })
end

-- the price arms, as functions of the base so nothing is a constant
local function escalate(n)
  return function(base)
    return boosted(base, n), base,
      string.format("a verb outside Ot6FoldTbl takes Ot6BoostPriceFor's "
        .. "x2.5 per pending level: min(99, floor(%d x 2.5^%d + 0.5)) = %d",
        base, n, boosted(base, n))
  end
end
local function flat()
  return function(base)
    return base, boosted(base, 1),
      "an unboosted cast pays its own base price, the number the boosted "
      .. "arms below are measured against"
  end
end
local function tierPrice(n, headId)
  return function(base)
    local folded = foldTo(headId, n)
    local price = baseMp(folded)
    return price, boosted(base, n),
      string.format("a tier-family head folds up %d tier(s) to $%02X and pays "
        .. "THAT tier's own vanilla MP (%d), which is the escalation -- the "
        .. "2.5x never applies on top of it", n, folded, price)
  end
end

-- ------------------------------------------------------------- the boots --
local function enterBoss(tag)
  return H.repeatN(1, {
    H.hold({ "up" }), H.waitFrames(4), H.release(), H.waitFrames(10),
    H.driveUntil(function() return H.battleLoadStarted() end, 3000, {
      H.pressButtons({ "a" }, 4), H.waitFrames(20),
    }, tag .. ": battle 72 opens"),
    H.waitUntil(function() return H.battleActive() end, 900,
      tag .. ": battle active", 30),
    H.waitFrames(150),
    H.call(function()
      locke = nil
      for s = 0, 3 do
        if H.readByte(0x3ED8 + s * 2) == LOCKE then locke = s end
      end
      H.assertEq(locke ~= nil, true, tag .. ": LOCKE really fights this")
      plans, planKey, steerBails = {}, {}, 0
      want.slot, want.mode, want.bank, want.pend = locke, "idle", 0, 0
      -- The pricing under test is MagicProp's, through Ot6SpellMP.  Two
      -- relics rewrite that leaf's answer before the boost ever sees it
      -- (economizer flattens to 1, gold hairpin halves), so a caster
      -- wearing one would measure a different, equally correct number
      -- against a base this file read straight from the table.
      H.assertEq(H.readByte(RELIC2 + locke * 2) & RELIC_MP, 0, string.format(
        "%s: LOCKE wears no Economizer or Gold Hairpin ($3c45 = $%02X), so "
        .. "MagicProp+5 IS the base Ot6SpellMP hands the boost", tag,
        H.readByte(RELIC2 + locke * 2)))
      H.assertEq(recId(locke, 0), IFRIT,
        tag .. ": list record 0 is the equipped IFRIT's summon row")
      H.assertEq(recEnabled(locke, 0), true,
        tag .. ": the summon is offered (nobody has spent it yet)")
      H.assertEq(H.readWord(SUMMONED) & (1 << locke), 0,
        tag .. ": $3f2e clear -- the once-per-battle divine is unspent")
      H.assertEq(recCost(locke, 0), baseMp(INFERNO), string.format(
        "%s: the UNBOOSTED summon row draws its base %d -- the control the "
        .. "boosted numbers below are not", tag, baseMp(INFERNO)))
      H.log(string.format("%s: LOCKE slot %d, %d MP, bank %d, pending %d; "
        .. "summon row draws %d", tag, locke, mp(locke), bp(locke),
        pend(locke), recCost(locke, 0)))
    end),
  })
end

local function bootPrologue(tag)
  return H.repeatN(1, {
    H.loadState(STATE),
    H.waitFrames(60),
    H.call(function()
      H.assertEq(H.readByte(0x1A69) & 0x02, 0x02,
        tag .. ": the IFRIT magicite is really in the bag ($1A69)")
    end),
    H.equipEsper(function() return charPos(LOCKE) end, IFRIT,
      { tag = tag .. " IFRIT -> LOCKE" }),
    H.call(function()
      H.assertEq(H.readByte(0x1600 + 37 * LOCKE + 0x1E), IFRIT,
        tag .. ": LOCKE really wears the stone (+$1E)")
    end),
    H.fieldCare({ tag = tag .. " before battle 72", threshold = 0.95,
                  magic = false }),
    enterBoss(tag),
  })
end

H.run({ maxFrames = 260000 }, {
  H.waitFrames(20),
  H.call(function()
    magicProp = H.sym("MagicProp") & 0x3FFFFF
    foldTbl = H.sym("Ot6FoldTbl") & 0x3FFFFF
    armWatch()
    -- The rule, against the library's own transcription of it (H.boostPrice
    -- is what the fight driver prices a boost with).  battle_boostprice pins
    -- that transcription over every byte base; this is the narrow agreement
    -- check for the four numbers this file then goes and measures.
    for _, c in ipairs({ { INFERNO, 1 }, { INFERNO, 2 }, { DRAIN, 1 },
                         { FIRE, 1 } }) do
      H.assertEq(H.boostPrice(baseMp(c[1]), c[2]), boosted(baseMp(c[1]), c[2]),
        string.format("H.boostPrice agrees with this file's own "
          .. "recomputation for $%02X at boost %d", c[1], c[2]))
    end
    -- Ot6FoldTbl decides WHICH rule applies, and it is the ROM's own bytes
    -- that decide it: Fire is a family head, Drain is in no row, and an
    -- esper's record is not a spell id at all.
    H.assertEq(foldTo(FIRE, 1) ~= nil, true,
      "Fire ($00) is a tier-family head in the shipped Ot6FoldTbl")
    H.assertEq(foldTo(DRAIN, 1), nil,
      "Drain ($04) is in NO row of Ot6FoldTbl, so Ot6MagicPrice sends it to "
      .. "Ot6BoostPriceFor -- that is the arm #226 says nothing has measured")
    H.assertEq(foldTo(INFERNO, 1), nil,
      "and an esper's record ($37) is in no family either: espers escalate")
    H.log(string.format("the shipped ladder: IFRIT/Inferno base %d -> %d at "
      .. "one pip -> %d at two; Drain %d -> %d; Fire %d -> Fire 2 ($%02X) at "
      .. "%d", baseMp(INFERNO), boosted(baseMp(INFERNO), 1),
      boosted(baseMp(INFERNO), 2), baseMp(DRAIN), boosted(baseMp(DRAIN), 1),
      baseMp(FIRE), foldTo(FIRE, 1), baseMp(foldTo(FIRE, 1))))
    -- The published claim, as a claim.  docs/release-notes-v0.19.md tells
    -- players "A boosted Ifrit costs 26 normally, 65 at one pip and 99 at
    -- two"; the numbers are derived above, and this is where a ROM edit that
    -- moves them stops being silent.
    H.assertEq(baseMp(INFERNO), 26,
      "release notes v0.19: a boosted Ifrit costs 26 normally")
    H.assertEq(boosted(baseMp(INFERNO), 1), 65,
      "release notes v0.19: ...65 at one pip")
    H.assertEq(boosted(baseMp(INFERNO), 2), 99,
      "release notes v0.19: ...and 99 at two")
  end),

  -- ===================================================== boot A: one pip ==
  -- LOCKE's five turns, in the order his bank can pay for: the divine first
  -- (a 172-MP pool, and it is the dearest thing here), then the family head
  -- unboosted as the control, then the non-tier spell boosted, then a plain
  -- Fight to bank the pip the folded cast needs, then the fold.
  bootPrologue("bootA"),
  measure({ tag = "summon", name = "Inferno (IFRIT)", id = INFERNO,
            cmd = CMD_SUMMON, mode = "summon", pend = 1,
            price = escalate(1),
            otherRule = "leaving summons unpriced by the boost, as they were "
              .. "before #219" }),
  H.call(function()
    H.assertEq(H.readWord(SUMMONED) & (1 << locke) ~= 0, true,
      "[summon] the engine really spent the once-per-battle divine ($3f2e) "
      .. "-- the 65 bought a summon, not a refused menu press")
    H.screenshot("boostcharge_summon_boost1")
  end),
  measure({ tag = "fold-control", name = "Fire", id = FIRE, cmd = CMD_MAGIC,
            mode = "spell", pend = 0, price = flat(),
            queuedAs = FIRE,
            queuedAsWhy = "an unboosted head does not fold: it is queued as "
              .. "itself",
            otherRule = "a pending pip, which is the point of the control -- "
              .. "the escalation is self-restoring at boost 0" }),
  measure({ tag = "nontier", name = "Drain", id = DRAIN, cmd = CMD_MAGIC,
            mode = "spell", pend = 1, price = escalate(1),
            queuedAs = DRAIN,
            queuedAsWhy = "a non-tier spell has no tier to fold into; only "
              .. "its price moves",
            otherRule = "the pre-#219 rule, where only tier-family magic "
              .. "cost more under a boost" }),
  measure({ tag = "fold", name = "Fire", id = FIRE, cmd = CMD_MAGIC,
            mode = "spell", pend = 1, price = tierPrice(1, FIRE),
            queuedAs = nil,       -- filled in below, from the ROM's own table
            otherRule = "applying the 2.5x escalation to a spell that already "
              .. "escalates by folding a tier -- which would charge twice for "
              .. "one boost" }),
  H.call(function()
    H.assertEq(rec.atk, foldTo(FIRE, 1), string.format(
      "[fold] the queue carries attack $%02X: the boost really folded Fire up "
      .. "a tier, and the %d it charged is that tier's own vanilla MP",
      foldTo(FIRE, 1), rec.want))
    H.screenshot("boostcharge_fold_boost1")
    H.log("[bootA] " .. table.concat(measured, " "))
  end),

  -- ===================================================== boot B: two pips ==
  -- A divine is once per battle and this one is spent, so the second pip
  -- needs a second battle: the fixture is booted again and battle 72 entered
  -- again, which is the same fight a player who reloaded their save would
  -- walk into.  LOCKE opens at 1 BP (Ot6InitBP), so one plain unboosted
  -- Fight banks the second pip before the boost can be raised to two.
  bootPrologue("bootB"),
  measure({ tag = "summon2", name = "Inferno (IFRIT)", id = INFERNO,
            cmd = CMD_SUMMON, mode = "summon", pend = 2,
            price = escalate(2),
            otherRule = "leaving summons unpriced by the boost, as they were "
              .. "before #219" }),
  H.call(function()
    H.assertEq(rec.spent, ANCHOR, string.format(
      "[summon2] two pips put Inferno on the ceiling: %d x 2.5^2 = %d, capped "
      .. "to the %d a two-digit price drawer can render (#219 ruling 1)",
      baseMp(INFERNO), math.floor(baseMp(INFERNO) * 6.25 + 0.5), ANCHOR))
    H.assertEq(H.readWord(SUMMONED) & (1 << locke) ~= 0, true,
      "[summon2] and the engine spent the divine for it")
    H.screenshot("boostcharge_summon_boost2")
    H.log("[measured] " .. table.concat(measured, " "))
    H.log("PASSED: the drawn number, the queued price and the pool agree, "
      .. "for a boosted summon, a boosted non-tier spell, and a folded "
      .. "family head that pays its tier rather than 2.5x on top of it")
  end),
})
