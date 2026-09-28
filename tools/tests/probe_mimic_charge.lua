-- @manual
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- probe_mimic_charge.lua -- what does a boosted Mimic cost?  (#260)
--
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/fire-out-v1 \
--     tools/tests/run.sh tools/tests/probe_mimic_charge.lua <log>
--
-- mp-economy.md: Mimic is free, "vanilla Mimic copies the action and not the
-- price".  Vanilla makes it free twice over.  The copied action overwrites
-- the mimic's own queue slot ($3420/$3520, mimicreplace) and keeps the cost
-- that slot was queued at, which for command $12 is 0.  The one copy that is
-- queued afresh, an x-magic's second spell, goes through CreateAction with
-- $b1.6 set, which GetMPCost clears (`trb $b1`) and answers 0 for.  OT6's
-- Ot6QueueFold runs after GetMPCost on that same path and re-prices magic,
-- x-magic and lore from the caster's pending boost; before #260 it could not
-- see $b1.6.  This measures what a boosted mimic is charged, and what its
-- boost buys, not what the code says.  The verdict (last step): every case
-- charged 0 MP, a boosted copy of a tier-family head cast its tier, and the
-- pips were spent.  Main at 6f8382cb fails it (x-magic copies charged 38 and
-- 20; plain copies of Fire cast plain Fire); build/attempts/wt/mimic-charge/.
--
-- DECLARED EXPEDIENT (tools/state_write_waivers.txt).  No fixture has Gogo:
-- he joins in the World of Ruin, past the route.  Nor does any fixture have
-- an x-magic caster (the Gem Box is World of Ruin too).  So after the cold
-- Continue, before the first step, this probe writes two command bytes in
-- the field character records ($1600 + 37*id + $16..$19): the stand-in's
-- second command becomes Mimic ($12), and TERRA's Morph row becomes X-Magic
-- ($17).  Battle init builds the battle command lists from those bytes, so
-- everything after is the engine's own: the menus, the queue, the charge.
-- Nothing else is written.  This is a mechanism measurement of the mimic
-- charge, not play and not a claim about Gogo's balance.
--
-- The run: Continue fire-out-v1 (TERRA LOCKE STRAGO on the world map by
-- Thamasa; LOCKE is the stand-in, RELM would be if present), write the two
-- bytes, walk to an encounter, and snapshot TERRA's first window (X, for the
-- x-magic cases: her second spell waits out its own delay, and a TERRA worn
-- down by Defend rounds was killed in it), then Defend until the stand-in
-- has 3 pips banked and snapshot TERRA's window (T) and STRAGO's (S).  Each case restores one snapshot: the source casts
-- (unboosted unless the case says), everyone else Defends, and the
-- stand-in, once the source's cast has resolved (SaveForMimic has run for
-- it), presses R to the case's boost and picks Mimic.  Observed, never
-- written: every store to the MP-cost queue ($3620-$371F) with the queue
-- context, Ot6QueueFold's entries, mimicreplace's entry (what is copied,
-- the pending there), the staged cost $3A4C the stand-in's actions start
-- with, Ot6BoostDmg's entries for the stand-in, damage numerals, and the
-- stand-in's MP and BP at the Mimic confirm and after Ot6ActionEnd.

local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F
local ST_CMD, ST_DEF, ST_TGT, ST_MAGIC = 0x05, 0x27, 0x38, 0x0E
local ST_LORE_OPEN, ST_LORE = 0x19, 0x1B
local BANK, PEND, CURMP, MLISTPTR = 0x3E9C, 0x3E9D, 0x3C08, 0x302C
local MSCROLL, MCOL, MROW, LSCROLL, LROW = 0x8913, 0x8917, 0x891B, 0x891F, 0x8927
local CMD_MAGIC, CMD_LORE, CMD_MIMIC, CMD_XMAGIC = 0x02, 0x0C, 0x12, 0x17
local TERRA, LOCKE, STRAGO, RELM = 0, 1, 7, 8

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function pend(s) return H.readByte(PEND + s * 2) end
local function bank(s) return H.readByte(BANK + s * 2) end
local function mp(s) return H.readWord(CURMP + s * 2) end
local function cmdRow(s, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + s * 12 + r * 3) == cmd then return r end
  end
end
local function listBase(s)
  local b = H.readWord(MLISTPTR + s * 2)
  if b < 0x2000 or b > 0x2600 then return nil end
  return b
end
-- magic grid cell (0..53) of a spell id, and its list cost
local function spellCell(s, id)
  local b = listBase(s)
  if not b then return nil end
  for cell = 0, 53 do
    local a = b + (cell + 1) * 4
    if H.readByte(a) == id then return cell, H.readByte(a + 3), H.readByte(a + 1) end
  end
end
local function loreRow(s, id)
  local b = listBase(s)
  if not b then return nil end
  for row = 0, 23 do
    local a = b + (55 + row) * 4
    if H.readByte(a) == id then return row, H.readByte(a + 3) end
  end
end
local function loreOffered(id) return H.readByte(0x306A + id) == id + 0x8B end

-- the field party and the two declared writes
local cast = {}          -- char id -> battle slot, filled at battle start
local standId, standS, terraS, stragoS
local function members()
  local p, t = H.readByte(0x1A6D) & 7, {}
  for c = 0, 13 do
    if (H.readByte(0x1850 + c) & 7) == p and p ~= 0 then t[#t + 1] = c end
  end
  return t
end
local function recCmd(c, r) return 0x1600 + 37 * c + 0x16 + r end

-- ---- observers -------------------------------------------------------------
local armed = nil        -- the case being measured
local function rd16(a) return H.readWord(a) end
local installed = false
local function installObservers()
  if installed then return end
  installed = true
  local function cx() return emu.getState()["cpu.x"] & 0xFFFF end
  local function cy() return emu.getState()["cpu.y"] & 0xFFFF end
  emu.addMemoryCallback(function(addr, v)
    if armed == nil or armed.endF then return end
    armed.stores[#armed.stores + 1] = string.format("[$%04X<-%d x=%02X 3a7a=$%02X 3a7b=$%02X]",
      addr & 0xFFFF, v, cx(), H.readByte(0x3A7A), H.readByte(0x3A7B))
    if cx() == standS * 2 then armed.standStores[#armed.standStores + 1] = v end
  end, emu.callbackType.write, 0x7E3620, 0x7E371F)
  local qf = H.sym("Ot6QueueFold")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    local x = cx()
    if x == armed.src * 2 and not armed.srcDone then
      armed.srcQueued = armed.srcQueued + 1
      if armed.srcQueued >= #armed.picks then armed.srcDone = true end
    end
    armed.folds[#armed.folds + 1] = string.format("[x=%02X y=%02X 3a7a=$%02X 3a7b=$%02X pend=%d b1=$%02X]",
      x, cy(), H.readByte(0x3A7A), H.readByte(0x3A7B),
      x < 8 and H.readByte(PEND + x) or -1, H.readByte(0x00B1))
  end, emu.callbackType.exec, qf, qf)
  local sfm = H.sym("SaveForMimic")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    armed.sfmAll[#armed.sfmAll + 1] = string.format("x=%02X:$%04X@f%d", cx(), rd16(0x3A7C), H.frame)
    if cx() == armed.src * 2 then
      armed.srcSaved = armed.srcSaved + 1
      armed.srcActs[#armed.srcActs + 1] = string.format("$%04X", rd16(0x3A7C))
    end
  end, emu.callbackType.exec, sfm, sfm)
  local mr = H.sym("mimicreplace")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    armed.replace = string.format("mimicreplace x=%02X: 3f20=$%04X 3f24=$%04X 3f28=$%02X pend=%d bank=%d mp=%d",
      cx(), rd16(0x3F20), rd16(0x3F24), H.readByte(0x3F28), pend(standS), bank(standS), mp(standS))
    armed.inStand = true
  end, emu.callbackType.exec, mr, mr)
  emu.addMemoryCallback(function(_, v)
    if armed == nil or armed.endF or not armed.inStand then return end
    if cx() ~= standS * 2 then return end
    armed.staged[#armed.staged + 1] = string.format("%d(3a7c=$%04X)", v, rd16(0x3A7C))
  end, emu.callbackType.write, 0x7E3A4C, 0x7E3A4C)
  local bd = H.sym("Ot6BoostDmg")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF or not armed.inStand then return end
    if cx() ~= standS * 2 then return end
    armed.dmg[#armed.dmg + 1] = string.format("[b5=$%02X 3a7c=$%02X 3a7d=$%02X pend=%d base=%d]",
      H.readByte(0x00B5), H.readByte(0x3A7C), H.readByte(0x3A7D), pend(standS), rd16(0x11B0))
    armed.castIds[#armed.castIds + 1] = H.readByte(0x3A7D)
  end, emu.callbackType.exec, bd, bd)
  local lastLo = {}
  emu.addMemoryCallback(function(addr, value)
    if armed == nil or armed.endF then return end
    local a = addr & 0xFFFF
    if a % 2 == 0 then lastLo[a] = value return end
    local w = (lastLo[a - 1] or 0) | (value << 8)
    if w == 0xFFFF then return end
    local t = armed.inStand and armed.standNums or armed.srcNums
    t[#t + 1] = string.format("%d", w & 0x3FFF) .. ((w & 0x4000) ~= 0 and "m" or "")
  end, emu.callbackType.write, 0x7E33D0, 0x7E33E3)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    local x = cx()
    if x == armed.src * 2 and armed.srcMpEnd == nil then armed.srcMpEnd = mp(armed.src) end
    if x == standS * 2 and armed.inStand then
      armed.endF = H.frame
      armed.mpEnd, armed.pendAtEnd, armed.bankAtEnd = mp(standS), pend(standS), bank(standS)
    end
  end, emu.callbackType.exec, ae, ae)
end

-- ---- the per-case menu policy ----------------------------------------------
local tick, held = 0, nil
local function defendPress(st)
  if st == ST_CMD then return "right" end
  if st == ST_DEF then return "a" end
  return nil
end

local function steerMagic(s, id)
  local cell = spellCell(s, id)
  if cell == nil then error("spell $" .. string.format("%02X", id) .. " not in list", 0) end
  local wr, wc = cell // 2, cell % 2
  local ar = H.readByte(MSCROLL + s) + H.readByte(MROW + s)
  local col = H.readByte(MCOL + s)
  if ar < wr then return "down" end
  if ar > wr then return "up" end
  if col < wc then return "right" end
  if col > wc then return "left" end
  return "a"
end

local function decide(c)
  if H.readByte(MENU) == 0 then return nil end
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if a == c.src and not c.srcDone then
    if st == ST_CMD then
      if pend(c.src) < (c.srcBoost or 0) then return "r" end
      local want = cmdRow(c.src, c.cmd)
      local cur = H.readByte(CMDROW + c.src) & 3
      if cur ~= want then return cur < want and "down" or "up" end
      c.srcMp0 = mp(c.src)
      return "a"
    end
    if st == ST_MAGIC then
      if c.tgtSeen then c.tgtSeen = false; c.pickIdx = c.pickIdx + 1 end
      return steerMagic(c.src, c.picks[math.min(c.pickIdx, #c.picks)])
    end
    if st == ST_LORE_OPEN then return nil end
    if st == ST_LORE then
      local want = loreRow(c.src, c.picks[1])
      local cur = H.readByte(LSCROLL + c.src) + H.readByte(LROW + c.src)
      if cur < want then return "down" end
      if cur > want then return "up" end
      return "a"
    end
    if st == ST_TGT then
      c.tgtSeen = true
      return "a"
    end
    return nil
  end
  if a == standS and c.srcDone and not c.mimicSent then
    if c.srcSaved < #c.picks then return nil end       -- the source's cast has not resolved
    if st == ST_TGT then
      -- Mimic's own target (itself): this A is the confirm
      c.mp0, c.pendAtConfirm, c.bank0 = mp(standS), pend(standS), bank(standS)
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
  if a == standS and c.mimicSent and st == ST_TGT and c.replace == nil then return "a" end
  return defendPress(st)
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
      c.pickIdx, c.srcSaved, c.srcActs, c.srcQueued, c.tgtSeen = 1, 0, {}, 0, false
      c.stores, c.standStores, c.folds, c.staged, c.dmg, c.castIds = {}, {}, {}, {}, {}, {}
      c.srcNums, c.standNums, c.sfmAll = {}, {}, {}
      armed = c
    end),
    H.driveUntil(function() return c.endF ~= nil and H.frame >= c.endF + 20 end, 12000, {
      H.call(function()
        tick = tick + 1
        local ph = tick % 12
        if ph == 0 then held = decide(c) end
        if ph == 0 and (held or tick % 120 == 0) then
          H.log(string.format("[mimicdbg] %s f%d menu=%02X st=%02X actor=%d press=%s srcDone=%s "
            .. "queued=%d saved=%d pick=%d mimicSent=%s pendS=%d src 32cc=%02X 3aa0=%02X 3aa1=%02X "
            .. "3ab5=%02X SaveForMimic{%s}", c.name, H.frame,
            H.readByte(MENU), H.readByte(MSTATE), H.readByte(ACTOR) & 3, tostring(held),
            tostring(c.srcDone), c.srcQueued, c.srcSaved, c.pickIdx, tostring(c.mimicSent),
            pend(standS), H.readByte(0x32CC + c.src * 2), H.readByte(0x3AA0 + c.src * 2),
            H.readByte(0x3AA1 + c.src * 2), H.readByte(0x3AB5 + c.src * 2), table.concat(c.sfmAll, " ")))
        end
        H.setPad((held and ph < 6) and { [held] = true } or {})
      end),
    }, "case " .. c.name .. " resolves"),
    H.call(function()
      armed = nil
      H.setPad({})
      local charged = (c.mp0 or 0) - (c.mpEnd or c.mp0 or 0)
      H.log(string.format("[mimic] %s: source slot %d cmd $%02X picks %s srcBoost %d (source MP %d -> %s); "
        .. "source actions saved %s", c.name, c.src, c.cmd, table.concat(c.pickNames, "+"),
        c.srcBoost or 0, c.srcMp0 or -1, tostring(c.srcMpEnd), table.concat(c.srcActs, " ")))
      H.log(string.format("[mimic] %s: stand-in boost %d: pending at confirm %d bank %d; %s",
        c.name, c.boost, c.pendAtConfirm or -1, c.bank0 or -1, c.replace or "mimicreplace NOT reached"))
      H.log(string.format("[mimic] %s: Ot6QueueFold entries %s", c.name, table.concat(c.folds, " ")))
      H.log(string.format("[mimic] %s: cost queue stores %s; by the stand-in (x=%02X) {%s}",
        c.name, table.concat(c.stores, " "), standS * 2, table.concat(c.standStores, ",")))
      H.log(string.format("[mimic] %s: stand-in staged cost $3A4C %s; Ot6BoostDmg %s",
        c.name, table.concat(c.staged, " "), table.concat(c.dmg, " ")))
      H.log(string.format("[mimic] %s: damage numerals source {%s} stand-in {%s}",
        c.name, table.concat(c.srcNums, ","), table.concat(c.standNums, ",")))
      H.log(string.format("[mimic] %s: RESULT boost %d: stand-in MP %d -> %d (charged %d); "
        .. "pending %d -> %d at ActionEnd entry, bank %d -> %d at ActionEnd entry, %d/%d two frames later",
        c.name, c.boost, c.mp0 or -1, c.mpEnd or -1, charged, c.pendAtConfirm or -1,
        c.pendAtEnd or -1, c.bank0 or -1, c.bankAtEnd or -1, c.pendAfter or -1, c.bankAfter or -1))
    end),
  }
end

-- ---- the run ----------------------------------------------------------------
local snapX, snapT, snapS = nil, nil, nil
local picks = {}
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
    local m, names = members(), {}
    for _, c in ipairs(m) do
      names[#names + 1] = string.format("%d[%02X %02X %02X %02X]", c,
        H.readByte(recCmd(c, 0)), H.readByte(recCmd(c, 1)), H.readByte(recCmd(c, 2)), H.readByte(recCmd(c, 3)))
    end
    H.log("[mimic] party (char[commands]) " .. table.concat(names, " ") .. string.format(
      " at world (%d,%d)", H.worldX(), H.worldY()))
    local have = {}
    for _, c in ipairs(m) do have[c] = true end
    assert(have[TERRA] and have[STRAGO], "TERRA and STRAGO are in the party")
    standId = have[RELM] and RELM or (have[LOCKE] and LOCKE or nil)
    assert(standId, "a stand-in (RELM or LOCKE) is in the party")
    -- the declared expedient: two command bytes, see the header
    local old1 = H.readByte(recCmd(standId, 1))
    H.writeByte(recCmd(standId, 1), CMD_MIMIC)
    local xr
    for r = 1, 3 do
      local v = H.readByte(recCmd(TERRA, r))
      if v ~= 0x00 and v ~= CMD_MAGIC and v ~= 0x01 then xr = r break end
    end
    assert(xr, "TERRA has a row that is not Fight, Magic or Item")
    local oldx = H.readByte(recCmd(TERRA, xr))
    H.writeByte(recCmd(TERRA, xr), CMD_XMAGIC)
    H.log(string.format("[mimic] EXPEDIENT: char %d command row 1 $%02X -> $12 (Mimic); "
      .. "TERRA command row %d $%02X -> $17 (X-Magic)", standId, old1, xr, oldx))
    installObservers()
  end),
  (function()
    -- lap between the Continue tile and a tile a few steps off it, each leg
    -- planned on the settled tilemap (M.worldBfs), until an encounter fires
    local home, away, goal, plan, idx
    return H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
      H.call(function()
        if not H.worldHasControl() or not H.worldSettled() then plan = nil; H.setPad({}) return end
        if not H.worldAligned() then return end
        local x, y = H.worldX(), H.worldY()
        if home == nil then
          home = { x, y }
          for _, o in ipairs({ { 0, -4 }, { 0, 4 }, { -4, 0 }, { 4, 0 }, { 0, -3 }, { 0, 3 },
                               { -3, 0 }, { 3, 0 }, { 2, 2 }, { -2, -2 }, { 2, -2 }, { -2, 2 } }) do
            local p = H.worldBfs(x + o[1], y + o[2])
            if p and #p >= 3 and #p <= 10 then away = { x + o[1], y + o[2] } break end
          end
          assert(away, "a reachable tile a few steps from the Continue tile")
          goal = away
          H.log(string.format("[mimic] encounter lap (%d,%d) <-> (%d,%d)", x, y, away[1], away[2]))
        end
        if plan == nil or idx > #plan then
          if x == goal[1] and y == goal[2] then goal = (goal == away) and home or away end
          plan, idx = H.worldBfs(goal[1], goal[2]), 1
          if not plan or #plan == 0 then plan = nil; H.setPad({}) return end
        end
        local dir = plan[idx]; idx = idx + 1
        H.setPad({ [dir] = true })
      end),
    }, "a random encounter")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5),
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id == TERRA then terraS = s end
      if id == STRAGO then stragoS = s end
      if id == standId then standS = s end
    end
    assert(terraS and stragoS and standS, "the three are in the battle")
    local function dump(s)
      local t = {}
      for cell = 0, 53 do
        local a = listBase(s) + (cell + 1) * 4
        local id = H.readByte(a)
        if id ~= 0xFF then t[#t + 1] = string.format("%02X:%d%s", id, H.readByte(a + 3),
          (H.readByte(a + 1) & 0x80) ~= 0 and "g" or "") end
      end
      return table.concat(t, " ")
    end
    H.log(string.format("[mimic] battle slots: TERRA %d STRAGO %d stand-in %d; commands T[%02X %02X %02X %02X] "
      .. "stand[%02X %02X %02X %02X]", terraS, stragoS, standS,
      H.readByte(CMDTBL + terraS * 12), H.readByte(CMDTBL + terraS * 12 + 3),
      H.readByte(CMDTBL + terraS * 12 + 6), H.readByte(CMDTBL + terraS * 12 + 9),
      H.readByte(CMDTBL + standS * 12), H.readByte(CMDTBL + standS * 12 + 3),
      H.readByte(CMDTBL + standS * 12 + 6), H.readByte(CMDTBL + standS * 12 + 9)))
    H.log("[mimic] TERRA list " .. dump(terraS))
    H.log(string.format("[mimic] MP: TERRA %d STRAGO %d stand-in %d", mp(terraS), mp(stragoS), mp(standS)))
    for _, id in ipairs({ 0x00, 0x01, 0x02 }) do
      local cell, cost, fl = spellCell(terraS, id)
      if cell and (fl & 0x80) == 0 then picks.fam = id break end
    end
    local cell, cost, fl = spellCell(terraS, 0x04)
    if cell and (fl & 0x80) == 0 then picks.non = 0x04 end
    for row = 0, 23 do
      local a = listBase(stragoS) + (55 + row) * 4
      local id = H.readByte(a)
      if id ~= 0xFF and loreOffered(id) then picks.lore = id break end
    end
    H.log(string.format("[mimic] picks: family $%02X, non-family $%02X, lore %s",
      picks.fam or 0xFF, picks.non or 0xFF, picks.lore and string.format("$%02X", picks.lore) or "none"))
    assert(picks.fam and picks.non, "TERRA knows a family head and Drain")
    assert(cmdRow(standS, CMD_MIMIC), "the stand-in's battle list has Mimic")
    assert(cmdRow(terraS, CMD_XMAGIC), "TERRA's battle list has X-Magic")
  end),
  H.driveUntil(function() return snapX ~= nil and snapT ~= nil and snapS ~= nil end, 40000, {
    H.call(function()
      tick = tick + 1
      if tick % 12 ~= 0 and tick % 12 ~= 6 then return end
      if tick % 12 == 6 then H.setPad({}) return end
      -- X: TERRA's first window, while her HP is still high -- an x-magic's
      -- second spell waits out its own advance delay, and a TERRA worn down
      -- by the Defend rounds below was killed in it (try6-xmagic.log).  The
      -- opening pip is enough for the x-magic cases, which boost 0 or 1.
      if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD and snapX == nil
         and (H.readByte(ACTOR) & 3) == terraS and bank(standS) >= 1 and pend(terraS) == 0 then
        H.setPad({}); snapX = H.requestSaveState()
        H.log(string.format("[mimic] snapshot X f%d: stand-in bank %d MP %d, TERRA MP %d HP %d",
          H.frame, bank(standS), mp(standS), mp(terraS), H.readWord(0x3BF4 + terraS * 2)))
        return
      end
      if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) == ST_CMD and bank(standS) >= 3 then
        local a = H.readByte(ACTOR) & 3
        if a == terraS and snapT == nil and pend(terraS) == 0 then
          H.setPad({}); snapT = H.requestSaveState()
          H.log(string.format("[mimic] snapshot T f%d: stand-in bank %d MP %d, TERRA MP %d",
            H.frame, bank(standS), mp(standS), mp(terraS)))
          return
        end
        if a == stragoS and snapS == nil and pend(stragoS) == 0 then
          H.setPad({}); snapS = H.requestSaveState()
          H.log(string.format("[mimic] snapshot S f%d: stand-in bank %d MP %d, STRAGO MP %d",
            H.frame, bank(standS), mp(standS), mp(stragoS)))
          return
        end
      end
      if H.readByte(MENU) == 0 then return end
      local b = defendPress(H.readByte(MSTATE))
      H.setPad(b and { [b] = true } or {})
    end),
  }, "snapshots at TERRA's first window, and TERRA's and STRAGO's with 3 stand-in pips"),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(snapX, "snapshot X"); H.checkReq(snapT, "snapshot T"); H.checkReq(snapS, "snapshot S")
  end),
}

local function nm(id) return string.format("$%02X", id) end
local function addCase(snapName, c)
  steps[#steps + 1] = H.call(function()
    c.src = (snapName == "S") and stragoS or terraS
    local p = {}
    for _, k in ipairs(c.pickKeys) do p[#p + 1] = picks[k] end
    c.picks = p
    c.pickNames = {}
    for _, id in ipairs(p) do c.pickNames[#c.pickNames + 1] = nm(id) end
  end)
  for _, s in ipairs(runCase(setmetatable({}, { __index = function(_, k)
    if k == "blob" then return ({ X = snapX, T = snapT, S = snapS })[snapName].blob end
  end }), c)) do steps[#steps + 1] = s end
  steps[#steps + 1] = H.waitFrames(2)
  steps[#steps + 1] = H.call(function()
    c.pendAfter, c.bankAfter = pend(standS), bank(standS)
    H.log(string.format("[mimic] %s: two frames later pending %d bank %d", c.name, c.pendAfter, c.bankAfter))
  end)
end

local CASES = {
  { "T", { name = "fam-b0",   cmd = CMD_MAGIC,  pickKeys = { "fam" },        boost = 0 } },
  { "T", { name = "fam-b1",   cmd = CMD_MAGIC,  pickKeys = { "fam" },        boost = 1 } },
  { "T", { name = "fam-b3",   cmd = CMD_MAGIC,  pickKeys = { "fam" },        boost = 3 } },
  { "T", { name = "non-b0",   cmd = CMD_MAGIC,  pickKeys = { "non" },        boost = 0 } },
  { "T", { name = "non-b1",   cmd = CMD_MAGIC,  pickKeys = { "non" },        boost = 1 } },
  { "T", { name = "non-b3",   cmd = CMD_MAGIC,  pickKeys = { "non" },        boost = 3 } },
  { "T", { name = "srcfold-b0", cmd = CMD_MAGIC, pickKeys = { "fam" }, srcBoost = 1, boost = 0 } },
  { "X", { name = "x-fam-non-b0", cmd = CMD_XMAGIC, pickKeys = { "fam", "non" }, boost = 0 } },
  { "X", { name = "x-fam-non-b1", cmd = CMD_XMAGIC, pickKeys = { "fam", "non" }, boost = 1 } },
  { "X", { name = "x-non-fam-b0", cmd = CMD_XMAGIC, pickKeys = { "non", "fam" }, boost = 0 } },
  { "X", { name = "x-non-fam-b1", cmd = CMD_XMAGIC, pickKeys = { "non", "fam" }, boost = 1 } },
  { "S", { name = "lore-b0",  cmd = CMD_LORE,   pickKeys = { "lore" },       boost = 0 } },
  { "S", { name = "lore-b1",  cmd = CMD_LORE,   pickKeys = { "lore" },       boost = 1 } },
}
local ONLY = nil                 -- a case-name prefix, or nil for all of them
for _, e in ipairs(CASES) do
  if ONLY == nil or e[2].name:sub(1, #ONLY) == ONLY then addCase(e[1], e[2]) end
end

-- The verdict, once every case has logged (so a red run still shows all of
-- them).  mp-economy.md: Mimic is free at every boost, and the boost buys
-- what it buys on the copied action -- on a tier-family head, the tier.
steps[#steps + 1] = H.call(function()
  -- the family heads and their tiers, off the built ROM's Ot6FoldTbl
  -- (8 rows of [head, +1 tier, +2 tiers])
  local TIERS, tbl = {}, H.sym("Ot6FoldTbl") & 0x3FFFFF
  for r = 0, 7 do
    TIERS[H.readRomByte(tbl + r * 3)] = { H.readRomByte(tbl + r * 3 + 1), H.readRomByte(tbl + r * 3 + 2) }
  end
  local bad = {}
  for _, e in ipairs(CASES) do
    local c = e[2]
    if c.mp0 then
      local charged = c.mp0 - (c.mpEnd or c.mp0)
      local queued = 0
      for _, v in ipairs(c.standStores) do queued = queued + v end
      local verdict = ""
      if charged ~= 0 or queued ~= 0 then
        verdict = string.format("; CHARGED %d MP (queued %s)", charged, table.concat(c.standStores, ","))
      end
      -- a boosted copy of a family head casts the tier the boost buys.  The
      -- cast ids are Ot6BoostDmg's entries, one per damage calc; consecutive
      -- repeats (one per target) fold to one per spell
      local casts = {}
      for _, id in ipairs(c.castIds) do
        if casts[#casts] ~= id then casts[#casts + 1] = id end
      end
      c.casts = casts
      if c.boost > 0 and (c.srcBoost or 0) == 0 and c.cmd ~= CMD_LORE then   -- a lore id is not a spell id
        for i, pick in ipairs(c.picks or {}) do
          if TIERS[pick] then
            local want = TIERS[pick][math.min(c.boost, 2)]
            if casts[i] ~= want then
              verdict = verdict .. string.format("; spell %d cast $%02X, not the tier $%02X",
                i, casts[i] or 0xFF, want)
            end
          end
        end
      end
      if c.boost > 0 and c.bankAfter ~= c.bank0 - c.boost then
        verdict = verdict .. string.format("; bank %d -> %d, not spent %d", c.bank0, c.bankAfter, c.boost)
      end
      if verdict ~= "" then bad[#bad + 1] = c.name else verdict = "; ok" end
      local t = {}
      for _, id in ipairs(c.casts) do t[#t + 1] = string.format("$%02X", id) end
      H.log(string.format("[mimic] VERDICT %s boost %d: charged %d, cast %s%s", c.name, c.boost,
        charged, table.concat(t, "+"), verdict))
    end
  end
  assert(#bad == 0, "a boosted mimic was charged, or bought nothing: " .. table.concat(bad, " "))
end)

H.run({ maxFrames = 400000 }, steps)
