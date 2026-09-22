-- @suite savestate=vargas_won slow
-- battle_boostprice.lua -- #219: boosting a multiplier verb costs escalating
-- MP.  price = min(99, floor(base * 2.5^boost + 0.5)), so a boost buys its
-- multiplier at x2.5 the base price per level, capped at the two-digit
-- ceiling.
--
-- Who pays it is ONE test, the same test the damage half makes: a price
-- escalates exactly when Ot6BoostDmg multiplies the action.  The chance verbs
-- -- Steal, Rage and Slot -- are on the other side of it and stay flat at
-- every level: a boost on them multiplies nothing, it converts variance into
-- reliability across a spread of outcomes that are not merely damage, and the
-- BP it costs is what pays for that certainty.  MP scales with magnitude; BP
-- alone pays for certainty.
--
-- This file carries both sides of the test, on one fixture and through the
-- real menu: SABIN's Blitz escalates, LOCKE's Steal does not.
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
--      N is 1 and 2 always, and 3 as well when the pool needs it: the
--      level the grey is shown flipping at is CHOSEN from SABIN's live pool
--      and learned set (the shallowest boost at which a row he can pay
--      unboosted prices out), because every ROM change regenerates the
--      chain and reshuffles both.  A pool no boost can price a learned row
--      out of (99 and up, say) is spent down first with real unboosted
--      Blitzes until one can.
--   3. a boosted Blitz is queued at the boosted price and deducts it.
--   4. LOCKE's whole thief submenu stays FLAT under a boost -- Steal as well
--      as Filch and Bestow -- and the stamp is checked against the escalated
--      number it must NOT be, so the arm can tell the two rules apart.
--   5. a boosted Steal is queued at the flat price and deducts it.
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
local MAX_BOOST = 3                     -- Ot6Boost caps a spend at 3

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

-- The rows the grey can be SHOWN flipping on at boost n: learned blitzes
-- the pool pays unboosted (white at boost 0) whose boosted price it does
-- not (grey at boost n).  Everything about the choice of n is read off the
-- live pool and learned set and priced by the rule above; nothing assumes
-- the pool the fixture happened to hold.
local learned = {}                       -- SABIN's learned blitz ids
local function flipsAt(pool, n)
  local out = {}
  for _, id in ipairs(learned) do
    local base = costOf(id)
    if base <= pool and boosted(base, n) > pool then out[#out + 1] = id end
  end
  return out
end
-- the shallowest boost that prices a payable row out of `pool`, or nil
local function greyLevel(pool)
  for n = 1, MAX_BOOST do
    if #flipsAt(pool, n) > 0 then return n end
  end
  return nil
end
-- the cheapest learned blitz `pool` pays unboosted: the spend-down's row,
-- and the one that steps the pool down finely enough that it cannot skip
-- a flip window (each window [base, boosted(base, 3) - 1] is wider than
-- its own base)
local function cheapestPayable(pool)
  local pick
  for _, id in ipairs(learned) do
    if costOf(id) <= pool and (pick == nil or costOf(id) < costOf(pick)) then
      pick = id
    end
  end
  return pick
end
local GREY_AT                            -- the chosen flip level (1..3)
local LEVELS = { 1, 2 }                  -- boost levels read; + GREY_AT

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
    elseif b == 0xfe or b == 0xff then s = s .. " "
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
-- Is anyone down, or badly hurt?  battle_kitrefuse's shape: an all-Defend
-- party never ends a fight, and a spend-down can take several, so the
-- bystanders swing instead of deferring once the party is in trouble.
local function partyHurt()
  for s = 0, 3 do
    local h, m = H.readWord(0x3BF4 + s * 2), H.readWord(0x3C1C + s * 2)
    if m > 0 and m < 9999 and (h == 0 or h * 100 // m < 55) then return true end
  end
  return false
end
-- ...and between battles, the route's own care stop (Tonics, never a cast;
-- instantly done when nobody needs it), so a run that crosses battles does
-- not carry one fight's attrition into the next.
local care, careDue = nil, false

local function pulse()
  ph = ph + 1
  heartbeat()
  local edge = ph % 10 < 5
  if not H.battleLoadStarted() then
    -- a care stop in progress owns the pad until it is done, menu and all
    -- (the menu takes field control away, so this comes first)
    if care then
      care.frame()
      if care.done() then care, careDue = nil, false end
      return
    end
    if not (H.hasControl() and H.tileAligned()) then
      H.setPad(ph % 8 < 4 and { a = true } or {})
      return
    end
    if careDue then
      care = H.newCareDriver({ tag = "boostprice care", threshold = 0.65 })
      care.frame()
      if care.done() then care, careDue = nil, false end
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
  care, careDue = nil, true     -- care at the next field control
  if H.readByte(MENU) == 0 then
    H.setPad(ph % 8 < 4 and { a = true } or {})
    return
  end
  local a, st = H.readByte(ACTOR) & 3, H.readByte(MSTATE)
  if st == ST_TRANS then H.setPad({}) return end
  if want.slot == nil or a ~= want.slot then
    local sub = ph % 40
    if partyHurt() then
      -- swing: row 0, with `left` putting Fight back in a row a Defend
      -- swapped to Def. (battle_kitrefuse's bystander)
      if st == ST_TGT then H.setPad(ph % 8 < 4 and { a = true } or {}) return end
      if st ~= ST_CMD then H.setPad(ph % 8 < 4 and { b = true } or {}) return end
      local cur = H.readByte(CMDROW + a) & 3
      if cur ~= 0 then H.setPad(sub < 4 and { up = true } or {})
      elseif sub < 4 then H.setPad({ left = true })
      elseif sub >= 20 and sub < 24 then H.setPad({ a = true })
      else H.setPad({}) end
      return
    end
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
    -- WHO reaches that ladder at all.  The canon is one test -- a price
    -- escalates exactly when Ot6BoostDmg multiplies the action -- so the
    -- library's copy of that gate is pinned here against Ot6BoostDmg's own
    -- `cmp #imm / beq` chain, read out of the built ROM.  Without this the
    -- Lua gate and the ROM gate could drift apart in silence, and the
    -- driver would refuse boosts the engine would happily have charged 4
    -- MP for (or plan ones it cannot pay).  The complementary check is
    -- battle_costtable's, which asks the same question of the ROM's own
    -- price arms; this one asks it of the driver.
    local gate = {}
    do
      local ofs = H.sym("Ot6BoostDmg") & 0x3FFFFF
      -- scan the proc's opening command gate: `cmp #imm` ($C9) followed by
      -- `beq` ($F0), up to the first `lda OT6_BOOST_REVEALED,x` that ends it
      for i = 0, 96 do
        if H.readRomByte(ofs + i) == 0xC9 and H.readRomByte(ofs + i + 2) == 0xF0 then
          gate[H.readRomByte(ofs + i + 1)] = true
        end
      end
      -- cmd $00 is the `beq` off `lda $b5` itself, not a cmp, so it never
      -- appears as an immediate: add it the way the ROM's comment does.
      gate[0x00] = true
    end
    for cmd in pairs(gate) do
      H.assertEq(H.boostEscalates(cmd), false, string.format(
        "cmd $%02X is in Ot6BoostDmg's gate, so the driver must price it flat",
        cmd))
    end
    for cmd in pairs(H.BOOST_FLAT_CMDS) do
      H.assertEq(gate[cmd] or false, true, string.format(
        "the driver calls cmd $%02X flat, so Ot6BoostDmg must gate it", cmd))
    end
    H.log(string.format("[boostprice] Ot6BoostDmg gates %d command(s); the "
      .. "driver's flat set matches it exactly", (function()
        local n = 0; for _ in pairs(gate) do n = n + 1 end; return n
      end)()))
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
    H.assertEq(mp(locke) >= STEAL_BASE, true, string.format(
      "LOCKE's %d MP covers the flat %d Steal the chance-verb arm charges",
      mp(locke), STEAL_BASE))
  end),

  ----------------------- 0. the pool the grey is shown against, chosen live --
  -- Which boost first prices a payable row out is a function of SABIN's
  -- pool and learned set, and both move whenever the chain is regenerated
  -- (a level is a new maximum, Ot6LevelUpHeal refills to it, and the fight
  -- before the fixture spends whatever it spends).  So the level is read
  -- off the live pool here.  When no legal boost prices anything out -- a
  -- pool of 99 or more, or a learned set too cheap for the pool -- SABIN
  -- spends it down first, the way a player would: real unboosted Blitzes
  -- of the cheapest learned row, each one charged by the ROM, until some
  -- boost can.
  H.call(function()
    local pool = mp(sabin)
    local names = {}
    for n = 1, MAX_BOOST do
      local f = {}
      for _, id in ipairs(flipsAt(pool, n)) do f[#f + 1] = nameText(id) end
      names[#names + 1] = string.format("boost %d {%s}", n, table.concat(f, " "))
    end
    H.log(string.format("[pool] SABIN %d MP; payable rows each boost prices "
      .. "out: %s", pool, table.concat(names, ", ")))
    if greyLevel(pool) ~= nil then return end
    local row = cheapestPayable(pool)
    H.assertEq(row ~= nil, true, string.format(
      "no boost 1..%d prices a payable blitz out of SABIN's %d MP, and he "
      .. "pays some blitz unboosted to spend it down with (without one this "
      .. "state cannot show ruling 2's grey)", MAX_BOOST, pool))
    H.log(string.format("[pool] no boost 1..%d prices a payable row out of "
      .. "%d MP: spending down with unboosted %s (%d MP each)", MAX_BOOST,
      pool, nameText(row), costOf(row)))
    want.slot, want.bank, want.pend = sabin, 0, 0
    want.mode, want.row = "blitz", row
  end),
  step("SABIN's pool is one some boost 1..3 prices a learned row out of",
    function()
      if not (H.battleLoadStarted() and H.monstersPresent() > 0) then
        return false
      end
      local m = mp(sabin)
      return m > 0 and m < 0x8000 and greyLevel(m) ~= nil
    end, 400000),
  H.call(function()
    want.mode, want.row = "idle", nil
    local pool = mp(sabin)
    GREY_AT = greyLevel(pool)
    if GREY_AT > LEVELS[#LEVELS] then LEVELS[#LEVELS + 1] = GREY_AT end
    local f = {}
    for _, id in ipairs(flipsAt(pool, GREY_AT)) do f[#f + 1] = nameText(id) end
    H.log(string.format("[pool] %d MP: boost %d is the shallowest that prices "
      .. "a payable row out (%s); reading boosts %s", pool, GREY_AT,
      table.concat(f, " "), table.concat(LEVELS, "/")))
    -- the charge arm below needs a row the pool pays AT a boost; checked
    -- here, before any of it runs, rather than discovered there
    local payable = false
    for _, id in ipairs(learned) do
      if boosted(costOf(id), 1) <= pool then payable = true end
    end
    H.assertEq(payable, true, string.format(
      "SABIN's %d MP pays some learned blitz at boost 1 -- the charge arm "
      .. "needs a payable boosted row", pool))
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
    -- action, so boost 2 costs one real Fight first and boost 3 two.  Boosts
    -- 1 and 2 are always read, which shows the rule twice over with
    -- different multipliers; boost 3 is read too when it is the shallowest
    -- level the live pool greys a payable row at (GREY_AT, chosen above).
    -- The whole column at every level is covered arithmetically in
    -- battle_costtable.
    local steps = {}
    for n = 1, MAX_BOOST do
      local function wanted()
        for _, l in ipairs(LEVELS) do if l == n then return true end end
        return false
      end
      steps[#steps + 1] = H.cond(wanted, {
        openAt(function() return sabin end, n, "blitz",
          string.format("SABIN's blitz window at boost %d", n)),
        H.call(function()
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
        end),
      }, {})
    end
    return H.repeatN(1, steps)
  end)(),

  H.call(function()
    -- the grey has to have moved somewhere, or the colour assertion above
    -- proved nothing about the boost.  GREY_AT was chosen so that it must
    -- have: every row the live pool says flips there is checked by name,
    -- white unboosted and grey at GREY_AT, on the windows actually drawn.
    local flipped = {}
    for _, id in ipairs(learned) do
      for _, n in ipairs(LEVELS) do
        if blitzAt[0][id].attr == WHITE and blitzAt[n][id].attr == GREY then
          flipped[#flipped + 1] = string.format("%s at boost %d",
            nameText(id), n)
        end
      end
    end
    H.log("rows the boost priced out: " ..
      (next(flipped) and table.concat(flipped, ", ") or "none"))
    for _, id in ipairs(flipsAt(blitzAt[GREY_AT][learned[1]].mp, GREY_AT)) do
      H.assertEq(blitzAt[0][id].attr == WHITE and blitzAt[GREY_AT][id].attr == GREY,
        true, string.format(
        "%s (base %d) is white unboosted and grey at boost %d, where it costs "
        .. "%d against the %d pool -- the shallowest boost the live pool "
        .. "prices it out at", nameText(id), costOf(id), GREY_AT,
        boosted(costOf(id), GREY_AT), blitzAt[GREY_AT][id].mp))
    end
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
  -- The other side of the one test.  Cmd $05 is in Ot6BoostDmg's gate, so no
  -- row of the thief submenu escalates: Steal's boost buys the rare/guarantee
  -- ladder (odds, not magnitude) and Filch's and Bestow's buys nothing at
  -- all.  Each assertion names the escalated number it must not be, so this
  -- section fails if the escalation ever comes back -- it does not merely
  -- stop mentioning it.
  openAt(function() return locke end, 1, "steal",
    "LOCKE's thief submenu at boost 1"),
  H.call(function()
    local price = STEAL_BASE                     -- flat, at every level
    local wouldBe = boosted(STEAL_BASE, 1)       -- ...if it escalated
    local q = {}
    for i = 0, 7 do
      local id = H.readByte(ITEMLIST + i * 3)
      if id ~= 0xff then q[id] = H.readByte(ITEMLIST + i * 3 + 1) end
    end
    H.log(string.format("  boost 1  Steal stamp %s (flat %d; escalated would "
      .. "be %d), Filch %s, Bestow %s, pool %d", tostring(q[THIEF_STEAL]),
      price, wouldBe, tostring(q[THIEF_FILCH]), tostring(q[THIEF_BESTOW]),
      mp(locke)))
    H.assertEq(price ~= wouldBe, true, string.format(
      "the flat price %d and the escalated %d are different numbers, so the "
      .. "stamp assertion below can fail", price, wouldBe))
    H.assertEq(q[THIEF_STEAL], price, string.format(
      "Steal at boost 1 is stamped its flat %d, NOT the %d a 2.5x escalation "
      .. "would draw.  Cmd $05 is in Ot6BoostDmg's gate: the boost buys the "
      .. "rare/guarantee ladder, which is certainty across a spread of "
      .. "outcomes rather than magnitude, and the BP already pays for it",
      price, wouldBe))
    H.assertEq(q[THIEF_FILCH], thiefCostOf(THIEF_FILCH),
      "Filch stays flat on the same gate -- and for it a boost buys nothing "
      .. "at all, so charging for it would be charging for nothing")
    H.assertEq(q[THIEF_BESTOW], thiefCostOf(THIEF_BESTOW),
      "Bestow stays flat, for the same reason.  All three thief rows now take "
      .. "one flat arm, with no per-row split left to go stale")
    H.screenshot("boostprice_steal_boost1")
    rec = { cmd = CMD_STEAL, want = price, slot = locke }
    H.assertEq(mp(locke) >= price, true,
      "LOCKE can pay the steal out of his real pool")
    want.slot, want.bank, want.pend = locke, 1, 1
    want.mode, want.row = "steal", THIEF_STEAL
  end),
  step("the boosted steal is queued", function() return rec.queued end),
  H.call(function()
    H.log(string.format("[charge] steal queued cost %s (want %d)",
      tostring(rec.qcost), rec.want))
    H.assertEq(rec.qcost, rec.want, string.format(
      "Ot6AbilityCost priced the boost-1 Steal at its flat %d, not the %d the "
      .. "escalation would have charged", rec.want, boosted(STEAL_BASE, 1)))
  end),
  step("the boosted steal resolves and the pool moves", charged, 20000),
  H.call(function()
    local spent = rec.spent
    H.log(string.format("[charge] LOCKE MP %d -> %d, spent %d",
      rec.mp0, rec.mp0 - spent, spent))
    H.assertEq(spent, rec.want, string.format(
      "the boost-1 Steal deducted exactly %d MP -- the stamp, the per-draw "
      .. "price and the pool all read the same flat number", rec.want))
    want.mode = "idle"
    H.log("PASSED: the stamp, the grey and the charge agree on ONE price per "
      .. "row -- escalating for the multiplier verb, flat for the chance verb")
  end),
})
