-- @suite slow
-- battle_analyze.lua -- Strago's Analyze: he always knows Scan, and a
-- character's Scan reads every weakness of its target (#381).
--
-- kits.md ("Strago"): Analyze is cheap and early, a full weakness reveal.
-- It is the Scan spell (ot6_analyze.asm): Strago is granted it in battle and
-- in the field whatever stone he wears, and a character's Scan puts every
-- weak element and weak class of the body onto the HUD's revealed bytes and
-- into the save's codex for its species, with a boost of a point or more
-- reading every enemy on the field.
--
-- Played: Continue fire-out-v1 (STRAGO L24 seated with TERRA and LOCKE,
-- wearing Bismark; he has learned no spell, $1A6E + 7*54 + $18 is not $ff),
-- walk to random battles near Thamasa and, through the real menu
-- (H.kitBattle), have STRAGO cast Scan: first unboosted on a live body (one
-- whose weaknesses the HUD has not all revealed, when the field has one),
-- then at 1 BP in a battle with two or more scannable bodies.  Everyone
-- else Defends.  A battle with no such body is fought out and the next
-- taken.  Nothing is written.
--
-- Which bodies a cast read is taken from the reveal itself: the pending
-- bytes Ot6AnalyzeOne writes (OT6_RVPEND_ELEM $7EED45 + 2*slot, _CLS
-- $7EED51 + 2*slot), counted only when Ot6AnalyzeOne is the writer.  So the
-- breadth is measured whatever the save's codex already knows (a species
-- revealed in earlier battles still has its pending written).
--
-- Asserted, between the cast's start (Scan's own $3410 write under Magic)
-- and STRAGO's Ot6ActionEnd:
--   0. STRAGO's battle Magic list holds Scan, castable (the grant);
--   1. unboosted: Ot6AnalyzeOne read the target alone, and what it wrote
--      holds the target's weak elements ($3BE0, less a Debilitator's) and
--      weak classes ($3E9C); afterwards the target's revealed elements
--      ($3E89) and classes ($3E9D) hold them, as does every body of its
--      species; no other species' revealed bytes moved; the save's codex
--      holds them for the species;
--   2. at 1 BP: Ot6AnalyzeOne read every present, scannable body, and each
--      one's revealed bytes hold its weaknesses afterwards;
--   3. Scan cost its price at each boost (3 MP; at 1 BP the x2.5 ladder
--      every boosted spell pays, H.battleSpellPrice), and the bank paid the
--      boost.
-- Old-ROM red and mutants: build/attempts/wt/v030-plan-kits/kit/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local STRAGO, SCAN, CMD_MAGIC, SCAN_MP = 0x07, 0x18, 0x02, 3   -- MagicProp's own, unboosted

local function ent(s) return 8 + s * 2 end
local function present(s) return (H.readByte(0x3AA8 + s * 2) & 1) == 1 end
local function live(s) return present(s) and H.readWord(0x3BFC + s * 2) > 0 end
local function species(s) return H.readWord(0x57C0 + s * 2) end
local function scannable(s) return (H.readByte(0x3C80 + ent(s)) & 0x10) == 0 end
local function codexBase()
  local slot = H.readByte(0x021F)   -- wSaveSlotToLoad: 0 transient, 1..3 saved
  if slot < 1 or slot > 3 then return 0x316C00 end
  return 0x316000 + (slot - 1) * 0x400
end
local function codexElem(sp) return emu.read(codexBase() + 0x10 + sp, emu.memType.snesMemory) end
local function codexCls(sp) return emu.read(codexBase() + 0x190 + sp, emu.memType.snesMemory) end
local function body(s)
  local e = ent(s)
  return { present = present(s), sp = species(s), weak = H.readByte(0x3BE0 + e) & ~H.readByte(0xEDD8 + e - 8) & 0xFF,
    cls = H.readByte(0x3E9C + e), rev = H.readByte(0x3E89 + e), rcls = H.readByte(0x3E9D + e),
    scan = scannable(s) }
end
local function bodies() local t = {} for s = 0, 5 do t[s] = body(s) end return t end
local function unread(b)
  return b.present and b.scan and ((b.weak & ~b.rev) ~= 0 or (b.cls & ~b.rcls) ~= 0)
end

local seat, rec, recs = nil, nil, {}
local function inAnalyzeOne(st)
  local pc = (st["cpu.k"] << 16) | st["cpu.pc"]
  local a = H.sym("Ot6AnalyzeOne")
  return pc >= a and pc < a + 76      -- the proc's size (ff6-en.dbg)
end
local function arm()
  -- the pending reveal Ot6AnalyzeOne writes, per slot (elements, classes)
  emu.addMemoryCallback(function(addr, v)
    if rec == nil or rec.ended or not inAnalyzeOne(emu.getState()) then return end
    local o = addr - 0x7EED45
    local cls = o >= 12
    local s = (cls and o - 12 or o) // 2
    rec.read[s] = rec.read[s] or { elem = 0, cls = 0 }
    if cls then rec.read[s].cls = rec.read[s].cls | v else rec.read[s].elem = rec.read[s].elem | v end
  end, emu.callbackType.write, 0x7EED45, 0x7EED5C)
  emu.addMemoryCallback(function(_, v)
    if v ~= SCAN or seat == nil or rec ~= nil then return end
    if H.readByte(0x3A7C) ~= CMD_MAGIC then return end
    local e = seat * 2
    rec = { pend = H.readByte(0x3E9D + e), bank0 = H.readByte(0x3E9C + e), mp0 = H.readWord(0x3C08 + e),
      b0 = bodies(), f = H.frame, read = {} }
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if rec == nil or rec.ended or seat == nil then return end
    if (emu.getState()["cpu.x"] & 0xff) == seat * 2 then rec.ended = H.frame end
  end, emu.callbackType.exec, ae, ae)
end
local function close()
  if rec == nil or not rec.ended or H.frame <= rec.ended + 30 then return false end
  local e = seat * 2
  rec.bank1, rec.mp1, rec.b1 = H.readByte(0x3E9C + e), H.readWord(0x3C08 + e), bodies()
  for s = 0, 5 do
    local o, n = rec.b0[s], rec.b1[s]
    if o.present then
      H.log(string.format("[analyze] cast %d (%d BP, f%d): slot %d $%03X weak $%02X cls $%02X%s: revealed $%02X/$%02X "
        .. "-> $%02X/$%02X; codex $%02X/$%02X", #recs + 1, rec.pend, rec.f, s, o.sp, o.weak, o.cls,
        o.scan and "" or " (can't be scanned)", o.rev, o.rcls, n.rev, n.rcls, codexElem(o.sp), codexCls(o.sp)))
    end
  end
  local rd = {}
  for s = 0, 5 do
    if rec.read[s] then rd[#rd + 1] = string.format("%d:$%02X/$%02X", s, rec.read[s].elem, rec.read[s].cls) end
  end
  H.log(string.format("[analyze] cast %d: MP %d -> %d, bank %d -> %d; Ot6AnalyzeOne read slots %s", #recs + 1,
    rec.mp0, rec.mp1, rec.bank0, rec.bank1, #rd > 0 and table.concat(rd, " ") or "none"))
  recs[#recs + 1] = rec
  rec = nil
  return true
end

local function holds(n, o, what)
  H.assertEq(n.rev & o.weak, o.weak, what .. ": every weak element revealed")
  H.assertEq(n.rcls & o.cls, o.cls, what .. ": every weak class revealed")
end
local function checkPrice(r, boost)
  H.assertEq(r.pend, boost, string.format("the cast ran at the %d BP planned", boost))
  local want = H.battleSpellPrice(seat, SCAN, boost)
  if boost == 0 then H.assertEq(want, SCAN_MP, "Scan's unboosted price is MagicProp's 3 MP") end
  H.assertEq(r.mp0 - r.mp1, want, string.format("Scan cost its %d MP at %d BP", want, boost))
  local regen = (boost == 0 and r.bank0 < 5) and 1 or 0
  H.assertEq(r.bank1, r.bank0 - boost + regen, string.format("the bank paid the %d boost point(s)%s", boost,
    regen == 1 and " and earned the unboosted turn's pip" or ""))
end
local function readHolds(r, s, what)
  local rd, o = r.read[s], r.b0[s]
  H.assertEq(rd ~= nil, true, what .. ": Ot6AnalyzeOne read it")
  H.assertEq(rd.elem & o.weak, o.weak, what .. ": the reveal it wrote holds its weak elements")
  H.assertEq(rd.cls & o.cls, o.cls, what .. ": the reveal it wrote holds its weak classes")
end
local function checkOne(r, t)
  checkPrice(r, 0)
  readHolds(r, t, string.format("unboosted, the target (slot %d)", t))
  for s = 0, 5 do
    if s ~= t then
      H.assertEq(r.read[s] == nil, true, string.format("unboosted: slot %d (not the target) was not read", s))
    end
  end
  local tsp = r.b0[t].sp
  for s = 0, 5 do
    local o, n = r.b0[s], r.b1[s]
    if o.present and o.sp == tsp then
      holds(n, o, string.format("unboosted, slot %d (species $%03X, the target's)", s, tsp))
    elseif o.present then
      H.assertEq(n.rev, o.rev, string.format("unboosted: slot %d (another species) revealed elements did not move", s))
      H.assertEq(n.rcls, o.rcls, string.format("unboosted: slot %d (another species) revealed classes did not move", s))
    end
  end
  local o = r.b0[t]
  H.assertEq(codexElem(tsp) & o.weak, o.weak, string.format("the codex holds species $%03X's weak elements", tsp))
  H.assertEq(codexCls(tsp) & o.cls, o.cls, string.format("the codex holds species $%03X's weak classes", tsp))
end
local function checkAll(r)
  checkPrice(r, 1)
  local n = 0
  for s = 0, 5 do
    local o = r.b0[s]
    if o.present and o.scan then
      n = n + 1
      local what = string.format("at 1 BP, slot %d (species $%03X)", s, o.sp)
      readHolds(r, s, what)
      holds(r.b1[s], o, what)
    end
  end
  H.assertEq(n >= 2, true, "the 1 BP cast met two or more scannable bodies (the precondition held at the cast)")
end

-- the cast to play next: 1 = unboosted on a live body (an unread one when
-- the field has one), 2 = 1 BP with two or more scannable bodies present
local stage, plan, target, battles, mode = 1, {}, nil, 0, nil
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local function stragoCasts()
  local e = seat * 2
  return H.readWord(0x3BF4 + e) > 0 and (H.readByte(0x3EE4 + e) & 0xE2) == 0
    and (H.readByte(0x3EE5 + e) & 0xB8) == 0 and H.readWord(0x3C08 + e) >= SCAN_MP
end
local function decide()
  battles = battles + 1
  H.assertEq(battles <= 12, true, "the two counted casts within 12 battles")
  seat, plan, target, mode, rec = nil, {}, nil, "cast", nil
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == STRAGO then seat = s end end
  H.assertEq(seat ~= nil, true, "STRAGO is seated")
  -- 0: the grant, read off his live battle Magic list (record 0 the stone,
  -- 1..54 the magic grid; +0 the spell id, +1 bit 7 greyed)
  local base, cell = H.readWord(0x302C + seat * 2), nil
  for c = 0, 53 do
    local a = base + (c + 1) * 4
    if H.readByte(a) == SCAN and (H.readByte(a + 1) & 0x80) == 0 then cell = c end
  end
  H.assertEq(cell ~= nil, true, "STRAGO's battle Magic list holds Scan, castable (the grant)")
  local b = bodies()
  local ids = {}
  for s = 0, 5 do
    if b[s].present then
      ids[#ids + 1] = string.format("%d:$%03X weak $%02X/$%02X rev $%02X/$%02X%s", s, b[s].sp, b[s].weak, b[s].cls,
        b[s].rev, b[s].rcls, b[s].scan and "" or " noscan")
    end
  end
  H.log(string.format("[analyze] battle %d, stage %d: STRAGO seat %d (Scan at cell %d); %s", battles, stage, seat,
    cell, table.concat(ids, "; ")))
  if not stragoCasts() then
    mode = "fightout"
    H.log("[analyze] STRAGO cannot cast here: fought out, the next battle taken")
    return
  end
  local scan = 0
  for s = 0, 5 do if b[s].present and b[s].scan then scan = scan + 1 end end
  for s = 0, 5 do
    if target == nil and live(s) and b[s].scan and unread(b[s]) then target = s end
  end
  for s = 0, 5 do
    if target == nil and live(s) and b[s].scan then target = s end
  end
  if stage == 2 and scan < 2 then target = nil end
  if target == nil then
    mode = "fightout"
    H.log(string.format("[analyze] no body for stage %d here: fought out, the next battle taken", stage))
    return
  end
  plan = { { who = STRAGO, cmd = CMD_MAGIC, spell = SCAN, boost = stage - 1, slot = target } }
end

-- ---- the walk to an encounter (battle_lifefold's lap) -------------------------
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

H.run({ maxFrames = 600000 }, {
  -- the cold Continue (battle_lifefold's): title, Continue, the world map
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
    H.assertEq((H.readByte(0x1850 + STRAGO) & 7) ~= 0, true, "STRAGO is in the party")
    H.assertEq(H.readByte(0x1A6E + STRAGO * 54 + SCAN) ~= 0xFF, true,
      "STRAGO has not learned Scan himself: what makes it castable is the grant")
    arm()
  end),
  H.waitUntil(function() return H.worldSettled() end, 1200, "world settled", 5),
  H.call(function()
    local x, y = H.worldX(), H.worldY()
    home = { x, y }
    for dx = -8, 8, 2 do
      for dy = -8, 8, 2 do
        local p = H.worldBfs(x + dx, y + dy)
        if not away and p and #p >= 6 and #p <= 12 then away = { x + dx, y + dy } end
      end
    end
    assert(away, "a tile 6-12 steps from the Continue tile, on the settled map")
  end),
  H.driveUntil(function() return stage > 2 end, 550000, {
    H.cond(function() return not H.battleLoadStarted() end, { lap(), H.release() }, {}),
    H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5),
    H.call(decide),
    H.cond(function() return mode == "fightout" end, { H.kitBattle({}, {}) }, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000, planDone = close }),
      H.call(function()
        local r = recs[#recs]
        if r == nil or r.done then
          H.log("[analyze] the battle ended before the cast resolved: not counted")
          return
        end
        r.done = true
        if stage == 1 then checkOne(r, target) else checkAll(r) end
        H.log(string.format("[analyze] stage %d passed", stage))
        stage = stage + 1
      end),
      H.cond(function() return H.battleLoadStarted() end, { H.kitBattle({}, {}) }, {}),
    }),
  }, "the two counted casts"),
  H.call(function()
    H.log("[analyze] PASS: STRAGO's Magic list holds Scan; unboosted it read its target's species, at 1 BP every "
      .. "enemy; 3 MP and the boost ladder; the codex learned them")
  end),
})
