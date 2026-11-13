-- @suite
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_boostreach.lua -- a boost reward for every action, the first tranche (#469)
--
-- Boots wor-kohlingen-v1 by cold Continue (configure.py TEST_ENV).  By hand:
--   OT6_SRAM_CHECKPOINT=build/checkpoints/wor-kohlingen-v1 \
--     tools/tests/run.sh tools/tests/battle_boostreach.lua <log>
--
-- The rules (docs/design/boost-rewards.md, built in #469):
--   * reach: a single-target status or cure (Safe, Imp, ...: Ot6ReachTbl)
--     cast through Magic covers one more body on the target's side per
--     point, in battle order after the target and wrapping, passing over a
--     body it cannot land on (not standing; under Rflect for a reflectable
--     spell; holding every status it sets, or immune to them); each body
--     pays its own cast: the list draws base x (1 + boost) and that is
--     charged (Ot6SpellReach, Ot6PerPointPrice);
--   * Debilitator adds one weakness and one more a point, until the body has
--     no element left, priced one firing a weakness (Ot6DebilSteps);
--   * NoiseBlaster, and the Gravity Rod used from Item (Quartr, a fraction),
--     buy nothing with a boost: R on the row is refused, and a boost raised
--     on the command window before the row was picked is dropped, never
--     charged, the price flat.
-- Cases (each one action, from a snapshot; everyone else Defends):
--   safe-b0/b1/b2  CELES's Safe on an ally: the target mask (read where
--                  CalcAttackEffect hands on after ChooseTarget, at
--                  Ot6Oblivion's entry) holds 1 + min(boost, the allies it can
--                  land on) bodies, each holds Safe after; the price drawn is
--                  safe-b0's times (1 + boost), and that is charged;
--   imp-b1         CELES's Imp at a monster: the mask holds the target and
--                  one more monster it can land on, when there is one;
--   debil-b0/b2    EDGAR's Debilitator: the target gains min(1 + boost, the
--                  elements it lacks) weaknesses; charged debil-b0's x (1 + b);
--   noise-r/b1     R on NoiseBlaster refused; raised before it, the bank ends
--                  where noise-b0's does and the price is noise-b0's;
--   grav-r/b1      the same for the Gravity Rod in the Item list.
-- The run: Continue wor-kohlingen-v1 (EDGAR SABIN CELES SETZER outside
-- Kohlingen), pace to an encounter with two or more bodies standing, one with
-- a shield (the target); everyone Defends until EDGAR's window opens with
-- three pips banked (snapshot E), then on to CELES's with three (snapshot C).
-- Nothing is written; everything is observed.
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F
local ST_CMD, ST_DEF, ST_TGT, ST_LIST, ST_ITEM, ST_MAGIC = 0x05, 0x27, 0x38, 0x30, 0x0A, 0x0E
local KCOL, KROW, KSCROLL = 0x8963, 0x8967, 0x895F
local BANK, PEND, CURMP, BATTINV = 0x3E9C, 0x3E9D, 0x3C08, 0x2686
local CMD_FIGHT, CMD_ITEM, CMD_MAGIC, CMD_TOOLS = 0x00, 0x01, 0x02, 0x09
local EDGAR, SABIN, CELES, SETZER = 4, 5, 6, 9
local SAFE, IMP = 0x1C, 0x23
local NOISE, DEBIL, GRAVITY = 0xA3, 0xA7, 0x3A
local BURN = type(BOOSTREACH_BURN) == "number" and BOOSTREACH_BURN or 0
local DRAWS = 12 + BURN

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function pend(s) return H.readByte(PEND + s * 2) end
local function bank(s) return H.readByte(BANK + s * 2) end
local function mp(s) return H.readWord(CURMP + s * 2) end
local function shield(m) return H.readByte(0x3E40 + m * 2) end
local function weak(m) return H.readByte(0x3BE0 + 8 + m * 2) end
local function live(m) return (H.readByte(0x3AA8 + m * 2) & 1) == 1 and H.readWord(0x3BFC + m * 2) > 0 end
local function liveCount() local n = 0 for m = 0, 5 do if live(m) then n = n + 1 end end return n end
local function popc(v) local n = 0 while v > 0 do n, v = n + (v & 1), v >> 1 end return n end
local function cmdRow(s, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + s * 12 + r * 3) == cmd then return r end
  end
end
local function bagIdx(id)
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == id and H.readByte(BATTINV + i * 5 + 3) > 0 then return i end
  end
end
local function members()
  local p, t = H.readByte(0x1A6D) & 7, {}
  for c = 0, 13 do
    if (H.readByte(0x1850 + c) & 7) == p and p ~= 0 then t[#t + 1] = c end
  end
  return t
end
local edgarS, celesS, sabinS, setzerS
local actS
local tgtMon, allyS
local function chars()
  return string.format("MP E%d C%d bank E%d C%d pend E%d C%d", mp(edgarS), mp(celesS), bank(edgarS),
    bank(celesS), pend(edgarS), pend(celesS))
end
local function mons()
  local t = {}
  for m = 0, 5 do
    if live(m) then
      t[#t + 1] = string.format("m%d hp%d sh%d weak%02X", m, H.readWord(0x3BFC + m * 2), shield(m), weak(m))
    end
  end
  return table.concat(t, " ")
end

-- the reach predicate, Ot6ReachLands' as the design states it, read off RAM
-- and the spell's MagicProp record: can the spell land on entity e?
local MPB
local function lands(e, spell)
  local r = MPB + spell * 14
  local standing = H.readWord(0x3A74) & H.readWord(0x3018 + e)
  if standing == 0 then return false end
  if (H.readRomByte(r + 2) & 1) ~= 0 and (H.readByte(0x3EE4 + e) & 0x10) ~= 0 then return false end
  if (H.readRomByte(r + 3) & 2) == 0 and (H.readByte(0x3EF8 + e) & 0x80) ~= 0 then return false end
  local lift = (H.readRomByte(r + 4) & 4) ~= 0
  local cur = { 0x3EE4, 0x3EE5, 0x3EF8, 0x3EF9 }
  local ok = { 0x331C, 0x331D, 0x3330, 0x3331 }
  for k = 1, 4 do
    local st = H.readRomByte(r + 9 + k)
    local c = H.readByte(cur[k] + e)
    if lift then c = c else c = (~c) & 0xFF end
    if (st & c & H.readByte(ok[k] + e)) ~= 0 then return true end
  end
  return false
end

-- ---- observers ---------------------------------------------------------------
local armed, installed = nil, false
local function ev(c, s) c.log[#c.log + 1] = string.format("f%d %s", H.frame, s) end
local function installObservers()
  if installed then return end
  installed = true
  local function cx() return emu.getState()["cpu.x"] & 0xFF end
  local function onExec(a, fn)
    emu.addMemoryCallback(function() if armed and armed.sent and not armed.endF then fn(armed) end end,
      emu.callbackType.exec, a, a)
  end
  -- CalcAttackEffect: the jsl after ChooseTarget (and after the reach, where
  -- it is built) is Ot6Oblivion's
  onExec(H.sym("Ot6Oblivion"), function(c)
    if cx() == actS * 2 and H.readByte(0x3A7C) == CMD_MAGIC and c.mask == nil then
      c.mask = H.readWord(0xB8)
      local side = (c.mask & 0xFF) ~= 0 and { 0, 2, 4, 6 } or { 8, 10, 12, 14, 16, 18 }
      local spell = H.readByte(0xB6)
      c.eligible = 0
      local landsOn = {}
      for _, e in ipairs(side) do
        local b = H.readWord(0x3018 + e)
        if c.aimBit == nil or (c.aimBit & b) == 0 then
          if lands(e, spell) then c.eligible = c.eligible + 1; landsOn[#landsOn + 1] = e end
        end
      end
      ev(c, string.format("after ChooseTarget: spell $%02X mask $%04X (aimed $%04X); the others it can land on: %s",
        spell, c.mask, c.aimBit or 0, table.concat(landsOn, ",")))
    end
  end)
  onExec(H.sym("Ot6ActionEnd"), function(c)
    if cx() == actS * 2 then
      c.endF = H.frame
      c.mpEnd = mp(actS)
      ev(c, string.format("Ot6ActionEnd entry: 3a7c=$%02X 3a7d=$%02X %s | %s", H.readByte(0x3A7C),
        H.readByte(0x3A7D), chars(), mons()))
    end
  end)
end
-- ---- the menu policy ---------------------------------------------------------
local tick, held = 0, nil
local function defendPress(st)
  if st == ST_CMD then return "right" end
  if st == ST_DEF then return "a" end
  if st == ST_TGT or st == ST_LIST or st == ST_ITEM or st == ST_MAGIC then return "b" end
  return nil
end
local Tm = H.targetCursor()
local Tc = H.targetCursor({ mask = 0x7B7D, dirs = { "down", "up", "left", "right" } })
local mf, tapNo, tapAt = 0, -1, 0
local function aim(T, want)
  mf = mf + 1
  local edge = (mf - 1) % 8 < 4
  if T.mask == nil then return {} end
  local btn = T.steer(want, mf)
  if btn == "a" then
    if not edge then btn = nil end
  else
    if btn ~= nil and T.press ~= tapNo then tapNo, tapAt = T.press, mf end
    btn = (tapNo >= 0 and mf - tapAt < 4) and T.dir or nil
  end
  return btn and { [btn] = true } or {}
end

local function spellIdx(s, id)
  for i = 0, 53 do
    if H.readByte(0x2092 + s * 0x13C + i * 4) == id then return i end
  end
end
local function toolCell(id)
  for i = 0, 15 do
    if H.readByte(0x4005 + i * 3) == id then return i end
  end
end
local function onRow(c, s)
  if c.rowR and not c.triedR then
    c.triedR, c.pendBeforeR = true, pend(s)
    return "r"
  end
  if c.rowR and c.pendAfterR == nil then
    c.pendAfterR = pend(s)
    ev(c, string.format("R on the row: pending %d -> %d", c.pendBeforeR, c.pendAfterR))
  end
  return "a"
end
local function actorPress(c, st)
  local s = actS
  if st == ST_CMD then
    if pend(s) < c.boost then return "r" end
    if pend(s) > c.boost then return "l" end
    local want = cmdRow(s, c.cmd)
    local cur = H.readByte(CMDROW + s) & 3
    if cur ~= want then return cur < want and "down" or "up" end
    c.mp0, c.bank0, c.pendAtCmd = mp(s), bank(s), pend(s)
    return "a"
  end
  if c.cmd == CMD_TOOLS and st == ST_LIST then
    local i = toolCell(c.item)
    if i == nil then return "b" end
    local row = i // 2 - H.readByte(KSCROLL + s)
    local col = i % 2
    local cc, cr = H.readByte(KCOL + s), H.readByte(KROW + s)
    if cc ~= col then return cc < col and "right" or "left" end
    if cr ~= row then return cr < row and "down" or "up" end
    return onRow(c, s)
  end
  if c.cmd == CMD_ITEM and st == ST_ITEM then
    local want = bagIdx(c.item)
    if want == nil then return "b" end
    local cur = H.readByte(0x8947 + s) + H.readByte(0x894F + s)
    if cur ~= want then return cur < want and "down" or "up" end
    return onRow(c, s)
  end
  if c.cmd == CMD_MAGIC and st == ST_MAGIC then
    local i = spellIdx(s, c.spell)
    if i == nil then return "b" end
    local wr, wc = i // 2, i % 2
    local ar = H.readByte(0x8913 + s) + H.readByte(0x891B + s)
    local col = H.readByte(0x8917 + s)
    if ar ~= wr then return ar < wr and "down" or "up" end
    if col ~= wc then return col < wc and "right" or "left" end
    c.listPrice = H.readByte(0x2092 + s * 0x13C + i * 4 + 3)   -- the row's drawn price
    return onRow(c, s)
  end
  return nil
end
local function actorAim(c)
  if H.readByte(MENU) == 0 or H.readByte(MSTATE) ~= ST_TGT or (H.readByte(ACTOR) & 3) ~= actS
     or c.sent then
    mf, tapNo = 0, -1
    return false
  end
  local btn
  if c.multi then
    -- a tool that aims at the whole side (NoiseBlaster's targeting $6A):
    -- the cursor already covers it, so the confirm is the press
    mf = mf + 1
    btn = (mf - 1) % 8 < 4 and { a = true } or {}
  else
    btn = c.ally and aim(Tc, allyS) or aim(Tm, tgtMon)
  end
  if next(btn) == "a" then
    c.sent = true
    c.pendAtConfirm = pend(actS)
    ev(c, "the measured actor's target confirmed: " .. chars() .. " | " .. mons())
  end
  return btn
end

local snaps = {}
local function runCase(c)
  local req
  return {
    H.call(function() H.setPad({}); req = H.requestLoadState(snaps[c.snap].blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load")
      H.rearmInputInjection()
      tick, held = 0, nil
      mf, tapNo = 0, -1
      c.log = {}
      actS = c.who == "C" and celesS or edgarS
      c.sent, c.after, c.endF, c.mask = false, false, nil, nil
      c.triedR, c.pendAfterR = false, nil
      c.aimBit = c.ally and H.readWord(0x3018 + allyS * 2) or H.readWord(0x3018 + 8 + tgtMon * 2)
      c.weak0 = weak(tgtMon)
      c.room = popc((~(weak(tgtMon) | H.readByte(0x3EC8))) & 0xFF)
      armed = c
      ev(c, "START " .. chars() .. " | " .. mons())
    end),
    H.driveUntil(function() return c.endF ~= nil and H.frame >= c.endF + 120 end, 14000, {
      H.call(function()
        Tm.observe(); Tc.observe()
        if c.endF and not c.after and H.frame >= c.endF + 6 then
          c.after = true
          c.bankEnd = bank(actS)
          c.weakEnd = weak(tgtMon)
          c.safeAfter = {}
          for e = 0, 6, 2 do c.safeAfter[e] = (H.readByte(0x3EF8 + e) & 0x40) ~= 0 end
          ev(c, "six frames after the actor's Ot6ActionEnd: " .. chars() .. " | " .. mons())
        end
        local ac = actorAim(c)
        if ac then held = nil; H.setPad(ac) return end
        tick = tick + 1
        local ph = tick % 12
        if ph == 0 then
          held = nil
          if H.readByte(MENU) ~= 0 then
            local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
            if a == actS and not c.sent then held = actorPress(c, st) else held = defendPress(st) end
          end
        end
        H.setPad((held and ph < 6) and { [held] = true } or {})
      end),
    }, "case " .. c.name .. " resolves"),
    H.call(function()
      armed = nil
      H.setPad({})
      for _, l in ipairs(c.log) do H.log(string.format("[boostreach] %s: %s", c.name, l)) end
      c.charged = (c.mp0 or 0) - (c.mpEnd or c.mp0 or 0)
      H.log(string.format("[boostreach] %s RESULT: boost %d (R on the row: %s; pending at confirm %s); bank %s -> %s; "
        .. "list price %s; MP charged %d; mask $%04X; others it could land on %s; target weak $%02X -> $%02X",
        c.name, c.boost, c.rowR and tostring(c.pendAfterR) or "-", tostring(c.pendAtConfirm), tostring(c.bank0),
        tostring(c.bankEnd), tostring(c.listPrice), c.charged, c.mask or 0, tostring(c.eligible), c.weak0,
        c.weakEnd or 0))
    end),
  }
end

-- drive until `who()`'s window opens with nothing pending and `cond()`;
-- snapshot it as `key`.  Everyone Defends meanwhile.
local function snapAt(key, cond, who)
  return {
    H.call(function() actS = who(); tick, held, mf, tapNo = 0, nil, 0, -1 end),
    H.driveUntil(function() return snaps[key] ~= nil end, 30000, {
      H.call(function()
        assert(H.battleLoadStarted(), "the battle is still up while snapshot " .. key .. " is sought")
        tick = tick + 1
        if tick % 12 == 6 then H.setPad({}) return end
        if tick % 12 ~= 0 then return end
        if H.readByte(MENU) == 0 then return end
        local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
        if a == actS and st == ST_CMD and pend(actS) == 0 and cond() then
          H.setPad({}); snaps[key] = H.requestSaveState()
          H.log(string.format("[boostreach] snapshot %s f%d: %s | %s", key, H.frame, chars(), mons()))
          return
        end
        local b = defendPress(st)
        H.setPad(b and { [b] = true } or {})
      end),
    }, "snapshot " .. key),
    H.waitFrames(2),
    H.call(function() H.checkReq(snaps[key], "snapshot " .. key) end),
    H.waitFrames(30),
  }
end

-- ---- the run -----------------------------------------------------------------
local steps = {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function()
    local ph = 0
    return H.driveUntil(function() return H.worldMode() and bright() >= 15 and H.worldHasControl() end,
      6000, {
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
    H.assertEntryContract("wor-kohlingen-v1")
    local have = {}
    for _, c in ipairs(members()) do have[c] = true end
    assert(have[EDGAR] and have[CELES], "EDGAR and CELES are in the party (wor-kohlingen-v1's contract)")
    MPB = H.sym("MagicProp") & 0x3FFFFF
    installObservers()
  end),
  (function()
    local P = H.newPacer({ tag = "boostreach pace" })
    local sx, sy
    local steps = {
      H.waitUntil(function() return H.worldMode() and H.worldHasControl() and H.worldSettled() end,
        1500, "the world map settled", 5),
      H.call(function() sx, sy = P.findStart(8) end),
      H.worldNavTo(function() return sx end, function() return sy end,
        { maxFrames = 4000, playBattles = "mustflee", care = false }),
      H.waitUntil(function() return H.worldSettled() end, 1500, "settled on the stretch", 5),
      H.call(function() P.plan() end),
    }
    local measured = false
    for try = 1, DRAWS do
      steps[#steps + 1] = H.cond(function() return measured end, {}, {
        H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
          H.call(function() H.setPad(P.pad()) end),
        }, "a random encounter (draw " .. try .. ")"),
        H.release(),
        H.waitUntil(function() return H.battleActive() end, 900, "battle up (draw " .. try .. ")", 5),
        H.waitFrames(60),
        H.call(function()
          edgarS, celesS = nil, nil
          for s = 0, 3 do
            local id = H.readByte(0x3ED8 + s * 2)
            if id == EDGAR then edgarS = s end
            if id == CELES then celesS = s end
          end
          -- the target: a shielded body with the most HP, another standing
          -- beside it, and an element it is not weak to
          local best
          for m = 0, 5 do
            if live(m) and shield(m) > 0 and weak(m) ~= 0xFF then
              if best == nil or H.readWord(0x3BFC + m * 2) > H.readWord(0x3BFC + best * 2) then best = m end
            end
          end
          local ok = best ~= nil and liveCount() >= 2 and try > BURN and edgarS ~= nil and celesS ~= nil
          H.log(string.format("[boostreach] draw %d: formation $%03X | %s -> %s", try, H.readWord(0x11E0), mons(),
            ok and ("target m" .. best) or "no target with a body beside it (run)"))
          if ok then tgtMon = best; measured = true end
        end),
        H.cond(function() return measured end, {}, {
          H.fleeBattle(9000, { onCantRun = "fight" }),
          H.waitUntil(function() return H.worldMode() and H.worldHasControl() end, 1200,
            "back on the world map after running from draw " .. try, 10),
          H.waitFrames(30),
        }),
      })
    end
    steps[#steps + 1] = H.call(function()
      assert(measured, "a draw with two or more bodies, one shielded")
    end)
    return H.repeatN(1, steps)
  end)(),
  H.call(function()
    -- CELES's ally: the next seat after her that stands
    for k = 1, 3 do
      local s = (celesS + k) % 4
      if allyS == nil and H.readByte(0x3ED8 + s * 2) ~= 0xFF and (H.readWord(0x3A74) & (1 << s)) ~= 0 then
        allyS = s
      end
    end
    H.log(string.format("[boostreach] slots: EDGAR %d CELES %d (ally %s); target m%d; %s | %s", edgarS, celesS,
      tostring(allyS), tgtMon, chars(), mons()))
    assert(allyS, "an ally standing beside CELES")
    assert(spellIdx(celesS, SAFE) and spellIdx(celesS, IMP), "CELES knows Safe and Imp (wor-kohlingen-v1)")
    assert(bagIdx(GRAVITY), "the bag holds the Gravity Rod")
    assert(cmdRow(edgarS, CMD_TOOLS) and cmdRow(edgarS, CMD_ITEM), "EDGAR's list has Tools and Item")
  end),
}
local function add(t) for _, s in ipairs(t) do steps[#steps + 1] = s end end
add(snapAt("E", function() return bank(edgarS) >= 3 end, function() return edgarS end))
add(snapAt("C", function() return bank(celesS) >= 3 end, function() return celesS end))

local CASES = {
  { name = "safe-b0",  snap = "C", who = "C", cmd = CMD_MAGIC, spell = SAFE, boost = 0, ally = true },
  { name = "safe-b1",  snap = "C", who = "C", cmd = CMD_MAGIC, spell = SAFE, boost = 1, ally = true },
  { name = "safe-b2",  snap = "C", who = "C", cmd = CMD_MAGIC, spell = SAFE, boost = 2, ally = true },
  { name = "safe-r",   snap = "C", who = "C", cmd = CMD_MAGIC, spell = SAFE, boost = 0, ally = true, rowR = 1 },
  { name = "imp-b1",   snap = "C", who = "C", cmd = CMD_MAGIC, spell = IMP,  boost = 1 },
  { name = "debil-b0", snap = "E", cmd = CMD_TOOLS, item = DEBIL, boost = 0 },
  { name = "debil-b2", snap = "E", cmd = CMD_TOOLS, item = DEBIL, boost = 2 },
  { name = "noise-b0", multi = true, snap = "E", cmd = CMD_TOOLS, item = NOISE, boost = 0 },
  { name = "noise-b1", multi = true, snap = "E", cmd = CMD_TOOLS, item = NOISE, boost = 1, keep = "noise-b0" },
  { name = "noise-r", multi = true,  snap = "E", cmd = CMD_TOOLS, item = NOISE, boost = 0, rowR = 0 },
  { name = "grav-b0",  snap = "E", cmd = CMD_ITEM, item = GRAVITY, boost = 0 },
  { name = "grav-b1",  snap = "E", cmd = CMD_ITEM, item = GRAVITY, boost = 1, keep = "grav-b0" },
  { name = "grav-r",   snap = "E", cmd = CMD_ITEM, item = GRAVITY, boost = 0, rowR = 0 },
}
local byName = {}
for _, c in ipairs(CASES) do
  byName[c.name] = c
  add(runCase(c))
end

steps[#steps + 1] = H.call(function()
  local bad = {}
  local function check(ok, msg)
    H.log(string.format("[boostreach] %s %s", ok and "ok:" or "FAIL:", msg))
    if not ok then bad[#bad + 1] = msg end
  end
  for _, c in ipairs(CASES) do
    if c.rowR then
      H.assertEq(c.pendBeforeR, 0, c.name .. ": nothing pending when R was pressed on the row")
      check(c.pendAfterR == c.rowR, string.format("%s: R on the row left the pending at %s (%s)", c.name,
        tostring(c.pendAfterR), c.rowR == 0 and "refused: the boost buys nothing here" or "raised: it buys"))
      c.boost = c.pendAfterR or c.boost
    end
    check(c.pendAtConfirm == c.boost, string.format("%s: the pending at the confirm %s (want %d)", c.name,
      tostring(c.pendAtConfirm), c.boost))
    if c.spell then
      H.assertEq(c.mask ~= nil, true, c.name .. ": the cast reached CalcAttackEffect")
      check((c.mask & c.aimBit) ~= 0, string.format("%s: the mask $%04X holds the body aimed at", c.name, c.mask))
      local want = 1 + math.min(c.boost, c.eligible)
      check(popc(c.mask) == want, string.format("%s: at %d BP the mask $%04X holds %d bodies (want %d: the target "
        .. "and %d of the %d others it can land on)", c.name, c.boost, c.mask, popc(c.mask), want,
        math.min(c.boost, c.eligible), c.eligible))
      if c.spell == SAFE then
        for e = 0, 6, 2 do
          if (c.mask & (1 << (e // 2))) ~= 0 then
            check(c.safeAfter[e], string.format("%s: entity %d holds Safe after the cast", c.name, e))
          end
        end
        local b0 = byName["safe-b0"].listPrice
        check(c.listPrice == math.min(99, b0 * (c.boost + 1)), string.format("%s: the list drew %s MP, safe-b0 %s "
          .. "(one cast a body)", c.name, tostring(c.listPrice), tostring(b0)))
        check(c.charged == c.listPrice, string.format("%s: charged %d MP, the drawn %s", c.name, c.charged,
          tostring(c.listPrice)))
      end
    end
    if c.item == DEBIL then
      local added = popc(c.weakEnd & ~c.weak0 & 0xFF)
      local want = math.min(c.boost + 1, c.room)
      check(added == want, string.format("%s: Debilitator at %d BP added %d weakness(es) ($%02X -> $%02X; want %d "
        .. "of the %d it lacked)", c.name, c.boost, added, c.weak0, c.weakEnd, want, c.room))
      local b0 = byName["debil-b0"].charged
      check(c.charged == math.min(99, b0 * (c.boost + 1)), string.format("%s: charged %d MP, debil-b0 %d (one "
        .. "firing a weakness)", c.name, c.charged, b0))
      local wantBank = math.min(5, c.bank0 - c.boost + (c.boost == 0 and 1 or 0))
      check(c.bankEnd == wantBank, string.format("%s: bank %d -> %d (want %d)", c.name, c.bank0, c.bankEnd,
        wantBank))
    end
    if c.keep then
      local base = byName[c.keep]
      H.assertEq(c.bank0, base.bank0, c.name .. ": the bank at the command, as in " .. c.keep)
      check(c.bankEnd == base.bankEnd, string.format("%s: the bank ended at %d, %s's at %d "
        .. "(a boost that buys nothing is never charged)", c.name, c.bankEnd, c.keep, base.bankEnd))
      check(c.charged == base.charged, string.format("%s: charged %d MP, %s %d (flat)", c.name, c.charged, c.keep,
        base.charged))
    end
  end
  assert(#bad == 0, #bad .. " boost-reach assertion(s) failed: " .. table.concat(bad, "; "))
  H.log("[boostreach] VERDICT: Safe and Imp reach one more body a point at a cast's price a body; Debilitator adds "
    .. "a weakness a point at a firing's price; NoiseBlaster and the Gravity Rod refuse R and never charge a boost")
end)

H.run({ maxFrames = 700000 }, steps)
