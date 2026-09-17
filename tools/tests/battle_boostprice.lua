-- @suite savestate=vargas_won slow
-- battle_boostprice.lua -- #219: every boosted ability except Fight costs
-- escalating MP.  price = min(99, floor(base * 2.5^boost + 0.5)), so a
-- boost buys its multiplier (or its odds) at x2.5 the base price per level,
-- capped at the two-digit ceiling.
--
-- This is the mechanism half of that rule: the boosted number is taken
-- through the real menu, on a real battle, at a real pending boost raised
-- by real R presses, and the three surfaces that state a price are made to
-- agree with each other and with the pool the charge actually moves:
--
--   the stamp   wItemList::Qty, written when the kit window opens
--               (Ot6BlitzListOpen / Ot6ThiefListOpen -> Ot6PendPrice)
--   the grey    the row's font attribute, written per draw by the row
--               decorator (Ot6KitRowCost -> Ot6AbilityGrey).  A row is
--               white iff the caster can pay the BOOSTED price, so the
--               colour is an independent reading of the same number: it
--               flips exactly where the escalated price crosses the pool.
--   the charge  the mp-cost queue store in CreateAction ($3620,y, what
--               Ot6AbilityCost handed back) and then the MP the pool
--               really loses.
--
-- vargas_won carries SABIN (Blitz), LOCKE (Steal) and EDGAR, so one fixture
-- covers both a multiplier verb and a chance verb.  Asserted:
--   1. boost 0 is the base price, on the same window, as the control.
--   2. boost N stamps min(99, floor(base * 2.5^N + 0.5)) on every learned
--      Blitz row, and greys exactly the rows that price out of the pool.
--   3. a boosted Blitz is queued at the boosted price and deducts it.
--   4. LOCKE's Steal row escalates the same way, while Filch and Bestow --
--      which a boost buys nothing at all -- stay flat.
--   5. a boosted Steal is queued at the boosted price and deducts it.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vargas_won.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_TRANS, ST_CMD, ST_TOOLS, ST_TGT = 0x01, 0x05, 0x30, 0x38
local CMD_BLITZ, CMD_STEAL = 0x0A, 0x05
local CMDTBL, CMDROW, ITEMLIST, KNOWN = 0x202E, 0x890F, 0x4005, 0x1D28
local SABIN, LOCKE = 0x05, 0x01
local BLITZ_ATK0 = 0x5D
local THIEF_STEAL, THIEF_FILCH, THIEF_BESTOW = 0x56, 0x57, 0x58
local WHITE, GREY = 0x21, 0x25
local ANCHOR = 99

local function bp(s) return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function mp(s) return H.readWord(0x3C08 + s * 2) end

-- The price rule, recomputed rather than copied: Ot6BoostPriceFor does
-- (base * 5^n + 2^(n-1)) >> n, capped at 99, which is exactly
-- min(99, floor(base * 2.5^n + 1/2)) for n = 0..3.
local function boosted(base, n)
  if n == 0 then return base end
  local x = base
  for _ = 1, n do x = x * 5 end
  x = (x + (1 << (n - 1))) >> n
  return math.min(ANCHOR, x)
end

local COSTTBL = H.sym("Ot6AbilityCostTbl") & 0x3FFFFF
local function costOf(id)
  local x = 0
  while true do
    local key = H.readRomByte(COSTTBL + x)
    if key == 0xff then return 0 end
    if key == id then return H.readRomByte(COSTTBL + x + 1) end
    x = x + 2
  end
end
local THIEFTBL = H.sym("Ot6ThiefCostTbl") & 0x3FFFFF
local function thiefCostOf(id)
  local x = 0
  while true do
    local key = H.readRomByte(THIEFTBL + x)
    if key == 0xff then return 0 end
    if key == id then return H.readRomByte(THIEFTBL + x + 1) end
    x = x + 2
  end
end
local STEAL_BASE                            -- Ot6StealCost's immediate

-- name glyph runs, for the font-attribute read (battle_blitzgrey's idiom)
local ATKNAME = H.sym("AttackName") & 0x3FFFFF
local ATKNAME_0, NAME_SIZE = 0x51, 10
local function nameSeq(id)
  local t = {}
  for i = 0, NAME_SIZE - 1 do
    t[#t + 1] = H.readRomByte(ATKNAME + (id - ATKNAME_0) * NAME_SIZE + i)
  end
  while #t > 0 and t[#t] == 0xff do table.remove(t) end
  return t
end
local function nameText(id)
  local s = ""
  for _, b in ipairs(nameSeq(id)) do
    if b >= 0x80 and b <= 0x99 then s = s .. string.char(65 + b - 0x80)
    elseif b >= 0x9a and b <= 0xb3 then s = s .. string.char(97 + b - 0x9a)
    else s = s .. "?" end
  end
  return s
end
local function attrOf(seq)
  local vr = emu.memType.snesVideoRam
  for w = 0x6000, 0x7FF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then hit = false break end
    end
    if hit then return emu.read(w * 2 + 1, vr) end
  end
  return nil
end

-- ---------------------------------------------------------------- the rig --
-- one write watch on the mp-cost queue: what Ot6AbilityCost returned for the
-- command being queued, captured at the source rather than inferred.
local rec = nil
local function armWatch()
  emu.addMemoryCallback(function(_, v)
    if rec and not rec.queued and H.readByte(0x3A7A) == rec.cmd then
      rec.qcost, rec.queued = v, true
      rec.mp0 = mp(rec.slot)   -- the pool AT QUEUE TIME, inside the live
                               --   battle: the charge lands later, at
                               --   CalcAttackEffect, and a pool sampled from
                               --   a step boundary can straddle a battle end
    end
  end, emu.callbackType.write, 0x7E3620, 0x7E3620 + 0xFE)
end

-- Latch the charge the frame it lands, while the battle is still live.
-- $3C08 is battle RAM and reads $FFFF once a battle tears down, so a plain
-- "has the pool moved?" condition can fire on the teardown instead of on the
-- debit -- measured 2026-09-17: `LOCKE MP 69 -> 65535, spent -65466`.
local function charged()
  if rec.spent == nil and H.battleActive() and rec.mp0 then
    local m = mp(rec.slot)
    if m < 0x8000 and m < rec.mp0 then rec.spent = rec.mp0 - m end
  end
  return rec.spent ~= nil
end

local sabin, locke                       -- battle slots
local learned = {}                       -- SABIN's learned blitz ids
local want = { slot = nil, bank = 0, pend = 0, mode = "idle", row = nil }
local ph, hb = 0, -900
-- the encounter lane: one step out of the anchor tile and one step back,
-- battle_blitzgrey's shape, so the pacing works wherever on map 98 the
-- fixture (or the last victory) left the party standing
local BACK = { left = "right", right = "left", up = "down", down = "up" }
local lane = nil

local function cmdCellOf(slot, cmd)
  for i = 0, 3 do
    if H.readByte(CMDTBL + slot * 12 + i * 3) == cmd then return i end
  end
  return nil
end

local function heartbeat()
  if H.frame - hb < 900 then return end
  hb = H.frame
  H.log(string.format("[hb f%d] mode=%s batt=%s menu=%02x actor=%s st=%02x "
    .. "bank=%s pend=%s mp=%s", H.frame, want.mode,
    tostring(H.battleLoadStarted()), H.readByte(MENU),
    tostring(H.readByte(ACTOR)), H.readByte(MSTATE),
    want.slot and bp(want.slot) or "?", want.slot and pend(want.slot) or "?",
    want.slot and mp(want.slot) or "?"))
end

-- The per-frame driver.  Off-battle it paces a lane on the Kolts ledge for
-- the next natural encounter and pages battle dialogs; in battle every other
-- character takes a real Defend (battle_toolslist's idiom: right swaps the
-- Fight row to Def, then A), which spends their turn without ending the
-- fight, and the target character is driven to `want`.
--
-- The three wants are ordered, and the order matters: a pending boost is
-- LOWERED with L before anything else, because banking is real unboosted
-- Fights and a Fight taken with a pending boost is charged the pip and pays
-- no regen (Ot6ActionEnd), so banking under a live pending never makes
-- progress.  Only then is the bank filled, and only then is the pending
-- raised back to exactly what the arm asked for -- exactly, because the
-- price under test is a function of it.
local function pulse()
  ph = ph + 1
  heartbeat()
  local edge = ph % 10 < 5
  if not H.battleLoadStarted() then
    if not (H.hasControl() and H.tileAligned()) then
      H.setPad(ph % 8 < 4 and { a = true } or {})
      return
    end
    local x, y = H.fieldX(), H.fieldY()
    if lane == nil then
      for _, d in ipairs({ "right", "left", "up", "down" }) do
        if H.canStep(x, y, d) then
          lane = { ax = x, ay = y, out = d, back = BACK[d] }
          break
        end
      end
      if lane == nil then H.setPad({}) return end
    end
    H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
    return
  end
  lane = nil                    -- re-anchor at the next field return
  if H.readByte(MENU) == 0 then
    H.setPad(ph % 8 < 4 and { a = true } or {})
    return
  end
  local a, st = H.readByte(ACTOR) & 3, H.readByte(MSTATE)
  if st == ST_TRANS then H.setPad({}) return end
  if want.slot == nil or a ~= want.slot then
    local sub = ph % 40
    if sub < 4 then H.setPad({ right = true })
    elseif sub >= 20 and sub < 24 then H.setPad({ a = true })
    else H.setPad({}) end
    return
  end
  local btn
  if pend(a) > want.pend then
    btn = (st == ST_CMD) and "l" or "b"
  elseif bp(a) < want.bank then
    -- bank a pip with a plain unboosted Fight (command row 0)
    if st == ST_CMD then
      local cur = H.readByte(CMDROW + a) & 3
      btn = (cur == 0) and "a" or "up"
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
  elseif pend(a) < want.pend then
    btn = (st == ST_CMD) and "r" or "b"
  elseif want.mode == "idle" then
    H.setPad({})
    return
  else
    local cmd = (want.mode == "steal") and CMD_STEAL or CMD_BLITZ
    if st == ST_CMD then
      local cell = cmdCellOf(a, cmd)
      assert(cell, "the target character's command list carries the verb")
      local cur = H.readByte(CMDROW + a) & 3
      btn = (cur == cell) and "a" or ((cur < cell) and "down" or "up")
    elseif st == ST_TOOLS then
      if want.row == nil then H.setPad({}) return end   -- hold the list open
      local entry
      for i = 0, 7 do
        if H.readByte(ITEMLIST + i * 3) == want.row then entry = i end
      end
      if entry == nil then H.setPad({}) return end
      local r, c = entry // 2, entry % 2
      local cr, cc = H.readByte(0x8967 + a), H.readByte(0x8963 + a)
      if cr ~= r then btn = (cr < r) and "down" or "up"
      elseif cc ~= c then btn = (cc < c) and "right" or "left"
      else btn = "a" end
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
  end
  H.setPad(edge and btn and { [btn] = true } or {})
end

local function step(what, cond, budget)
  return H.driveUntil(cond, budget or 40000,
    { H.call(pulse), H.waitFrames(1) }, what)
end

-- bring the target character's kit window up at exactly `n` pending boost,
-- banking pips first if the bank cannot pay for them
local function openAt(slotf, n, verb, what)
  return H.repeatN(1, {
    H.call(function()
      want.slot, want.bank, want.pend = slotf(), n, n
      want.mode, want.row = verb, nil
    end),
    step(what, function()
      local slot = want.slot
      return H.battleLoadStarted() and H.readByte(MENU) ~= 0
         and (H.readByte(ACTOR) & 3) == slot
         and H.readByte(MSTATE) == ST_TOOLS and pend(slot) == n
    end),
    H.waitFrames(30),
  })
end

-- ------------------------------------------------------------- the report --
local blitzAt = {}          -- boost -> { id -> { qty, attr, mp } }

H.run({ maxFrames = 300000 }, {
  -- 0. The FIGHT DRIVER's copy of the rule, against this file's own
  --    recomputation of it.  The driver has to price a boost before it
  --    plans one (#219: an unaffordable boost is refused and the turn
  --    evaporates), so H.boostPrice transcribes Ot6BoostPriceFor into
  --    Lua; everything below then proves that rule against the ROM's
  --    three surfaces, and this step is what keeps the driver's copy on
  --    the same rule instead of drifting into a second opinion.
  H.call(function()
    local n_checked = 0
    for base = 0, 255 do
      for n = 0, 3 do
        local want = math.max(base, boosted(base, n))   -- never below base
        local got = H.boostPrice(base, n)
        if got ~= want then
          error(string.format("H.boostPrice(%d, %d) = %d, the rule says %d",
            base, n, got, want))
        end
        n_checked = n_checked + 1
      end
    end
    H.assertEq(n_checked, 256 * 4,
      "H.boostPrice agrees with the rule for every byte base at boost 0..3")
    -- and the one case the cap's floor exists for: Phoenix's 110 base
    H.assertEq(H.boostPrice(110, 1), 110,
      "the 99 ceiling never makes a boost cheaper than not boosting")
  end),
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control on the Kolts ledge"),
  H.call(function()
    -- Ot6StealCost is `lda #imm / rtl`: the immediate is the price.
    local ofs = H.sym("Ot6StealCost") & 0x3FFFFF
    H.assertEq(H.readRomByte(ofs), 0xa9,
      "Ot6StealCost still opens with LDA #imm -- the +1 read is the price")
    STEAL_BASE = H.readRomByte(ofs + 1)
    local mask = H.readByte(KNOWN)
    for i = 0, 7 do
      if (mask >> i) & 1 == 1 then learned[#learned + 1] = BLITZ_ATK0 + i end
    end
    local names = {}
    for _, id in ipairs(learned) do
      names[#names + 1] = string.format("%s(%d)", nameText(id), costOf(id))
    end
    H.log(string.format("SABIN's learned blitzes: %s; Steal base %d",
      table.concat(names, " "), STEAL_BASE))
    H.assertEq(#learned >= 2, true,
      "two learned blitzes -- the escalation is checked on a real ladder")
    armWatch()
  end),

  step("a ledge encounter fires", function() return H.battleLoadStarted() end,
    20000),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.waitFrames(240),
  H.call(function()
    for s = 0, 3 do
      local who = H.readByte(0x3ED8 + s * 2)
      if who == SABIN then sabin = s end
      if who == LOCKE then locke = s end
    end
    H.assertEq(sabin ~= nil, true, "SABIN is in this party")
    H.assertEq(locke ~= nil, true, "LOCKE is in this party")
    H.log(string.format("SABIN slot %d (%d MP), LOCKE slot %d (%d MP)",
      sabin, mp(sabin), locke, mp(locke)))
  end),

  ----------------------------------------- 1. boost 0: the base, the control --
  openAt(function() return sabin end, 0, "blitz",
    "SABIN's blitz window, unboosted"),
  H.call(function()
    blitzAt[0] = {}
    for _, id in ipairs(learned) do
      local qty
      for i = 0, 7 do
        if H.readByte(ITEMLIST + i * 3) == id then
          qty = H.readByte(ITEMLIST + i * 3 + 1)
        end
      end
      blitzAt[0][id] = { qty = qty, attr = attrOf(nameSeq(id)), mp = mp(sabin) }
      H.log(string.format("  boost 0  %-10s stamp %s  attr %s  (base %d)",
        nameText(id), tostring(qty),
        blitzAt[0][id].attr and string.format("$%02x", blitzAt[0][id].attr)
        or "nil", costOf(id)))
      H.assertEq(qty, costOf(id), string.format(
        "%s is stamped at its base price %d when nothing is boosted -- the "
        .. "escalation is self-restoring at boost 0", nameText(id), costOf(id)))
    end
    H.screenshot("boostprice_blitz_boost0")
  end),

  ----------------------------------- 2/3. boost N: the stamp, the grey, the charge --
  (function()
    -- Every character opens at 1 BP (Ot6InitBP) and banks +1 per unboosted
    -- action, so boost 2 costs one real Fight first.  Two is enough to show
    -- the rule twice over with different multipliers, and the third level is
    -- covered arithmetically over the whole column in battle_costtable.
    local steps = {}
    for _, n in ipairs({ 1, 2 }) do
      steps[#steps + 1] = openAt(function() return sabin end, n, "blitz",
        string.format("SABIN's blitz window at boost %d", n))
      steps[#steps + 1] = H.call(function()
        local pool = mp(sabin)
        blitzAt[n] = {}
        for _, id in ipairs(learned) do
          local qty
          for i = 0, 7 do
            if H.readByte(ITEMLIST + i * 3) == id then
              qty = H.readByte(ITEMLIST + i * 3 + 1)
            end
          end
          local price = boosted(costOf(id), n)
          local attr = attrOf(nameSeq(id))
          blitzAt[n][id] = { qty = qty, attr = attr, mp = pool }
          H.log(string.format("  boost %d  %-10s stamp %s  attr %s  "
            .. "(base %d -> %d, pool %d)", n, nameText(id), tostring(qty),
            attr and string.format("$%02x", attr) or "nil",
            costOf(id), price, pool))
          H.assertEq(qty, price, string.format(
            "%s at boost %d is stamped %d = min(99, floor(%d x 2.5^%d + 0.5)) "
            .. "(#219)", nameText(id), n, price, costOf(id), n))
          H.assertEq(attr, (pool >= price) and WHITE or GREY, string.format(
            "%s at boost %d costs %d against a %d pool, so the row renders "
            .. "%s -- the grey reads the BOOSTED price (#219, ruling 2)",
            nameText(id), n, price, pool,
            (pool >= price) and "white" or "grey"))
        end
        H.screenshot("boostprice_blitz_boost" .. n)
      end)
    end
    return H.repeatN(1, steps)
  end)(),

  H.call(function()
    -- the grey has to have moved somewhere, or the colour assertion above
    -- proved nothing about the boost
    local flipped = {}
    for _, id in ipairs(learned) do
      for _, n in ipairs({ 1, 2 }) do
        if blitzAt[0][id].attr == WHITE and blitzAt[n][id].attr == GREY then
          flipped[#flipped + 1] = string.format("%s at boost %d",
            nameText(id), n)
        end
      end
    end
    H.log("rows the boost priced out: " ..
      (next(flipped) and table.concat(flipped, ", ") or "none"))
    H.assertEq(#flipped > 0, true, string.format(
      "at least one learned blitz that SABIN could afford unboosted is "
      .. "greyed once boosted -- otherwise the pool (%d MP) is too deep for "
      .. "this fixture to exercise ruling 2 and the grey assertions above "
      .. "are vacuous", mp(sabin)))
  end),

  -- ... and the charge: a boosted Blitz the pool CAN pay
  H.call(function()
    local pick, price
    for _, id in ipairs(learned) do
      local p = boosted(costOf(id), 1)
      if mp(sabin) >= p and (pick == nil or p < price) then pick, price = id, p end
    end
    H.assertEq(pick ~= nil, true,
      "SABIN can still afford some blitz at boost 1 -- the charge needs a "
      .. "payable row")
    rec = { cmd = CMD_BLITZ, want = price, id = pick, slot = sabin }
    H.log(string.format("charging a boost-1 %s: %d base -> %d boosted, "
      .. "pool %d", nameText(pick), costOf(pick), price, mp(sabin)))
    want.slot, want.bank, want.pend = sabin, 1, 1
    want.mode, want.row = "blitz", rec.id
  end),
  step("the boosted blitz is queued", function() return rec.queued end),
  H.call(function()
    H.log(string.format("[charge] queued cost %s (want %d)",
      tostring(rec.qcost), rec.want))
    H.assertEq(rec.qcost, rec.want, string.format(
      "Ot6AbilityCost priced the boost-1 %s at %d, not its base %d (#219)",
      nameText(rec.id), rec.want, costOf(rec.id)))
  end),
  step("the boosted blitz resolves and the pool moves", charged, 20000),
  H.call(function()
    local spent = rec.spent
    H.log(string.format("[charge] MP %d -> %d, spent %d",
      rec.mp0, rec.mp0 - spent, spent))
    H.assertEq(spent, rec.want, string.format(
      "the boost-1 %s deducted exactly %d MP -- the drawn price, the queued "
      .. "price and the pool all agree (#219, ruling 3)",
      nameText(rec.id), rec.want))
    want.mode = "idle"
  end),

  ------------------------------------------- 4/5. LOCKE's Steal, a chance verb --
  openAt(function() return locke end, 1, "steal",
    "LOCKE's thief submenu at boost 1"),
  H.call(function()
    local price = boosted(STEAL_BASE, 1)
    local q = {}
    for i = 0, 7 do
      local id = H.readByte(ITEMLIST + i * 3)
      if id ~= 0xff then q[id] = H.readByte(ITEMLIST + i * 3 + 1) end
    end
    H.log(string.format("  boost 1  Steal stamp %s (base %d -> %d), "
      .. "Filch %s, Bestow %s, pool %d", tostring(q[THIEF_STEAL]),
      STEAL_BASE, price, tostring(q[THIEF_FILCH]), tostring(q[THIEF_BESTOW]),
      mp(locke)))
    H.assertEq(q[THIEF_STEAL], price, string.format(
      "Steal at boost 1 is stamped %d: boost buys the rare/guarantee ladder, "
      .. "so it is a chance verb and pays for it (#219)", price))
    H.assertEq(q[THIEF_FILCH], thiefCostOf(THIEF_FILCH),
      "Filch stays flat -- Ot6BoostDmg gives cmd $05 no multiplier and Filch "
      .. "is not a chance verb, so a boost buys it nothing to pay for")
    H.assertEq(q[THIEF_BESTOW], thiefCostOf(THIEF_BESTOW),
      "Bestow stays flat, for the same reason")
    H.screenshot("boostprice_steal_boost1")
    rec = { cmd = CMD_STEAL, want = price, slot = locke }
    H.assertEq(mp(locke) >= price, true,
      "LOCKE can pay the boosted steal out of his real pool")
    want.slot, want.bank, want.pend = locke, 1, 1
    want.mode, want.row = "steal", THIEF_STEAL
  end),
  step("the boosted steal is queued", function() return rec.queued end),
  H.call(function()
    H.log(string.format("[charge] steal queued cost %s (want %d)",
      tostring(rec.qcost), rec.want))
    H.assertEq(rec.qcost, rec.want, string.format(
      "Ot6AbilityCost priced the boost-1 Steal at %d, not its base %d",
      rec.want, STEAL_BASE))
  end),
  step("the boosted steal resolves and the pool moves", charged, 20000),
  H.call(function()
    local spent = rec.spent
    H.log(string.format("[charge] LOCKE MP %d -> %d, spent %d",
      rec.mp0, rec.mp0 - spent, spent))
    H.assertEq(spent, rec.want, string.format(
      "the boost-1 Steal deducted exactly %d MP", rec.want))
    want.mode = "idle"
    H.log("PASSED: the stamp, the grey and the charge all read one boosted "
      .. "price, for a multiplier verb and for a chance verb")
  end),
})
