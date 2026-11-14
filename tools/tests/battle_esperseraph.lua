-- @suite
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_esperseraph.lua -- Sraphim's two rungs that are new code (#328, the owner's call of 2026-11-14:
-- docs/design/esper-rework.md "Sraphim, the healer's stone"; ot6_esper.asm Ot6SeraphHeal): at rung 3 the member's
-- healing is 25% stronger, and at rung 5 anyone the member revives comes back at full HP.
--
-- Boots fire-out-v1 by cold Continue (configure.py TEST_ENV).  By hand:
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/fire-out-v1 \
--     tools/tests/run.sh tools/tests/battle_esperseraph.lua <log>
--
-- TERRA is the healer: she knows Cure and Life (kits.md: Life at 18), and the bag holds Potions and Fenix Downs.
-- The walk and the two snapshots are battle_lifefold's: a random encounter, everyone Defends until TERRA has
-- three pips banked with LOCKE standing below his max HP (STRAGO Fights him if the draw left him full), and that
-- command window is T; then from T TERRA's Fire and STRAGO's Fight knock LOCKE out through the real target cursor
-- and the window where TERRA has three pips again is K.  Each case restores T or K, stages TERRA's Sraphim count
-- (or not), and has TERRA take one action on LOCKE through the real menus while everyone else Defends:
--   cure-0 / cure-75      Cure, unboosted
--   cure2-0 / cure2-75    Cure at one boost point: Cure 2 (the boost bought the tier)
--   item-0 / item-75      a Potion from Item (a Tonic when the bag has no Potion)
--   life-0 / life-75 / life-500   Life on the KO'd LOCKE
--   fenix-0 / fenix-500   a Fenix Down on the KO'd LOCKE
-- The staging (declared in state_write_waivers.txt, a mechanism expedient: Sraphim is a World of Ruin stone and a
-- rung takes 75 or 500 Magic Points in it) is TERRA's Sraphim count on the live esper page ($317C00), written after
-- the snapshot is restored, so a pair of cases is the same draw: the same RNG, the same variance roll.
-- Measured: the amount the action heals LOCKE (every write to his damage-healed cell, $33E4 + seat * 2, between
-- TERRA's confirm and the end of her action), his HP at the end of her action, and the spell cast ($3410).
--   rung 3:   cure-75 = cure-0 + cure-0 / 4 (rounded down), and the same for cure2 and item;
--             life-75's revival heals life-0's + a quarter, and LOCKE stands at that HP;
--   rung 5:   life-500 and fenix-500 raise LOCKE at his max HP; life-0 and fenix-0 raise him below it (Life and a
--             Fenix Down give an eighth), the vanilla amount.
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F
local ST_CMD, ST_DEF, ST_TGT, ST_MAGIC, ST_TRANS, ST_ITEM = 0x05, 0x27, 0x38, 0x0E, 0x01, 0x0A
local BANK, PEND, CURMP, MLISTPTR = 0x3E9C, 0x3E9D, 0x3C08, 0x302C
local MSCROLL, MCOL, MROW = 0x8913, 0x8917, 0x891B
local ITEMSCR, ITEMROW, BATTINV = 0x8947, 0x894F, 0x2686
local STATUS1, STATUS4 = 0x3EE4, 0x3EF9
local KO = 0x80
local CMD_FIGHT, CMD_ITEM, CMD_MAGIC = 0x00, 0x01, 0x02
local TERRA, LOCKE, STRAGO = 0, 1, 7
local FIRE, CURE, CURE2, LIFE = 0x00, 0x2D, 0x2E, 0x30
local TONIC, POTION, FENIX = 0xE8, 0xE9, 0xF0
local LIVE, SRAPHIM = 0x317C00, 20                  -- the live esper page; Sraphim's counter slot

local function pend(s) return H.readByte(PEND + s * 2) end
local function bank(s) return H.readByte(BANK + s * 2) end
local function mp(s) return H.readWord(CURMP + s * 2) end
local function hp(s) return H.readWord(0x3BF4 + s * 2) end
local function hpMax(s) return H.readWord(0x3C1C + s * 2) end
local function ko(s) return (H.readByte(STATUS1 + s * 2) & KO) ~= 0 end
local function sramW(a) return emu.read(a, emu.memType.snesMemory) | (emu.read(a + 1, emu.memType.snesMemory) << 8) end
local function stage(n)
  local a = LIVE + 0x10 + (TERRA * 26 + SRAPHIM) * 2
  emu.write(a, n & 0xFF, emu.memType.snesMemory)
  emu.write(a + 1, n >> 8, emu.memType.snesMemory)
end
local function cmdRow(s, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + s * 12 + r * 3) == cmd then return r end
  end
end
local function spellCell(s, id)
  local b = H.readWord(MLISTPTR + s * 2)
  for cell = 0, 53 do
    local a = b + (cell + 1) * 4
    if H.readByte(a) == id and (H.readByte(a + 1) & 0x80) == 0 then return cell end
  end
end
local function invIdx(id)
  for i = 0, 251 do if H.readByte(BATTINV + i * 5) == id and H.readByte(BATTINV + i * 5 + 3) > 0 then return i end end
end

-- ---- observers ---------------------------------------------------------------
local terraS, lockeS, stragoS
local armed = nil
local installed = false
local function installObservers()
  if installed then return end
  installed = true
  local function cx() return emu.getState()["cpu.x"] & 0xFF end
  emu.addMemoryCallback(function(_, v)
    if armed and armed.sent and not armed.endF then armed.casts[#armed.casts + 1] = v end
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
  -- LOCKE's damage-healed cell: the word is whole once its high byte is written.  The amount is the first write
  -- below $8000: the display then marks it ($8000 set, _c262ef) and clears it ($FFFF)
  emu.addMemoryCallback(function(addr)
    if armed and armed.sent and not armed.endF and lockeS and (addr & 0xFFFF) == 0x33E5 + lockeS * 2 then
      local w = H.readWord(0x33E4 + lockeS * 2)
      if w ~= 0xFFFF then armed.heals[#armed.heals + 1] = w end
    end
  end, emu.callbackType.write, 0x7E33E4, 0x7E33F7)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if armed and armed.sent and not armed.endF and cx() == terraS * 2 then
      armed.endF, armed.hpEnd, armed.hpMax, armed.koEnd = H.frame, hp(lockeS), hpMax(lockeS), ko(lockeS)
    end
  end, emu.callbackType.exec, ae, ae)
end

-- ---- the walk to an encounter (battle_lifefold's) ------------------------------
local home, away
local function lap()
  local goal, plan, idx
  return H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
    H.call(function()
      if not H.worldHasControl() or not H.worldSettled() then plan = nil; H.setPad({}) return end
      if not H.worldAligned() then return end
      local x, y = H.worldX(), H.worldY()
      goal = goal or away
      if plan == nil or idx > #plan then
        if x == goal[1] and y == goal[2] then goal = (goal == away) and home or away end
        plan, idx = H.worldBfs(goal[1], goal[2]), 1
        if not plan or #plan == 0 then plan = nil; H.setPad({}) return end
      end
      local dir = plan[idx]; idx = idx + 1
      H.setPad({ [dir] = true })
    end),
  }, "a random encounter")
end

-- ---- the menu policy (one call per frame) ------------------------------------
local tc = H.targetCursor({ mask = 0x7B7D, dirs = { "down", "up", "left", "right" } })
local mf, tapNo, tapAt, inList = 0, -1, 0, 0
local function defend(st, edge)
  if not edge then return nil end
  if st == ST_CMD then return "right" end
  if st == ST_DEF then return "a" end
  if st == ST_TGT then return "b" end
  return nil
end
local function steerTarget(target, onConfirm)
  local btn = tc.steer(target, mf)
  local edge = (mf - 1) % 8 < 4
  if btn == "a" then
    if edge then onConfirm() else btn = nil end
  else
    if btn ~= nil and tc.press ~= tapNo then tapNo, tapAt = tc.press, mf end
    btn = (tapNo >= 0 and mf - tapAt < 4) and tc.dir or nil
  end
  return btn
end
local function walkGrid(a, cell)
  local wr, wc = cell // 2, cell % 2
  local ar = H.readByte(MSCROLL + a) + H.readByte(MROW + a)
  local col = H.readByte(MCOL + a)
  if ar < wr then return "down" elseif ar > wr then return "up"
  elseif col < wc then return "right" elseif col > wc then return "left" end
  return "a"
end

-- c == nil: everyone Defends (banking).  Otherwise TERRA takes c's action on LOCKE; everyone else Defends.
local function pulse(c)
  tc.observe()
  if H.readByte(MENU) == 0 then H.setPad({}); return end
  mf = mf + 1
  local edge = (mf - 1) % 8 < 4
  local a, st = H.readByte(ACTOR) & 3, H.readByte(MSTATE)
  if st ~= ST_TGT then tapNo = -1 end
  if st ~= ST_MAGIC and st ~= ST_ITEM then inList = 0 end
  local btn
  if st == ST_TRANS then
    btn = nil
  elseif c == nil or a ~= terraS or c.sent then
    btn = defend(st, edge)
  elseif st == ST_CMD then
    if pend(terraS) < c.boost then btn = "r"
    elseif pend(terraS) > c.boost then btn = "l"
    else
      local want, cur = cmdRow(terraS, c.cmd), H.readByte(CMDROW + terraS) & 3
      btn = (cur == want) and "a" or ((cur < want) and "down" or "up")
    end
    if not edge then btn = nil end
  elseif st == ST_MAGIC and c.cmd == CMD_MAGIC then
    inList = inList + 1
    if pend(terraS) ~= c.boost then btn = edge and "b" or nil
    elseif inList >= 20 then
      local cell = spellCell(terraS, c.spell)
      assert(cell, string.format("TERRA's list holds spell $%02X", c.spell))
      btn = edge and walkGrid(terraS, cell) or nil
    end
  elseif st == ST_ITEM and c.cmd == CMD_ITEM then
    inList = inList + 1
    if inList >= 20 then
      local want = invIdx(c.item)
      assert(want, string.format("the bag holds item $%02X", c.item))
      local cur = H.readByte(ITEMSCR + terraS) + H.readByte(ITEMROW + terraS)
      btn = (cur < want) and "down" or ((cur > want) and "up" or "a")
      if not edge then btn = nil end
    end
  elseif st == ST_TGT then
    btn = steerTarget(lockeS, function()
      c.hp0, c.pendAtConfirm, c.mp0 = hp(lockeS), pend(terraS), mp(terraS)
      c.sent = true
    end)
  else
    btn = edge and "b" or nil
  end
  H.setPad(btn and { [btn] = true } or {})
end

-- The knockout (battle_lifefold's): TERRA casts Fire at two points on LOCKE when she has the pips and Fights him
-- when she does not, STRAGO Fights him, LOCKE passes (X).  hurt == true: STRAGO Fights a LOCKE at full HP and the
-- rest Defend.
local function killPulse(hurt)
  tc.observe()
  if H.readByte(MENU) == 0 then H.setPad({}); return end
  mf = mf + 1
  local edge = (mf - 1) % 8 < 4
  local a, st = H.readByte(ACTOR) & 3, H.readByte(MSTATE)
  if st ~= ST_TGT then tapNo = -1 end
  if st ~= ST_MAGIC then inList = 0 end
  local p
  if hurt then
    if a == stragoS and not ko(lockeS) and hp(lockeS) >= hpMax(lockeS) then p = { cmd = CMD_FIGHT, boost = 0 } end
  elseif a == terraS then
    p = (bank(terraS) >= 2) and { cmd = CMD_MAGIC, spell = FIRE, boost = 2 } or { cmd = CMD_FIGHT, boost = 0 }
  elseif a == stragoS then
    p = { cmd = CMD_FIGHT, boost = 0 }
  end
  local btn
  if st == ST_TRANS then btn = nil
  elseif p == nil and hurt then btn = defend(st, edge)
  elseif p == nil then btn = edge and ((st == ST_CMD) and "x" or "b") or nil
  elseif st == ST_CMD then
    if pend(a) < p.boost then btn = "r"
    elseif pend(a) > p.boost then btn = "l"
    else
      local want, cur = cmdRow(a, p.cmd), H.readByte(CMDROW + a) & 3
      btn = (cur == want) and "a" or ((cur < want) and "down" or "up")
    end
    if not edge then btn = nil end
  elseif st == ST_MAGIC then
    inList = inList + 1
    if inList >= 20 then
      local cell = spellCell(a, p.spell)
      assert(cell, "TERRA's list holds Fire")
      btn = walkGrid(a, cell)
    end
    if not edge then btn = nil end
  elseif st == ST_TGT then
    btn = steerTarget(lockeS, function() end)
  else btn = edge and "b" or nil end
  H.setPad(btn and { [btn] = true } or {})
end

-- ---- the run -------------------------------------------------------------------
local snap, snapK = nil, nil
local healItem, healName
local CASES = {
  { name = "cure-0", cmd = CMD_MAGIC, spell = CURE, cast = CURE, boost = 0, stage = 0 },
  { name = "cure-75", cmd = CMD_MAGIC, spell = CURE, cast = CURE, boost = 0, stage = 75 },
  { name = "cure2-0", cmd = CMD_MAGIC, spell = CURE, cast = CURE2, boost = 1, stage = 0 },
  { name = "cure2-75", cmd = CMD_MAGIC, spell = CURE, cast = CURE2, boost = 1, stage = 75 },
  { name = "item-0", cmd = CMD_ITEM, boost = 0, stage = 0 },
  { name = "item-75", cmd = CMD_ITEM, boost = 0, stage = 75 },
  { name = "life-0", cmd = CMD_MAGIC, spell = LIFE, cast = LIFE, boost = 0, stage = 0, ko = true },
  { name = "life-75", cmd = CMD_MAGIC, spell = LIFE, cast = LIFE, boost = 0, stage = 75, ko = true },
  { name = "life-500", cmd = CMD_MAGIC, spell = LIFE, cast = LIFE, boost = 0, stage = 500, ko = true },
  { name = "fenix-0", cmd = CMD_ITEM, item = FENIX, boost = 0, stage = 0, ko = true },
  { name = "fenix-500", cmd = CMD_ITEM, item = FENIX, boost = 0, stage = 500, ko = true },
}

local steps = {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function()
    local ph = 0
    return H.driveUntil(function()
      return H.worldMode() and (emu.getState()["ppu.screenBrightness"] or 0) >= 15 and H.worldHasControl()
    end, 6000, {
      H.call(function()
        ph = (ph + 1) % 48
        if (emu.getState()["ppu.screenBrightness"] or 0) < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "cold Continue -> world map control")
  end)(),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("fire-out-v1")
    H.assertEq((H.readByte(0x1850 + TERRA) & 7) ~= 0, true, "TERRA is in the party")
    H.assertEq((H.readByte(0x1850 + LOCKE) & 7) ~= 0, true, "LOCKE is in the party")
    H.log(string.format("[seraph] the live esper page's signature $%04X; TERRA's Sraphim count %d",
      sramW(LIVE), sramW(LIVE + 0x10 + (TERRA * 26 + SRAPHIM) * 2)))
    installObservers()
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
  lap(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5),
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id == TERRA then terraS = s end
      if id == LOCKE then lockeS = s end
      if id == STRAGO then stragoS = s end
    end
    assert(terraS and lockeS and stragoS, "TERRA, LOCKE and STRAGO are in the battle")
    assert(spellCell(terraS, CURE), "TERRA knows Cure")
    assert(spellCell(terraS, LIFE), "TERRA knows Life (kits.md: level 18)")
    assert(cmdRow(terraS, CMD_ITEM), "TERRA's command list has Item")
    healItem = invIdx(POTION) and POTION or (invIdx(TONIC) and TONIC or nil)
    assert(healItem, "the bag holds a Potion or a Tonic")
    healName = healItem == POTION and "Potion" or "Tonic"
    assert(invIdx(FENIX), "the bag holds a Fenix Down")
    for _, c in ipairs(CASES) do if c.cmd == CMD_ITEM and c.item == nil then c.item = healItem end end
    H.log(string.format("[seraph] TERRA slot %d (%d MP), LOCKE slot %d (%d/%d), STRAGO slot %d; the item case "
      .. "uses a %s", terraS, mp(terraS), lockeS, hp(lockeS), hpMax(lockeS), stragoS, healName))
  end),
  (function()
    local hurtSeen = false
    return H.driveUntil(function() return snap ~= nil end, 40000, {
      H.call(function()
        local full = not ko(lockeS) and hp(lockeS) >= hpMax(lockeS)
        if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD and (H.readByte(ACTOR) & 3) == terraS
           and bank(terraS) >= 3 and pend(terraS) == 0 and not ko(lockeS) and not full then
          H.setPad({})
          snap = H.requestSaveState()
          H.log(string.format("[seraph] snapshot T f%d: TERRA bank %d MP %d; LOCKE HP %d/%d", H.frame,
            bank(terraS), mp(terraS), hp(lockeS), hpMax(lockeS)))
          return
        end
        if full and bank(terraS) >= 3 and not hurtSeen then
          hurtSeen = true
          H.log(string.format("[seraph] f%d: LOCKE is at full HP; STRAGO Fights him", H.frame))
        end
        if hurtSeen then killPulse(true) else pulse(nil) end
      end),
    }, "TERRA's command window with 3 pips banked, LOCKE standing below max HP")
  end)(),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap, "snapshot T") end),
}

local function knockout()
  local req
  return {
    H.call(function() H.setPad({}); req = H.requestLoadState(snap.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load")
      H.rearmInputInjection()
      mf, tapNo, tapAt, inList = 0, -1, 0, 0
    end),
    H.driveUntil(function() return ko(lockeS) end, 40000, { H.call(killPulse) },
      "LOCKE knocked out by his own party"),
    H.driveUntil(function() return snapK ~= nil end, 40000, {
      H.call(function()
        if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD and (H.readByte(ACTOR) & 3) == terraS
           and bank(terraS) >= 3 and pend(terraS) == 0 then
          H.setPad({})
          snapK = H.requestSaveState()
          H.log(string.format("[seraph] snapshot K f%d: TERRA bank %d MP %d; LOCKE HP %d/%d status1 $%02X",
            H.frame, bank(terraS), mp(terraS), hp(lockeS), hpMax(lockeS), H.readByte(STATUS1 + lockeS * 2)))
          return
        end
        pulse(nil)
      end),
    }, "TERRA's command window with 3 pips, LOCKE down"),
    H.waitFrames(2),
    H.call(function() H.checkReq(snapK, "snapshot K") end),
  }
end

local knocked = false
for _, c in ipairs(CASES) do
  local req
  if c.ko and not knocked then
    knocked = true
    for _, st in ipairs(knockout()) do steps[#steps + 1] = st end
  end
  steps[#steps + 1] = H.call(function()
    H.setPad({}); req = H.requestLoadState((c.ko and snapK or snap).blob)
  end)
  steps[#steps + 1] = H.waitFrames(2)
  steps[#steps + 1] = H.call(function()
    H.checkReq(req, "snapshot load")
    H.rearmInputInjection()
    mf, tapNo, tapAt, inList = 0, -1, 0, 0
    if c.stage > 0 then stage(c.stage) end
    c.count = sramW(LIVE + 0x10 + (TERRA * 26 + SRAPHIM) * 2)
    H.assertEq(c.count, c.stage, c.name .. ": TERRA's Sraphim count")
    H.assertEq(ko(lockeS), c.ko == true, c.name .. (c.ko and ": LOCKE is KO'd" or ": LOCKE is alive"))
    H.assertEq(mp(terraS) >= 40, true, c.name .. ": TERRA's MP pays the cast")
    c.casts, c.heals = {}, {}
    armed = c
  end)
  steps[#steps + 1] = H.driveUntil(function() return c.endF ~= nil and H.frame >= c.endF + 60 end,
    15000, { H.call(function() pulse(c) end) }, "case " .. c.name .. " resolves")
  steps[#steps + 1] = H.call(function()
    armed = nil
    H.setPad({})
    local cs, hs = {}, {}
    for _, v in ipairs(c.casts) do cs[#cs + 1] = string.format("$%02X", v) end
    for _, v in ipairs(c.heals) do hs[#hs + 1] = tostring(v) end
    for _, v in ipairs(c.heals) do if c.amt == nil and v < 0x8000 then c.amt = v end end
    H.log(string.format("[seraph] %s: Sraphim count %d, boost %d (pending %d at the confirm); cast %s; "
      .. "LOCKE healed %s; LOCKE HP %d at the confirm, %d/%d at TERRA's action end (%s)", c.name, c.count,
      c.boost, c.pendAtConfirm or -1, table.concat(cs, " "), table.concat(hs, ","), c.hp0 or -1, c.hpEnd,
      c.hpMax, c.koEnd and "KO'd" or "standing"))
  end)
end

steps[#steps + 1] = H.call(function()
  local by, bad = {}, {}
  for _, c in ipairs(CASES) do by[c.name] = c end
  local function check(ok, what) if not ok then bad[#bad + 1] = what end end
  local function quarter(a) return a + a // 4 end
  for _, c in ipairs(CASES) do
    check(c.amt ~= nil, string.format("%s: TERRA's action healed LOCKE", c.name))
    check(c.pendAtConfirm == c.boost, string.format("%s: %d boost pending at the confirm", c.name, c.boost))
    if c.cast then
      local ok = false
      for _, v in ipairs(c.casts) do if v == c.cast then ok = true end end
      check(ok, string.format("%s: TERRA cast $%02X", c.name, c.cast))
    end
  end
  -- rung 3: the same draw heals a quarter more
  for _, p in ipairs({ { "cure-0", "cure-75" }, { "cure2-0", "cure2-75" }, { "item-0", "item-75" },
                       { "life-0", "life-75" } }) do
    local a, b = by[p[1]], by[p[2]]
    if a.amt and b.amt then
      check(a.amt > 0 and b.amt == quarter(a.amt), string.format("%s heals %d, %s's %d plus a quarter (%d)",
        b.name, b.amt, a.name, a.amt, quarter(a.amt)))
    end
  end
  -- the revivals: vanilla's eighth without the signature, full with it
  for _, c in ipairs({ by["life-0"], by["life-75"], by["fenix-0"] }) do
    check(not c.koEnd and c.hpEnd == c.amt and c.hpEnd < c.hpMax, string.format("%s: LOCKE revived at the "
      .. "amount healed, below his max (%d/%d, healed %s)", c.name, c.hpEnd, c.hpMax, tostring(c.amt)))
  end
  for _, c in ipairs({ by["life-500"], by["fenix-500"] }) do
    check(not c.koEnd and c.hpEnd == c.hpMax, string.format("%s: LOCKE revived at full HP (%d/%d)", c.name,
      c.hpEnd, c.hpMax))
  end
  check(by["fenix-0"].amt == by["life-0"].amt, string.format("a Fenix Down revives as Life does (%s, %s)",
    tostring(by["fenix-0"].amt), tostring(by["life-0"].amt)))
  for _, c in ipairs(CASES) do
    H.log(string.format("[seraph] VERDICT %s: healed %s, LOCKE %d/%d %s", c.name, tostring(c.amt), c.hpEnd,
      c.hpMax, c.koEnd and "KO'd" or "standing"))
  end
  for _, b in ipairs(bad) do H.log("[seraph] FAIL " .. b) end
  assert(#bad == 0, "Sraphim's rungs: " .. table.concat(bad, "; "))
  H.log("[seraph] PASS: Sraphim's rung 3 heals a quarter more on the same draw, and its signature revives at full HP")
end)

H.run({ maxFrames = 400000 }, steps)
