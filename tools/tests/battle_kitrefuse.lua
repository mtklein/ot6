-- @suite savestate=vargas_won slow
-- battle_kitrefuse.lua -- an unaffordable kit row is REFUSED at the confirm,
-- not merely drawn grey.
--
-- Vanilla magic does two things to a spell the caster cannot pay for: it
-- greys the row, and it refuses the A button (btlgfx UpdateMenuState_0e
-- @81ae, `lda $2093,x / bmi` -> `inc $95`: buzz, stay open, spend nothing).
-- OT6 ported the grey to the kit windows in Ot6AbilityGrey and, until this
-- file, nothing else: the player could commit a greyed Blitz/Tool/Steal row,
-- the action was queued, the pending boost was banked, and the cast then died
-- at CalcAttackEffect's universal MP gate.  The turn AND the banked BP went
-- with it, with no feedback.  #219 turned that from a rarity into a routine
-- outcome -- a boost multiplies the price by 2.5 per level, so a row the pool
-- covers unboosted prices out the moment BP is spent on it -- and it is what
-- ate sixteen turns in the Narshe descent (docs/design/narshe-descent.md).
--
-- docs/design/mp-economy.md ruling 2 says an unaffordable boost is "greyed
-- AND refused".  This file is the mechanism evidence for the second word.
-- Ot6KitConfirmMP (ot6_cmdmenu.asm) is called from the tools-shell confirm
-- (btlgfx UpdateMenuState_30 @8809, the one confirm that serves Blitz, real
-- Tools, SwdTech and the thief submenu).  It prices the selected row through
-- Ot6KitRowCost -- the leaf the drawn number and the charge both read -- and
-- asks Ot6AbilityGrey the same question the row's colour asked.  "Greyed" and
-- "refused" are therefore the same byte, and there is no fourth opinion about
-- what a boosted row costs.
--
-- Every arm ASSERTS THE REFUSAL rather than the absence of a commit:
--   * the error sound fired ($95, magic's own buzz), and the confirm sound
--     fired with it ($96, which this window stamps on every A press before
--     the gate) -- so the press really landed on the list and was rejected,
--     rather than never arriving;
--   * the list is still open (menu state $30, close flag $7bcb still 0) with
--     the same caster and the cursor still on the same row;
--   * the turn was not consumed: the action-queue commit counter $7b80 has
--     not moved and CreateAction never wrote this verb's price to the mp-cost
--     queue at $3620;
--   * the BP is still banked (bank and pending boost both unmoved);
--   * the pool is unmoved.
-- ...and then the same row, at a boost the pool CAN pay, commits and deducts
-- exactly the price that was drawn, so the refusal is a gate and not a wall.
--
-- Three windows, one fixture.  vargas_won carries SABIN (Blitz, a multiplier
-- verb whose price escalates), EDGAR (real Tools, mode 0 of the same confirm)
-- and LOCKE (the thief submenu, mode 3).
--   1. BLITZ, priced out by a real boost: pips banked with real Fights, the
--      pending boost raised with real R presses until a learned blitz costs
--      more than the pool, then confirmed.  The row's font attribute is read
--      off VRAM in the same breath, so the grey and the refusal are shown to
--      be one answer about one row.
--   2. BLITZ, affordable: the boost drops back to a level the pool covers and
--      the same row commits and debits exactly what it drew.
--   3. TOOLS, priced out by the same ladder.
--   4. STEAL, priced out at its BASE price.  Steal is a chance verb and stays
--      flat at 4 MP at every boost level (#219's exemption), so no boost can
--      price it out; the only unaffordable Steal is a drained pool.  LOCKE's
--      pool is pinned one under the flat price for that arm and restored
--      immediately after -- the file's one state write, declared in
--      tools/state_write_waivers.txt.  It stages the poverty and nothing
--      else: the window, the grey, the confirm, the queue and the buzz are
--      all the real ROM's.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/vargas_won.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_TRANS, ST_CMD, ST_TOOLS, ST_TGT = 0x01, 0x05, 0x30, 0x38
local CMD_BLITZ, CMD_TOOLS, CMD_STEAL = 0x0A, 0x09, 0x05
local CMDTBL, CMDROW, ITEMLIST, KNOWN = 0x202E, 0x890F, 0x4005, 0x1D28
local QCOUNT, CLOSEFLAG = 0x7B80, 0x7BCB   -- commit counter / "close the menu"
local QCMD = 0x3A7A                        -- the command CreateAction is queuing
local SABIN, LOCKE, EDGAR = 0x05, 0x01, 0x04
local BLITZ_ATK0 = 0x5D
local THIEF_STEAL = 0x56
local GREY = 0x25
local ANCHOR = 99

local function bp(s) return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function mp(s) return H.readWord(0x3C08 + s * 2) end

-- #219's arithmetic, recomputed rather than copied (battle_boostprice's
-- shape): Ot6BoostPriceFor does (base * 5^n + 2^(n-1)) >> n capped at 99,
-- i.e. min(99, floor(base * 2.5^n + 1/2)).
local function boosted(base, n)
  if n == 0 then return base end
  local x = base
  for _ = 1, n do x = x * 5 end
  return math.min(ANCHOR, (x + (1 << (n - 1))) >> n)
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

-- AttackName glyph runs, for the VRAM font-attribute read (battle_blitzgrey's
-- idiom, reused so the grey this file reads is the grey that file asserts).
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

-- --------------------------------------------------------------- watches --
-- Three write watches, all read at the source rather than inferred.
--   $3620,y  the mp-cost queue CreateAction writes.  Counted PER COMMAND
--            ($3a7a, the command being queued), because bystanders are taking
--            real Defends throughout and a bare count would be theirs.  A
--            refused confirm must never reach this store for its own verb.
--   $95      the error sound request: magic's buzz, and this window's own
--            refusal for an empty cell.
--   $96      the confirm/cursor sound, which the tools window stamps on every
--            A press BEFORE the affordability gate -- so it says the press
--            arrived at the list even when the gate then rejects it.
-- Direct-page stores land in bank $00, so both the $000095/6 and the
-- $7e0095/6 views are watched and counted together.
local seen = { [CMD_BLITZ] = 0, [CMD_TOOLS] = 0, [CMD_STEAL] = 0 }
local lastQ = nil
local watchSlot = nil
local buzzes, confirms = 0, 0
local function armWatches()
  emu.addMemoryCallback(function(_, v)
    local c = H.readByte(QCMD)
    if seen[c] ~= nil then
      seen[c] = seen[c] + 1
      -- the pool AT QUEUE TIME, inside the live battle: the charge lands
      -- later at CalcAttackEffect, and a pool sampled from a step boundary
      -- can straddle a battle end ($3c08 reads $ffff once it tears down)
      lastQ = { cmd = c, cost = v,
                mp0 = watchSlot and mp(watchSlot) or nil }
    end
  end, emu.callbackType.write, 0x7E3620, 0x7E3620 + 0xFE)
  for _, base in ipairs({ 0x000000, 0x7E0000 }) do
    emu.addMemoryCallback(function() buzzes = buzzes + 1 end,
      emu.callbackType.write, base + 0x95, base + 0x95)
    emu.addMemoryCallback(function() confirms = confirms + 1 end,
      emu.callbackType.write, base + 0x96, base + 0x96)
  end
end

-- ---------------------------------------------------------------- driver --
-- battle_boostprice's per-frame driver, with one addition: `want.press`.
-- With it false the driver parks the cursor on `want.row` and holds -- which
-- is what the grey is read on -- and with it true the driver confirms that
-- row.  Everything else is the same real play: bystanders take real Defends,
-- pips are banked with real unboosted Fights, and the pending boost is raised
-- and lowered with real R and L presses at the command window.
local sabin, locke, edgar
local learned = {}
local want = { slot = nil, bank = 0, pend = 0, mode = "idle",
               row = nil, press = false, finish = false }

-- Is anyone down, or badly hurt?  battle_stealmp's shape.  An all-Defend
-- party is a party that never ends a fight, and on run 2 of this file that
-- ground three seats to 0 HP and lost the run while the arm was still
-- banking pips (build/attempts/battle_kitrefuse.run2.log: "the last battle up
-- (f36450) was formation 0032 0032 ... a4:2/280 a1:0/249 a0:0/241 a5:0/324").
-- So the bystanders stop deferring and start swinging as soon as the party is
-- in trouble, and each arm hands the battle back through recover() below.
local function partyHurt()
  for s = 0, 3 do
    local h, m = H.readWord(0x3BF4 + s * 2), H.readWord(0x3C1C + s * 2)
    if m > 0 and m < 9999 and (h == 0 or h * 100 // m < 55) then return true end
  end
  return false
end
local ph, hb = 0, -900
local BACK = { left = "right", right = "left", up = "down", down = "up" }
local lane = nil
local CMD_OF = { blitz = CMD_BLITZ, tools = CMD_TOOLS, steal = CMD_STEAL }

local function cmdCellOf(slot, cmd)
  for i = 0, 3 do
    if H.readByte(CMDTBL + slot * 12 + i * 3) == cmd then return i end
  end
  return nil
end

local function rowEntry(id)
  for i = 0, 7 do
    if H.readByte(ITEMLIST + i * 3) == id then return i end
  end
  return nil
end

local function heartbeat()
  if H.frame - hb < 900 then return end
  hb = H.frame
  H.log(string.format("[hb f%d] mode=%s press=%s batt=%s menu=%02x actor=%s "
    .. "st=%02x bank=%s pend=%s mp=%s", H.frame, want.mode,
    tostring(want.press), tostring(H.battleLoadStarted()), H.readByte(MENU),
    tostring(H.readByte(ACTOR)), H.readByte(MSTATE),
    want.slot and bp(want.slot) or "?", want.slot and pend(want.slot) or "?",
    want.slot and mp(want.slot) or "?"))
end

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
  lane = nil
  if H.readByte(MENU) == 0 then
    H.setPad(ph % 8 < 4 and { a = true } or {})
    return
  end
  local a, st = H.readByte(ACTOR) & 3, H.readByte(MSTATE)
  if st == ST_TRANS then H.setPad({}) return end
  if want.slot == nil or a ~= want.slot then
    -- A bystander who is standing in a KIT window has to be backed out of it
    -- before the Fight->Def->A walk means anything: an A press in the tools
    -- shell confirms a row, and once the rows are priced out that press is
    -- refused forever and the turn never ends.  (Measured: without this the
    -- arm that hands EDGAR's window back after his refusal deadlocked --
    -- build/attempts/battle_kitrefuse.run1.log, "timeout after 40000 frames
    -- driving toward LOCKE's command window".)
    if st == ST_TGT then
      H.setPad(ph % 8 < 4 and { a = true } or {})   -- a swing needs a target
      return
    end
    if st ~= ST_CMD then
      H.setPad(ph % 8 < 4 and { b = true } or {})
      return
    end
    local cur = H.readByte(CMDROW + a) & 3
    local sub = ph % 40
    if want.finish or partyHurt() then
      -- swing: row 0, with `left` putting Fight back in a row a previous
      -- Defend swapped to Def.
      if cur ~= 0 then H.setPad(sub < 4 and { up = true } or {})
      elseif sub < 4 then H.setPad({ left = true })
      elseif sub >= 20 and sub < 24 then H.setPad({ a = true })
      else H.setPad({}) end
      return
    end
    if sub < 4 then H.setPad({ right = true })       -- Fight row -> Def.
    elseif sub >= 20 and sub < 24 then H.setPad({ a = true })
    else H.setPad({}) end
    return
  end
  local btn
  if pend(a) > want.pend then
    btn = (st == ST_CMD) and "l" or "b"
  elseif bp(a) < want.bank then
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
    local cmd = CMD_OF[want.mode]
    if st == ST_CMD then
      local cell = cmdCellOf(a, cmd)
      assert(cell, "the target character's command list carries the verb")
      local cur = H.readByte(CMDROW + a) & 3
      btn = (cur == cell) and "a" or ((cur < cell) and "down" or "up")
    elseif st == ST_TOOLS then
      if want.row == nil then H.setPad({}) return end
      local entry = rowEntry(want.row)
      if entry == nil then H.setPad({}) return end
      local r, c = entry // 2, entry % 2
      local cr, cc = H.readByte(0x8967 + a), H.readByte(0x8963 + a)
      if cr ~= r then btn = (cr < r) and "down" or "up"
      elseif cc ~= c then btn = (cc < c) and "right" or "left"
      elseif want.press then btn = "a"
      else H.setPad({}) return end
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
  end
  H.setPad(edge and btn and { [btn] = true } or {})
end

local function step(what, cond, budget)
  return H.driveUntil(cond, budget or 40000,
    { H.call(pulse), H.waitFrames(1) }, what)
end

local function val(x) return (type(x) == "function") and x() or x end

-- Hand the battle back between arms: everyone swings until it is over, then a
-- real field care stop (the route's own pattern, and the owner's standing
-- guideline).  Each arm then walks into a fresh encounter with a whole party
-- and an opening bank, instead of inheriting the last arm's attrition.
local function recover(tag)
  return H.repeatN(1, {
    H.call(function()
      want.slot, want.mode, want.row, want.press = nil, "idle", nil, false
      want.finish = true
    end),
    step(tag .. ": fight the battle out",
      function() return not H.battleLoadStarted() end, 60000),
    H.call(function() want.finish = false H.setPad({}) end),
    H.waitFrames(120),
    H.fieldCare({ tag = tag, threshold = 0.9 }),
    H.call(function() H.setPad({}) end),
  })
end

-- bring a character's kit window up at exactly `n` pending boost, cursor
-- parked on `row`, nothing pressed
local function parkOn(slotf, nf, verb, rowf, what)
  return H.repeatN(1, {
    H.call(function()
      want.slot = val(slotf)
      want.bank, want.pend = val(nf), val(nf)
      want.mode, want.row, want.press = verb, nil, false
    end),
    step(what .. " (the window)", function()
      local slot = want.slot
      return H.battleLoadStarted() and H.readByte(MENU) ~= 0
         and (H.readByte(ACTOR) & 3) == slot
         and H.readByte(MSTATE) == ST_TOOLS and pend(slot) == want.pend
    end),
    H.call(function() want.row = val(rowf) end),
    step(what .. " (the cursor)", function()
      local slot, entry = want.slot, rowEntry(want.row)
      return entry ~= nil and H.readByte(MSTATE) == ST_TOOLS
         and (H.readByte(ACTOR) & 3) == slot
         and H.readByte(0x8967 + slot) == entry // 2
         and H.readByte(0x8963 + slot) == entry % 2
    end),
    H.waitFrames(30),
  })
end

-- ------------------------------------------------- the refusal assertion --
-- One shape, used by every arm.  `before` is snapshotted with the cursor
-- parked; then the confirm is pressed and NOTHING may have happened except
-- the two sounds.
local before = {}
local function snapshot(slot, verb, label)
  before = {
    slot = slot, verb = verb, label = label,
    mp = mp(slot), bp = bp(slot), pend = pend(slot),
    qcount = H.readByte(QCOUNT), seen = seen[CMD_OF[verb]],
    buzzes = buzzes, confirms = confirms,
    entry = rowEntry(want.row),
  }
  H.log(string.format("[%s] parked on entry %s: mp=%d bank=%d pend=%d "
    .. "qcount=%d", label, tostring(before.entry), before.mp, before.bp,
    before.pend, before.qcount))
end

local function assertRefused()
  local slot, label, cmd = before.slot, before.label, CMD_OF[before.verb]
  H.log(string.format("[%s] after the confirm: mp=%d bank=%d pend=%d "
    .. "qcount=%d state=%02x actor=%02x close=%d cursor=(%d,%d) "
    .. "queued(+%d) buzz(+%d) confirm(+%d)",
    label, mp(slot), bp(slot), pend(slot), H.readByte(QCOUNT),
    H.readByte(MSTATE), H.readByte(ACTOR), H.readByte(CLOSEFLAG),
    H.readByte(0x8967 + slot), H.readByte(0x8963 + slot),
    seen[cmd] - before.seen, buzzes - before.buzzes,
    confirms - before.confirms))
  H.assertEq(confirms > before.confirms, true, string.format(
    "%s: the A press reached the list ($96, which this window stamps before "
    .. "the gate) -- the refusal below is a rejection and not a press that "
    .. "never arrived", label))
  H.assertEq(buzzes > before.buzzes, true, string.format(
    "%s: ...and the confirm BUZZED ($95, magic's own error sound).  The "
    .. "refusal is observed, not inferred from an absence", label))
  H.assertEq(H.readByte(MSTATE), ST_TOOLS, string.format(
    "%s: the list is still open (menu state $30) -- the player is still "
    .. "choosing, exactly as vanilla magic leaves them", label))
  H.assertEq(H.readByte(ACTOR) & 3, slot, string.format(
    "%s: ...and it is still this caster's window", label))
  H.assertEq(H.readByte(0x8967 + slot), before.entry // 2, string.format(
    "%s: the cursor is still on the refused row", label))
  H.assertEq(H.readByte(CLOSEFLAG), 0, string.format(
    "%s: the window was never told to close ($7bcb)", label))
  H.assertEq(H.readByte(QCOUNT), before.qcount, string.format(
    "%s: no action was committed -- the queue counter $7b80 has not moved, "
    .. "so the TURN was not consumed", label))
  H.assertEq(seen[cmd], before.seen, string.format(
    "%s: CreateAction never queued a cmd $%02x -- nothing reached the mp-cost "
    .. "store at $3620, which is where a commit would have shown up",
    label, cmd))
  H.assertEq(bp(slot), before.bp, string.format(
    "%s: the BP bank is untouched -- the banked pips are still the player's",
    label))
  H.assertEq(pend(slot), before.pend, string.format(
    "%s: the pending boost is still pending -- refusing costs no BP", label))
  H.assertEq(mp(slot), before.mp, string.format(
    "%s: the pool is unmoved", label))
end

-- the charge, latched the frame it lands while the battle is still live
local charge = nil
local function charged()
  if charge.spent == nil and H.battleActive() and charge.mp0 then
    local m = mp(charge.slot)
    if m < 0x8000 and m < charge.mp0 then charge.spent = charge.mp0 - m end
  end
  return charge.spent ~= nil
end

-- ------------------------------------------------------------- the arms --
local blitzRow, blitzBoost, blitzPayBoost
local toolRow, toolBoost
local stealPrice, lockeMp0

H.run({ maxFrames = 620000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control on the Kolts ledge"),
  H.call(function()
    local mask = H.readByte(KNOWN)
    for i = 0, 7 do
      if (mask >> i) & 1 == 1 then learned[#learned + 1] = BLITZ_ATK0 + i end
    end
    local names = {}
    for _, id in ipairs(learned) do
      names[#names + 1] = string.format("%s(%d)", nameText(id), costOf(id))
    end
    H.log("SABIN's learned blitzes: " .. table.concat(names, " "))
    H.assertEq(#learned >= 1, true, "SABIN has a learned blitz to refuse")
    -- Ot6StealCost is `lda #imm / rtl`: the immediate is the flat price
    local ofs = H.sym("Ot6StealCost") & 0x3FFFFF
    H.assertEq(H.readRomByte(ofs), 0xa9,
      "Ot6StealCost still opens with LDA #imm -- the +1 read is the price")
    stealPrice = H.readRomByte(ofs + 1)
    armWatches()
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
      if who == EDGAR then edgar = s end
    end
    H.assertEq(sabin ~= nil, true, "SABIN is in this party")
    H.assertEq(locke ~= nil, true, "LOCKE is in this party")
    H.assertEq(edgar ~= nil, true, "EDGAR is in this party")
    H.log(string.format("SABIN slot %d (%d MP), LOCKE slot %d (%d MP), "
      .. "EDGAR slot %d (%d MP)", sabin, mp(sabin), locke, mp(locke),
      edgar, mp(edgar)))
    -- the shallowest boost that prices a learned blitz out of SABIN's real
    -- pool (shallower is both cheaper to bank for and a stronger statement)
    local pool = mp(sabin)
    for n = 1, 3 do
      for _, id in ipairs(learned) do
        if blitzBoost == nil and boosted(costOf(id), n) > pool then
          blitzBoost, blitzRow = n, id
        end
      end
    end
    H.assertEq(blitzBoost ~= nil, true, string.format(
      "some learned blitz prices out of SABIN's %d MP pool at boost 1..3 -- "
      .. "otherwise this fixture cannot exercise the refusal at all and every "
      .. "assertion below would be vacuous", pool))
    for n = blitzBoost - 1, 0, -1 do
      if blitzPayBoost == nil and boosted(costOf(blitzRow), n) <= pool then
        blitzPayBoost = n
      end
    end
    H.assertEq(blitzPayBoost ~= nil, true,
      "the same row is affordable at some shallower boost -- the refusal has "
      .. "to be a gate, not a wall")
    H.log(string.format("BLITZ arm: %s base %d; boost %d costs %d > pool %d "
      .. "(refused), boost %d costs %d <= pool (commits)",
      nameText(blitzRow), costOf(blitzRow), blitzBoost,
      boosted(costOf(blitzRow), blitzBoost), pool, blitzPayBoost,
      boosted(costOf(blitzRow), blitzPayBoost)))
  end),

  -- ---- 1. BLITZ: a boost the pool cannot pay is greyed AND refused -------
  parkOn(function() return sabin end, function() return blitzBoost end,
    "blitz", function() return blitzRow end,
    "SABIN's blitz window, boosted past his pool"),
  H.call(function()
    local price = boosted(costOf(blitzRow), blitzBoost)
    local attr = attrOf(nameSeq(blitzRow))
    H.log(string.format("[blitz] %s at boost %d costs %d, pool %d, attr %s",
      nameText(blitzRow), blitzBoost, price, mp(sabin),
      attr and string.format("$%02x", attr) or "nil"))
    H.assertEq(attr, GREY, string.format(
      "%s renders GREY at boost %d (%d MP against a %d pool) -- the grey and "
      .. "the refusal below are the same Ot6AbilityGrey answer about the same "
      .. "row, which is why routing the confirm through it cannot drift",
      nameText(blitzRow), blitzBoost, price, mp(sabin)))
    H.screenshot("kitrefuse_blitz_grey")
    snapshot(sabin, "blitz", "blitz")
    want.press = true
  end),
  H.driveUntil(function() return buzzes > before.buzzes end, 1800,
    { H.call(pulse), H.waitFrames(1) },
    "the greyed blitz is confirmed and buzzes"),
  H.release(),
  H.waitFrames(120),
  H.call(function()
    H.setPad({})
    want.press = false
    assertRefused()
    H.screenshot("kitrefuse_blitz_refused")
  end),

  -- ---- 2. ...and the same row, affordable, commits normally -------------
  H.call(function()
    watchSlot = sabin
    charge = { slot = sabin, want = boosted(costOf(blitzRow), blitzPayBoost),
               base = seen[CMD_BLITZ], mp0 = nil, spent = nil }
    want.slot, want.bank, want.pend = sabin, blitzPayBoost, blitzPayBoost
    want.mode, want.row, want.press = "blitz", blitzRow, true
    H.log(string.format("[blitz-pay] dropping to boost %d: %s costs %d of %d",
      blitzPayBoost, nameText(blitzRow), charge.want, mp(sabin)))
  end),
  step("the affordable blitz is queued", function()
    return seen[CMD_BLITZ] > charge.base
  end, 60000),
  H.call(function()
    charge.mp0 = lastQ and lastQ.mp0 or mp(sabin)
    H.log(string.format("[blitz-pay] queued cost %s at pool %s",
      tostring(lastQ and lastQ.cost), tostring(charge.mp0)))
    H.assertEq(lastQ.cost, charge.want, string.format(
      "the affordable row DID reach CreateAction, priced %d -- so arm 1's "
      .. "refusal was about the PRICE and not about the menu", charge.want))
    want.mode, want.row, want.press = "idle", nil, false
  end),
  step("the affordable blitz resolves and the pool moves", charged, 30000),
  H.call(function()
    H.log(string.format("[blitz-pay] MP %d -> %d, spent %d (want %d)",
      charge.mp0, charge.mp0 - charge.spent, charge.spent, charge.want))
    H.assertEq(charge.spent, charge.want, string.format(
      "the boost-%d %s deducted exactly the %d it drew -- the refusal, the "
      .. "grey, the drawn price and the charge are one number",
      blitzPayBoost, nameText(blitzRow), charge.want))
    watchSlot = nil
  end),

  -- ---- 3. TOOLS: mode 0 of the same confirm -----------------------------
  recover("before the tools arm"),
  H.repeatN(1, {
    H.call(function()
      want.slot, want.bank, want.pend = edgar, 0, 0
      want.mode, want.row, want.press = "tools", nil, false
    end),
    step("EDGAR's tools window (survey)", function()
      return H.battleLoadStarted() and H.readByte(MENU) ~= 0
         and (H.readByte(ACTOR) & 3) == edgar
         and H.readByte(MSTATE) == ST_TOOLS
    end),
    H.waitFrames(30),
    H.call(function()
      local owned, pool, shown = {}, mp(edgar), {}
      for i = 0, 7 do
        local id = H.readByte(ITEMLIST + i * 3)
        if id ~= 0xff then
          owned[#owned + 1] = id
          shown[#shown + 1] = string.format("$%02x(%d)", id, costOf(id))
        end
      end
      H.log(string.format("[tools] EDGAR's rows: %s (pool %d)",
        table.concat(shown, " "), pool))
      H.assertEq(#owned >= 1, true, "EDGAR owns a tool to be refused")
      for n = 1, 3 do
        for _, id in ipairs(owned) do
          if toolBoost == nil and costOf(id) > 0
             and boosted(costOf(id), n) > pool then
            toolBoost, toolRow = n, id
          end
        end
      end
      H.assertEq(toolBoost ~= nil, true, string.format(
        "some owned tool prices out of EDGAR's %d MP pool at boost 1..3",
        pool))
      H.log(string.format("[tools] $%02x base %d, boost %d costs %d > pool %d",
        toolRow, costOf(toolRow), toolBoost,
        boosted(costOf(toolRow), toolBoost), pool))
    end),
  }),
  parkOn(function() return edgar end, function() return toolBoost end,
    "tools", function() return toolRow end,
    "EDGAR's tools window, boosted past his pool"),
  H.call(function()
    snapshot(edgar, "tools", "tools")
    want.press = true
  end),
  H.driveUntil(function() return buzzes > before.buzzes end, 1800,
    { H.call(pulse), H.waitFrames(1) },
    "the greyed tool is confirmed and buzzes"),
  H.release(),
  H.waitFrames(120),
  H.call(function()
    H.setPad({})
    want.press = false
    assertRefused()
    H.screenshot("kitrefuse_tools_refused")
    want.mode, want.row = "idle", nil
    want.bank, want.pend = 0, 0
  end),

  -- ---- 4. STEAL: the BASE price, on a drained pool (mode 3) -------------
  -- The pin is taken with LOCKE's own command window already up, so it
  -- belongs to the battle whose thief submenu then opens; a pin taken across
  -- a battle boundary would be re-seeded from the save and prove nothing.
  recover("before the steal arm"),
  H.call(function()
    want.slot, want.bank, want.pend = locke, 0, 0
    want.mode, want.row, want.press = "idle", nil, false
  end),
  step("a battle for the steal arm", function()
    return H.battleLoadStarted() and H.battleActive()
  end, 30000),
  step("LOCKE's command window", function()
    return H.battleLoadStarted() and H.readByte(MENU) ~= 0
       and (H.readByte(ACTOR) & 3) == locke
       and H.readByte(MSTATE) == ST_CMD and pend(locke) == 0
  end),
  H.call(function()
    lockeMp0 = mp(locke)
    H.assertEq(lockeMp0 >= stealPrice, true,
      "LOCKE starts this arm able to afford a steal (the control)")
    H.writeWord(0x3C08 + locke * 2, stealPrice - 1)
    H.log(string.format("[steal] LOCKE's pool pinned %d -> %d, one under the "
      .. "flat price %d", lockeMp0, stealPrice - 1, stealPrice))
  end),
  parkOn(function() return locke end, 0, "steal",
    function() return THIEF_STEAL end,
    "LOCKE's thief submenu on a drained pool"),
  H.call(function()
    local stamp
    for i = 0, 7 do
      if H.readByte(ITEMLIST + i * 3) == THIEF_STEAL then
        stamp = H.readByte(ITEMLIST + i * 3 + 1)
      end
    end
    H.log(string.format("[steal] Steal stamped %s, pool %d",
      tostring(stamp), mp(locke)))
    H.assertEq(stamp, stealPrice,
      "the Steal row still draws its flat price -- the row under the cursor "
      .. "is the priced one, and no boost moved it (#219's chance-verb rule)")
    snapshot(locke, "steal", "steal")
    want.press = true
  end),
  H.driveUntil(function() return buzzes > before.buzzes end, 1800,
    { H.call(pulse), H.waitFrames(1) },
    "the greyed Steal is confirmed and buzzes"),
  H.release(),
  H.waitFrames(120),
  H.call(function()
    H.setPad({})
    want.press = false
    assertRefused()
    H.screenshot("kitrefuse_steal_refused")
    -- restore the real pool; the arm's second and last write
    H.writeWord(0x3C08 + locke * 2, lockeMp0)
    H.log("[steal] LOCKE's pool restored to the real " .. lockeMp0)
    want.mode, want.row, want.press = "idle", nil, false
    H.log("PASSED: an unaffordable kit row is refused at the confirm on all "
      .. "three windows -- buzz, list still open, turn not spent, BP still "
      .. "banked, pool unmoved -- and the same row commits at a price the "
      .. "pool covers")
  end),
})
