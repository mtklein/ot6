-- @suite slow
-- battle_lockekit.lua -- LOCKE's kit past Steal (#382): Mug, Trickshot,
-- Dismantle and Appraise, each through the real thief list.
--
-- kits.md ("Locke"): the rows sit behind his Steal command beside Steal,
-- Filch and Bestow, each taught by a story beat's event switch
-- (ot6_thief.asm Ot6ThiefRowTbl).  At fire-out-v1 the Lete River, his South
-- Figaro escape, the Sealed Gate and Strago's meeting are behind him, so
-- four of the five are learned; the Air Force's ($00A0) is not, so Master's
-- Mark is not (battle_mastersmark plays it).
--
-- Played: Continue fire-out-v1 (TERRA, LOCKE, STRAGO) and walk the plain east
-- of Thamasa (battle_study's lap), one counted LOCKE action a battle through
-- H.kitBattle; the others Fight.  Nothing is written.  Stages:
--   1. the list (peek): Steal $56, Filch $57, Bestow $58 and Mug $E0 down the
--      left column, Trickshot $E1, Dismantle $E2 and Appraise $E3 down the
--      right, Master's Mark's cell empty; prices 4 / 4 / 8 / 3 MP;
--   2. Mug at 1 BP on a body that carries loot: it runs as Capture --
--      Ot6FightBoost buys its two extra swings (four passes of _magicpunch,
--      a Fight's two, one a hand, and two for the point, or fewer only when
--      no body is left standing), each
--      landing hit runs Steal's effect, and the steal rolls vanilla's odds
--      (Ot6StealBoostLevel hands back the raw level with a point pending:
--      the boost bought the swings and pays once); 4 MP, the bank pays the
--      point;
--   3. Trickshot at 0 BP, then 4. at 1 BP: at the damage calc the props are
--      the coin's (power 40, physical, ignore defense, class pierce) under
--      command $18, which Ot6BoostDmg multiplies; the body loses HP; 4 MP,
--      then 10 at 1 BP (x2.5, the price escalates with the multiplier);
--   5. Dismantle at 2 BP: the body's defense ($3BB8) drops by three quarter
--      steps (each a quarter, at least one point), the stab goes in under
--      Steal's command $05 (not multiplied), class pierce; 8 MP flat;
--   6. Appraise at 0 BP: Ot6AnalyzeOne read the target alone, its weak
--      elements and classes; 7. at 1 BP with two or more bodies standing:
--      it read every one; 3 MP flat at either boost.
-- A battle where the stage cannot be played (no loot for Mug, one body for
-- stage 7, LOCKE out or short of MP) is fought out and the next taken; a
-- stage whose counted effect did not happen (every Mug swing missed, the
-- body fell first) is not counted and is played again.
-- Old-ROM red and mutants: build/attempts/wt/v032-locke-kit/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local LOCKE, CMD = 0x01, 0x05
local STEAL, FILCH, BESTOW, MUG, TRICK, DIS, APP, MARK = 0x56, 0x57, 0x58, 0xE0, 0xE1, 0xE2, 0xE3, 0xE4
local PIERCE = 0x02

local function ent(s) return 8 + s * 2 end
local function present(s) return (H.readByte(0x3AA8 + s * 2) & 1) == 1 end
local function live(s) return present(s) and H.readWord(0x3BFC + s * 2) > 0 end
local function loot(s) return H.readByte(0x3308 + ent(s)) ~= 0xFF or H.readByte(0x3309 + ent(s)) ~= 0xFF end
local function liveCount() local n = 0 for s = 0, 5 do if live(s) then n = n + 1 end end return n end
local function anyLive() for s = 0, 5 do if live(s) then return true end end return false end
local function slotOfMask(m) for s = 0, 5 do if (m >> s) & 1 == 1 then return s end end end
local function price(base, boost)
  if boost == 0 then return base end
  return math.max(base, math.min(99, math.floor(base * 2.5 ^ boost + 0.5)))
end
local function corrode(def, steps)
  for _ = 1, steps do
    if def == 0 then break end
    local cut = def >> 2
    if cut == 0 then cut = 1 end
    def = def - cut
  end
  return def
end

local seat, rec, stage, battles, mode = nil, nil, 1, 0, nil
local plan = {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local function lockeX() return (emu.getState()["cpu.x"] & 0xFF) == seat * 2 end
local function inAnalyzeOne()
  local st = emu.getState()
  local pc = (st["cpu.k"] << 16) | st["cpu.pc"]
  local a = H.sym("Ot6AnalyzeOne")
  return pc >= a and pc < a + 76      -- the proc's size (ff6-en.dbg)
end

-- the return address of the jsl that entered the routine now executing (its
-- first instruction): the three bytes the jsl pushed
local function jslReturn()
  local st = emu.getState()
  local sp = st["cpu.sp"] & 0xFFFF
  local function rb(o) return emu.read(sp + o, emu.memType.snesMemory) end
  return ((rb(3) << 16) | (rb(2) << 8) | rb(1)) + 1
end

local function arm()
  local function open(row, target)
    if seat == nil or rec ~= nil then return end
    local e = seat * 2
    rec = { row = row, pend = H.readByte(0x3E9D + e), bank0 = H.readByte(0x3E9C + e), mp0 = H.readWord(0x3C08 + e),
      f = H.frame, swings = 0, steals = 0, levels = {}, calc = {}, read = {}, target = target }
    if target ~= nil then
      rec.hp0 = H.readWord(0x3BFC + target * 2)
      rec.def0 = H.readByte(0x3BB8 + ent(target))
    end
  end
  emu.addMemoryCallback(function()
    if seat == nil or not lockeX() then return end
    local row = H.readByte(0xB6)
    if row >= TRICK and row <= MARK then open(row, slotOfMask(H.readByte(0xB9))) end
  end, emu.callbackType.exec, H.sym("Ot6ThiefExec"), H.sym("Ot6ThiefExec"))
  emu.addMemoryCallback(function()
    if seat == nil or (emu.getState()["cpu.y"] & 0xFF) ~= seat * 2 then return end
    if H.readByte(0xB6) == MUG then open(MUG, slotOfMask(H.readByte(0xB9))) end
  end, emu.callbackType.exec, H.sym("Ot6MugCheck"), H.sym("Ot6MugCheck"))
  emu.addMemoryCallback(function()
    if rec == nil or rec.ended or not lockeX() then return end
    rec.fightBoost = H.readByte(0x3E9D + seat * 2)
  end, emu.callbackType.exec, H.sym("Ot6FightBoost"), H.sym("Ot6FightBoost"))
  emu.addMemoryCallback(function()
    if rec == nil or rec.ended or not lockeX() then return end
    rec.swings = rec.swings + 1
  end, emu.callbackType.exec, H.sym("_c2299f"), H.sym("_c2299f"))
  emu.addMemoryCallback(function()
    if rec == nil or rec.ended then return end
    rec.steals = rec.steals + 1
  end, emu.callbackType.exec, H.sym("TargetEffect_52"), H.sym("TargetEffect_52"))
  -- what the steal roll is handed: Ot6StealBoostLevel's A at its return
  -- (one exec callback at the jsl's return site, armed by the entry)
  local retArmed, entry = {}, nil
  emu.addMemoryCallback(function()
    if rec == nil or rec.ended or not lockeX() then return end
    local ret = jslReturn()
    entry = { pend = H.readByte(0x3E9D + seat * 2), b5 = H.readByte(0xB5) }
    if not retArmed[ret] then
      retArmed[ret] = true
      emu.addMemoryCallback(function()
        if entry == nil or rec == nil then return end
        rec.levels[#rec.levels + 1] = { a = emu.getState()["cpu.a"] & 0xFF, level = H.readByte(0x3B18 + seat * 2),
          pend = entry.pend, b5 = entry.b5 }
        entry = nil
      end, emu.callbackType.exec, ret, ret)
    end
  end, emu.callbackType.exec, H.sym("Ot6StealBoostLevel"), H.sym("Ot6StealBoostLevel"))
  emu.addMemoryCallback(function()
    if rec == nil or rec.ended or not lockeX() then return end
    rec.calc[#rec.calc + 1] = { b5 = H.readByte(0xB5), power = H.readByte(0x11A6), flags = H.readByte(0x11A2),
      cls = H.readByte(0x57B8), pend = H.readByte(0x3E9D + seat * 2), dmg = H.readWord(0x11B0) }
  end, emu.callbackType.exec, H.sym("Ot6BoostDmg"), H.sym("Ot6BoostDmg"))
  -- the pending reveal Ot6AnalyzeOne writes, per slot (battle_analyze's)
  emu.addMemoryCallback(function(addr, v)
    if rec == nil or rec.ended or not inAnalyzeOne() then return end
    local o = addr - 0x7EED45
    local cls = o >= 12
    local s = (cls and o - 12 or o) // 2
    rec.read[s] = rec.read[s] or { elem = 0, cls = 0 }
    if cls then rec.read[s].cls = rec.read[s].cls | v else rec.read[s].elem = rec.read[s].elem | v end
  end, emu.callbackType.write, 0x7EED45, 0x7EED5C)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if rec == nil or rec.ended or seat == nil or not lockeX() then return end
    rec.ended = H.frame
  end, emu.callbackType.exec, ae, ae)
end
local function closed()
  if rec == nil or rec.ended == nil or H.frame <= rec.ended + 30 then return false end
  if rec.mp1 == nil then
    local e = seat * 2
    rec.mp1, rec.bank1 = H.readWord(0x3C08 + e), H.readByte(0x3E9C + e)
    if rec.target ~= nil then
      rec.hp1, rec.def1 = H.readWord(0x3BFC + rec.target * 2), H.readByte(0x3BB8 + ent(rec.target))
    end
  end
  return true
end

local function bankPaid(r, boost, what)
  local regen = (boost == 0 and r.bank0 < 5) and 1 or 0
  H.assertEq(r.bank1, r.bank0 - boost + regen, string.format("%s: the bank paid the %d point(s)%s", what, boost,
    regen == 1 and " and earned the unboosted turn's pip" or ""))
end

-- the stage's plan entry for this battle, or nil (fought out)
local function entryFor()
  local e = seat * 2
  local mp = H.readWord(0x3C08 + e)
  local can = H.readWord(0x3BF4 + e) > 0 and (H.readByte(0x3EE4 + e) & 0xE2) == 0 and mp >= 12
  if not can then return nil, "LOCKE cannot act or is short of MP" end
  local first
  for s = 0, 5 do if live(s) then first = first or s end end
  if stage == 1 then return { who = LOCKE, cmd = CMD, peek = true } end
  if stage == 2 then
    for s = 0, 5 do
      if live(s) and loot(s) then return { who = LOCKE, cmd = CMD, row = MUG, boost = 1, slot = s } end
    end
    return nil, "no standing body carries loot"
  end
  if stage == 3 then return { who = LOCKE, cmd = CMD, row = TRICK, boost = 0, slot = first } end
  if stage == 4 then return { who = LOCKE, cmd = CMD, row = TRICK, boost = 1, slot = first } end
  if stage == 5 then
    for s = 0, 5 do
      if live(s) and H.readByte(0x3BB8 + ent(s)) > 0 then
        return { who = LOCKE, cmd = CMD, row = DIS, boost = 2, slot = s }
      end
    end
    return nil, "no standing body has defense to corrode"
  end
  if stage == 6 then return { who = LOCKE, cmd = CMD, row = APP, boost = 0, slot = first } end
  if stage == 7 then
    if liveCount() < 2 then return nil, "one body: the breadth needs two" end
    return { who = LOCKE, cmd = CMD, row = APP, boost = 1, slot = first }
  end
end

local function onList(p, a)
  if not p.peek then return end
  local cells = {}
  for i = 0, 7 do cells[i] = { id = H.readByte(0x4005 + i * 3), qty = H.readByte(0x4006 + i * 3) } end
  local t = {}
  for i = 0, 7 do t[#t + 1] = string.format("%d:$%02X/%d", i, cells[i].id, cells[i].qty) end
  H.log("[lockekit] the thief list: " .. table.concat(t, " "))
  H.assertEq(H.readByte(0x6168), 3, "the list is the thief list (w7e6168 = 3)")
  local want = { [0] = STEAL, [2] = FILCH, [4] = BESTOW, [6] = MUG, [1] = TRICK, [3] = DIS, [5] = APP }
  for i, id in pairs(want) do
    H.assertEq(cells[i].id, id, string.format("cell %d holds row $%02X", i, id))
  end
  H.assertEq(cells[7].id, 0xFF, "Master's Mark's cell is empty: the Air Force ($00A0) is still ahead")
  H.assertEq(cells[6].qty, 4, "Mug draws 4 MP")
  H.assertEq(cells[1].qty, 4, "Trickshot draws 4 MP at 0 BP")
  H.assertEq(cells[3].qty, 8, "Dismantle draws 8 MP")
  H.assertEq(cells[5].qty, 3, "Appraise draws 3 MP")
  H.screenshot("lockekit_list")
end

local function judge()
  local r = rec
  local what = ({ [MUG] = "Mug", [TRICK] = "Trickshot", [DIS] = "Dismantle", [APP] = "Appraise" })[r.row]
  H.log(string.format("[lockekit] stage %d: %s at %d BP (f%d) on slot %s: MP %d -> %d, bank %d -> %d; HP %s -> %s, "
    .. "def %s -> %s; swings %d, steal effects %d, fight boost %s", stage, what, r.pend, r.f, tostring(r.target),
    r.mp0, r.mp1, r.bank0, r.bank1, tostring(r.hp0), tostring(r.hp1), tostring(r.def0), tostring(r.def1), r.swings,
    r.steals, tostring(r.fightBoost)))
  for i, c in ipairs(r.calc) do
    H.log(string.format("[lockekit]   damage calc %d: $b5 $%02X power %d flags $%02X class $%02X pend %d base %d",
      i, c.b5, c.power, c.flags, c.cls, c.pend, c.dmg))
  end
  for i, l in ipairs(r.levels) do
    H.log(string.format("[lockekit]   steal roll %d: level handed %d (raw %d) at %d BP pending, $b5 $%02X", i, l.a,
      l.level, l.pend, l.b5))
  end
  if stage == 2 then
    H.assertEq(r.row, MUG, "the counted action is the Mug")
    H.assertEq(r.pend, 1, "Mug ran at the 1 BP planned")
    H.assertEq(r.fightBoost, 1, "Mug ran as Capture: Ot6FightBoost saw its point (the boost buys swings)")
    if not (r.swings == 4 or (r.swings >= 1 and not anyLive())) then
      H.assertEq(r.swings, 4, "a 1-BP Mug makes four passes: a Fight's two (one a hand) and two a point")
    end
    if r.steals == 0 or #r.levels == 0 then
      H.log("[lockekit] no hit reached the steal roll (missed, or the loot was gone): not counted")
      return false
    end
    for _, l in ipairs(r.levels) do
      H.assertEq(l.b5, 0x06, "the steal on Mug's hit runs under Capture ($b5 = $06)")
      H.assertEq(l.a, l.level, "the steal on Mug's hit rolls vanilla's odds: the raw level, not the boosted one "
        .. "(the boost bought the swings; it pays once)")
    end
    H.assertEq(r.mp0 - r.mp1, 4, "Mug cost 4 MP")
    bankPaid(r, 1, "Mug")
  elseif stage == 3 or stage == 4 then
    local b = stage == 3 and 0 or 1
    H.assertEq(r.row, TRICK, "the counted action is the Trickshot")
    H.assertEq(r.pend, b, string.format("Trickshot ran at the %d BP planned", b))
    H.assertEq(#r.calc, 1, "Trickshot is one damage calc")
    local c = r.calc[1]
    H.assertEq(c.b5, 0x18, "the coin runs under command $18, which Ot6BoostDmg multiplies (not Steal's gated $05)")
    H.assertEq(c.power, 40, "the coin's battle power is 40")
    H.assertEq(c.flags & 0x21, 0x21, "the coin is physical and ignores defense")
    H.assertEq(c.cls, PIERCE, "the coin pierces")
    H.assertEq(r.hp1 < r.hp0, true, "the body lost HP to the coin")
    H.assertEq(r.mp0 - r.mp1, price(4, b), string.format("Trickshot cost %d MP at %d BP", price(4, b), b))
    bankPaid(r, b, "Trickshot")
  elseif stage == 5 then
    H.assertEq(r.row, DIS, "the counted action is the Dismantle")
    H.assertEq(r.pend, 2, "Dismantle ran at the 2 BP planned")
    H.assertEq(r.def1, corrode(r.def0, 3), string.format("the body's defense corroded three steps, %d -> %d",
      r.def0, corrode(r.def0, 3)))
    H.assertEq(#r.calc, 1, "Dismantle's stab is one damage calc")
    H.assertEq(r.calc[1].b5, 0x05, "the stab runs under Steal's command $05: the boost bought the corrode, not a "
      .. "multiplier")
    H.assertEq(r.calc[1].cls, PIERCE, "the stab pierces")
    H.assertEq(r.mp0 - r.mp1, 8, "Dismantle cost 8 MP flat at 2 BP")
    bankPaid(r, 2, "Dismantle")
  elseif stage == 6 or stage == 7 then
    local b = stage == 6 and 0 or 1
    H.assertEq(r.row, APP, "the counted action is the Appraise")
    H.assertEq(r.pend, b, string.format("Appraise ran at the %d BP planned", b))
    local want = {}
    if b == 0 then want[r.target] = true else
      for s = 0, 5 do
        if live(s) and (H.readByte(0x3C80 + ent(s)) & 0x10) == 0 then want[s] = true end
      end
    end
    for s = 0, 5 do
      if want[s] then
        local rd = r.read[s]
        H.assertEq(rd ~= nil, true, string.format("Ot6AnalyzeOne read slot %d", s))
        local weak = H.readByte(0x3BE0 + ent(s)) & ~H.readByte(0xEDD8 + ent(s) - 8) & 0xFF
        H.assertEq(rd.elem & weak, weak, string.format("slot %d: the read holds its weak elements", s))
        H.assertEq(rd.cls & H.readByte(0x3E9C + ent(s)), H.readByte(0x3E9C + ent(s)),
          string.format("slot %d: the read holds its weak classes", s))
      elseif b == 0 then
        H.assertEq(r.read[s], nil, string.format("unboosted, slot %d (not the target) was not read", s))
      end
    end
    H.assertEq(r.mp0 - r.mp1, 3, string.format("Appraise cost 3 MP flat at %d BP", b))
    bankPaid(r, b, "Appraise")
  end
  return true
end

local function decide()
  battles = battles + 1
  H.assertEq(battles <= 30, true, "the seven stages within 30 battles")
  seat, plan, mode, rec = nil, {}, "play", nil
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == LOCKE then seat = s end end
  H.assertEq(seat ~= nil, true, "LOCKE is seated")
  local p, why = entryFor()
  local ids = {}
  for s = 0, 5 do
    if live(s) then
      ids[#ids + 1] = string.format("%d:$%03X%s", s, H.readWord(0x57C0 + s * 2), loot(s) and "*" or "")
    end
  end
  H.log(string.format("[lockekit] battle %d, stage %d: %s; LOCKE seat %d MP %d bank %d", battles, stage,
    table.concat(ids, " "), seat, H.readWord(0x3C08 + seat * 2), H.readByte(0x3E9C + seat * 2)))
  if p == nil then
    mode = "fightout"
    H.log("[lockekit] " .. why .. ": fought out, the next battle taken")
    return
  end
  plan = { p }
end

local home, away
local function lap()
  local goal, wplan, idx
  return H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
    H.call(function()
      if not H.worldHasControl() or not H.worldSettled() then wplan = nil; H.setPad({}) return end
      if not H.worldAligned() then return end
      local x, y = H.worldX(), H.worldY()
      goal = goal or away
      if wplan == nil or idx > #wplan then
        if x == goal[1] and y == goal[2] then goal = (goal == away) and home or away end
        wplan, idx = H.worldBfs(goal[1], goal[2]), 1
        if not wplan or #wplan == 0 then wplan = nil; H.setPad({}) return end
      end
      local dir = wplan[idx]; idx = idx + 1
      H.setPad({ [dir] = true })
    end),
  }, "a random encounter")
end

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

H.run({ maxFrames = 1500000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function()
    local ph = 0
    return H.driveUntil(function()
      return H.worldMode() and bright() >= 15 and H.worldHasControl()
    end, 6000, {
      H.call(function()
        ph = (ph + 1) % 48
        if bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "cold Continue -> world map control")
  end)(),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("fire-out-v1")
    H.assertEq((H.readByte(0x1850 + LOCKE) & 7) ~= 0, true, "LOCKE is in the party")
    for _, sw in ipairs({ 0x001A, 0x001E, 0x0079, 0x008D }) do
      H.assertEq((H.readByte(0x1E80 + (sw >> 3)) >> (sw & 7)) & 1, 1, string.format("switch $%04X is set (a row's "
        .. "story beat is behind him)", sw))
    end
    H.assertEq((H.readByte(0x1E80 + (0xA0 >> 3)) >> (0xA0 & 7)) & 1, 0, "switch $00A0 is clear (the Air Force is "
      .. "ahead)")
    arm()
  end),
  H.waitUntil(function() return H.worldSettled() end, 1200, "world settled", 5),
  H.call(function()
    home, away = { 250, 126 }, { 251, 127 }
    H.assertEq(H.worldBfs(home[1], home[2]) ~= nil, true, "the lap's tiles are reachable")
  end),
  H.driveUntil(function() return stage > 7 end, 1450000, {
    H.cond(function() return not H.battleLoadStarted() end,
      { H.fieldCare({ tag = "lockekit" }), lap(), H.release() }, {}),
    H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5),
    H.call(decide),
    H.cond(function() return mode == "fightout" end, { H.kitBattle({}, {}) }, {
      H.kitBattle(proxy, { untilPlanDone = true, others = "fight", idle = "defend", maxFrames = 60000,
        onList = onList, planDone = function() return stage == 1 or closed() end }),
      H.call(function()
        if stage == 1 then
          local k = H.vars.kit[#H.vars.kit]
          if k ~= nil and k.refusedSeen then stage = 2 end
          return
        end
        if not closed() then
          H.log("[lockekit] the battle ended before the action resolved: not counted")
          return
        end
        if judge() then
          H.log(string.format("[lockekit] PASSED stage %d", stage))
          stage = stage + 1
        end
      end),
      H.cond(function() return H.battleLoadStarted() end, { H.kitBattle({}, {}) }, {}),
    }),
    H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000,
      "back on the world map", 5),
  }, "the seven stages"),
  H.call(function()
    H.log("[lockekit] PASS: the list holds the four learned rows at their prices; Mug swings as Capture and steals "
      .. "at vanilla odds; Trickshot's coin pierces past defense and its boost multiplies at an escalating price; "
      .. "Dismantle corrodes a step a point; Appraise reads its target, every body with a point")
  end),
})
