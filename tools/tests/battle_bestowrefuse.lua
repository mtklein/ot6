-- @suite slow savestate=figaro_cleared
-- battle_bestowrefuse.lua -- the thief submenu's Bestow row, greyed at 0 BP,
-- is REFUSED at the confirm (#232): the BP twin of battle_kitrefuse's MP
-- refusals, on the same gate.
--
-- Ot6BushidoRowGrey's thief arm greys Bestow when the caster holds no pip,
-- because Ot6Bestow's first refusal is that same test and there is nothing
-- to hand over.  Until #232 the grey was advice: the confirm let the row
-- through, the action was queued and paid for (5 MP), and Ot6Bestow then
-- no-op'd at execution -- the turn and the MP gone with no feedback, the
-- defect v0.19 fixed for MP on every other kit row.  SwdTech's BP reason
-- already had its confirm twin (Ot6BushidoConfirm); Bestow was the one
-- greyed row left that could be committed.
--
-- Ot6KitConfirmMP now takes the row's BP grey from the very
-- Ot6BushidoRowGrey the row's colour took, on top of the MP grey, so a
-- greyed Bestow and a refused Bestow are one byte.  This file is the
-- mechanism evidence, in battle_kitrefuse's shape:
--   1. at the opening bank of 1, Bestow commits: it is queued at its drawn
--      5 MP, the ally banks the pip, LOCKE is charged it and skips his regen
--      (so he stands at 0 BP by real play, the caster #232 is about);
--   2. his next window: Bestow reads GREY off VRAM, the A press reaches the
--      list ($96) and is BUZZED ($95); the list is still open on the same
--      caster and row, $7b80 has not moved, no cmd $05 reached the $3620
--      cost queue, bank, pending boost, pool and the ally's bank are all
--      unmoved.  A build that lets the row through is not merely asserted
--      against: the arm rides the committed turn out and writes down what
--      it bought (nothing), then fails on the refusal it did not see;
--   3. one real item turn banks the pip back and the same row commits again
--      and lands, so the refusal is a gate and not a wall.
--
-- One fixture, one battle, no state writes: figaro_cleared's TERRA + LOCKE
-- + EDGAR in the desert (battle_thief's ground).  TERRA is the ledger's
-- ally and only ever defers, so her bank moves by Bestow alone; EDGAR
-- defers too, and spends a Tonic on whoever drops under half, so the fight
-- lasts the three LOCKE windows this needs without anyone pinning HP.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/figaro_cleared.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_THIEF, ST_ITEM, ST_TGT, ST_TRANS = 0x05, 0x30, 0x0A, 0x38, 0x01
local CMD_STEAL, CMD_ITEM = 0x05, 0x01
local KITMODE = 0x6168                  -- w7e6168: 3 = the thief submenu
local ILIST = 0x4005                    -- wItemList: Index +0, Qty +1, Flags +2
local TCURSOR = 0x7B7D                  -- target cursor's CHARACTER mask
local KCOL, KROW = 0x8963, 0x8967       -- the kit list's own cursor (read!)
local QCOUNT, CLOSEFLAG = 0x7B80, 0x7BCB   -- commit counter / "close the menu"
local QCMD = 0x3A7A                     -- the command CreateAction is queuing
local WHITE, GREY = 0x21, 0x25
local TONIC, POTION = 0xE8, 0xE9
local TERRA, LOCKE = 0x00, 0x01

local ID_STEAL, ID_BESTOW = 0x56, 0x58
local BESTOW_ROW = 2                    -- Ot6ThiefListOpen: Steal / Filch / Bestow
local COST_BESTOW = 5

local function bp(s) return H.readByte(0x3E9C + s * 2) end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function mp(s) return H.readWord(0x3C08 + s * 2) end
local function hp(s) return H.readWord(0x3BF4 + s * 2) end
local function maxHp(s) return H.readWord(0x3C1C + s * 2) end

local function glyphs(s)
  local t = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    t[i] = (c >= "A" and c <= "Z") and (0x80 + c:byte() - ("A"):byte())
                                    or  (0x9a + c:byte() - ("a"):byte())
  end
  return t
end
local NM = { Steal = glyphs("Steal"), Bestow = glyphs("Bestow") }
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
local function fmt(a) return a and string.format("$%02x", a) or "nil" end

local function cmdRowOf(slot, cmd)
  for r = 0, 3 do
    if H.readByte(0x202E + slot * 12 + r * 3) == cmd then return r end
  end
  return nil
end
local function bagIdxOf(ids)
  for i = 0, 251 do
    local id = H.readByte(0x2686 + i * 5)
    for _, w in ipairs(ids) do
      if id == w and H.readByte(0x2686 + i * 5 + 3) > 0 then return i end
    end
  end
  return nil
end
local function hurtSlot()
  local worst, wpct = nil, 50
  for s = 0, 3 do
    local h, m = hp(s), maxHp(s)
    if h > 0 and m > 0 and m < 9999 and h * 100 // m < wpct then
      worst, wpct = s, h * 100 // m
    end
  end
  return worst
end

-- --------------------------------------------------------------- watches --
-- battle_kitrefuse's three, read at the source: the mp-cost queue
-- CreateAction writes ($3620,y, counted per command out of $3a7a, because
-- the bystanders' own Items go through the same store), the error sound
-- ($95) and the confirm sound ($96, which the tools shell stamps on every A
-- press BEFORE the gate).  Direct-page stores land in bank $00, so both
-- views of $95/$96 are watched.
local seen = { [CMD_STEAL] = 0, [CMD_ITEM] = 0 }
local lastQ = nil
local buzzes, confirms = 0, 0
local function armWatches()
  emu.addMemoryCallback(function(_, v)
    local c = H.readByte(QCMD)
    if seen[c] ~= nil then
      seen[c] = seen[c] + 1
      lastQ = { cmd = c, cost = v }
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
-- battle_thief's per-slot menu drive, one mode per slot:
--   "defer"        X at the command window, B anywhere else (TERRA, always)
--   "care"         EDGAR: a Tonic on whoever is under half, else defer
--   "item"         one Tonic turn on the default target (the pip-paying turn)
--   "park:<row>"   open the thief submenu, walk to the row, hold
--   "confirm:<row>" ...and press A there; in target select steer to `target`
local mf = 0
local modeOf = {}
local target = nil
local locke, ally = nil, nil
local tc = H.targetCursor({ mask = TCURSOR,
                            dirs = { "down", "up", "left", "right" } })
local hb = -900
local function heartbeat()
  if H.frame - hb < 900 then return end
  hb = H.frame
  local hps = {}
  for s = 0, 3 do
    if maxHp(s) > 0 and maxHp(s) < 9999 then
      hps[#hps + 1] = string.format("%d/%d", hp(s), maxHp(s))
    end
  end
  H.log(string.format("[hb f%d] locke=%s batt=%s menu=%02x actor=%s st=%02x "
    .. "bank=%s pend=%s mp=%s hp=%s", H.frame,
    locke and modeOf[locke] or "?", tostring(H.battleLoadStarted()),
    H.readByte(MENU), tostring(H.readByte(ACTOR)), H.readByte(MSTATE),
    locke and bp(locke) or "?", locke and pend(locke) or "?",
    locke and mp(locke) or "?", table.concat(hps, " ")))
end

local function toCmd(slot, cmd)
  local want = cmdRowOf(slot, cmd)
  local cur = H.readByte(CMDROW + slot) & 3
  if cur == want then return "a" end
  return (cur < want) and "down" or "up"
end
local function itemPick(slot)
  local want = bagIdxOf({ TONIC, POTION })
  if want == nil then return "b" end
  local cur = H.readByte(0x8947 + slot) + H.readByte(0x894F + slot)
  if cur < want then return "down" end
  if cur > want then return "up" end
  return "a"
end

local function decide()
  heartbeat()
  if H.readByte(MENU) == 0 then
    return (H.frame % 8 < 4) and { a = true } or {}
  end
  tc.observe()
  mf = mf + 1
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  if st == ST_TRANS then return {} end
  local mode = modeOf[act] or "defer"
  if st == ST_ITEM then
    if (mf - 1) % 30 >= 6 then return {} end
  else
    if (mf - 1) % 8 >= 4 then return {} end
  end
  local btn
  if mode == "defer" then
    btn = (st == ST_CMD) and "x" or "b"
  elseif mode == "care" then
    local who = hurtSlot()
    if who == nil or bagIdxOf({ TONIC, POTION }) == nil then
      btn = (st == ST_CMD) and "x" or "b"
    elseif st == ST_CMD then btn = toCmd(act, CMD_ITEM)
    elseif st == ST_ITEM then btn = itemPick(act)
    elseif st == ST_TGT then btn = tc.steer(who, mf)
    else btn = "b" end
  elseif mode == "item" then
    if st == ST_CMD then btn = toCmd(act, CMD_ITEM)
    elseif st == ST_ITEM then btn = itemPick(act)
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
  else
    local row = tonumber(mode:match(":(%d)"))
    local press = mode:sub(1, 7) == "confirm"
    if st == ST_CMD then btn = toCmd(act, CMD_STEAL)
    elseif st == ST_THIEF then
      local curRow = H.readByte(KROW + act)
      if H.readByte(KCOL + act) ~= 0 then btn = "left"
      elseif curRow < row then btn = "down"
      elseif curRow > row then btn = "up"
      elseif press then btn = "a"
      else btn = nil end                    -- parked: hold for the reads
    elseif st == ST_TGT then btn = tc.steer(target, mf)
    else btn = "b" end
  end
  return btn and { [btn] = true } or {}
end

local function driveTo(pred, maxF, tag)
  return H.driveUntil(pred, maxF, {
    H.call(function() H.setPad(decide()) end),
  }, tag)
end

local function parkedOnBestow()
  return H.battleLoadStarted() and H.readByte(MENU) ~= 0
     and (H.readByte(ACTOR) & 3) == locke and H.readByte(MSTATE) == ST_THIEF
     and H.readByte(KROW + locke) == BESTOW_ROW and H.readByte(KCOL + locke) == 0
end

-- ------------------------------------------------- the refusal assertion --
local before = {}
local function snapshot(label)
  before = {
    label = label, mp = mp(locke), bp = bp(locke), pend = pend(locke),
    allyBp = bp(ally), qcount = H.readByte(QCOUNT), seen = seen[CMD_STEAL],
    buzzes = buzzes, confirms = confirms,
  }
  H.log(string.format("[%s] parked on Bestow (row %d): mp=%d bank=%d pend=%d "
    .. "ally bank=%d qcount=%d", label, BESTOW_ROW, before.mp, before.bp,
    before.pend, before.allyBp, before.qcount))
end

local function assertRefused()
  local label = before.label
  H.log(string.format("[%s] after the confirm: mp=%d bank=%d pend=%d "
    .. "ally bank=%d qcount=%d state=%02x actor=%02x close=%d cursor=(%d,%d) "
    .. "queued(+%d) buzz(+%d) confirm(+%d)",
    label, mp(locke), bp(locke), pend(locke), bp(ally), H.readByte(QCOUNT),
    H.readByte(MSTATE), H.readByte(ACTOR), H.readByte(CLOSEFLAG),
    H.readByte(KROW + locke), H.readByte(KCOL + locke),
    seen[CMD_STEAL] - before.seen, buzzes - before.buzzes,
    confirms - before.confirms))
  H.assertEq(confirms > before.confirms, true, string.format(
    "%s: the A press reached the list ($96, which this window stamps before "
    .. "the gate) -- the refusal below is a rejection and not a press that "
    .. "never arrived", label))
  H.assertEq(buzzes > before.buzzes, true, string.format(
    "%s: ...and the confirm BUZZED ($95, magic's own error sound) -- the "
    .. "greyed Bestow was refused, as an unaffordable Blitz is", label))
  H.assertEq(H.readByte(MSTATE), ST_THIEF, string.format(
    "%s: the list is still open (menu state $30) -- the player is still "
    .. "choosing", label))
  H.assertEq(H.readByte(ACTOR) & 3, locke, string.format(
    "%s: ...and it is still LOCKE's window", label))
  H.assertEq(H.readByte(KROW + locke), BESTOW_ROW, string.format(
    "%s: the cursor is still on the refused row", label))
  H.assertEq(H.readByte(CLOSEFLAG), 0, string.format(
    "%s: the window was never told to close ($7bcb)", label))
  H.assertEq(H.readByte(QCOUNT), before.qcount, string.format(
    "%s: no action was committed -- the queue counter $7b80 has not moved, "
    .. "so the TURN was not consumed", label))
  H.assertEq(seen[CMD_STEAL], before.seen, string.format(
    "%s: CreateAction never queued a cmd $05 -- nothing reached the mp-cost "
    .. "store at $3620, which is where a commit would have shown up", label))
  H.assertEq(bp(locke), before.bp, string.format(
    "%s: the bank is untouched (still %d)", label, before.bp))
  H.assertEq(pend(locke), before.pend, string.format(
    "%s: no pending boost was armed -- refusing costs no BP", label))
  H.assertEq(mp(locke), before.mp, string.format(
    "%s: the pool is unmoved -- the 5 MP was never paid", label))
  H.assertEq(bp(ally), before.allyBp, string.format(
    "%s: the ally's bank is unmoved -- nothing was handed over", label))
end

-- one Bestow, from LOCKE's command window to the ally's bank moving
local function bestowLands(label, allyWant)
  return H.repeatN(1, {
    H.call(function()
      H.vars.mp0, H.vars.q0, H.vars.seen0 = mp(locke), H.readByte(QCOUNT),
        seen[CMD_STEAL]
      H.vars.allyBp0, H.vars.bp0 = bp(ally), bp(locke)
      H.log(string.format("[%s] LOCKE bank=%d pend=%d mp=%d, ally bank=%d",
        label, bp(locke), pend(locke), mp(locke), bp(ally)))
      target = ally
      modeOf[locke] = "confirm:" .. BESTOW_ROW
    end),
    driveTo(function() return seen[CMD_STEAL] > H.vars.seen0 end, 20000,
      label .. ": Bestow is queued"),
    H.call(function()
      H.log(string.format("[%s] queued: cmd $%02x cost %d, qcount %d -> %d",
        label, lastQ.cmd, lastQ.cost, H.vars.q0, H.readByte(QCOUNT)))
      H.assertEq(lastQ.cost, COST_BESTOW, string.format(
        "%s: the committed row reached CreateAction priced %d -- Bestow's "
        .. "drawn price", label, COST_BESTOW))
      modeOf[locke] = "defer"
      target = nil
    end),
    driveTo(function() return bp(ally) >= allyWant end, 20000,
      label .. ": the bestow lands (the ally's bank goes up)"),
    H.waitFrames(180),                          -- past LOCKE's own ActionEnd
    H.call(function()
      H.log(string.format("[%s] landed: ally bank %d -> %d, LOCKE bank %d -> %d, "
        .. "mp %d -> %d", label, H.vars.allyBp0, bp(ally), H.vars.bp0,
        bp(locke), H.vars.mp0, mp(locke)))
      H.assertEq(bp(ally), H.vars.allyBp0 + 1, string.format(
        "%s: the ally banked exactly one pip", label))
      H.assertEq(bp(locke), H.vars.bp0 - 1, string.format(
        "%s: LOCKE paid it -- Ot6ActionEnd charged the pending 1 and skipped "
        .. "his regen", label))
      H.assertEq(mp(locke), H.vars.mp0 - COST_BESTOW, string.format(
        "%s: ...and the pool paid the %d drawn", label, COST_BESTOW))
    end),
  })
end

H.run({ maxFrames = 90000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.hold({ "b" }),
  H.driveUntil(function() return H.readByte(0x11fa) & 3 == 0 end, 900, {
    H.waitFrames(1) }, "chocobo dismount"),
  H.release(),
  H.waitFrames(120),
  H.driveUntil(function() return H.battleLoadStarted() end, 25000, {
    H.call(function()
      if not H.worldMode() or not H.worldHasControl() then H.setPad({}); return end
      H.setPad(((H.frame // 120) % 2 == 0) and { left = true } or { right = true })
    end),
  }, "desert encounter"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(90),
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id == LOCKE then locke = s end
      if id == TERRA then ally = s end
    end
    H.assertEq(locke ~= nil, true, "LOCKE is really in this party")
    H.assertEq(ally ~= nil, true, "TERRA (the ally) is really in this party")
    for s = 0, 3 do
      if s ~= locke and s ~= ally and maxHp(s) > 0 and maxHp(s) < 9999 then
        modeOf[s] = "care"
      end
    end
    modeOf[ally] = "defer"
    H.assertEq(bp(locke), 1, "LOCKE opens with Ot6InitBP's 1")
    H.assertEq(bp(ally), 1, "so does the ally (her ledger starts here)")
    H.assertEq(mp(locke) >= 3 * COST_BESTOW, true,
      "his pool covers the three Bestows below, so every refusal is the BP's")
    H.assertEq(bagIdxOf({ TONIC, POTION }) ~= nil, true,
      "the bag holds a Tonic for the pip-paying item turn")
    H.log(string.format("LOCKE slot %d (mp %d), ally slot %d; formation %s",
      locke, mp(locke), ally, table.concat((function()
        local t = {}
        for _, id in ipairs(H.monsterIds()) do
          if id ~= 0xFFFF then t[#t + 1] = string.format("%03x", id) end
        end
        return t
      end)(), ",")))
    armWatches()
  end),

  -- ---- 1. the opening bank: Bestow commits, lands, and empties the bank ---
  bestowLands("bestow-1bp", 2),
  H.call(function()
    H.assertEq(bp(locke), 0, "LOCKE stands at 0 BP by real play: the "
      .. "caster #232 is about")
    H.log("PASSED 1: at 1 BP Bestow commits and lands")
  end),

  -- ---- 2. the 0 bank: greyed, and now refused ----------------------------
  H.call(function() modeOf[locke] = "park:" .. BESTOW_ROW end),
  driveTo(parkedOnBestow, 20000,
    "his next window's submenu, parked on Bestow at a 0 bank"),
  H.call(function() H.setPad({}) end),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(KITMODE), 0x03, "the thief submenu is up (w7e6168 == 3)")
    H.assertEq(H.readByte(ILIST + BESTOW_ROW * 6), ID_BESTOW,
      "row 2 is the Bestow id")
    local aS, aB = attrOf(NM.Steal), attrOf(NM.Bestow)
    H.log(string.format("[bestow-0bp] bank=%d mp=%d -> attr Steal=%s Bestow=%s",
      bp(locke), mp(locke), fmt(aS), fmt(aB)))
    H.assertEq(bp(locke), 0, "the window was staged on a 0 bank")
    H.assertEq(aB, GREY, "Bestow renders GREY at 0 BP -- the grey and the "
      .. "refusal below are the same Ot6BushidoRowGrey answer about the same row")
    H.assertEq(aS, WHITE, "Steal has no BP precondition: still white")
    H.screenshot("bestowrefuse_grey")
    snapshot("bestow-0bp")
    target = ally
    modeOf[locke] = "confirm:" .. BESTOW_ROW
  end),
  driveTo(function()
    return buzzes > before.buzzes or seen[CMD_STEAL] > before.seen
  end, 1800, "the greyed Bestow is confirmed: refused, or (the defect) queued"),
  H.release(),
  -- The defect's own path, so a build that lets the row through says so in
  -- play rather than by an absence: ride the committed turn out and write
  -- down what it bought.
  H.cond(function() return seen[CMD_STEAL] > before.seen end, {
    H.call(function()
      H.log(string.format("[bestow-0bp] COMMITTED: the greyed row went through "
        .. "-- cmd $%02x queued at cost %d, qcount %d -> %d", lastQ.cmd,
        lastQ.cost, before.qcount, H.readByte(QCOUNT)))
      modeOf[locke] = "defer"
      target = nil
      H.vars.t0 = H.frame
    end),
    driveTo(function()
      return mp(locke) <= before.mp - COST_BESTOW or H.frame - H.vars.t0 > 2400
    end, 3000, "the committed bestow resolves (the pool pays)"),
    H.waitFrames(180),
    H.call(function()
      H.log(string.format("[bestow-0bp] the turn bought: LOCKE bank %d -> %d, "
        .. "ally bank %d -> %d, mp %d -> %d, qcount %d -> %d -- the turn and "
        .. "%d MP spent, the ally banked nothing", before.bp, bp(locke),
        before.allyBp, bp(ally), before.mp, mp(locke), before.qcount,
        H.readByte(QCOUNT), before.mp - mp(locke)))
    end),
  }, {}),
  H.waitFrames(120),
  H.call(function()
    H.setPad({})
    modeOf[locke] = "park:" .. BESTOW_ROW
    target = nil
    assertRefused()
    H.screenshot("bestowrefuse_refused")
    H.log("PASSED 2: at 0 BP the greyed Bestow is refused at the confirm")
  end),

  -- ---- 3. one real pip back, and the same row commits: a gate, not a wall -
  H.call(function() modeOf[locke] = "item" end),
  driveTo(function() return bp(locke) == 1 end, 20000,
    "one real item turn banks the pip back"),
  bestowLands("bestow-again", 3),
  H.call(function()
    H.log("PASSED 3: the row that was refused commits again at 1 BP -- the "
      .. "refusal is a gate, not a wall")
    H.screenshot("bestowrefuse_done")
  end),
})
