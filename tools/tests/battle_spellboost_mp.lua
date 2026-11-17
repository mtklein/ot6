-- @suite slow
-- battle_spellboost_mp.lua -- a point the MP cannot pay for is refused where it is pressed (#555).
--
-- The owner (#555): "let's deny the boost rather than quietly step it down."  R in a list raises the pending
-- boost only when the caster's MP pays what the row under the cursor costs at the raised boost (Ot6RaiseUnpaid:
-- the next tier of a spell family, the x2.5 of a multiplied row, a reach row's price again).  Before, the point
-- was taken, the row went grey and its confirm buzzed, and nothing could be cast on that row until L took the
-- point back.  On the command window nothing is picked yet: R stands there, and the list it opens shows every
-- row at that boost, greyed where the pool falls short, and refuses it (the A buzzes).
--
-- Played: Continue world-figaro-v1 (TERRA at level 5, a pool of about 30 MP: Fire 2's 20 but not Fire 3's 51),
-- meet an encounter on the desert row beside the save, and play through the real menu (H.kitBattle), banking
-- points by Defending first:
--   1. two points raised on the command window, then Magic: the Fire row reads Fire 3's price, grey, and its
--      A is refused (the list tells the truth; the boost stands there);
--   2. Fire with no boost, then two R taps on its row in the list: the first is taken (a ching, Fire 2, 20,
--      white), the second refused (a buzz, still 1 pending, the row still Fire 2's 20 and white); Fire 2 is
--      cast for that price and one point;
--   3. with the pool now under Fire 2's price, one R tap on Fire: refused (a buzz, nothing pending), and plain
--      Fire is cast for its own price and no point.
-- Each R tap is attributed by its sound: Ot6Boost chings an accepted point ($6281) and buzzes a refused one
-- ($95).  Nothing is written.
-- @checkpoint world-figaro-v1
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")
local TERRA = 0
local CMD_MAGIC = 0x02
local FIRE, FIRE2 = 0x00, 0x05
local SPELL_PTR = { [0] = 0x0000, [1] = 0x013C, [2] = 0x0278, [3] = 0x03B4 }

local function seat()
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == TERRA then return s end end
end
local function pend(s) return H.readByte(0x3E9D + s * 2) end
local function bank(s) return H.readByte(0x3E9C + s * 2) end
local function mp(s) return H.readWord(0x3C08 + s * 2) end
local function fireCell(s)
  for i = 0, 53 do
    local a = 0x2092 + SPELL_PTR[s] + i * 4
    if H.readByte(a) == FIRE then return a end
  end
end
-- MagicProp's price byte (+5, 14-byte records): the unboosted price of a spell, relics aside (TERRA wears no
-- MP relic here; asserted against the list's own byte at the open)
local MAGICPROP = H.sym("MagicProp") & 0x3FFFFF
local function baseMp(id) return H.readRomByte(MAGICPROP + id * 14 + 5) end

local CASES = {
  { name = "two points on the command window, then Magic", entry = { who = TERRA, cmd = CMD_MAGIC, spell = FIRE,
      boost = 2, refused = "list" }, refused = true },
  { name = "two R taps on Fire: the first taken, the second refused", entry = { who = TERRA, cmd = CMD_MAGIC,
      spell = FIRE, boost = 0, bank = 2, listR = 2 }, chings = 1, buzzes = 1, pend = 1, cast = FIRE2, spent = 1 },
  { name = "one R tap on Fire the pool cannot raise", entry = { who = TERRA, cmd = CMD_MAGIC, spell = FIRE,
      boost = 0, bank = 1, listR = 1 }, chings = 0, buzzes = 1, pend = 0, cast = FIRE, spent = 0 },
}

local case, ci, rec = nil, 1, nil
local plan = {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local sounds = nil                       -- { ching, buzz } while a case's R taps are counted

local function arm()
  emu.addMemoryCallback(function(_, v)
    if sounds and v ~= 0 then sounds.ching = sounds.ching + 1 end
  end, emu.callbackType.write, 0x7e6281, 0x7e6281)
  -- (`inc $95` is a direct-page store: it lands in bank $00, so both views are watched, as lib/ot6.lua's
  -- refusal note does)
  for _, page in ipairs({ 0x000000, 0x7E0000 }) do
    emu.addMemoryCallback(function(_, v)
      if sounds and v ~= 0 then sounds.buzz = sounds.buzz + 1 end
    end, emu.callbackType.write, page + 0x95, page + 0x95)
  end
  emu.addMemoryCallback(function()
    local s = seat()
    if rec == nil or rec.listed == nil or rec.mp0 ~= nil or s == nil then return end
    local x = emu.getState()["cpu.x"] & 0xFF
    if x ~= s * 2 or (H.readByte(0xB1) & 1) == 1 or H.readByte(0xB5) == 0x12 then return end
    rec.mp0, rec.bank0, rec.pend0 = mp(s), bank(s), pend(s)
  end, emu.callbackType.exec, H.sym("ExecCmd@battle_code"))
  emu.addMemoryCallback(function()
    local s = seat()
    if rec == nil or rec.mp0 == nil or rec.ended ~= nil or s == nil then return end
    if (emu.getState()["cpu.x"] & 0xFF) ~= s * 2 then return end
    rec.ended, rec.cmd, rec.atk = H.frame, H.readByte(0x3A7C), H.readByte(0x3A7D)
  end, emu.callbackType.exec, H.sym("Ot6ActionEnd"))
end

local function resolved()
  if case.refused then return rec.refusedDone == true end
  if rec == nil or rec.ended == nil or H.frame <= rec.ended + 30 then return false end
  if rec.mp1 == nil then
    local s = seat()
    rec.mp1, rec.bank1 = mp(s), bank(s)
  end
  return true
end

local function start()
  case = CASES[ci]
  rec = { name = case.name }
  plan = { case.entry }
  H.freshKitEntries(plan)
  sounds = nil
  local s = seat()
  H.log(string.format("[spellboost_mp] case %d (%s): TERRA seat %s, MP %d, bank %d", ci, case.name, tostring(s),
    s and mp(s) or -1, s and bank(s) or -1))
end

-- the list, as the cursor reaches Fire (before the R taps: the taps' sounds are counted from here)
local function readRow(a, tag)
  local c = fireCell(a)
  local r = { pend = pend(a), cost = H.readByte(c + 3), grey = (H.readByte(c + 1) & 0x80) ~= 0, mp = mp(a) }
  H.log(string.format("[spellboost_mp] f%d %s: pending %d, Fire's row %d MP (%s), pool %d", H.frame, tag,
    r.pend, r.cost, r.grey and "grey" or "white", r.mp))
  return r
end
local function onList(p, a)
  if p ~= case.entry or not case.refused or rec.shot then return end
  rec.shot = true
  H.screenshot("spellboost_mp_1_list")
end
local function onListR(p, a)
  if p ~= case.entry then return end
  rec.afterR = readRow(a, "after the R taps")
  rec.sounds = sounds
  H.log(string.format("[spellboost_mp] the %d R tap(s) made %d ching(s) and %d buzz(es)", p.listR,
    sounds.ching, sounds.buzz))
  sounds = nil
  H.screenshot(string.format("spellboost_mp_%d_afterR", ci))
  -- judged here, not only after the cast: a point the pool cannot pay for leaves a grey row whose A the kit
  -- would press until its timeout
  H.assertEq(rec.sounds.ching, case.chings, string.format("case %d: R taps taken (chings)", ci))
  H.assertEq(rec.sounds.buzz, case.buzzes, string.format("case %d: R taps refused (buzzes)", ci))
  H.assertEq(rec.afterR.pend, case.pend, string.format("case %d: the pending boost after the taps", ci))
  H.assertEq(rec.afterR.grey, false, string.format("case %d: the row stays white: what it shows can be cast", ci))
end

local function judge()
  local r = rec
  if case.refused then
    H.assertEq(r.listed.pend, 2, "case 1: two points pending as the cursor reaches Fire")
    H.assertEq(r.listed.cost > r.listed.mp, true, "case 1: Fire's row prices Fire 3, above the pool")
    H.assertEq(r.listed.grey, true, "case 1: and is grey")
    H.assertEq(H.vars.kit[#H.vars.kit].refusedSeen, true, "case 1: the A on the grey row was refused")
    return
  end
  H.log(string.format("[spellboost_mp] case %d: began pending %d bank %d MP %d; ended cmd $%02X attack $%02X; "
    .. "MP %d -> %d, bank %d -> %d", ci, r.pend0, r.bank0, r.mp0, r.cmd, r.atk, r.mp0, r.mp1, r.bank0, r.bank1))
  H.assertEq(r.afterR.cost <= r.afterR.mp, true, string.format("case %d: its price is in the pool", ci))
  H.assertEq(r.pend0, case.pend, string.format("case %d: the action began at that boost", ci))
  H.assertEq(r.atk, case.cast, string.format("case %d: the spell cast ($%02X)", ci, case.cast))
  H.assertEq(r.mp0 - r.mp1, r.afterR.cost, string.format("case %d: the MP charged is the price shown", ci))
  H.assertEq(r.bank0 - r.bank1 == case.spent or (case.spent == 0 and r.bank1 == r.bank0 + 1), true,
    string.format("case %d: the bank paid %d point(s) (%d -> %d; an unboosted turn earns one)", ci, case.spent,
      r.bank0, r.bank1))
  if ci == 3 then
    H.assertEq(r.afterR.cost, baseMp(FIRE), "case 3: plain Fire's own price")
    H.assertEq(r.mp0 < baseMp(FIRE2), true, "case 3: the pool is under Fire 2's price, the tier R would buy")
  end
end

-- the list as the cursor first rests on Fire for the case's pick, before any R tap; the R taps' sounds are
-- counted from there to the end of the taps (onListR)
local function countWhenListed()
  if rec == nil or rec.listed ~= nil or H.readByte(0x7BCA) == 0 or H.readByte(0x7BC2) ~= 0x0E then return end
  local s = seat()
  if s == nil or (H.readByte(0x62CA) & 3) ~= s or not case.entry.opened then return end
  local idx
  for i = 0, 53 do
    if H.readByte(0x2092 + SPELL_PTR[s] + i * 4) == FIRE then idx = i end
  end
  if idx == nil or H.readByte(0x8913 + s) + H.readByte(0x891B + s) ~= idx // 2
     or H.readByte(0x8917 + s) ~= idx % 2 then return end
  rec.listed = readRow(s, "the cursor on Fire")
  if not case.refused then
    sounds = { ching = 0, buzz = 0 }
    H.screenshot(string.format("spellboost_mp_%d_list", ci))
  end
end

local tries = 0
H.run({ maxFrames = 600000 }, {
  H.bootCheckpoint("world-figaro-v1"),
  H.call(function()
    arm()
    emu.addEventCallback(countWhenListed, emu.eventType.startFrame)
    start()
  end),
  H.driveUntil(function() return ci > #CASES end, 580000, {
    H.cond(function() return not H.battleLoadStarted() end, {
      H.seqStep(H.newEncounterDraw({ tag = "spellboost_mp", minBodies = 1, minHp = 0, pace = 4 }).steps()) }, {}),
    H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000, onList = onList,
      onListR = onListR, planDone = function()
        if case.refused and H.vars.kit[#H.vars.kit] and H.vars.kit[#H.vars.kit].refusedSeen then
          rec.refusedDone = true
        end
        return resolved()
      end }),
    H.call(function()
      if resolved() then
        judge()
        H.log(string.format("[spellboost_mp] case %d PASSED", ci))
        ci = ci + 1
        tries = 0
        if ci <= #CASES then start() end
      else
        tries = tries + 1
        H.log(string.format("[spellboost_mp] case %d: the battle ended before the case resolved (try %d): again",
          ci, tries))
        H.assertEq(tries <= 6, true, "each case resolves within six battles")
        start()
      end
    end),
    H.cond(function() return H.battleLoadStarted() and ci > #CASES end, { H.kitBattle({}, {}) }, {}),
  }, "the three cases"),
})
