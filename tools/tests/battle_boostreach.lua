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
-- Toggles (Imp, Vanish: MagicProp +4 bit 3) reach in the direction of the
-- body aimed at: aimed at one holding the status they lift it from the others
-- that hold it, else they set it.  A spell the boost buys nothing on (a
-- power of 0 or a fraction, not a reach spell, a tier or Scan: CELES's list,
-- read off the ROM) refuses R, and one raised before it is dropped; so is
-- Vanish's at a monster (Vanish reaches allies only), priced as itself.
-- Every case asserts it played the action it names (the command and attack
-- Ot6ActionEnd's entry meets), so a turn that resolved as something else
-- (a Defend) cannot pass vacuously.
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
--   grav-r/b1      the same for the Gravity Rod in the Item list;
--   safe-pass-b2   from snapshot S (two allies under Safe, after safe-b1),
--                  Safe at an ally without it: the walk passes over the two;
--   impa-b1/impl-b1  Imp at an ally (snapshot I after it: two allies imped),
--                  then Imp at the imped ally reaches the other imped one and
--                  lifts it from both;
--   quiet-b0/b1/r  CELES's spell the boost buys nothing on: R refused, a
--                  boost raised before it never charged, its price its own;
--   vanmon-b0/b1   Vanish at a monster: the boost dropped, its price its own;
--   debil-oc-b3    from snapshot D (after debil-b2), EDGAR's overclocked
--                  Debilitator: eight firings at most, stopping when the
--                  body has no element left; 80 MP.  The Tools list's drawn
--                  price (the decorator's cost cell) is the charge.
-- The run: Continue wor-kohlingen-v1 (EDGAR SABIN CELES SETZER outside
-- Kohlingen), CELES equips Phantom through the field menu (Vanish, Demi), pace to an encounter with two or more bodies standing, one with
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
local SAFE, IMP, VANISH = 0x1C, 0x23, 0x26
local PHANTOM = 20
-- the reach spells (boost-rewards.md proposal 1), named here rather than read
-- off the ROM, so a ROM without them is judged by the rule and not by itself
local REACH = { [0x1B] = true, [0x1C] = true, [0x1D] = true, [0x1E] = true, [0x20] = true, [0x21] = true,
  [0x23] = true, [0x24] = true, [0x25] = true, [0x26] = true, [0x2C] = true, [0x32] = true, [0x33] = true,
  [0x34] = true }
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
local quiet
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
local function holds(e, spell)
  local r = MPB + spell * 14
  local cur = { 0x3EE4, 0x3EE5, 0x3EF8, 0x3EF9 }
  for k = 1, 4 do
    if (H.readRomByte(r + 9 + k) & H.readByte(cur[k] + e)) ~= 0 then return true end
  end
  return false
end
local function lands(e, spell, first)
  local r = MPB + spell * 14
  local standing = H.readWord(0x3A74) & H.readWord(0x3018 + e)
  if standing == 0 then return false end
  if (H.readRomByte(r + 2) & 1) ~= 0 and (H.readByte(0x3EE4 + e) & 0x10) ~= 0 then return false end
  if (H.readRomByte(r + 3) & 2) == 0 and (H.readByte(0x3EF8 + e) & 0x80) ~= 0 then return false end
  local lift = (H.readRomByte(r + 4) & 4) ~= 0
  if not lift and (H.readRomByte(r + 4) & 8) ~= 0 then lift = first ~= nil and holds(first, spell) end   -- a toggle
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
local drawn = {}       -- the Tools list's drawn price per tool id (Ot6ToolRowDecorate's cost cells)
local function installObservers()
  if installed then return end
  installed = true
  -- only the decorator's own stores are the drawn cost (DrawToolsListText's
  -- template writes the same cells first)
  local dec = H.sym("Ot6ToolRowDecorate")
  local function inDec()
    local st = emu.getState()
    local pc = (st["cpu.k"] << 16) | st["cpu.pc"]
    return pc >= dec and pc < dec + 0x80
  end
  emu.addMemoryCallback(function(_, v)
    if H.readByte(0x6168) == 0 and inDec() then drawn[H.readByte(0x575A)] = v end
  end, emu.callbackType.write, 0x7E5758, 0x7E5758)
  emu.addMemoryCallback(function(_, v)
    if H.readByte(0x6168) == 0 and inDec() then drawn[H.readByte(0x5760)] = v end
  end, emu.callbackType.write, 0x7E575E, 0x7E575E)
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
      local first
      for _, e in ipairs(side) do
        if c.aimBit ~= nil and (c.aimBit & H.readWord(0x3018 + e)) ~= 0 then first = e end
      end
      c.first = first
      for _, e in ipairs(side) do
        local b = H.readWord(0x3018 + e)
        if c.aimBit == nil or (c.aimBit & b) == 0 then
          if lands(e, spell, first) then c.eligible = c.eligible + 1; landsOn[#landsOn + 1] = e end
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
      c.cmdEnd, c.atkEnd = H.readByte(0x3A7C), H.readByte(0x3A7D)
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
    c.listPrice = drawn[c.item]        -- the price the row drew, pending boost and all
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
    btn = (mf > 8 and (mf - 1) % 8 < 4) and { a = true } or {}   -- a fresh press: the list's A released
  else
    if c.here then
      -- confirm where the cursor opens (a spell whose side this case does
      -- not choose: the quiet spell)
      mf = mf + 1
      btn = (mf > 8 and (mf - 1) % 8 < 4) and { a = true } or {}
    elseif not c.ally and Tm.mask == nil and Tc.mask ~= nil then
      -- a spell that opens on the party (Vanish), aimed at a monster: cross
      -- over to the monsters' side, on the left
      mf = mf + 1
      btn = ((mf - 1) % 8 < 4) and { left = true } or {}
    else
      btn = c.ally and aim(Tc, c.allyT or allyS) or aim(Tm, tgtMon)
    end
  end
  if next(btn) == "a" then
    c.sent = true
    c.pendAtConfirm = pend(actS)
    ev(c, "the measured actor's target confirmed: " .. chars() .. " | " .. mons())
  end
  return btn
end

local snaps = {}
local snapDone = false
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
      c.allyT = allyS
      if c.aimFree then
        -- a seat without Safe whose walk (battle order after it, wrapping)
        -- meets a body under Safe before one it can reach: from S (Safe on
        -- the two after CELES) that is CELES's own seat, and the walk goes
        -- pass, pass, reach
        local function stands(e) return H.readByte(0x3ED8 + e) ~= 0xFF and (H.readWord(0x3A74) & (1 << (e // 2))) ~= 0 end
        local function safe(e) return (H.readByte(0x3EF8 + e) & 0x40) ~= 0 end
        c.allyT = nil
        for t = 0, 6, 2 do
          if c.allyT == nil and stands(t) and not safe(t) then
            local passed = false
            for k = 1, 3 do
              local e = (t + 2 * k) % 8
              if stands(e) and safe(e) then passed = true
              elseif stands(e) and passed then c.allyT = t // 2; break
              elseif stands(e) then break end
            end
          end
        end
        H.assertEq(c.allyT ~= nil, true, c.name .. ": a seat whose walk passes a body under Safe before one it reaches")
      end
      c.aimBit = c.ally and H.readWord(0x3018 + c.allyT * 2) or H.readWord(0x3018 + 8 + tgtMon * 2)
      c.safe0, c.imp0 = {}, {}
      for e = 0, 6, 2 do
        c.safe0[e] = (H.readByte(0x3EF8 + e) & 0x40) ~= 0
        c.imp0[e] = (H.readByte(0x3EE4 + e) & 0x20) ~= 0
      end
      snapDone = false
      c.weak0 = weak(tgtMon)
      c.room = popc((~(weak(tgtMon) | H.readByte(0x3EC8))) & 0xFF)
      armed = c
      ev(c, "START " .. chars() .. " | " .. mons())
    end),
    H.driveUntil(function()
      return c.endF ~= nil and H.frame >= c.endF + 120 and (c.snapAfter == nil or snapDone)
    end, c.snapAfter and 30000 or 14000, {
      H.call(function()
        Tm.observe(); Tc.observe()
        if c.after and c.snapAfter and not snapDone and H.frame >= c.endF + 30 then
          -- on to the actor's next window that meets the snapshot's need
          tick = tick + 1
          if tick % 12 == 6 then H.setPad({}) return end
          if tick % 12 ~= 0 or H.readByte(MENU) == 0 then return end
          local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
          if a == actS and st == ST_CMD and pend(actS) == 0 and c.snapCond() then
            H.setPad({}); snaps[c.snapAfter] = H.requestSaveState(); snapDone = true
            H.log(string.format("[boostreach] snapshot %s f%d (after %s): %s | %s", c.snapAfter, H.frame, c.name,
              chars(), mons()))
            return
          end
          local b = defendPress(st)
          H.setPad(b and { [b] = true } or {})
          return
        end
        if c.endF and not c.after and H.frame >= c.endF + 6 then
          c.after = true
          c.bankEnd = bank(actS)
          c.weakEnd = weak(tgtMon)
          c.safeAfter, c.impAfter = {}, {}
          for e = 0, 6, 2 do
            c.safeAfter[e] = (H.readByte(0x3EF8 + e) & 0x40) ~= 0
            c.impAfter[e] = (H.readByte(0x3EE4 + e) & 0x20) ~= 0
          end
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
            if a == actS and not c.sent then held = actorPress(c, st)
            elseif a == actS and st == ST_TGT then held = "a"   -- the confirm not yet landed
            else held = defendPress(st) end
          end
        end
        H.setPad((held and ph < 6) and { [held] = true } or {})
      end),
    }, "case " .. c.name .. " resolves"),
    H.waitFrames(2),
    H.call(function()
      if c.snapAfter then H.checkReq(snaps[c.snapAfter], "snapshot " .. c.snapAfter) end
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
  -- CELES puts on Phantom (owned, worn by nobody here) through the field menu,
  -- as a player would for its spells: Vanish and Demi, the latter one the
  -- boost buys nothing on (a fraction)
  H.equipEsper(function() return (H.readByte(0x1850 + CELES) >> 3) & 3 end, PHANTOM, { tag = "Phantom -> CELES" }),
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
    -- CELES's spell the boost buys nothing on, as Ot6SpellNoBoost reads the
    -- ROM: not a tier family (Ot6FoldTbl, Break), not Scan, not a reach spell,
    -- and a power of 0 or a fraction
    local fold = H.sym("Ot6FoldTbl") & 0x3FFFFF
    local inFold = { [0x0C] = true, [0x18] = true }
    for i = 0, 0x17 do inFold[H.readRomByte(fold + i)] = true end
    local list = {}
    for i = 0, 53 do
      local id = H.readByte(0x2092 + celesS * 0x13C + i * 4)
      if id ~= 0xFF then
        list[#list + 1] = string.format("$%02X", id)
        local r = MPB + id * 14
        if quiet == nil and id < 0x36 and not inFold[id] and not REACH[id]
           and ((H.readRomByte(r + 4) & 0x80) ~= 0 or H.readRomByte(r + 6) == 0) then quiet = id end
      end
    end
    H.log(string.format("[boostreach] CELES's list: %s; the quiet spell %s", table.concat(list, " "),
      quiet and string.format("$%02X", quiet) or "none"))
    assert(quiet, "CELES's list holds a spell the boost buys nothing on (Float, Demi, Quartr...)")
    assert(spellIdx(celesS, VANISH), "CELES's list holds Vanish")
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
  -- the walk passes over: from S (after safe-b1 put Safe on two allies)
  { name = "safe-s1",  snap = "C", who = "C", cmd = CMD_MAGIC, spell = SAFE, boost = 1, ally = true, snapAfter = "S",
    snapCond = function() return bank(celesS) >= 2 end },
  { name = "safe-pass-b2", snap = "S", who = "C", cmd = CMD_MAGIC, spell = SAFE, boost = 2, ally = true,
    aimFree = true },
  -- the toggle: Imp on two allies, then Imp at the imped one lifts it from both
  { name = "impa-b1",  snap = "C", who = "C", cmd = CMD_MAGIC, spell = IMP, boost = 1, ally = true, snapAfter = "I",
    snapCond = function() return bank(celesS) >= 1 end },
  { name = "impl-b1",  snap = "I", who = "C", cmd = CMD_MAGIC, spell = IMP, boost = 1, ally = true },
  -- a spell the boost buys nothing on; Vanish at a monster
  { name = "quiet-b0", snap = "C", who = "C", cmd = CMD_MAGIC, spell = "quiet", boost = 0, here = true },
  { name = "quiet-b1", snap = "C", who = "C", cmd = CMD_MAGIC, spell = "quiet", boost = 1, here = true,
    keep = "quiet-b0", sameMp = "quiet-b0" },
  { name = "quiet-r",  snap = "C", who = "C", cmd = CMD_MAGIC, spell = "quiet", boost = 0, here = true, rowR = 0 },
  { name = "vanmon-b0", snap = "C", who = "C", cmd = CMD_MAGIC, spell = VANISH, boost = 0 },
  { name = "vanmon-b1", snap = "C", who = "C", cmd = CMD_MAGIC, spell = VANISH, boost = 1, keep = "vanmon-b0",
    sameMp = "vanmon-b0", vanmon = true },
  -- Debilitator overclocked on a body with fewer elements left than firings
  { name = "debil-d2", snap = "E", cmd = CMD_TOOLS, item = DEBIL, boost = 2, snapAfter = "D",
    snapCond = function() return bank(edgarS) >= 3 end },
  { name = "debil-oc-b3", snap = "D", cmd = CMD_TOOLS, item = DEBIL, boost = 3, overclock = true },
}
local byName = {}
for _, c in ipairs(CASES) do
  byName[c.name] = c
  if c.spell == "quiet" then add({ H.call(function() c.spell = quiet end) }) end
  add(runCase(c))
end

steps[#steps + 1] = H.call(function()
  local bad = {}
  local function check(ok, msg)
    H.log(string.format("[boostreach] %s %s", ok and "ok:" or "FAIL:", msg))
    if not ok then bad[#bad + 1] = msg end
  end
  for _, c in ipairs(CASES) do
    -- the case played the action it names
    local wantAtk = c.spell or c.item
    check(c.cmdEnd == c.cmd and c.atkEnd == wantAtk, string.format("%s: the turn ran command $%02X attack $%02X "
      .. "(want $%02X $%02X)", c.name, c.cmdEnd or 0, c.atkEnd or 0, c.cmd, wantAtk))
    if c.rowR then
      H.assertEq(c.pendBeforeR, 0, c.name .. ": nothing pending when R was pressed on the row")
      check(c.pendAfterR == c.rowR, string.format("%s: R on the row left the pending at %s (%s)", c.name,
        tostring(c.pendAfterR), c.rowR == 0 and "refused: the boost buys nothing here" or "raised: it buys"))
      c.boost = c.pendAfterR or c.boost
    end
    check(c.pendAtConfirm == c.boost, string.format("%s: the pending at the confirm %s (want %d)", c.name,
      tostring(c.pendAtConfirm), c.boost))
    if c.spell then
      check(c.mask ~= nil, c.name .. ": the cast reached CalcAttackEffect")
      c.mask = c.mask or 0
      if not c.here then
        check((c.mask & c.aimBit) ~= 0, string.format("%s: the mask $%04X holds the body aimed at", c.name, c.mask))
      end
      -- a reach spell covers the target and a body a point it can land on;
      -- anything else (the quiet spell, Vanish at a monster) the one body
      local want = (REACH[c.spell] and not c.vanmon) and 1 + math.min(c.boost, c.eligible) or 1
      check(popc(c.mask) == want, string.format("%s: at %d BP the mask $%04X holds %d bodies (want %d: the target "
        .. "and %d of the %d others it can land on)", c.name, c.boost, c.mask, popc(c.mask), want,
        math.min(c.boost, c.eligible), c.eligible))
      if c.aimFree then
        -- walk order from the target: every body under Safe is passed, and a
        -- body reached beyond a passed one is in the mask
        local t = c.allyT * 2
        local passed, beyond = 0, nil
        for k = 1, 3 do
          local e = (t + 2 * k) % 8
          if c.safe0[e] then
            passed = passed + 1
            check((c.mask & (1 << (e // 2))) == 0, string.format("%s: the walk passed over entity %d, already under "
              .. "Safe (mask $%04X)", c.name, e, c.mask))
          elseif passed > 0 and beyond == nil and H.readByte(0x3ED8 + e) ~= 0xFF then
            beyond = e
          end
        end
        check(passed >= 1 and beyond ~= nil and (c.mask & (1 << (beyond // 2))) ~= 0, string.format("%s: entity %s, "
          .. "beyond %d body(ies) under Safe in walk order from entity %d, is reached (mask $%04X)", c.name,
          tostring(beyond), passed, t, c.mask))
      end
      if c.name == "impl-b1" then
        local imped = 0
        for e = 0, 6, 2 do if c.imp0[e] then imped = imped + 1 end end
        check(c.first ~= nil and c.imp0[c.first] and imped >= 2, c.name .. ": the target and another ally are "
          .. "imped (snapshot I)")
        for e = 0, 6, 2 do
          if (c.mask & (1 << (e // 2))) ~= 0 then
            check(c.imp0[e], string.format("%s: entity %d in the mask was imped (the toggle lifts)", c.name, e))
            check(c.impAfter[e] == false, string.format("%s: entity %d is no longer imped after the cast", c.name, e))
          end
        end
      end
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
      local want = math.min((c.boost + 1) * (c.overclock and 2 or 1), c.room)
      if c.overclock then
        check(c.room < 8, c.name .. ": the body has fewer elements left than the eight firings")
      end
      check(added == want, string.format("%s: Debilitator at %d BP added %d weakness(es) ($%02X -> $%02X; want %d "
        .. "of the %d it lacked)", c.name, c.boost, added, c.weak0, c.weakEnd, want, c.room))
      local b0 = byName["debil-b0"].charged
      local wantMp = math.min(99, b0 * (c.boost + 1) * (c.overclock and 2 or 1))
      check(c.charged == wantMp, string.format("%s: charged %d MP, debil-b0 %d (one firing a weakness; want %d)",
        c.name, c.charged, b0, wantMp))
      check(c.listPrice == c.charged, string.format("%s: the Tools list drew %s MP, the charge %d", c.name,
        tostring(c.listPrice), c.charged))
      local wantBank = math.min(5, c.bank0 - c.boost + (c.boost == 0 and 1 or 0))
      check(c.bankEnd == wantBank, string.format("%s: bank %d -> %d (want %d)", c.name, c.bank0, c.bankEnd,
        wantBank))
    end
    if c.sameMp and not c.vanmon then
      -- (Vanish's list draws the reach price: the list cannot know the cursor
      -- will cross to a monster; the charge is its own, checked below)
      check(c.listPrice == byName[c.sameMp].listPrice, string.format("%s: the list drew %s MP with the boost "
        .. "pending, %s %s (its own price)", c.name, tostring(c.listPrice), c.sameMp,
        tostring(byName[c.sameMp].listPrice)))
    end
    if c.keep then
      local base = byName[c.keep]
      check(c.bank0 == base.bank0, c.name .. ": the bank at the command, as in " .. c.keep)
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
