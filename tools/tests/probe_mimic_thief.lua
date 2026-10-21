-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- @manual a measurement probe for #261 (what a mimicked Steal, Filch and Bestow cost); no design verdict
-- probe_mimic_thief.lua -- what a MIMICKED Steal, Filch and Bestow cost, and do  (#261)
--
-- A measurement probe (no verdict asserts on the design question; it asserts
-- only that each case ran to the end and that the controls held).  By hand:
--   OT6_SRAM_CHECKPOINT=build/checkpoints/fire-out-v1 \
--     tools/tests/run.sh tools/tests/probe_mimic_thief.lua <log>
--
-- The question.  ot6_thief.asm and Ot6AbilityCost's @steal comment said a Gogo
-- mimic "falls through to Ot6StealCost"; #260 measured that mimicreplace copies
-- the source's queue row without passing CreateAction, so the copy keeps
-- Mimic's own 0 cost.  This measures it for the three priced rows under
-- command $05 (Steal 4 MP, Filch 4, Bestow 5: Ot6StealCost, Ot6ThiefCostTbl),
-- and what each copy does (Filch banks a pip for the copier; Bestow gives one
-- of the copier's pips to the ally).
--
-- DECLARED EXPEDIENT (tools/state_write_waivers.txt), the battle_mimic one:
-- no fixture has LOCKE and GOGO in one party (GOGO joins in the World of Ruin,
-- LOCKE is not in wor_opera_switch's party).  So after the cold Continue and
-- before the first step this writes ONE command byte in the field character
-- record ($1600 + 37*id + $17): STRAGO's second command becomes Mimic ($12).
-- Battle init builds the command lists from it; everything after is the
-- engine's own.  LOCKE is the source (his real thief list), STRAGO the
-- stand-in, TERRA the ally Bestow hands to.  A mechanism measurement, not
-- play, and not a claim about GOGO's balance.
--
-- The run: Continue fire-out-v1 (TERRA LOCKE STRAGO by Thamasa), pace to an
-- encounter on the plain whose bodies carry loot and a shield, snapshot
-- LOCKE's first window, then per case restore it: LOCKE plays the row at the
-- named target and everyone else Defends; once his SaveForMimic has run,
-- STRAGO presses R to the case's boost, picks Mimic, and confirms its target.
-- Observed, never written: every store to the MP-cost queue ($3620-$371F)
-- with the queue context, Ot6AbilityCost's entries, SaveForMimic (what is
-- saved), mimicreplace (what is copied), Ot6ThiefExec/Ot6Filch/Ot6Bestow
-- entries (which entity ran which row), the stand-in's staged cost $3A4C,
-- MP / bank / pending / shields / loot at each step, steal's code ($3401)
-- and grant ($32F4), and Ot6ActionEnd for each.
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F
local ST_CMD, ST_DEF, ST_TGT, ST_THIEF = 0x05, 0x27, 0x38, 0x30
local KCOL, KROW = 0x8963, 0x8967
local BANK, PEND, CURMP = 0x3E9C, 0x3E9D, 0x3C08
local CMD_STEAL, CMD_MIMIC = 0x05, 0x12
local TERRA, LOCKE, STRAGO = 0, 1, 7
local ROWS = { steal = 0, filch = 1, bestow = 2 }
local ROWID = { steal = 0x56, filch = 0x57, bestow = 0x58 }
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
      t[#t + 1] = string.format("m%d sh%d loot%02X/%02X", m, shield(m), r, c)
    end
  end
  return table.concat(t, " ")
end

-- ---- observers ---------------------------------------------------------------
local armed, installed = nil, false
local function rd16(a) return H.readWord(a) end
local function ev(c, s) c.log[#c.log + 1] = string.format("f%d %s", H.frame, s) end
local function installObservers()
  if installed then return end
  installed = true
  local function cx() return emu.getState()["cpu.x"] & 0xFFFF end
  local function cy() return emu.getState()["cpu.y"] & 0xFFFF end
  local function onExec(a, fn)
    emu.addMemoryCallback(function() if armed and not armed.endF then fn(armed) end end,
      emu.callbackType.exec, a, a)
  end
  emu.addMemoryCallback(function(addr, v)
    if armed == nil or armed.endF then return end
    ev(armed, string.format("COSTQUEUE [$%04X<-%d x=%02X 3a7a=$%02X 3a7b=$%02X]",
      addr & 0xFFFF, v, cx(), H.readByte(0x3A7A), H.readByte(0x3A7B)))
    if cx() == standS * 2 then armed.standStores[#armed.standStores + 1] = v end
    if cx() == lockeS * 2 then armed.lockeStores[#armed.lockeStores + 1] = v end
  end, emu.callbackType.write, 0x7E3620, 0x7E371F)
  onExec(H.sym("Ot6AbilityCost"), function(c)
    ev(c, string.format("Ot6AbilityCost x=%02X 3a7a=$%02X 3a7b=$%02X vanillaCost=%d", cx(),
      H.readByte(0x3A7A), H.readByte(0x3A7B), emu.getState()["cpu.a"] & 0xFF))
  end)
  onExec(H.sym("SaveForMimic"), function(c)
    ev(c, string.format("SaveForMimic x=%02X 3a7c=$%04X 3a30=$%04X", cx(), rd16(0x3A7C), rd16(0x3A30)))
    if cx() == lockeS * 2 then c.srcSaved = c.srcSaved + 1; c.saved = rd16(0x3A7C) end
  end)
  onExec(H.sym("mimicreplace"), function(c)
    ev(c, string.format("mimicreplace x=%02X: 3f20=$%04X 3f22=$%04X 3f24=$%04X 3f26=$%04X 3f28=$%02X %s",
      cx(), rd16(0x3F20), rd16(0x3F22), rd16(0x3F24), rd16(0x3F26), H.readByte(0x3F28), chars()))
    if cx() == standS * 2 then c.inStand = true end
  end)
  emu.addMemoryCallback(function(_, v)
    if armed == nil or armed.endF or not armed.inStand or cx() ~= standS * 2 then return end
    ev(armed, string.format("stand-in staged cost $3A4C<-%d (3a7a=$%02X 3a7b=$%02X)", v,
      H.readByte(0x3A7A), H.readByte(0x3A7B)))
    armed.staged[#armed.staged + 1] = v
  end, emu.callbackType.write, 0x7E3A4C, 0x7E3A4C)
  onExec(H.sym("Ot6ThiefExec"), function(c)
    ev(c, string.format("Ot6ThiefExec x=%02X b6=$%02X b8=$%02X b9=$%02X", cx(), H.readByte(0xB6),
      H.readByte(0xB8), H.readByte(0xB9)))
  end)
  onExec(H.sym("Ot6Filch"), function(c)
    ev(c, string.format("Ot6Filch x=%02X b9=$%02X %s | %s", cx(), H.readByte(0xB9), chars(), mons()))
  end)
  onExec(H.sym("Ot6Bestow"), function(c)
    ev(c, string.format("Ot6Bestow x=%02X b8=$%02X %s", cx(), H.readByte(0xB8), chars()))
  end)
  emu.addMemoryCallback(function(_, v)
    if armed == nil or armed.endF then return end
    ev(armed, string.format("steal code $3401<-%d (x=%02X)", v, cx()))
  end, emu.callbackType.write, 0x7E3401, 0x7E3401)
  emu.addMemoryCallback(function(_, v)
    if armed == nil or armed.endF or v == 0xFF then return end
    ev(armed, string.format("grant $32F4+<-$%02X (x=%02X)", v, cx()))
  end, emu.callbackType.write, 0x7E32F4, 0x7E3306)
  onExec(H.sym("Ot6ActionEnd"), function(c)
    local x = cx()
    if x == lockeS * 2 and c.srcEnd == nil then
      c.srcEnd = true
      c.srcMpEnd = mp(lockeS)
      ev(c, string.format("Ot6ActionEnd LOCKE: %s | %s", chars(), mons()))
    elseif x == standS * 2 and c.inStand then
      c.endF = H.frame
      c.mpEnd = mp(standS)
      c.endLine = string.format("Ot6ActionEnd STAND-IN entry: %s | %s", chars(), mons())
      ev(c, c.endLine)
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
-- the steering for one target window; wantSlot is a monster slot or a character slot
local function aim(T, want, edgeOnly)
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

local tgtMon          -- the monster slot Steal and Filch aim at
local function decide(c)
  if H.readByte(MENU) == 0 then return nil end
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if a == lockeS and not c.srcDone then
    if st == ST_CMD then
      local want = cmdRow(lockeS, CMD_STEAL)
      local cur = H.readByte(CMDROW + lockeS) & 3
      if cur ~= want then return cur < want and "down" or "up" end
      c.srcMp0, c.srcBank0 = mp(lockeS), bank(lockeS)
      return "a"
    end
    if st == ST_THIEF then
      local row = ROWS[c.row]
      local cur = H.readByte(KROW + lockeS)
      if H.readByte(KCOL + lockeS) ~= 0 then return "left" end
      if cur < row then return "down" end
      if cur > row then return "up" end
      return "a"
    end
    return nil
  end
  if a == standS and c.srcDone and not c.mimicSent then
    if c.srcSaved < 1 then return nil end            -- LOCKE's row has not resolved
    if st == ST_TGT then
      c.mp0, c.pendAtConfirm, c.bank0 = mp(standS), pend(standS), bank(standS)
      ev(c, string.format("stand-in Mimic target confirmed: %s", chars()))
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
  if H.readByte(MENU) == 0 or H.readByte(MSTATE) ~= ST_TGT or (H.readByte(ACTOR) & 3) ~= lockeS
     or c.srcDone then
    mf, tapNo = 0, -1
    return false
  end
  local btn = c.row == "bestow" and aim(Tc, terraS) or aim(Tm, tgtMon)
  if next(btn) == "a" then c.srcDone = true; c.tgtConfirmed = true end
  return btn
end

local function runCase(snapRef, c)
  local req
  return {
    H.call(function() H.setPad({}); req = H.requestLoadState(snapRef.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load")
      H.rearmInputInjection()
      tick, held = 0, nil
      mf, tapNo = 0, -1
      c.log, c.standStores, c.lockeStores, c.staged = {}, {}, {}, {}
      c.srcSaved, c.srcDone, c.mimicSent, c.after = 0, false, false, false
      c.endF, c.inStand, c.srcEnd = nil, false, nil
      armed = c
      ev(c, "START " .. chars() .. " | " .. mons())
    end),
    H.driveUntil(function() return c.endF ~= nil and H.frame >= c.endF + 120 end, 14000, {
      H.call(function()
        Tm.observe(); Tc.observe()
        if c.endF and not c.after and H.frame >= c.endF + 6 then
          c.after = true
          ev(c, "six frames after the stand-in's Ot6ActionEnd: " .. chars() .. " | " .. mons())
        end
        local ac = lockeAim(c)
        if ac then held = nil; H.setPad(ac) return end
        tick = tick + 1
        local ph = tick % 12
        if ph == 0 then held = decide(c) end
        -- Locke's pick has been confirmed by the target window above; the
        -- first thing that follows is his turn running, so srcDone holds
        if c.tgtConfirmed then c.srcDone = true end
        H.setPad((held and ph < 6) and { [held] = true } or {})
      end),
    }, "case " .. c.name .. " resolves"),
    H.call(function()
      armed = nil
      H.setPad({})
      for _, l in ipairs(c.log) do H.log(string.format("[mimicthief] %s: %s", c.name, l)) end
      local charged = (c.mp0 or 0) - (c.mpEnd or c.mp0 or 0)
      H.log(string.format("[mimicthief] %s RESULT: row %s, stand-in boost %d. LOCKE paid %s MP "
        .. "(queue stores {%s}); stand-in MP %d -> %d (charged %d; queue stores by stand-in {%s}, staged {%s}); "
        .. "pending at confirm %d, bank %d -> %s", c.name, c.row, c.boost,
        tostring((c.srcMp0 or 0) - (c.srcMpEnd or c.srcMp0 or 0)), table.concat(c.lockeStores, ","),
        c.mp0 or -1, c.mpEnd or -1, charged, table.concat(c.standStores, ","), table.concat(c.staged, ","),
        c.pendAtConfirm or -1, c.bank0 or -1, "see Ot6ActionEnd line"))
      c.charged = charged
    end),
  }
end

-- ---- the run -----------------------------------------------------------------
local snapL, snapRef = nil, {}
local steps = {
  H.bootCheckpoint("fire-out-v1"),   -- the cold Continue, its entry contract asserted
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("fire-out-v1")
    local m = members()
    local have = {}
    for _, c in ipairs(m) do have[c] = true end
    assert(have[TERRA] and have[LOCKE] and have[STRAGO], "TERRA, LOCKE and STRAGO are in the party")
    local old1 = H.readByte(recCmd(STRAGO, 1))
    H.writeByte(recCmd(STRAGO, 1), CMD_MIMIC)
    H.log(string.format("[mimicthief] EXPEDIENT: STRAGO command row 1 $%02X -> $12 (Mimic)", old1))
    installObservers()
  end),
  (function()
    local P = H.newPacer({ tag = "mimicthief pace" })
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
          H.log(string.format("[mimicthief] draw %d: monsters %s | %s -> target %s", try,
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
    H.log(string.format("[mimicthief] battle slots: LOCKE %d STRAGO(stand-in) %d TERRA(ally) %d; %s | %s",
      lockeS, standS, terraS, chars(), mons()))
    assert(cmdRow(standS, CMD_MIMIC), "the stand-in's battle list has Mimic")
    assert(cmdRow(lockeS, CMD_STEAL), "LOCKE's battle list has Steal")
  end),
  H.driveUntil(function() return snapL ~= nil end, 20000, {
    H.call(function()
      tick = tick + 1
      if tick % 12 ~= 0 and tick % 12 ~= 6 then return end
      if tick % 12 == 6 then H.setPad({}) return end
      if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD and (H.readByte(ACTOR) & 3) == lockeS
         and pend(lockeS) == 0 then
        H.setPad({}); snapL = H.requestSaveState()
        H.log(string.format("[mimicthief] snapshot L f%d: %s", H.frame, chars()))
        return
      end
      if H.readByte(MENU) == 0 then return end
      local b = defendPress(H.readByte(MSTATE))
      H.setPad(b and { [b] = true } or {})
    end),
  }, "snapshot at LOCKE's first window"),
  H.waitFrames(2),
  H.call(function() H.checkReq(snapL, "snapshot L"); snapRef.blob = snapL.blob end),
}

local CASES = {
  { name = "steal-b0",  row = "steal",  boost = 0 },
  { name = "filch-b0",  row = "filch",  boost = 0 },
  { name = "bestow-b0", row = "bestow", boost = 0 },
  { name = "steal-b1",  row = "steal",  boost = 1 },
  { name = "filch-b1",  row = "filch",  boost = 1 },
  { name = "bestow-b1", row = "bestow", boost = 1 },
}
for _, c in ipairs(CASES) do
  for _, s in ipairs(runCase(snapRef, c)) do steps[#steps + 1] = s end
end

steps[#steps + 1] = H.call(function()
  for _, c in ipairs(CASES) do
    H.log(string.format("[mimicthief] VERDICT %s: stand-in charged %s MP (row %s, boost %d, LOCKE's own MP %s)",
      c.name, tostring(c.charged), c.row, c.boost,
      tostring((c.srcMp0 or 0) - (c.srcMpEnd or c.srcMp0 or 0))))
  end
end)

H.run({ maxFrames = 400000 }, steps)
