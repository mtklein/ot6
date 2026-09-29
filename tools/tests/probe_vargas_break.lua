-- @manual one-off #314 lab; deleted by the next commit
-- probe_vargas_break.lua -- one-off lab for #314: does Sabin's Pummel still
-- end the VARGAS fight when VARGAS is Broken?  Not a suite (no @suite line).
--
-- Boots vargas_entry, plays phase one exactly as battle_vargas does (Fight
-- until the Ipoohs are down and a plain hit lands, one BioBlaster, Fight until
-- battle_event $07/$08 bring SABIN on), then snapshots the first frame SABIN's
-- menu is up and branches three experiments from that one snapshot:
--
--   normal   : SABIN Pummels at once (4 shields -> 2, VARGAS stays unbroken)
--   breaking : AuraBolt until 2 shields remain, then Pummel: its second hit
--              takes the last shield, so the break lands inside the Pummel
--   broken   : AuraBolt until VARGAS is Broken, then Pummel while it holds
--
-- In every branch SABIN keeps Pummeling on each later turn (what a player does
-- when the finish did not happen), Potions himself under 35%, and the branch
-- runs until the battle tears down, the party is wiped, or a frame budget.
-- Traced (exec callbacks, VARGAS's entity only): Ot6MayAct with his
-- broken-ticks byte, CreateRetalAction, ExecAIRetal, AICmd_f7 (battle_event)
-- with its event id, and every write to his broken-ticks byte.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/vargas_entry.mss.lua"

local VARGAS, IPOOH = 0x0103, 0x014D
local HOLY, POISON = 0x20, 0x08
local PUMMEL, AURABOLT = 0x5D, 0x5E
local BIOBLASTER = 0xA4
local CMD_FIGHT, CMD_ITEM, CMD_MAGIC = 0x00, 0x01, 0x02
local CMD_TOOLS, CMD_BLITZ = 0x09, 0x0A
local SABIN_E, EDGAR_E, TERRA_E = 3, 0, 2
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_ITEM, ST_MAGIC, ST_TOOLS, ST_TGT = 0x05, 0x0A, 0x0E, 0x30, 0x38
local CMDTBL, ITEMLIST, BATTINV, MONMASK = 0x202E, 0x4005, 0x2686, 0x7B7E
local POTION, TONIC, CURE_ID = 0xE9, 0xE8, 0x2D
local SPELL_PTR = { [0] = 0x0000, [1] = 0x013C, [2] = 0x0278, [3] = 0x03B4 }
local BRK_BASE = 0x3E88                 -- OT6_BROKEN_TICKS
local BUDGET = 30000                    -- frames per branch after the snapshot

local function SH(s)  return 0x3E38 + (8 + s * 2) end
local function MHP(s) return 0x3BFC + s * 2 end
local function hp(e) return H.readWord(0x3BF4 + e * 2) end
local function maxhp(e) return H.readWord(0x3C1C + e * 2) end
local function mp(e) return H.readWord(0x3C08 + e * 2) end
local function bp(e) return H.readByte(0x3E9C + e * 2) end
local function pend(e) return H.readByte(0x3E9D + e * 2) end
local function alive(e) return hp(e) > 0 end

local vSlot, vEnt = 0, 8
local vHp0 = 0
local function shields() return H.readByte(SH(vSlot)) end
local function brk() return H.readByte(BRK_BASE + vEnt) end

local function itemSlot(id)
  for i = 0, 15 do
    if H.readByte(BATTINV + i * 5) == id
       and H.readByte(BATTINV + i * 5 + 3) > 0 then return i end
  end
  return nil
end
local function spellIndexOf(slot, id)
  for i = 0, 15 do
    local a = 0x2092 + SPELL_PTR[slot] + i * 4
    if H.readByte(a) == id and (H.readByte(a + 1) & 0x80) == 0 then return i end
  end
  return nil
end
local healBusy = {}
local function needsHeal(thresh, lo, hi)
  local best, bestR = nil, 1.0
  for e = lo or 0, hi or 2 do
    if alive(e) and maxhp(e) > 0 then
      local r = hp(e) / maxhp(e)
      if r < thresh and r < bestR
         and (not healBusy[e] or H.frame - healBusy[e] > 900) then
        best, bestR = e, r
      end
    end
  end
  return best
end
local function hpLine()
  local s = ""
  for e = 0, 3 do
    s = s .. string.format(" e%d=%d/%d(b%d,%dmp)", e, hp(e), maxhp(e), bp(e), mp(e))
  end
  return s .. string.format(" V=%d sh=%d brk=%d", H.readWord(MHP(vSlot)),
    shields(), brk())
end
local function monsterAlive(s)
  return (H.readByte(0x3AA8 + s * 2) & 0x01) == 1
     and (H.readByte(0x3EEC + s * 2) & 0xC2) == 0
end
local function ipoohsDown()
  for s = 0, 5 do
    if s ~= vSlot and H.readWord(0x57C0 + s * 2) == IPOOH and monsterAlive(s) then
      return false
    end
  end
  return true
end

-- ------------------------------------------------------------ trace --
local CASE = "phase1"
local pummels = {}                      -- per-branch: {frame, brkAtCheck}
local mayActLog = {}
local events = {}
local lastMayAct = nil
local function tlog(fmt, ...)
  H.log(string.format("[trace %s f%d] " .. fmt, CASE, H.frame, ...))
end
-- literal H.sym calls: compose.py injects only the names it sees spelled out
local SYMS = {
  Ot6MayAct = function() return H.sym("Ot6MayAct") end,
  CreateRetalAction = function() return H.sym("CreateRetalAction") end,
  ExecAIRetal = function() return H.sym("ExecAIRetal") end,
  AICmd_f7 = function() return H.sym("AICmd_f7") end,
}
local function armTrace()
  local function hook(name, fn)
    local ok, a = pcall(function() return SYMS[name]() end)
    if not ok then H.log("[trace] symbol " .. name .. " unavailable: " .. tostring(a)); return end
    emu.addMemoryCallback(fn, emu.callbackType.exec, a, a)
    H.log(string.format("[trace] hooked %s at $%06X", name, a))
  end
  hook("Ot6MayAct", function()
    local x = emu.getState()["cpu.x"] & 0xff
    if x ~= vEnt then return end
    lastMayAct = { f = H.frame, brk = brk(), sh = shields(), skill = H.readByte(0x3410) }
    mayActLog[#mayActLog + 1] = lastMayAct
    tlog("Ot6MayAct ent=$%02X brk=%d shields=%d lastSkill=$%02X -> %s", x,
      lastMayAct.brk, lastMayAct.sh, lastMayAct.skill,
      lastMayAct.brk ~= 0 and "REFUSED (no counter)" or "may counter")
  end)
  hook("CreateRetalAction", function()
    local x = emu.getState()["cpu.x"] & 0xff
    if x ~= vEnt then return end
    tlog("CreateRetalAction ent=$%02X cmd=$%02X brk=%d", x, H.readByte(0x3A7A), brk())
  end)
  hook("ExecAIRetal", function()
    local x = emu.getState()["cpu.x"] & 0xff
    if x ~= vEnt then return end
    tlog("ExecAIRetal ent=$%02X brk=%d $33fc=$%04X", x, brk(), H.readWord(0x33FC))
  end)
  hook("AICmd_f7", function()
    local ev = H.readByte(0x3A2D)
    events[#events + 1] = { f = H.frame, ev = ev }
    tlog("AICmd_f7 battle_event $%02X (x=$%02X brk=%d)", ev,
      emu.getState()["cpu.y"] & 0xff, brk())
  end)
  emu.addMemoryCallback(function(_, v)
    tlog("broken-ticks write %d (shields=%d)", v, shields())
  end, emu.callbackType.write, 0x7E0000 + BRK_BASE + vEnt, 0x7E0000 + BRK_BASE + vEnt)
  -- Pummel's two hits each re-write the skill id ($FF between them), 59-134
  -- frames apart; SABIN's turns are ~1000 apart.  One action per 300 frames.
  local lastW = {}
  emu.addMemoryCallback(function(_, v)
    if v == 0xFF then return end
    local prev = lastW[v]
    lastW[v] = H.frame
    if prev and H.frame - prev < 300 then
      tlog("skill $%02X second hit: brk=%d shields=%d", v, brk(), shields())
      return
    end
    if v == PUMMEL then
      pummels[#pummels + 1] = { f = H.frame, brk = brk(), sh = shields() }
      tlog("PUMMEL #%d executes: brk=%d shields=%d V=%d", #pummels, brk(),
        shields(), H.readWord(MHP(vSlot)))
    elseif v == AURABOLT then
      tlog("AURABOLT executes: brk=%d shields=%d V=%d", brk(), shields(),
        H.readWord(MHP(vSlot)))
    end
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
end

-- ------------------------------------------------- the per-menu driver --
local mode = "control"
local bioFired = false
local M = {}
local function resetM()
  M.actor, M.n, M.plan, M.via, M.d = nil, 0, nil, nil, 0
  M.lastCur, M.dirI, M.tgtN = nil, nil, 0
end
resetM()

local function sabinPlan()
  local emerg = needsHeal(0.35, 3, 3)
  if emerg then
    local slot = itemSlot(POTION) or itemSlot(TONIC)
    if slot then return { kind = "potion", target = emerg, slot = slot } end
  end
  local sh, tk = shields(), brk()
  local aura = { kind = "blitz", skill = AURABOLT, name = "AURABOLT" }
  local pum = { kind = "blitz", skill = PUMMEL, name = "PUMMEL" }
  if #pummels > 0 or CASE == "normal" then return pum end
  if CASE == "breaking" then
    if tk == 0 and sh > 2 and mp(SABIN_E) >= 14 then return aura end
    return pum
  end
  if CASE == "broken" then
    if tk == 0 and sh > 0 and mp(SABIN_E) >= 14 then return aura end
    return pum
  end
  return { kind = "wait" }
end

local function decidePlan(a)
  if a == SABIN_E then
    if mode == "sabin" then return sabinPlan() end
    return { kind = "wait" }
  end
  if mode == "hold" or mode == "sabin" then return { kind = "wait" } end
  if mode == "bio" and a == EDGAR_E and not bioFired then return { kind = "bio" } end
  local emerg = needsHeal(0.30)
  if emerg then
    local slot = itemSlot(POTION) or itemSlot(TONIC)
    if slot then return { kind = "potion", target = emerg, slot = slot } end
  end
  if a == TERRA_E and mp(TERRA_E) >= 10 then
    local t = needsHeal(0.60)
    if t then return { kind = "cure", target = t } end
  end
  return { kind = "fight" }
end

local function pulse()
  local a = H.readByte(ACTOR)
  if M.actor ~= a then
    if M.plan and M.plan.kind == "bio" and M.via == "toolshell" then bioFired = true end
    resetM()
    M.actor, M.plan = a, decidePlan(a)
    if M.plan.kind ~= "fight" and M.plan.kind ~= "wait" then
      H.log(string.format("[plan %s f%d] actor=%d %s%s |%s", CASE, H.frame, a,
        M.plan.kind, M.plan.name and (" " .. M.plan.name) or "", hpLine()))
    end
  end
  if M.plan.kind == "wait" then return {} end
  M.n = M.n + 1
  local ph = M.n % 10
  local st = H.readByte(MSTATE)
  if M.n > 1200 then
    H.log(string.format("[wd %s f%d] actor=%d st=%02X plan=%s", CASE, H.frame, a, st,
      M.plan.kind))
    M.n, M.via, M.d = 0, nil, 0
    M.plan = { kind = "fight" }
    return { "b" }
  end
  if st == ST_CMD then
    M.via = nil
    local wantCmd = CMD_FIGHT
    if M.plan.kind == "potion" then wantCmd = CMD_ITEM end
    if M.plan.kind == "cure" then wantCmd = CMD_MAGIC end
    if M.plan.kind == "bio" then wantCmd = CMD_TOOLS end
    if M.plan.kind == "blitz" then wantCmd = CMD_BLITZ end
    local wantCell = nil
    for i = 0, 3 do
      if H.readByte(CMDTBL + a * 12 + i * 3) == wantCmd then wantCell = i end
    end
    if wantCell == nil then M.plan = { kind = "fight" }; wantCell = 0 end
    local cur = H.readByte(0x890F + a)
    if cur == wantCell then
      if M.plan.kind == "fight" then
        local want = math.min(bp(a), 3)
        if pend(a) < want then return (ph < 5) and { "r" } or {} end
      end
      return (ph < 5) and { "a" } or {}
    end
    local DIRS = { "down", "up", "left", "right" }
    if ph == 0 then
      if M.lastCur == cur then M.dirI = ((M.dirI or 0) % 4) + 1
      else M.dirI = M.dirI or 1 end
      M.lastCur = cur
    end
    return (ph < 5) and { DIRS[M.dirI or 1] } or {}
  end
  if st == ST_ITEM then
    M.d = 0
    if M.plan.kind ~= "potion" then return (ph < 5) and { "b" } or {} end
    M.via = "item"
    local cr = H.readByte(0x894F)
    if cr ~= M.plan.slot then
      return (ph < 5) and { (cr < M.plan.slot) and "down" or "up" } or {}
    end
    return (ph < 5) and { "a" } or {}
  end
  if st == ST_MAGIC then
    M.d = 0
    if M.plan.kind ~= "cure" then return (ph < 5) and { "b" } or {} end
    M.via = "magic"
    local idx = spellIndexOf(a, CURE_ID)
    if idx == nil then M.plan = { kind = "fight" }; return (ph < 5) and { "b" } or {} end
    local wantRow, wantCol = idx // 2, idx % 2
    local absRow = H.readByte(0x8913 + a) + H.readByte(0x891B + a)
    local col = H.readByte(0x8917 + a)
    if absRow ~= wantRow then
      return (ph < 5) and { (absRow < wantRow) and "down" or "up" } or {}
    end
    if col ~= wantCol then
      return (ph < 5) and { (col < wantCol) and "right" or "left" } or {}
    end
    return (ph < 5) and { "a" } or {}
  end
  if st == ST_TOOLS then
    M.d = 0
    if M.plan.kind ~= "bio" and M.plan.kind ~= "blitz" then
      return (ph < 5) and { "b" } or {}
    end
    local wantId = (M.plan.kind == "bio") and BIOBLASTER or M.plan.skill
    local entry = nil
    for i = 0, 7 do
      if H.readByte(ITEMLIST + i * 3) == wantId then entry = i end
    end
    if entry == nil then return {} end
    M.via = "toolshell"
    local row, col = entry // 2, entry % 2
    local cr, cc = H.readByte(0x8967 + a), H.readByte(0x8963 + a)
    if cr ~= row then return (ph < 5) and { (cr < row) and "down" or "up" } or {} end
    if cc ~= col then return (ph < 5) and { (cc < col) and "right" or "left" } or {} end
    return (ph < 5) and { "a" } or {}
  end
  if st == ST_TGT then
    if M.plan.kind == "potion" or M.plan.kind == "cure" then
      if M.via ~= "item" and M.via ~= "magic" then return (ph < 5) and { "b" } or {} end
      local want = 1 << M.plan.target
      if H.readByte(MONMASK) ~= 0 then return (ph < 5) and { "left" } or {} end
      if H.readByte(0x7B7D) ~= want then
        M.d = M.d + 1
        if M.d > 40 then
          healBusy[M.plan.target] = H.frame
          return (ph < 5) and { "a" } or {}
        end
        return (ph < 5) and { "down" } or {}
      end
      healBusy[M.plan.target] = H.frame
      return (ph < 5) and { "a" } or {}
    end
    if M.plan.kind == "bio" or M.plan.kind == "blitz" then
      if M.via ~= "toolshell" then return (ph < 5) and { "b" } or {} end
      return (ph < 5) and { "a" } or {}
    end
    return (ph < 5) and { "a" } or {}
  end
  return {}
end

local hb = -600
local function fightDriver()
  return H.call(function()
    if H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("[hb %s %s f%d]%s", CASE, mode, H.frame, hpLine()))
    end
    if H.readByte(MENU) == 0 then
      resetM()
      H.setPad(H.frame % 8 < 4 and { "a" } or {})
      return
    end
    H.setPad(pulse())
  end)
end

-- ------------------------------------------------------------ branches --
local blob = nil
local results = {}
local branchStart = 0

local function wiped()
  for e = 0, 3 do
    if H.readByte(0x3ED8 + e * 2) ~= 0xFF and alive(e) then return false end
  end
  return true
end

local function branch(name)
  local loadReq
  local verdict = nil
  return {
    H.call(function()
      if name ~= "normal" then
        loadReq = H.requestLoadState(blob)
      end
    end),
    H.waitFrames(2),
    H.call(function()
      if name ~= "normal" then H.checkReq(loadReq, name .. ": snapshot restore") end
      CASE = name
      pummels, mayActLog, events, lastMayAct = {}, {}, {}, nil
      for k in pairs(healBusy) do healBusy[k] = nil end
      resetM()
      H.gameOverFired = 0
      mode = "sabin"
      branchStart = H.frame
      H.log(string.format("[branch %s] starts at f%d:%s", name, H.frame, hpLine()))
    end),
    H.driveUntil(function()
      if not H.battleLoadStarted() then verdict = "ENDED"; return true end
      if (H.gameOverFired or 0) > 0 or wiped() then verdict = "WIPED"; return true end
      if H.frame - branchStart > BUDGET then verdict = "NOT ENDED (budget)"; return true end
      return false
    end, BUDGET + 600, { fightDriver() }, name .. " branch resolves"),
    H.call(function()
      H.setPad({})
      local ev9 = nil
      for _, e in ipairs(events) do if e.ev == 0x09 then ev9 = ev9 or e.f end end
      local pl = {}
      for i, p in ipairs(pummels) do
        pl[#pl + 1] = string.format("#%d f%d(+%d) brk=%d sh=%d", i, p.f,
          p.f - branchStart, p.brk, p.sh)
      end
      local ml = {}
      for _, m in ipairs(mayActLog) do
        ml[#ml + 1] = string.format("f%d skill=$%02X brk=%d", m.f, m.skill, m.brk)
      end
      local lastP = pummels[#pummels]
      local line = string.format("[verdict %s] %s at f%d (+%d after branch start); " ..
        "pummels: %s; Ot6MayAct(VARGAS): %s; battle_event $09 at %s; " ..
        "frames from last Pummel to teardown: %s", name, verdict, H.frame,
        H.frame - branchStart, #pl > 0 and table.concat(pl, ", ") or "none",
        #ml > 0 and table.concat(ml, ", ") or "none",
        ev9 and ("f" .. ev9) or "never",
        (verdict == "ENDED" and lastP) and tostring(H.frame - lastP.f) or "-")
      H.log(line)
      results[#results + 1] = line
    end),
  }
end

local steps = {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(function() H.setPad(H.frame % 8 < 4 and { "a" } or {}) end),
  }, "the VARGAS scene reaches battle 66"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 3000, "battle up", 10),
  H.waitFrames(120),
  H.call(function()
    vSlot = nil
    for s = 0, 5 do if H.readWord(0x57C0 + s * 2) == VARGAS then vSlot = s end end
    H.assertEq(vSlot ~= nil, true, "VARGAS ($0103) is in the formation")
    vEnt = 8 + vSlot * 2
    vHp0 = H.readWord(MHP(vSlot))
    H.log(string.format("[seed] VARGAS slot %d ent $%02X shields=%d brk=%d |%s",
      vSlot, vEnt, shields(), brk(), hpLine()))
    armTrace()
  end),
  H.driveUntil(function()
    return ipoohsDown() and H.readWord(MHP(vSlot)) < vHp0
  end, 36000, { fightDriver() }, "Ipoohs down and a plain hit on VARGAS"),
  H.call(function() mode = "bio" end),
  H.driveUntil(function() return shields() < 5 end, 20000, { fightDriver() },
    "BioBlaster chips VARGAS"),
  H.call(function() mode = "grind" end),
  H.driveUntil(function()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == SABIN_E
  end, 60000, { fightDriver() }, "SABIN takes the field"),
  H.call(function()
    mode = "hold"
    H.log(string.format("[phase two] f%d |%s", H.frame, hpLine()))
  end),
  (function()
    local req
    return H.cond(function() return true end, {
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "phase-two snapshot")
        blob = req.blob
        H.log(string.format("[phase two] snapshot %d bytes at f%d", #blob, H.frame))
      end),
    }, {})
  end)(),
}
for _, name in ipairs({ "normal", "breaking", "broken" }) do
  for _, s in ipairs(branch(name)) do steps[#steps + 1] = s end
end
steps[#steps + 1] = H.call(function()
  for _, l in ipairs(results) do H.log("[summary] " .. l) end
end)

H.run({ maxFrames = 260000, allowGameOver = true }, steps)
