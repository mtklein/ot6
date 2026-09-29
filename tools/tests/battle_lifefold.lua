-- @suite
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_lifefold.lua -- Life boosts to Life 2 and then Life 3 (#327).
--
-- Boots fire-out-v1 by cold Continue (configure.py TEST_ENV).  By hand:
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/fire-out-v1 \
--     tools/tests/run.sh tools/tests/battle_lifefold.lua <log>
--
-- The owner's call (2026-09-29): Phoenix grants Life, which boosts to Life 2
-- and then Life 3, so Ot6FoldTbl's life row is [Life, Life 2, Life 3] and
-- Life 3 is a tier nothing grants.  This measures the third tier on every
-- surface the fold drives, in a real battle through the real menus, at
-- boost 0, 1, 2 and 3 (a 3-point boost buys two tiers, Ot6FoldSteps):
--   the name    the Life row of the Magic list, read off the BG tilemap
--               with the boost pending (Ot6PreviewList_ext): "Life",
--               "Life 2", "Life 3", "Life 3";
--   the stamp   the Life row's cost byte in TERRA's list (entry+3), the one
--               cell the drawn number, the grey, the confirm and the charge
--               read (Ot6FoldPrices; battle_fold measures that chain);
--   the cast    the spell id the action executes ($3410): Life, Life 2,
--               Life 3, Life 3;
--   the charge  the cost queued for TERRA's action ($3620-$371f) and what
--               her pool loses: the cast tier's own MagicProp price, and a
--               boost never makes Life cheaper (b2 >= b1 >= b0);
--   the effect  the target gains the Life 3 status (status 4 bit $04,
--               MagicProp $35 +$0d) exactly when Life 3 is cast.
-- The b cases target LOCKE alive: Life and Life 2 are revivals that only
-- hit a KO'd body (MagicProp +$02 bit $04), so on him they land nothing, and
-- Life 3 marks a living body to rise once.  Those two misses are the
-- effect's negative control.
--
-- The ko cases target LOCKE KO'd.  The owner's call (2026-09-29): Life 3
-- on a KO'd body revives it at full HP, as Life 2 does, AND grants the
-- Life 3 status (Ot6RezTargeting, Ot6Life3Revive).  ko-b1 (Life 2: full
-- HP, no status) is the control that tells the two apart.
--
-- No state is written.  fire-out-v1 has TERRA (Life at 18, kits.md) with a
-- 204-MP pool, LOCKE and STRAGO by Thamasa.  The run walks to an encounter,
-- Defends until TERRA has 3 pips banked, snapshots her command window (T),
-- and restores T for each b case: TERRA presses R to the case's boost,
-- opens Magic, casts Life on LOCKE; everyone else Defends.  Then, from T,
-- TERRA's two-point Fire and STRAGO's Fight knock LOCKE out (the party's
-- own hands, through the real target cursor; LOCKE passes his turns), the
-- two Defend until TERRA has 3 pips again, and that window (K) is restored
-- for each ko case.
--
-- Red on a ROM whose life row stops at Life 2 (the name and the cast at
-- boost 2 and 3 are Life 2), on one that keeps Life 3's vanilla 50 MP
-- (boost 2 charged less than boost 1), and on one without the revival
-- (ko-b2 leaves LOCKE at 0 HP, KO'd); build/attempts/wt/wor-espers/.

local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F
local ST_CMD, ST_DEF, ST_TGT, ST_MAGIC, ST_TRANS = 0x05, 0x27, 0x38, 0x0E, 0x01
local BANK, PEND, CURMP, MLISTPTR = 0x3E9C, 0x3E9D, 0x3C08, 0x302C
local MSCROLL, MCOL, MROW = 0x8913, 0x8917, 0x891B
local STATUS1, STATUS4 = 0x3EE4, 0x3EF9
local KO, LIFE3_STATUS = 0x80, 0x04
local CMD_MAGIC = 0x02
local TERRA, LOCKE = 0, 1
local LIFE, LIFE2, LIFE3 = 0x30, 0x31, 0x35
local MAGIC_REC, MAGIC_MP = 14, 5
-- "Life" as the list prints it (FF3-US glyphs: A = $80, a = $9a, 0 = $b4)
local NAME = { 0x8B, 0xA2, 0x9F, 0x9E }
local DIGIT0 = 0xB4

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function pend(s) return H.readByte(PEND + s * 2) end
local function bank(s) return H.readByte(BANK + s * 2) end
local function mp(s) return H.readWord(CURMP + s * 2) end
local function listBase(s) return H.readWord(MLISTPTR + s * 2) end
local function cmdRow(s, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + s * 12 + r * 3) == cmd then return r end
  end
end
-- magic grid cell (0..53) of a spell id in slot s's list, and its stamp
local function spellCell(s, id)
  local b = listBase(s)
  for cell = 0, 53 do
    local a = b + (cell + 1) * 4
    if H.readByte(a) == id and (H.readByte(a + 1) & 0x80) == 0 then
      return cell, H.readByte(a + 3)
    end
  end
end
local function mapWord(w) return emu.readWord(w * 2, emu.memType.snesVideoRam) end
-- every "Life" on the BG tilemap, with the glyphs of the two cells after it
local function lifeNames()
  local out = {}
  for w = 0x5800, 0x7FF0 do
    local hit = true
    for i = 1, #NAME do
      if (mapWord(w + i - 1) & 0xFF) ~= NAME[i] then hit = false break end
    end
    if hit then
      local digit = nil
      for i = #NAME, #NAME + 1 do
        local g = mapWord(w + i) & 0xFF
        if g >= DIGIT0 and g <= DIGIT0 + 9 then digit = g - DIGIT0 end
      end
      out[#out + 1] = { at = w, digit = digit }
    end
  end
  return out
end
local function romPrice(id)
  return H.readRomByte((H.sym("MagicProp") & 0x3FFFFF) + id * MAGIC_REC + MAGIC_MP)
end

-- ---- observers ---------------------------------------------------------------
local terraS, lockeS
local armed = nil
local installed = false
local function installObservers()
  if installed then return end
  installed = true
  local function cx() return emu.getState()["cpu.x"] & 0xFF end
  emu.addMemoryCallback(function(_, v)
    if armed and not armed.endF then armed.casts[#armed.casts + 1] = v end
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
  emu.addMemoryCallback(function(_, v)
    if armed and not armed.endF and cx() == terraS * 2 then
      armed.queued[#armed.queued + 1] = v
    end
  end, emu.callbackType.write, 0x7E3620, 0x7E371F)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if armed and armed.sent and not armed.endF and cx() == terraS * 2 then
      armed.endF, armed.mpEnd = H.frame, mp(terraS)
      armed.hpEnd = H.readWord(0x3BF4 + lockeS * 2)
      armed.hpMax = H.readWord(0x3C1C + lockeS * 2)
      armed.koEnd = (H.readByte(STATUS1 + lockeS * 2) & KO) ~= 0
      armed.statusEnd = H.readByte(STATUS4 + lockeS * 2)
    end
  end, emu.callbackType.exec, ae, ae)
end

-- ---- the walk to an encounter ------------------------------------------------
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
local mf, tapNo, tapAt, inMagic = 0, -1, 0, 0
local function defend(st, edge)
  if not edge then return nil end
  if st == ST_CMD then return "right" end
  if st == ST_DEF then return "a" end
  if st == ST_TGT then return "b" end
  return nil
end

-- c == nil: bank pips (everyone Defends).  Otherwise TERRA casts Life on
-- LOCKE at c.boost.
local function pulse(c)
  tc.observe()
  if H.readByte(MENU) == 0 then H.setPad({}); return end
  mf = mf + 1
  local edge = (mf - 1) % 8 < 4
  local a, st = H.readByte(ACTOR) & 3, H.readByte(MSTATE)
  if st ~= ST_TGT then tapNo = -1 end
  if st ~= ST_MAGIC then inMagic = 0 end
  local btn
  if st == ST_TRANS then
    btn = nil
  elseif c == nil or a ~= terraS or c.sent then
    btn = defend(st, edge)
  elseif st == ST_CMD then
    if pend(terraS) < c.boost then btn = "r"
    elseif pend(terraS) > c.boost then btn = "l"
    else
      local want, cur = cmdRow(terraS, CMD_MAGIC), H.readByte(CMDROW + terraS) & 3
      btn = (cur == want) and "a" or ((cur < want) and "down" or "up")
    end
    if not edge then btn = nil end
  elseif st == ST_MAGIC then
    inMagic = inMagic + 1
    if pend(terraS) ~= c.boost then
      btn = edge and "b" or nil
    elseif inMagic < 20 then
      btn = nil                           -- let the list finish drawing
    else
      if c.names == nil then
        c.names = lifeNames()
        local cell, stamp = spellCell(terraS, LIFE)
        c.stamp, c.pendAtList = stamp, pend(terraS)
        local t = {}
        for _, n in ipairs(c.names) do
          t[#t + 1] = string.format("$%04X:%s", n.at, n.digit and ("Life " .. n.digit) or "Life")
        end
        H.log(string.format("[lifefold] %s: pending %d, Life row cell %s stamp %s; tilemap %s",
          c.name, c.pendAtList, tostring(cell), tostring(stamp), table.concat(t, " ")))
        H.screenshot("lifefold_" .. c.name)
      end
      local cell = spellCell(terraS, LIFE)
      assert(cell, "TERRA's list holds Life")
      local wr, wc = cell // 2, cell % 2
      local ar = H.readByte(MSCROLL + terraS) + H.readByte(MROW + terraS)
      local col = H.readByte(MCOL + terraS)
      if ar < wr then btn = "down"
      elseif ar > wr then btn = "up"
      elseif col < wc then btn = "right"
      elseif col > wc then btn = "left"
      else btn = "a" end
      if not edge then btn = nil end
    end
  elseif st == ST_TGT then
    btn = tc.steer(lockeS, mf)
    if btn == "a" then
      if edge then
        c.mp0, c.pendAtConfirm, c.bank0 = mp(terraS), pend(terraS), bank(terraS)
        c.status0 = H.readByte(STATUS4 + lockeS * 2)
        c.sent = true
      else btn = nil end
    else
      if btn ~= nil and tc.press ~= tapNo then tapNo, tapAt = tc.press, mf end
      btn = (tapNo >= 0 and mf - tapAt < 4) and tc.dir or nil
    end
  else
    btn = edge and "b" or nil
  end
  H.setPad(btn and { [btn] = true } or {})
end

-- The knockout: TERRA casts Fire at two points (Fire 3) on LOCKE when she
-- has the pips and Fights him when she does not, STRAGO Fights him, LOCKE
-- passes (X).  Every press goes through the real menus and target cursor.
local STRAGO, FIRE, CMD_FIGHT = 7, 0x00, 0x00
local stragoS
local function killPulse()
  tc.observe()
  if H.readByte(MENU) == 0 then H.setPad({}); return end
  mf = mf + 1
  local edge = (mf - 1) % 8 < 4
  local a, st = H.readByte(ACTOR) & 3, H.readByte(MSTATE)
  if st ~= ST_TGT then tapNo = -1 end
  if st ~= ST_MAGIC then inMagic = 0 end
  local p
  if a == terraS then
    p = (bank(terraS) >= 2) and { cmd = CMD_MAGIC, spell = FIRE, boost = 2 }
        or { cmd = CMD_FIGHT, boost = 0 }
  elseif a == stragoS then
    p = { cmd = CMD_FIGHT, boost = 0 }
  end
  local btn
  if st == ST_TRANS then btn = nil
  elseif p == nil then
    btn = edge and ((st == ST_CMD) and "x" or "b") or nil
  elseif st == ST_CMD then
    if pend(a) < p.boost then btn = "r"
    elseif pend(a) > p.boost then btn = "l"
    else
      local want, cur = cmdRow(a, p.cmd), H.readByte(CMDROW + a) & 3
      btn = (cur == want) and "a" or ((cur < want) and "down" or "up")
    end
    if not edge then btn = nil end
  elseif st == ST_MAGIC then
    inMagic = inMagic + 1
    if inMagic >= 20 then
      local cell = spellCell(a, p.spell)
      assert(cell, "TERRA's list holds Fire")
      local wr, wc = cell // 2, cell % 2
      local ar = H.readByte(MSCROLL + a) + H.readByte(MROW + a)
      local col = H.readByte(MCOL + a)
      if ar < wr then btn = "down" elseif ar > wr then btn = "up"
      elseif col < wc then btn = "right" elseif col > wc then btn = "left" else btn = "a" end
    end
    if not edge then btn = nil end
  elseif st == ST_TGT then
    btn = tc.steer(lockeS, mf)
    if btn == "a" then
      if not edge then btn = nil end
    else
      if btn ~= nil and tc.press ~= tapNo then tapNo, tapAt = tc.press, mf end
      btn = (tapNo >= 0 and mf - tapAt < 4) and tc.dir or nil
    end
  else btn = edge and "b" or nil end
  H.setPad(btn and { [btn] = true } or {})
end
local function ko(s) return (H.readByte(STATUS1 + s * 2) & KO) ~= 0 end

-- ---- the run -------------------------------------------------------------------
local snap, snapK = nil, nil
local CASES = {
  { name = "b0", boost = 0, cast = LIFE },
  { name = "b1", boost = 1, cast = LIFE2 },
  { name = "b2", boost = 2, cast = LIFE3 },
  { name = "b3", boost = 3, cast = LIFE3 },
  { name = "ko-b1", boost = 1, cast = LIFE2, ko = true },
  { name = "ko-b2", boost = 2, cast = LIFE3, ko = true },
  { name = "ko-b3", boost = 3, cast = LIFE3, ko = true },
}

local steps = {
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
    H.assertEq((H.readByte(0x1850 + TERRA) & 7) ~= 0, true, "TERRA is in the party")
    H.assertEq((H.readByte(0x1850 + LOCKE) & 7) ~= 0, true, "LOCKE is in the party")
    -- the owner's fold, read out of the built ROM
    local tbl, row = H.sym("Ot6FoldTbl") & 0x3FFFFF, nil
    for r = 0, 7 do
      if H.readRomByte(tbl + r * 3) == LIFE then row = r end
    end
    assert(row, "Ot6FoldTbl has a life row")
    local t1, t2 = H.readRomByte(tbl + row * 3 + 1), H.readRomByte(tbl + row * 3 + 2)
    H.log(string.format("[lifefold] Ot6FoldTbl life row %d: $%02X $%02X $%02X; MagicProp MP "
      .. "Life %d, Life 2 %d, Life 3 %d", row, LIFE, t1, t2, romPrice(LIFE), romPrice(LIFE2),
      romPrice(LIFE3)))
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
    local cell, stamp = spellCell(terraS, LIFE)
    H.log(string.format("[lifefold] TERRA slot %d (%d MP, %d BP), LOCKE slot %d; Life cell %s "
      .. "stamp %s", terraS, mp(terraS), bank(terraS), lockeS, tostring(cell), tostring(stamp)))
    assert(cell, "TERRA knows Life (kits.md: level 18)")
  end),
  H.driveUntil(function() return snap ~= nil end, 40000, {
    H.call(function()
      if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD
         and (H.readByte(ACTOR) & 3) == terraS and bank(terraS) >= 3 and pend(terraS) == 0 then
        H.setPad({})
        snap = H.requestSaveState()
        H.log(string.format("[lifefold] snapshot f%d: TERRA bank %d MP %d HP %d; LOCKE HP %d "
          .. "status1 $%02X status4 $%02X", H.frame, bank(terraS), mp(terraS),
          H.readWord(0x3BF4 + terraS * 2), H.readWord(0x3BF4 + lockeS * 2),
          H.readByte(STATUS1 + lockeS * 2), H.readByte(STATUS4 + lockeS * 2)))
        return
      end
      pulse(nil)
    end),
  }, "TERRA's command window with 3 pips banked"),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(snap, "snapshot")
  end),
}

local function knockout()
  local req
  return {
    H.call(function() H.setPad({}); req = H.requestLoadState(snap.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load")
      H.rearmInputInjection()
      mf, tapNo, tapAt, inMagic = 0, -1, 0, 0
    end),
    H.driveUntil(function() return ko(lockeS) end, 40000, { H.call(killPulse) },
      "LOCKE knocked out by his own party"),
    H.driveUntil(function() return snapK ~= nil end, 40000, {
      H.call(function()
        if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD
           and (H.readByte(ACTOR) & 3) == terraS and bank(terraS) >= 3 and pend(terraS) == 0 then
          H.setPad({})
          snapK = H.requestSaveState()
          H.log(string.format("[lifefold] snapshot K f%d: TERRA bank %d MP %d; LOCKE HP %d/%d "
            .. "status1 $%02X status4 $%02X", H.frame, bank(terraS), mp(terraS),
            H.readWord(0x3BF4 + lockeS * 2), H.readWord(0x3C1C + lockeS * 2),
            H.readByte(STATUS1 + lockeS * 2), H.readByte(STATUS4 + lockeS * 2)))
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
    mf, tapNo, tapAt, inMagic = 0, -1, 0, 0
    c.casts, c.queued = {}, {}
    armed = c
    c.ko0 = ko(lockeS)
    H.assertEq(c.ko0, c.ko == true, c.ko and "LOCKE is KO'd" or "LOCKE is alive")
    H.assertEq((H.readByte(STATUS4 + lockeS * 2) & LIFE3_STATUS) == 0, true,
      "LOCKE does not already carry Life 3")
    H.assertEq(mp(terraS) >= romPrice(LIFE3) and mp(terraS) >= romPrice(LIFE2), true,
      "TERRA's pool pays every tier (so each charge is measured, not refused)")
  end)
  steps[#steps + 1] = H.driveUntil(function() return c.endF ~= nil and H.frame >= c.endF + 60 end,
    12000, { H.call(function() pulse(c) end) }, "case " .. c.name .. " resolves")
  steps[#steps + 1] = H.call(function()
    armed = nil
    H.setPad({})
    c.charged = c.mp0 - c.mpEnd
    c.hpLater, c.statusLater = H.readWord(0x3BF4 + lockeS * 2), H.readByte(STATUS4 + lockeS * 2)
    local cs, qs = {}, {}
    for _, v in ipairs(c.casts) do cs[#cs + 1] = string.format("$%02X", v) end
    for _, v in ipairs(c.queued) do qs[#qs + 1] = tostring(v) end
    H.log(string.format("[lifefold] %s: boost %d (pending %d at confirm, bank %d); cast %s; "
      .. "queued %s; MP %d -> %d (charged %d); LOCKE at TERRA's action end: status4 $%02X -> "
      .. "$%02X, HP %d/%d, %s; 60 frames on: HP %d, status4 $%02X", c.name, c.boost,
      c.pendAtConfirm, c.bank0, table.concat(cs, " "), table.concat(qs, " "), c.mp0, c.mpEnd,
      c.charged, c.status0, c.statusEnd, c.hpEnd, c.hpMax, c.koEnd and "KO'd" or "standing",
      c.hpLater, c.statusLater))
    H.screenshot("lifefold_" .. c.name .. "_after")
  end)
end

-- The verdict, once every case has logged.
steps[#steps + 1] = H.call(function()
  local bad = {}
  local function check(ok, what) if not ok then bad[#bad + 1] = what end end
  for _, c in ipairs(CASES) do
    local want = c.cast
    local price = romPrice(want)
    local digit = (want == LIFE2) and 2 or ((want == LIFE3) and 3 or nil)
    local named = #(c.names or {}) > 0
    for _, n in ipairs(c.names or {}) do
      if n.digit ~= digit then named = false end
    end
    check(named, string.format("%s: the Life row reads %s", c.name,
      digit and ("Life " .. digit) or "Life"))
    check(c.stamp == price, string.format("%s: the Life row's stamp %s is %d", c.name,
      tostring(c.stamp), price))
    local cast = false
    for _, v in ipairs(c.casts) do if v == want then cast = true end end
    for _, v in ipairs(c.casts) do
      if v == LIFE or v == LIFE2 or v == LIFE3 then
        if v ~= want then cast = false end
      end
    end
    check(cast, string.format("%s: the action cast $%02X and no other Life tier", c.name, want))
    local q = false
    for _, v in ipairs(c.queued) do if v == price then q = true end end
    check(q, string.format("%s: TERRA's action was queued at %d", c.name, price))
    check(c.charged == price, string.format("%s: TERRA's pool lost %d (lost %d)", c.name, price,
      c.charged))
    local gained = (c.statusEnd & LIFE3_STATUS) ~= 0 and (c.status0 & LIFE3_STATUS) == 0
    check(gained == (want == LIFE3), string.format("%s: LOCKE %s the Life 3 status", c.name,
      (want == LIFE3) and "gains" or "does not gain"))
    check(c.pendAtConfirm == c.boost, string.format("%s: %d boost was pending at the confirm "
      .. "(%s)", c.name, c.boost, tostring(c.pendAtConfirm)))
    if c.ko then
      -- Life 2 and (#327) Life 3 revive a KO'd body at full HP
      check(not c.koEnd and c.hpEnd == c.hpMax, string.format("%s: LOCKE revived at full HP "
        .. "(%d/%d, %s)", c.name, c.hpEnd, c.hpMax, c.koEnd and "KO'd" or "standing"))
    else
      check(not c.koEnd, string.format("%s: LOCKE still standing", c.name))
    end
  end
  local by = {}
  for _, c in ipairs(CASES) do by[c.name] = c end
  check(by.b1.charged >= by.b0.charged and by.b2.charged >= by.b1.charged,
    string.format("a boost never makes Life cheaper: %d, %d, %d at boost 0, 1, 2",
      by.b0.charged, by.b1.charged, by.b2.charged))
  for _, c in ipairs(CASES) do
    H.log(string.format("[lifefold] VERDICT %s: charged %d, Life 3 status %s, LOCKE %d/%d %s",
      c.name, c.charged, (c.statusEnd & LIFE3_STATUS) ~= 0 and "set" or "clear", c.hpEnd,
      c.hpMax, c.koEnd and "KO'd" or "standing"))
  end
  for _, b in ipairs(bad) do H.log("[lifefold] FAIL " .. b) end
  assert(#bad == 0, "Life's fold: " .. table.concat(bad, "; "))
end)

H.run({ maxFrames = 300000 }, steps)
