-- @suite
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_boostkeep.lua -- no boost where the boost can buy nothing (#463)
--
-- Boots fire-out-v1 by cold Continue (configure.py TEST_ENV).  By hand:
--   OT6_SRAM_CHECKPOINT=build/checkpoints/fire-out-v1 \
--     tools/tests/run.sh tools/tests/battle_boostkeep.lua <log>
--
-- The rule (the owner; DESIGN.md's BP economy): a boosted action charges
-- nothing, is not allowed a boost, or keeps what was spent; never a refund.
-- Where the menu can name a row the boost buys nothing on, R does not raise
-- one there (Ot6Boost, Ot6RowNoBoost) and its price does not escalate; a
-- boost raised on the command window before such a row was picked is dropped
-- before anything charges it (Ot6KeepBoost).  The rows: Filch and Bestow
-- (Bestow's transfer is its one pip at every boost), an item that moves no
-- number (a status cure, a Fenix Down: Ot6ItemNoBoost), a spell that moves
-- none (TERRA's, chosen off the ROM: Ot6SpellNoBoost); and Def., a command
-- with no list (Ot6CmdNoBoost: Row, Def., Leap, Control, Possess).  So:
--   * <row>-r: R pressed with the cursor on the row leaves the pending at 0
--     (refused) on those rows, at 1 on the controls (Tonic, a multiplied
--     spell);
--   * <row>-b1/b2: raised on the command window, then the row: the bank ends
--     where the unboosted case's does, and the spell's price (drawn and
--     charged) is its own.
-- Where only the resolve can tell the boost found nothing (a Steal on a body
-- already robbed, Appraise with one body standing) it is spent: the bank
-- ends `boost` below where it stood, as the controls' (a Tonic, the
-- multiplied spell, Appraise with two bodies standing) do.
--
-- The run: Continue fire-out-v1 (TERRA LOCKE STRAGO by Thamasa), pace to an
-- encounter on the plain with two or more bodies, one of which carries loot
-- and a shield (the target).  Everyone Defends until LOCKE's window opens
-- with four pips banked and none pending (snapshot L), then on to TERRA's
-- with two (snapshot T).  Each case is one action of LOCKE's (from L) or
-- TERRA's (from T), everyone else Defending.  Then from L LOCKE Steals from
-- the target at 3 BP (certain, Ot6StealBoostLevel), and at his next window
-- with a pip banked comes snapshot R: the body robbed.  From R, TERRA and
-- STRAGO Fight every body but the target while LOCKE Defends, and at his
-- window with the target alone standing comes snapshot A.
-- Nothing is written; everything is observed: the actor's bank, pending and
-- MP around the action (the bank six frames after its Ot6ActionEnd), the
-- spell row's drawn price, whether a Steal rolled (Ot6StealBoostLevel), the
-- bodies Ot6AnalyzeOne read, and the base each Ot6BoostDmg call met.
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F
local ST_CMD, ST_DEF, ST_TGT, ST_LIST, ST_ITEM, ST_MAGIC = 0x05, 0x27, 0x38, 0x30, 0x0A, 0x0E
local KCOL, KROW = 0x8963, 0x8967
local BANK, PEND, CURMP, BATTINV = 0x3E9C, 0x3E9D, 0x3C08, 0x2686
local CMD_FIGHT, CMD_ITEM, CMD_MAGIC, CMD_STEAL = 0x00, 0x01, 0x02, 0x05
local TERRA, LOCKE, STRAGO = 0, 1, 7
-- the thief window's cells: { column, row } (Ot6ThiefRowTbl)
local CELL = { steal = { 0, 0 }, filch = { 0, 1 }, bestow = { 0, 2 }, appraise = { 1, 2 } }
local ROWID = { steal = 0x56, filch = 0x57, bestow = 0x58, appraise = 0xE3 }
local TONIC, FENIX = 0xE8, 0xF0
-- items whose whole effect is a status cure, cheapest first
local CURES = { 0xF2, 0xF3, 0xF4, 0xFB, 0xF8, 0xF1, 0xF5 }
-- Lever, for evidence only (the suite runs BURN 0; a lab sets the global
-- BOOSTKEEP_BURN ahead of the file): run from that many draws first, so the
-- battle measured is a later one (TESTING.md: vary the encounters, not seeds)
local BURN = type(BOOSTKEEP_BURN) == "number" and BOOSTKEEP_BURN or 0
local DRAWS = 12 + BURN

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function pend(s) return H.readByte(PEND + s * 2) end
local function bank(s) return H.readByte(BANK + s * 2) end
local function mp(s) return H.readWord(CURMP + s * 2) end
local function hp(s) return H.readWord(0x3BF4 + s * 2) end
local function shield(m) return H.readByte(0x3E40 + m * 2) end
local function loot(m) return H.readByte(0x3308 + 8 + m * 2), H.readByte(0x3309 + 8 + m * 2) end
local function live(m) return (H.readByte(0x3AA8 + m * 2) & 1) == 1 and H.readWord(0x3BFC + m * 2) > 0 end
local function liveCount() local n = 0 for m = 0, 5 do if live(m) then n = n + 1 end end return n end
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
local lockeS, terraS, stragoS
local actS            -- the slot whose action the case measures
local function chars()
  return string.format("MP L%d bank L%d T%d S%d pend L%d T%d S%d hp T%d", mp(lockeS), bank(lockeS), bank(terraS),
    bank(stragoS), pend(lockeS), pend(terraS), pend(stragoS), hp(terraS))
end
local function mons()
  local t = {}
  for m = 0, 5 do
    if live(m) then
      local r, c = loot(m)
      t[#t + 1] = string.format("m%d hp%d sh%d loot%02X/%02X", m, H.readWord(0x3BFC + m * 2), shield(m), r, c)
    end
  end
  return table.concat(t, " ")
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
  onExec(H.sym("Ot6StealBoostLevel"), function(c)
    if cx() == actS * 2 then
      c.rolled = true
      ev(c, "Ot6StealBoostLevel: the Steal rolls, pend " .. pend(actS))
    end
  end)
  onExec(H.sym("Ot6ThiefExec"), function(c)
    if cx() == actS * 2 then
      c.row = H.readByte(0xB6)
      ev(c, string.format("Ot6ThiefExec b6=$%02X %s | %s", H.readByte(0xB6), chars(), mons()))
    end
  end)
  onExec(H.sym("Ot6AnalyzeOne"), function(c)
    c.read = (c.read or 0) + 1
    ev(c, string.format("Ot6AnalyzeOne reads body %d", ((emu.getState()["cpu.y"] & 0xFF) - 8) // 2))
  end)
  onExec(H.sym("Ot6BoostDmg"), function(c)
    if cx() == actS * 2 then
      ev(c, string.format("Ot6BoostDmg entry: b5=$%02X 3a7c=$%02X base $11B0=%d $11A4=$%02X pend %d",
        H.readByte(0xB5), H.readByte(0x3A7C), H.readWord(0x11B0), H.readByte(0x11A4), pend(actS)))
    end
  end)
  onExec(H.sym("Ot6ActionEnd"), function(c)
    if cx() == actS * 2 then
      c.endF = H.frame
      c.mpEnd = mp(actS)
      ev(c, string.format("Ot6ActionEnd entry: 3a7c=$%02X %s | %s", H.readByte(0x3A7C), chars(), mons()))
    end
  end)
end

-- ---- the menu policy ---------------------------------------------------------
local tick, held = 0, nil
local function defendPress(st)
  if st == ST_CMD then return "right" end
  if st == ST_DEF then return "a" end
  if st == ST_TGT or st == ST_LIST or st == ST_ITEM then return "b" end
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

local tgtMon          -- the body LOCKE's rows aim at: loot and a shield
local cureItem        -- the status cure the bag holds
-- The measured actor's own turn: the case's action at its boost.  c.cmd is
-- Steal (a thief row, c.rowName), Item (c.item) or Magic (c.spell); c.ally
-- aims at the other of LOCKE and TERRA.  c.boost is raised on the command
-- window, before the row is picked; c.rowR presses R once with the cursor on
-- the row (Ot6Boost refuses it on a row the boost buys nothing on, #463).
local function spellIdx(s, id)
  for i = 0, 53 do
    if H.readByte(0x2092 + s * 0x13C + i * 4) == id then return i end
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
  if c.cmd == "defend" then
    -- Def. is the cell right of the command window; it has no list and no
    -- target, so its confirm is the commit
    if st == ST_CMD then
      if pend(s) < c.boost then return "r" end
      if pend(s) > c.boost then return "l" end
      c.mp0, c.bank0, c.pendAtCmd = mp(s), bank(s), pend(s)
      return "right"
    end
    if st == ST_DEF then
      c.sent, c.pendAtConfirm = true, pend(s)
      ev(c, "the measured actor's Def. confirmed: " .. chars() .. " | " .. mons())
      return "a"
    end
    return "b"
  end
  if st == ST_CMD then
    if pend(s) < c.boost then return "r" end
    if pend(s) > c.boost then return "l" end
    local want = cmdRow(s, c.cmd)
    local cur = H.readByte(CMDROW + s) & 3
    if cur ~= want then return cur < want and "down" or "up" end
    c.mp0, c.bank0, c.pendAtCmd = mp(s), bank(s), pend(s)
    return "a"
  end
  if c.cmd == CMD_STEAL and st == ST_LIST then
    local col, row = CELL[c.rowName][1], CELL[c.rowName][2]
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
local function lockeAim(c)
  if H.readByte(MENU) == 0 or H.readByte(MSTATE) ~= ST_TGT or (H.readByte(ACTOR) & 3) ~= actS
     or c.sent then
    mf, tapNo = 0, -1
    return false
  end
  local btn = c.ally and aim(Tc, actS == terraS and lockeS or terraS) or aim(Tm, tgtMon)
  if next(btn) == "a" then
    c.sent = true
    c.pendAtConfirm = pend(actS)
    ev(c, "the measured actor's target confirmed: " .. chars() .. " | " .. mons())
  end
  return btn
end
-- the others' turns: Defend, or (fightOthers) Fight a live body that is not
-- the target
local function othersPress(a, st, fightOthers)
  local other = false
  for m = 0, 5 do if m ~= tgtMon and live(m) then other = true end end
  if not fightOthers or not other or a == actS then return defendPress(st) end
  if st == ST_CMD then
    local want = cmdRow(a, CMD_FIGHT)
    if want == nil then return "right" end
    if pend(a) > 0 then return "l" end
    local cur = H.readByte(CMDROW + a) & 3
    if cur ~= want then return cur < want and "down" or "up" end
    return "a"
  end
  if st == ST_DEF then return "a" end
  return nil
end
local function fightAim()
  if H.readByte(MENU) == 0 or H.readByte(MSTATE) ~= ST_TGT or (H.readByte(ACTOR) & 3) == actS then
    mf, tapNo = 0, -1
    return false
  end
  local want
  for m = 0, 5 do if m ~= tgtMon and live(m) then want = want or m end end
  if want == nil then return { b = true } end
  return aim(Tm, want)
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
      actS = c.who == "T" and terraS or lockeS
      c.sent, c.after, c.endF, c.rolled, c.read, c.row = false, false, nil, false, 0, nil
      c.triedR, c.pendAfterR = false, nil
      c.hp0 = hp(terraS)
      armed = c
      ev(c, "START " .. chars() .. " | " .. mons())
    end),
    H.driveUntil(function() return c.endF ~= nil and H.frame >= c.endF + 120 end, 14000, {
      H.call(function()
        Tm.observe(); Tc.observe()
        if c.endF and not c.after and H.frame >= c.endF + 6 then
          c.after = true
          c.bankEnd = bank(actS)
          c.hpEnd = hp(terraS)
          ev(c, "six frames after the actor's Ot6ActionEnd: " .. chars() .. " | " .. mons())
        end
        local ac = lockeAim(c)
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
      for _, l in ipairs(c.log) do H.log(string.format("[boostkeep] %s: %s", c.name, l)) end
      c.charged = (c.mp0 or 0) - (c.mpEnd or c.mp0 or 0)
      H.log(string.format("[boostkeep] %s RESULT: boost %d (R on the row: %s; pending at confirm %s); %s bank "
        .. "%s at the command -> %s after the turn; MP charged %d; Steal rolled: %s; bodies read %d; "
        .. "TERRA HP %d -> %s", c.name, c.boost, c.rowR and tostring(c.pendAfterR) or "-",
        tostring(c.pendAtConfirm), c.who == "T" and "TERRA" or "LOCKE", tostring(c.bank0), tostring(c.bankEnd),
        c.charged, tostring(c.rolled), c.read, c.hp0, tostring(c.hpEnd)))
    end),
  }
end

-- drive from the current state until LOCKE's window opens with nothing
-- pending and `cond()`; snapshot it as `key`.  `fightOthers`: TERRA and
-- STRAGO Fight every body but the target meanwhile.  `first`: LOCKE's
-- first window takes this action (a case table) before anything else.
local function snapAt(key, cond, fightOthers, first, who)
  return {
    H.call(function()
      actS = who and who() or lockeS
      tick, held, mf, tapNo = 0, nil, 0, -1
      if first then first.log, first.sent = {}, false; armed = first end
    end),
    H.driveUntil(function() return snaps[key] ~= nil end, 30000, {
      H.call(function()
        Tm.observe(); Tc.observe()
        assert(H.battleLoadStarted(), "the battle is still up while snapshot " .. key .. " is sought")
        if first and not first.sent then
          local ac = lockeAim(first)
          if ac then H.setPad(ac) return end
        end
        if fightOthers then
          local ac = fightAim()
          if ac then H.setPad(ac) return end
        end
        tick = tick + 1
        if tick % 12 == 6 then H.setPad({}) return end
        if tick % 12 ~= 0 then return end
        if H.readByte(MENU) == 0 then return end
        local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
        if a == actS and first and not first.sent then
          local b = actorPress(first, st)
          H.setPad(b and { [b] = true } or {})
          return
        end
        if a == actS and st == ST_CMD and pend(actS) == 0 and cond() then
          H.setPad({}); snaps[key] = H.requestSaveState()
          H.log(string.format("[boostkeep] snapshot %s f%d: %s | %s", key, H.frame, chars(), mons()))
          return
        end
        local b = othersPress(a, st, fightOthers)
        H.setPad(b and { [b] = true } or {})
      end),
    }, "snapshot " .. key),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(snaps[key], "snapshot " .. key)
      if first then
        armed = nil
        for _, l in ipairs(first.log) do H.log(string.format("[boostkeep] %s: %s", first.name, l)) end
      end
    end),
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
    H.assertEntryContract("fire-out-v1")
    local have = {}
    for _, c in ipairs(members()) do have[c] = true end
    assert(have[TERRA] and have[LOCKE] and have[STRAGO], "TERRA, LOCKE and STRAGO are in the party")
    installObservers()
  end),
  (function()
    local P = H.newPacer({ tag = "boostkeep pace" })
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
          for s = 0, 3 do
            local id = H.readByte(0x3ED8 + s * 2)
            if id == TERRA then terraS = s end
            if id == LOCKE then lockeS = s end
            if id == STRAGO then stragoS = s end
          end
          -- the target: a body that carries loot and has a shield on, the
          -- one with the most HP; and another body beside it
          local best
          for m = 0, 5 do
            local r, cm = loot(m)
            if live(m) and shield(m) > 0 and (r ~= 0xFF or cm ~= 0xFF) then
              if best == nil or H.readWord(0x3BFC + m * 2) > H.readWord(0x3BFC + best * 2) then best = m end
            end
          end
          local ids = H.monsterIds()
          local names = {}
          for m = 0, 5 do names[#names + 1] = string.format("%d:%04X", m, ids[m + 1]) end
          local ok = best ~= nil and liveCount() >= 2 and try > BURN
          H.log(string.format("[boostkeep] draw %d: monsters %s | %s -> %s", try, table.concat(names, " "),
            mons(), ok and ("target m" .. best) or "no target with a body beside it (run)"))
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
      assert(measured, "a draw with two or more bodies, one carrying loot and a shield")
    end)
    return H.repeatN(1, steps)
  end)(),
  H.call(function()
    for _, id in ipairs(CURES) do if cureItem == nil and bagIdx(id) then cureItem = id end end
    local bag = {}
    for _, id in ipairs({ TONIC, FENIX, table.unpack(CURES) }) do
      local i = bagIdx(id)
      bag[#bag + 1] = string.format("$%02X:%s", id, i and tostring(H.readByte(BATTINV + i * 5 + 3)) or "-")
    end
    H.log(string.format("[boostkeep] battle slots: LOCKE %d TERRA %d STRAGO %d; bag %s; the cure $%s; %s | %s",
      lockeS, terraS, stragoS, table.concat(bag, " "), cureItem and string.format("%02X", cureItem) or "none",
      chars(), mons()))
    assert(cmdRow(lockeS, CMD_STEAL) and cmdRow(lockeS, CMD_ITEM), "LOCKE's battle list has Steal and Item")
    assert(bagIdx(TONIC) and bagIdx(FENIX), "the bag holds a Tonic and a Fenix Down")
    assert(cureItem, "the bag holds an item whose effect is a status cure")
  end),
}
local function add(t) for _, s in ipairs(t) do steps[#steps + 1] = s end end

-- TERRA's two spells, read off the ROM as Ot6SpellNoBoost reads it: one the
-- boost buys nothing on (not a tier family, not Scan, power 0 or a fraction
-- of HP/MP), one it multiplies (power, no fraction, not a tier family)
local quiet, loud
steps[#steps + 1] = H.call(function()
  local mpb, fold = H.sym("MagicProp") & 0x3FFFFF, H.sym("Ot6FoldTbl") & 0x3FFFFF
  local inFold = {}
  for i = 0, 0x17 do inFold[H.readRomByte(fold + i)] = true end
  inFold[0x0C] = true                     -- Break (Ot6InFoldTbl's own arm)
  local names = {}
  for i = 0, 53 do
    local id = H.readByte(0x2092 + terraS * 0x13C + i * 4)
    if id ~= 0xFF and not inFold[id] and id ~= 0x18 then
      local flags, power = H.readRomByte(mpb + id * 14 + 4), H.readRomByte(mpb + id * 14 + 6)
      local none = (flags & 0x80) ~= 0 or power == 0
      if none and quiet == nil then quiet = id end
      if not none and loud == nil then loud = id end
      names[#names + 1] = string.format("$%02X%s", id, none and "-" or "+")
    end
  end
  H.log(string.format("[boostkeep] TERRA's spells (- buys nothing, + the multiplier): %s; quiet $%s, loud $%s",
    table.concat(names, " "), quiet and string.format("%02X", quiet) or "none",
    loud and string.format("%02X", loud) or "none"))
  assert(quiet and loud, "TERRA knows a spell the boost buys nothing on and one it multiplies")
end)

-- snapshot L: LOCKE's window, four pips banked
add(snapAt("L", function() return bank(lockeS) >= 4 end))
-- snapshot T: on from L, TERRA's window with two pips banked
add(snapAt("T", function() return bank(terraS) >= 2 end, false, nil, function() return terraS end))
-- snapshot R: from L, LOCKE robs the target at 3 BP (certain); his next
-- window with a pip banked and the target standing
local rob = { name = "rob-b3", cmd = CMD_STEAL, rowName = "steal", boost = 3 }
add({ H.call(function()
  local req = H.requestLoadState(snaps.L.blob)
  H.vars.robReq = req
end), H.waitFrames(2), H.call(function()
  H.checkReq(H.vars.robReq, "snapshot load (rob)")
  H.rearmInputInjection()
end) })
add(snapAt("R", function()
  local r, cm = loot(tgtMon)
  return bank(lockeS) >= 1 and live(tgtMon) and r == 0xFF and cm == 0xFF
end, false, rob))
-- snapshot A: from R, every body but the target falls to TERRA and STRAGO
add(snapAt("A", function() return bank(lockeS) >= 1 and live(tgtMon) and liveCount() == 1 end, true))

-- keep: the boosted case's bank ends where the unboosted case's does.
-- spend: the boosted case's bank ends `boost` below where it stood (no regen)
local CASES = {
  { name = "filch-b0",     snap = "L", cmd = CMD_STEAL, rowName = "filch",    boost = 0 },
  { name = "filch-b1",     snap = "L", cmd = CMD_STEAL, rowName = "filch",    boost = 1, keep = "filch-b0" },
  { name = "filch-r",      snap = "L", cmd = CMD_STEAL, rowName = "filch",    boost = 0, rowR = 0 },
  { name = "bestow-b0",    snap = "L", cmd = CMD_STEAL, rowName = "bestow",   boost = 0, ally = true },
  { name = "bestow-b1",    snap = "L", cmd = CMD_STEAL, rowName = "bestow",   boost = 1, ally = true,
    keep = "bestow-b0" },
  { name = "bestow-b2",    snap = "L", cmd = CMD_STEAL, rowName = "bestow",   boost = 2, ally = true,
    keep = "bestow-b0" },
  { name = "bestow-r",     snap = "L", cmd = CMD_STEAL, rowName = "bestow",   boost = 0, ally = true, rowR = 0 },
  { name = "appraise2-b1", snap = "L", cmd = CMD_STEAL, rowName = "appraise", boost = 1, spend = true },
  { name = "tonic-b0",     snap = "L", cmd = CMD_ITEM, item = TONIC, boost = 0, ally = true },
  { name = "tonic-b1",     snap = "L", cmd = CMD_ITEM, item = TONIC, boost = 1, ally = true, spend = true },
  { name = "tonic-r",      snap = "L", cmd = CMD_ITEM, item = TONIC, boost = 0, ally = true, rowR = 1,
    spend = true },
  { name = "cure-b0",      snap = "L", cmd = CMD_ITEM, item = "cure", boost = 0, ally = true },
  { name = "cure-b1",      snap = "L", cmd = CMD_ITEM, item = "cure", boost = 1, ally = true, keep = "cure-b0" },
  { name = "cure-r",       snap = "L", cmd = CMD_ITEM, item = "cure", boost = 0, ally = true, rowR = 0 },
  { name = "fenix-b0",     snap = "L", cmd = CMD_ITEM, item = FENIX, boost = 0, ally = true },
  { name = "fenix-b1",     snap = "L", cmd = CMD_ITEM, item = FENIX, boost = 1, ally = true, keep = "fenix-b0" },
  { name = "fenix-r",      snap = "L", cmd = CMD_ITEM, item = FENIX, boost = 0, ally = true, rowR = 0 },
  { name = "quiet-b0",     snap = "T", who = "T", cmd = CMD_MAGIC, spell = "quiet", boost = 0, ally = true },
  { name = "quiet-b1",     snap = "T", who = "T", cmd = CMD_MAGIC, spell = "quiet", boost = 1, ally = true,
    keep = "quiet-b0", sameMp = "quiet-b0" },
  { name = "quiet-r",      snap = "T", who = "T", cmd = CMD_MAGIC, spell = "quiet", boost = 0, ally = true,
    rowR = 0 },
  { name = "loud-b0",      snap = "T", who = "T", cmd = CMD_MAGIC, spell = "loud", boost = 0 },
  { name = "loud-b1",      snap = "T", who = "T", cmd = CMD_MAGIC, spell = "loud", boost = 1, spend = true,
    moreMp = "loud-b0" },
  { name = "loud-r",       snap = "T", who = "T", cmd = CMD_MAGIC, spell = "loud", boost = 0, rowR = 1,
    spend = true },
  { name = "defend-b0",    snap = "L", cmd = "defend", boost = 0 },
  { name = "defend-b1",    snap = "L", cmd = "defend", boost = 1, keep = "defend-b0" },
  { name = "steal-b0",     snap = "R", cmd = CMD_STEAL, rowName = "steal",    boost = 0 },
  { name = "steal-b1",     snap = "R", cmd = CMD_STEAL, rowName = "steal",    boost = 1, spend = true },
  { name = "appraise1-b0", snap = "A", cmd = CMD_STEAL, rowName = "appraise", boost = 0 },
  { name = "appraise1-b1", snap = "A", cmd = CMD_STEAL, rowName = "appraise", boost = 1, spend = true },
}
local byName = {}
for _, c in ipairs(CASES) do
  byName[c.name] = c
  steps[#steps + 1] = H.call(function()
    if c.item == "cure" then c.item = cureItem end
    if c.spell == "quiet" then c.spell = quiet elseif c.spell == "loud" then c.spell = loud end
  end)
  add(runCase(c))
end

steps[#steps + 1] = H.call(function()
  local bad = {}
  local function check(ok, msg)
    H.log(string.format("[boostkeep] %s %s", ok and "ok:" or "FAIL:", msg))
    if not ok then bad[#bad + 1] = msg end
  end
  for _, c in ipairs(CASES) do
    -- what the case played: the actor's action, at the case's boost; R on
    -- the row raised it (rowR = 1) or was refused (rowR = 0)
    if c.rowR then
      H.assertEq(c.pendBeforeR, 0, c.name .. ": nothing pending when R was pressed on the row")
      check(c.pendAfterR == c.rowR, string.format("%s: R on the row left the pending at %s (%s)", c.name,
        tostring(c.pendAfterR), c.rowR == 0 and "refused: the boost buys nothing here" or "raised: it buys"))
      c.boost = c.pendAfterR or c.boost
    end
    H.assertEq(c.pendAtConfirm, c.boost, c.name .. ": the pending at the confirm")
    if c.rowName then H.assertEq(c.row, ROWID[c.rowName], c.name .. ": LOCKE ran the row") end
    if c.rowName == "steal" then
      H.assertEq(c.rolled, false, c.name .. ": the Steal met a body with nothing left (the 3-BP Steal took it)")
    end
    if c.sameMp then
      check(c.listPrice == byName[c.sameMp].listPrice, string.format("%s: the list drew %s MP with the boost "
        .. "pending, %s %s (no escalated price)", c.name, tostring(c.listPrice), c.sameMp,
        tostring(byName[c.sameMp].listPrice)))
      check(c.charged == byName[c.sameMp].charged, string.format("%s: charged %d MP, %s %d (no escalated price)",
        c.name, c.charged, c.sameMp, byName[c.sameMp].charged))
    end
    if c.moreMp then
      check((c.listPrice or 0) > (byName[c.moreMp].listPrice or 0), string.format("%s: the list drew %s MP with "
        .. "the boost pending, %s %s", c.name, tostring(c.listPrice), c.moreMp, tostring(byName[c.moreMp].listPrice)))
      check(c.charged > byName[c.moreMp].charged, string.format("%s: charged %d MP, %s %d (the price escalates)",
        c.name, c.charged, c.moreMp, byName[c.moreMp].charged))
    end
    if c.rowName == "appraise" then
      if c.snap == "A" then
        H.assertEq(c.read, 1, c.name .. ": Appraise read the one body standing")
      else
        check(c.read >= 2, string.format("%s: the boosted Appraise read %d bodies (every one standing)", c.name,
          c.read))
      end
    end
    if c.keep then
      local base = byName[c.keep]
      H.assertEq(c.bank0, base.bank0, c.name .. ": the bank at the command, as in " .. c.keep)
      check(c.bankEnd == base.bankEnd, string.format("%s: the bank ended at %d, %s's at %d "
        .. "(a boost that buys nothing is never charged)", c.name, c.bankEnd, c.keep, base.bankEnd))
    elseif c.spend then
      check(c.bankEnd == c.bank0 - c.boost, string.format("%s: the bank went %d -> %d, "
        .. "%d spent and no regen (a boost spent, whatever it found)", c.name, c.bank0, c.bankEnd, c.boost))
    end
  end
  assert(#bad == 0, #bad .. " boost-keep assertion(s) failed: " .. table.concat(bad, "; "))
  H.log("[boostkeep] VERDICT: R refused on every row the boost buys nothing on, and a boost raised before such "
    .. "a row (or Def.) never charged; Tonic's, the multiplied spell's, Appraise's and a Steal's on a robbed body "
    .. "spent")
end)

H.run({ maxFrames = 600000 }, steps)
