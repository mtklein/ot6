-- @suite
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_mimicboost.lua -- a boosted Mimic of an action its boost cannot buy
-- into keeps the boost  (#461; the thief rows' cost, #261)
--
-- Boots fire-out-v1 by cold Continue (configure.py TEST_ENV).  By hand:
--   OT6_SRAM_CHECKPOINT=build/checkpoints/fire-out-v1 \
--     tools/tests/run.sh tools/tests/battle_mimicboost.lua <log>
--
-- Mimic is a free copy in all circumstances (the owner, #461): its boost
-- buys what a boost buys on the copied action, and where the copy cannot use
-- it the pending boost is kept, the bank untouched and the turn's regen pip
-- earned (Ot6KeepBoost and its callers; ot6_boost.asm).  So a boosted
-- copy of these ends with the copier's bank where the unboosted copy of the
-- same action from the same snapshot ends:
--   * Filch and Bestow (cmd $05): neither reads a boost.  Bestow hands one
--     pip over and charges exactly that one, and a refused one charges
--     nothing, so the boosted case is at 2.  Here the copy meets TERRA at
--     the 5 cap (LOCKE's own Bestow and her regen put her there), so it is
--     the refusal that is measured (battle_boostkeep plays the transfer);
--   * Steal on a body with nothing left to take: no roll, so no ladder;
--   * SwdTech: the source's boost bought the tech at its own menu;
--   * Slot, a reel result: the source's boost bought the rig at its spin;
--   * an Item that moves no number, a status cure (#465), and a spell that
--     moves none (TERRA's, chosen off the ROM): the boost buys nothing on
--     them (Ot6ItemNoBoost in Ot6ActionEnd, Ot6SpellNoBoost in Ot6MimicKeep).
-- The controls: a copied Trickshot (cmd $05 too) and a copied Tonic take
-- the multiplier, so their boost is spent: the bank ends one below where it
-- stood, no regen.  And every copy is free of MP.  Main at 7b4f90ec fails
-- every keep assertion but Bestow's at 1 (Bestow already charged its one pip
-- there): build/attempts/wt/v035-boost-scope/; the Item cases' red is
-- build/attempts/wt/v036-boost/.
--
-- DECLARED EXPEDIENT (tools/state_write_waivers.txt), the battle_mimic one:
-- no fixture has a Mimic beside LOCKE, nor anyone beside a Mimic with SwdTech
-- and Slot (GOGO joins in the World of Ruin).  So after the cold Continue and
-- before the first step this writes three command bytes in the field
-- character records ($1600 + 37*id + $16..$19): STRAGO's second command
-- becomes Mimic ($12), TERRA's second (Morph) SwdTech ($07) and her first
-- (Fight) Slot ($0f), so she keeps Magic (#463's copied spell).  Battle init
-- builds the command lists from them;
-- everything after is the engine's own: the menus, the queue, the copy, the
-- charge.  LOCKE is the thief rows' source (his real list), TERRA the
-- SwdTech, Slot, Item and Magic source, STRAGO the copier.  A mechanism test, not play,
-- and not a claim about GOGO's balance.
--
-- The run: Continue fire-out-v1 (TERRA LOCKE STRAGO by Thamasa), pace to an
-- encounter on the plain whose bodies carry loot and a shield, Defend until
-- LOCKE's window opens with LOCKE and STRAGO holding two pips (snapshot L),
-- then on to TERRA's (snapshot T).  Per case restore the source's snapshot:
-- the source plays the row (LOCKE boosts his Steal by 3, which makes the
-- take certain at any level, Ot6StealBoostLevel, so the copy meets a body
-- with nothing left; snapshot L waits for his third pip) and
-- everyone else Defends; once the source's SaveForMimic has run, STRAGO
-- presses R to the case's boost, picks Mimic, and confirms its target.
-- Observed, never written: the copy (mimicreplace), the copier's MP and
-- bank around it, whether the copied Steal rolled (Ot6StealBoostLevel for
-- the copier), and the bank six frames after the copier's Ot6ActionEnd.
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F
local ST_CMD, ST_DEF, ST_TGT, ST_LIST, ST_SWD, ST_REELS = 0x05, 0x27, 0x38, 0x30, 0x37, 0x08
local KCOL, KROW = 0x8963, 0x8967
local BANK, PEND, CURMP = 0x3E9C, 0x3E9D, 0x3C08
local CMD_ITEM, CMD_MAGIC, CMD_STEAL, CMD_SWDTECH, CMD_SLOT, CMD_MIMIC = 0x01, 0x02, 0x05, 0x07, 0x0F, 0x12
local ST_ITEM, ST_MAGIC, BATTINV = 0x0A, 0x0E, 0x2686
-- TERRA's spell the boost buys nothing on (#463), read off the ROM as
-- Ot6SpellNoBoost reads it: not a tier family, not Break or Scan, power 0
-- or a fraction of HP/MP
local quiet
local function quietSpell(s)
  local mpb, fold = H.sym("MagicProp") & 0x3FFFFF, H.sym("Ot6FoldTbl") & 0x3FFFFF
  local inFold = { [0x0C] = true, [0x18] = true }
  for i = 0, 0x17 do inFold[H.readRomByte(fold + i)] = true end
  for i = 0, 53 do
    local id = H.readByte(0x2092 + s * 0x13C + i * 4)
    if id ~= 0xFF and not inFold[id] then
      local flags, power = H.readRomByte(mpb + id * 14 + 4), H.readRomByte(mpb + id * 14 + 6)
      if (flags & 0x80) ~= 0 or power == 0 then return id, i end
    end
  end
end
local TONIC, ANTIDOTE = 0xE8, 0xF2
local TERRA, LOCKE, STRAGO = 0, 1, 7
-- the thief window's cells: { column, row } (Ot6ThiefRowTbl)
local CELL = { steal = { 0, 0 }, filch = { 0, 1 }, bestow = { 0, 2 }, trick = { 1, 0 } }
local ROWID = { steal = 0x56, filch = 0x57, bestow = 0x58, trick = 0xE1 }
local DRAWS = 12

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function pend(s) return H.readByte(PEND + s * 2) end
local function bank(s) return H.readByte(BANK + s * 2) end
local function mp(s) return H.readWord(CURMP + s * 2) end
local function shield(m) return H.readByte(0x3E40 + m * 2) end
local function loot(m) return H.readByte(0x3308 + 8 + m * 2), H.readByte(0x3309 + 8 + m * 2) end
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
local function recCmd(c, r) return 0x1600 + 37 * c + 0x16 + r end
local lockeS, standS, terraS
local function chars()
  return string.format("MP L%d S%d T%d bank L%d S%d T%d pend L%d S%d T%d", mp(lockeS), mp(standS), mp(terraS),
    bank(lockeS), bank(standS), bank(terraS), pend(lockeS), pend(standS), pend(terraS))
end
local function mons()
  local t = {}
  for m = 0, 5 do
    if H.readWord(0x3BFC + m * 2) > 0 then
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
    emu.addMemoryCallback(function() if armed and not armed.endF then fn(armed) end end,
      emu.callbackType.exec, a, a)
  end
  onExec(H.sym("SaveForMimic"), function(c)
    if cx() == c.srcS * 2 then
      c.srcSaved, c.srcDone = c.srcSaved + 1, true
      ev(c, string.format("SaveForMimic (source) 3a7c=$%04X 3a30=$%04X", H.readWord(0x3A7C), H.readWord(0x3A30)))
    end
  end)
  onExec(H.sym("mimicreplace"), function(c)
    if cx() ~= standS * 2 then return end
    c.inStand = true
    c.copyCmd, c.copyAtk = H.readByte(0x3F20), H.readByte(0x3F21)
    c.bankCopy, c.pendCopy = bank(standS), pend(standS)
    ev(c, string.format("mimicreplace (copier): 3f20=$%04X 3f22=$%04X %s | %s", H.readWord(0x3F20),
      H.readWord(0x3F22), chars(), mons()))
  end)
  onExec(H.sym("Ot6StealBoostLevel"), function(c)
    if c.inStand and cx() == standS * 2 then
      c.rolled = true
      ev(c, "Ot6StealBoostLevel (copier): the copied Steal rolls, pend " .. pend(standS))
    end
  end)
  onExec(H.sym("Ot6ThiefExec"), function(c)
    if cx() == standS * 2 then
      c.standRow = H.readByte(0xB6)
      ev(c, string.format("Ot6ThiefExec (copier) b6=$%02X %s | %s", H.readByte(0xB6), chars(), mons()))
    end
  end)
  onExec(H.sym("Ot6ActionEnd"), function(c)
    if c.inStand and cx() == standS * 2 then
      c.endF = H.frame
      c.mpEnd = mp(standS)
      ev(c, string.format("Ot6ActionEnd (copier) entry: 3a7c=$%02X %s | %s", H.readByte(0x3A7C), chars(), mons()))
    end
  end)
end

-- ---- the menu policy ---------------------------------------------------------
local tick, held = 0, nil
local function defendPress(st)
  if st == ST_CMD then return "right" end
  if st == ST_DEF then return "a" end
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

local tgtMon          -- the monster slot LOCKE's rows aim at
-- the source's own turn: LOCKE's thief row, or TERRA's SwdTech or Slot
local function sourcePress(c, st)
  local s = c.srcS
  if st == ST_CMD then
    if pend(s) < c.srcBoost then return "r" end
    local want = cmdRow(s, c.cmd)
    local cur = H.readByte(CMDROW + s) & 3
    if cur ~= want then return cur < want and "down" or "up" end
    c.srcMp0 = mp(s)
    return "a"
  end
  if c.cmd == CMD_STEAL and st == ST_LIST then
    local col, row = CELL[c.row][1], CELL[c.row][2]
    local cc, cr = H.readByte(KCOL + s), H.readByte(KROW + s)
    if cc ~= col then return cc < col and "right" or "left" end
    if cr ~= row then return cr < row and "down" or "up" end
    return "a"
  end
  if c.cmd == CMD_SWDTECH and (st == ST_LIST or st == ST_SWD) then return "a" end
  if c.cmd == CMD_MAGIC and st == ST_MAGIC then
    local _, i = quietSpell(s)
    if i == nil then return "b" end
    local ar = H.readByte(0x8913 + s) + H.readByte(0x891B + s)
    local col = H.readByte(0x8917 + s)
    if ar ~= i // 2 then return ar < i // 2 and "down" or "up" end
    if col ~= i % 2 then return col < i % 2 and "right" or "left" end
    return "a"
  end
  if c.cmd == CMD_ITEM and st == ST_ITEM then
    local want = bagIdx(c.item)
    if want == nil then return "b" end
    local cur = H.readByte(0x8947 + s) + H.readByte(0x894F + s)
    if cur ~= want then return cur < want and "down" or "up" end
    return "a"
  end
  if c.cmd == CMD_SLOT and st == ST_REELS then return "a" end
  if c.cmd ~= CMD_STEAL and st == ST_TGT then return "a" end
  return nil
end
local function decide(c)
  if H.readByte(MENU) == 0 then return nil end
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if a == c.srcS and not c.srcDone then return sourcePress(c, st) end
  if a == standS and not c.mimicSent then
    if c.srcSaved < 1 then return nil end            -- the source's action has not resolved
    if st == ST_TGT then
      c.mp0, c.pendAtConfirm, c.bank0 = mp(standS), pend(standS), bank(standS)
      ev(c, string.format("copier's Mimic target confirmed: %s", chars()))
      c.mimicSent = true
      return "a"
    end
    if st ~= ST_CMD then return nil end
    if pend(standS) < c.boost then return "r" end
    local want = cmdRow(standS, CMD_MIMIC)
    local cur = H.readByte(CMDROW + standS) & 3
    if cur ~= want then return cur < want and "down" or "up" end
    return "a"
  end
  if a == standS and c.mimicSent and st == ST_TGT then return "a" end
  return defendPress(st)
end

-- the target window of LOCKE's own pick
local function lockeAim(c)
  if c.cmd ~= CMD_STEAL or H.readByte(MENU) == 0 or H.readByte(MSTATE) ~= ST_TGT
     or (H.readByte(ACTOR) & 3) ~= lockeS or c.srcDone or c.tgtConfirmed then
    mf, tapNo = 0, -1
    return false
  end
  local btn = c.row == "bestow" and aim(Tc, terraS) or aim(Tm, tgtMon)
  if next(btn) == "a" then c.tgtConfirmed = true end
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
      c.srcS = c.snap == "L" and lockeS or terraS
      c.log = {}
      c.srcSaved, c.srcDone, c.mimicSent, c.after, c.tgtConfirmed = 0, false, false, false, false
      c.endF, c.inStand, c.rolled = nil, false, false
      armed = c
      ev(c, "START " .. chars() .. " | " .. mons())
    end),
    H.driveUntil(function() return c.endF ~= nil and H.frame >= c.endF + 120 end, 14000, {
      H.call(function()
        Tm.observe(); Tc.observe()
        if c.endF and not c.after and H.frame >= c.endF + 6 then
          c.after = true
          c.bankEnd = bank(standS)
          ev(c, "six frames after the copier's Ot6ActionEnd: " .. chars() .. " | " .. mons())
        end
        local ac = lockeAim(c)
        if ac then held = nil; H.setPad(ac) return end
        tick = tick + 1
        local ph = tick % 12
        if ph == 0 then held = decide(c) end
        H.setPad((held and ph < 6) and { [held] = true } or {})
      end),
    }, "case " .. c.name .. " resolves"),
    H.call(function()
      armed = nil
      H.setPad({})
      for _, l in ipairs(c.log) do H.log(string.format("[mimicboost] %s: %s", c.name, l)) end
      c.charged = (c.mp0 or 0) - (c.mpEnd or c.mp0 or 0)
      H.log(string.format("[mimicboost] %s RESULT: copy $%02X/$%02X at boost %d (pending at confirm %s); "
        .. "copier bank %s at confirm -> %s after its turn; MP charged %d; copied Steal rolled: %s",
        c.name, c.copyCmd or 0xFF, c.copyAtk or 0xFF, c.boost, tostring(c.pendAtConfirm), tostring(c.bank0),
        tostring(c.bankEnd), c.charged, tostring(c.rolled)))
    end),
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
    local o1, o2, o3 = H.readByte(recCmd(STRAGO, 1)), H.readByte(recCmd(TERRA, 1)), H.readByte(recCmd(TERRA, 0))
    H.writeByte(recCmd(STRAGO, 1), CMD_MIMIC)
    H.writeByte(recCmd(TERRA, 1), CMD_SWDTECH)
    H.writeByte(recCmd(TERRA, 0), CMD_SLOT)
    H.log(string.format("[mimicboost] EXPEDIENT: STRAGO command row 1 $%02X -> $12 (Mimic); TERRA row 1 "
      .. "$%02X -> $07 (SwdTech), row 0 $%02X -> $0F (Slot)", o1, o2, o3))
    installObservers()
  end),
  (function()
    local P = H.newPacer({ tag = "mimicboost pace" })
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
            if id == STRAGO then standS = s end
          end
          -- a body that carries loot and has a shield on: Steal and Filch both show
          local best
          for m = 0, 5 do
            local r, cm = loot(m)
            if H.readWord(0x3BFC + m * 2) > 0 and shield(m) > 0 and (r ~= 0xFF or cm ~= 0xFF) then
              if best == nil or H.readWord(0x3BF4 + (4 + m) * 2) > H.readWord(0x3BF4 + (4 + best) * 2) then best = m end
            end
          end
          local ids = H.monsterIds()
          local names = {}
          for m = 0, 5 do names[#names + 1] = string.format("%d:%04X", m, ids[m + 1]) end
          H.log(string.format("[mimicboost] draw %d: monsters %s | %s -> target %s", try,
            table.concat(names, " "), mons(), best and ("m" .. best) or "none (run)"))
          if best then tgtMon = best; measured = true end
        end),
        H.cond(function() return measured end, {}, {
          H.fleeBattle(9000, { onCantRun = "fight" }),
          H.waitUntil(function() return H.worldMode() and H.worldHasControl() end, 1200,
            "back on the world map after running from draw " .. try, 10),
          H.waitFrames(30),
        }),
      })
    end
    steps[#steps + 1] = H.call(function() assert(measured, "a draw with a body that carries loot and a shield") end)
    return H.repeatN(1, steps)
  end)(),
  H.call(function()
    H.log(string.format("[mimicboost] battle slots: LOCKE %d STRAGO(copier) %d TERRA %d; %s | %s",
      lockeS, standS, terraS, chars(), mons()))
    assert(cmdRow(standS, CMD_MIMIC), "the copier's battle list has Mimic")
    assert(cmdRow(lockeS, CMD_STEAL), "LOCKE's battle list has Steal")
    assert(cmdRow(terraS, CMD_SWDTECH) and cmdRow(terraS, CMD_SLOT), "TERRA's battle list has SwdTech and Slot")
    assert(cmdRow(terraS, CMD_ITEM), "TERRA's battle list has Item")
    quiet = quietSpell(terraS)
    H.log(string.format("[mimicboost] TERRA's spell the boost buys nothing on: %s",
      quiet and string.format("$%02X", quiet) or "none"))
    assert(quiet, "TERRA knows a spell the boost buys nothing on")
    assert(bagIdx(TONIC) and bagIdx(ANTIDOTE), "the bag holds a Tonic and an Antidote")
  end),
}
-- the two snapshots: LOCKE's window, then TERRA's, each with the source's
-- pending at 0 and the copier holding two pips (and LOCKE, who boosts his
-- Steal by 3, three); everyone else Defends meanwhile
local function snapAt(key, who)
  return H.driveUntil(function() return snaps[key] ~= nil end, 20000, {
    H.call(function()
      tick = tick + 1
      if tick % 12 ~= 0 and tick % 12 ~= 6 then return end
      if tick % 12 == 6 then H.setPad({}) return end
      local s = who()
      if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD and (H.readByte(ACTOR) & 3) == s
         and pend(s) == 0 and bank(standS) >= 2 and bank(lockeS) >= 3 then
        H.setPad({}); snaps[key] = H.requestSaveState()
        H.log(string.format("[mimicboost] snapshot %s f%d: %s | %s", key, H.frame, chars(), mons()))
        return
      end
      if H.readByte(MENU) == 0 then return end
      local b = defendPress(H.readByte(MSTATE))
      H.setPad(b and { [b] = true } or {})
    end),
  }, "snapshot " .. key)
end
steps[#steps + 1] = snapAt("L", function() return lockeS end)
steps[#steps + 1] = H.waitFrames(2)
steps[#steps + 1] = H.call(function() H.checkReq(snaps.L, "snapshot L") end)
steps[#steps + 1] = H.waitFrames(30)
steps[#steps + 1] = snapAt("T", function() return terraS end)
steps[#steps + 1] = H.waitFrames(2)
steps[#steps + 1] = H.call(function() H.checkReq(snaps.T, "snapshot T") end)

-- keep: the boosted copy's bank ends where the unboosted copy's does.
-- spend: the boosted copy's bank ends `boost` below where it stood (no regen)
local CASES = {
  { name = "steal-b0",   snap = "L", cmd = CMD_STEAL, row = "steal",  srcBoost = 3, boost = 0 },
  { name = "steal-b1",   snap = "L", cmd = CMD_STEAL, row = "steal",  srcBoost = 3, boost = 1, keep = "steal-b0" },
  { name = "filch-b0",   snap = "L", cmd = CMD_STEAL, row = "filch",  srcBoost = 0, boost = 0 },
  { name = "filch-b1",   snap = "L", cmd = CMD_STEAL, row = "filch",  srcBoost = 0, boost = 1, keep = "filch-b0" },
  { name = "bestow-b0",  snap = "L", cmd = CMD_STEAL, row = "bestow", srcBoost = 0, boost = 0 },
  { name = "bestow-b2",  snap = "L", cmd = CMD_STEAL, row = "bestow", srcBoost = 0, boost = 2, keep = "bestow-b0" },
  { name = "trick-b0",   snap = "L", cmd = CMD_STEAL, row = "trick",  srcBoost = 0, boost = 0 },
  { name = "trick-b1",   snap = "L", cmd = CMD_STEAL, row = "trick",  srcBoost = 0, boost = 1, spend = true },
  { name = "swdtech-b0", snap = "T", cmd = CMD_SWDTECH, srcBoost = 0, boost = 0 },
  { name = "swdtech-b1", snap = "T", cmd = CMD_SWDTECH, srcBoost = 0, boost = 1, keep = "swdtech-b0" },
  { name = "slot-b0",    snap = "T", cmd = CMD_SLOT, srcBoost = 0, boost = 0 },
  { name = "slot-b1",    snap = "T", cmd = CMD_SLOT, srcBoost = 0, boost = 1, keep = "slot-b0" },
  { name = "tonic-b0",   snap = "T", cmd = CMD_ITEM, item = TONIC, srcBoost = 0, boost = 0 },
  { name = "tonic-b1",   snap = "T", cmd = CMD_ITEM, item = TONIC, srcBoost = 0, boost = 1, spend = true },
  { name = "cure-b0",    snap = "T", cmd = CMD_ITEM, item = ANTIDOTE, srcBoost = 0, boost = 0 },
  { name = "cure-b1",    snap = "T", cmd = CMD_ITEM, item = ANTIDOTE, srcBoost = 0, boost = 1, keep = "cure-b0" },
  { name = "quiet-b0",   snap = "T", cmd = CMD_MAGIC, srcBoost = 0, boost = 0 },
  { name = "quiet-b1",   snap = "T", cmd = CMD_MAGIC, srcBoost = 0, boost = 1, keep = "quiet-b0" },
}
local byName = {}
for _, c in ipairs(CASES) do
  byName[c.name] = c
  for _, s in ipairs(runCase(c)) do steps[#steps + 1] = s end
end

steps[#steps + 1] = H.call(function()
  local bad = {}
  local function check(ok, msg)
    H.log(string.format("[mimicboost] %s %s", ok and "ok:" or "FAIL:", msg))
    if not ok then bad[#bad + 1] = msg end
  end
  for _, c in ipairs(CASES) do
    -- what the case played: the copy is the source's action, at the case's boost
    H.assertEq(c.copyCmd, c.cmd, c.name .. ": the copied command")
    if c.row then H.assertEq(c.standRow, ROWID[c.row], c.name .. ": the copier ran the source's row") end
    if c.cmd == CMD_SLOT then
      assert(c.copyAtk < 0x59 or c.copyAtk > 0x5B, c.name .. ": the copy is a reel result, not a kit row")
    end
    H.assertEq(c.pendAtConfirm, c.boost, c.name .. ": the copier's pending at its Mimic confirm")
    if c.row == "steal" then
      H.assertEq(c.rolled, false, c.name .. ": the copied Steal met a body with nothing left (LOCKE took it)")
    end
    check(c.charged == 0, string.format("%s: the copy charged %d MP (Mimic is free)", c.name, c.charged))
    if c.keep then
      local base = byName[c.keep]
      H.assertEq(c.bank0, base.bank0, c.name .. ": the copier's bank at confirm, as in " .. c.keep)
      check(c.bankEnd == base.bankEnd, string.format("%s: the copier's bank ended at %d, %s's at %d "
        .. "(a boost the copy cannot use is kept)", c.name, c.bankEnd, c.keep, base.bankEnd))
    elseif c.spend then
      check(c.bankEnd == c.bank0 - c.boost, string.format("%s: the copier's bank went %d -> %d, "
        .. "%d spent and no regen (a boost the copy uses is spent)", c.name, c.bank0, c.bankEnd, c.boost))
    end
  end
  assert(#bad == 0, #bad .. " mimic-boost assertion(s) failed: " .. table.concat(bad, "; "))
  H.log("[mimicboost] VERDICT: every copy free of MP; every boost a copy cannot use kept; the copied Trickshot's "
    .. "and Tonic's spent")
end)

H.run({ maxFrames = 400000 }, steps)
