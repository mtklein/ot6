-- @suite slow
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_gogomimic.lua -- GOGO's Mimic at three of his points buys the copied
-- action's owner extra (#559; docs/design/kit-gogo.md section 4).
--
-- Since #547 the divines keyed on the owner's actor id answer for GOGO
-- (actor $0C) whatever command he uses, and a copy reads his own pending
-- boost where the copied action reads one (Ot6MimicFold, Ot6MimicKeep).  So a
-- Mimic of an owner's plain (0 BP) action, copied with three of GOGO's
-- points pending, is the owner's divine: battle_gogokits plays his own
-- commands; this suite plays the copies.
--
-- Played (battle_gogokits' machinery, one declared staging per arm that needs
-- it; state_write_waivers.txt): Continue wor-colosseum-v1 (beside the Falcon
-- by Maranda), board, and in the Falcon's cabin seat the round's party; lift
-- off, land again by Maranda, set GOGO's three commands in his Status menu
-- (row 0 stays Mimic; none of them the copied command, so only the Mimic
-- reaches it), and pace the world map into random battles.  In each battle,
-- through the real menu (H.kitBattle), the owner plays the plain action and
-- GOGO, his bank filled to 3 by real Defends, raises three points with R and
-- picks Mimic once that action has run (the others Defend; no Item care
-- while a copy is in flight, so the last action is the owner's).  Every copy
-- is read where the engine makes it (mimicreplace for his seat: the copied
-- command and attack, $3F20, and the pips pending, $3E9D) and where it runs
-- (ExecCmd for his seat).  A copy of another action, or one at another
-- boost, is not counted and the pair is played again in a later battle.
--   M1 (GOGO, EDGAR, CELES, SHADOW; GOGO's commands Steal, Blitz, Rage)
--     * overclock: a copy of EDGAR's 0-BP Debilitator, at 3 of GOGO's
--       points, fires twice (Ot6PassTargeted for his seat: 2 passes);
--     * blade: a copy of CELES's 0-BP Runic at 3 is a RunicBlade (his
--       OT6_RUNICBLADE bit when the copy ends);
--     * assassinate: a copy of SHADOW's 0-BP Shuriken at 3 marks Death on
--       the Broken non-boss it hits (Ot6AssassinateGate's write).  The
--       staging is battle_gogokits': every standing non-boss monster without
--       a Death ward is Broken (OT6_BROKEN_TICKS) as the copy begins; no
--       party here breaks one on cue.
--   M2 (GOGO, TERRA, STRAGO, RELM; GOGO's commands Lore, Steal, Blitz)
--     * ultima: a copy of TERRA's 0-BP Fire at 3 runs as Ultima ($14; $B6 at
--       ExecCmd), TERRA's fourth fold, once she has rejoined (switch $00BF);
--     * study: a copy of STRAGO's 0-BP Scan at 3, GOGO carrying Lore, writes
--       exactly the lores the present species could teach that STRAGO lacks
--       (Ot6StudyOne's $3A84 writes).  The staging is battle_gogokits' (the
--       battle_study expedient): STRAGO knows every lore this plain's
--       casters cast, so those bits of $1D29 are cleared at the open of the
--       battle the study is played in, and put back if no study taught them.
-- Each assertion has its mutant, the arm's Gogo compare in its leaf
-- (build/attempts/wt/v051-tests/mutants/mutants.py): overclock
-- (Ot6Overclocks), blade (Ot6BladeRaise), assassin (Ot6AssassinateGate),
-- ultima (Ot6FoldSteps), study (Ot6StudyCaster); each is red at its own
-- check.  Runs: build/attempts/wt/v051-tests/gogomimic/.
--
-- Lever, for evidence only (the suite runs BURN 0; a lab sets the global
-- GOGOMIMIC_BURN ahead of the file): the walker fights that many encounters
-- by the landing first, to vary the encounter history (TESTING.md).
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, SHADOW, EDGAR, CELES, STRAGO, RELM, GOGO = 0x00, 0x03, 0x04, 0x06, 0x07, 0x08, 0x0C
local NAMES = { [TERRA] = "TERRA", [SHADOW] = "SHADOW", [EDGAR] = "EDGAR", [CELES] = "CELES", [STRAGO] = "STRAGO",
  [RELM] = "RELM", [GOGO] = "GOGO" }
local CMD = { MAGIC = 0x02, STEAL = 0x05, THROW = 0x08, TOOLS = 0x09, BLITZ = 0x0A, RUNIC = 0x0B, LORE = 0x0C,
  RAGE = 0x10, MIMIC = 0x12 }
local FIRE, SCAN, ULTIMA = 0x00, 0x18, 0x14
local DEBIL, SHURIKEN = 0xA7, 0x41
local BREAK_TICKS = 16                                     -- a staged break's length (OT6_BROKEN_TICKS)
local RUNICBLADE = 0x7EEDD4                                -- OT6_RUNICBLADE (ot6_memory.inc)
local LANDING = { 69, 183 }                                 -- the Falcon's tile by Maranda (wor-colosseum-v1's)
local BURN = type(GOGOMIMIC_BURN) == "number" and GOGOMIMIC_BURN or 0
local MAX_BATTLES = 24
local ROUND_BATTLES = 10                                   -- a round's arms all played within this many
local DANGER = 1 / 3
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

local K = H.worLegKit({ fight = FIGHT, names = NAMES })
local regroup, liftOff, say = K.regroup, K.liftOff, K.say

local function sw(n) return (H.readByte(0x1E80 + (n >> 3)) >> (n & 7)) & 1 end
local function hx(t)
  local s = {}
  for _, v in ipairs(t) do s[#s + 1] = string.format("%02X", v) end
  return table.concat(s, " ")
end

-- ---- GOGO's commands (battle_gogokits' field-menu walk) ----------------------
local REC = 0x1600 + 37 * GOGO
local function gogoCmdByte(row) return H.readByte(REC + 0x16 + row) end
local function gogoCommands(want, what)
  local ph, idx, listLogged = 0, 1, false
  local function st() return H.menuRunning() and H.readByte(0x26) or -1 end
  local function steer(cur, row)
    if cur == row then return { "a" } end
    return { [cur < row and "down" or "up"] = true }
  end
  local function gogoPos()
    local b = H.readByte(0x1850 + GOGO)
    if (b & 7) == H.activeParty() then return (b >> 3) & 3 end
    return nil
  end
  local function allSet()
    for _, w in ipairs(want) do if gogoCmdByte(w[1]) ~= w[2] then return false end end
    return true
  end
  local function ctl() return H.hasControl() or (H.worldMode() and H.worldHasControl()) end
  return H.withReset(H.seqStep({
    H.driveUntil(function() return allSet() and not H.menuRunning() and ctl() end, 9000, {
      H.call(function()
        ph = (ph + 1) % 12
        local s = st()
        local held = {}
        while idx <= #want and gogoCmdByte(want[idx][1]) == want[idx][2] do idx = idx + 1 end
        if allSet() then
          if s ~= -1 then held = { "b" } end
        elseif s == -1 then
          if ctl() then held = { "x" } end
        elseif s == 0x05 then
          held = steer(H.readByte(0x4B), 4)
        elseif s == 0x06 then
          local p = gogoPos()
          if p == nil then error(what .. ": GOGO is not in the active party", 0) end
          held = steer(H.readByte(0x4B), p)
        elseif s == 0x0C then
          held = steer(H.readByte(0x4B), want[idx][1])
        elseif s == 0x6A then
          local n = H.readByte(0x7E9D89)
          if not listLogged then
            local t = {}
            for r = 0, n - 1 do t[#t + 1] = H.readByte(0x7E9D8A + r) end
            H.log(string.format("[gogomimic] %s: GOGO's command list (%d): %s", what, n, hx(t)))
            listLogged = true
          end
          local row = nil
          for r = 0, n - 1 do if H.readByte(0x7E9D8A + r) == want[idx][2] then row = r end end
          if row == nil then error(string.format("%s: command $%02X is not in GOGO's list", what, want[idx][2]), 0) end
          held = steer(H.readByte(0x4B), row)
        end
        if ph < 4 then H.setPad(held) else H.setPad({}) end
      end),
    }, what),
    H.call(function()
      H.log(string.format("[gogomimic] %s: GOGO's commands %02X %02X %02X %02X", what, gogoCmdByte(0),
        gogoCmdByte(1), gogoCmdByte(2), gogoCmdByte(3)))
      H.assertEq(gogoCmdByte(0), CMD.MIMIC, what .. ": GOGO's first command is Mimic")
    end),
  }), function() ph, idx, listLogged = 0, 1, false end)
end

-- ---- the battle's seats --------------------------------------------------------
local seatOf = {}
local function findSeats()
  seatOf = {}
  for s = 0, 3 do
    local id = H.readByte(0x3ED8 + s * 2)
    if id ~= 0xFF then seatOf[id] = s end
  end
end
local function gseat() return seatOf[GOGO] end
local function mpOf(s) return H.readWord(0x3C08 + s * 2) end
local function present(m) return (H.readByte(0x3AA8 + m * 2) & 1) == 1 end
local function species(m) return H.readWord(0x57C0 + m * 2) end
local function lores() return H.readByte(0x1D29) | H.readByte(0x1D2A) << 8 | H.readByte(0x1D2B) << 16 end
local function studyRow(sp)
  local a = H.sym("Ot6StudyTbl") & 0x3FFFFF
  while true do
    local s = H.readRomByte(a) | H.readRomByte(a + 1) << 8
    if s == 0xFFFF then return 0 end
    if s == sp then return H.readRomByte(a + 2) | H.readRomByte(a + 3) << 8 | H.readRomByte(a + 4) << 16 end
    a = a + 5
  end
end

-- ---- observers ---------------------------------------------------------------
-- acts: every action GOGO runs: { copy = { cmd, atk, pend } (mimicreplace, or
-- nil for his own command), cmd, atk ($b5/$b6 at ExecCmd), pend, mp0, mp1,
-- passes (Ot6PassTargeted), marks (Ot6AssassinateGate's Death writes), staged,
-- studied (Ot6StudyOne's $3A84 writes), want, blade, f }
-- src: the last action each owner ran, { cmd, atk, f } at its ExecCmd
local acts, cur, copyAt, src = {}, nil, nil, {}
local inflight = nil   -- the arm whose copy is queued or running (no Item care meanwhile)
local awaiting = nil   -- the arm whose owner's action has run, its copy still to come (no Item care either)
local round = nil
local function closeAct()
  if cur == nil or not cur.ended or H.frame <= cur.ended + 1 then return false end
  cur.mp1 = mpOf(cur.seat)
  acts[#acts + 1] = cur
  local c = cur.copy
  H.log(string.format("[gogomimic] GOGO's action %d (f%d): %s; ran cmd $%02X atk $%02X at %d BP: MP %d -> %d, "
    .. "passes %d, marks %d (staged $%02X), studied $%06X (want $%06X), blade %s", #acts, cur.f,
    c and string.format("a Mimic's copy of cmd $%02X atk $%02X at %d BP", c.cmd, c.atk, c.pend) or "his own command",
    cur.cmd, cur.atk, cur.pend, cur.mp0, cur.mp1, cur.passes, cur.marks, cur.staged or 0, cur.studied, cur.want,
    tostring(cur.blade)))
  if c ~= nil then inflight, awaiting = nil, nil end
  cur = nil
  return true
end

local installed = false
local function install()
  if installed then return end
  installed = true
  local function cpu() return emu.getState() end
  local function pc(st) return (st["cpu.k"] << 16) | st["cpu.pc"] end
  local mr = H.sym("mimicreplace")
  emu.addMemoryCallback(function()
    local s = gseat()
    if s == nil or (cpu()["cpu.x"] & 0xFF) ~= s * 2 then return end
    copyAt = { cmd = H.readByte(0x3F20), atk = H.readByte(0x3F21), pend = H.readByte(0x3E9D + s * 2), f = H.frame }
    H.log(string.format("[gogomimic] f%d GOGO's Mimic copies cmd $%02X atk $%02X with %d BP pending", H.frame,
      copyAt.cmd, copyAt.atk, copyAt.pend))
  end, emu.callbackType.exec, mr, mr)
  emu.addMemoryCallback(function()
    local x = cpu()["cpu.x"] & 0xFF
    if x >= 8 or (H.readByte(0xB1) & 1) == 1 then return end
    local id = H.readByte(0x3ED8 + x)
    if id ~= GOGO then
      -- (a Defend or a Row change runs here too and is never mimicked)
      if H.readByte(0xB5) == 0x15 or H.readByte(0xB5) == 0x14 then return end
      src[id] = { cmd = H.readByte(0xB5), atk = H.readByte(0xB6), f = H.frame, pend = H.readByte(0x3E9D + x) }
      H.log(string.format("[gogomimic] f%d %s runs cmd $%02X atk $%02X at %d BP ($3A7C/D $%02X $%02X)", H.frame,
        NAMES[id] or string.format("$%02X", id), src[id].cmd, src[id].atk, src[id].pend, H.readByte(0x3A7C),
        H.readByte(0x3A7D)))
      for _, arm in ipairs(round and round.arms or {}) do
        if arm.owner == id and arm.cmd == src[id].cmd and (arm.atk == nil or arm.atk == src[id].atk) then
          awaiting = arm.tag
        end
      end
      return
    end
    local s = x // 2
    local want = 0
    for m = 0, 5 do if present(m) then want = want | studyRow(species(m)) end end
    cur = { copy = copyAt, cmd = H.readByte(0xB5), atk = H.readByte(0xB6), pend = H.readByte(0x3E9D + x),
      seat = s, mp0 = mpOf(s), passes = 0, marks = 0, studied = 0, want = want & ~lores() & 0xFFFFFF, f = H.frame,
      planned = copyAt and inflight }
    copyAt = nil
    if cur.copy ~= nil and cur.cmd == CMD.THROW and cur.pend >= 3 then
      -- the declared staging (state_write_waivers.txt; battle_gogokits'):
      -- every standing non-boss monster without a Death ward is Broken as
      -- GOGO's 3-BP copy of a throw begins, so the divine has a body it may
      -- kill; OT6_BROKEN_TICKS is what Ot6AssassinateGate reads
      cur.staged = 0
      for m = 0, 5 do
        local e = 8 + m * 2
        if present(m) and H.readWord(0x3BF4 + e) > 0 and (H.readByte(0x3AA1 + e) & 0x04) == 0 then
          H.writeByte(0x3E88 + e, BREAK_TICKS)
          cur.staged = cur.staged | (1 << m)
        end
      end
      if cur.staged == 0 then
        H.log(string.format("[gogomimic] f%d GOGO's copied throw: no standing monster without a Death ward to "
          .. "stage: not counted, played again next battle", H.frame))
      end
    end
  end, emu.callbackType.exec, H.sym("ExecCmd@battle_code"), H.sym("ExecCmd@battle_code"))
  -- the copy's source is stored once the action has run (SaveForMimic, after ExecCmd's animation)
  local sm = H.sym("SaveForMimic")
  emu.addMemoryCallback(function()
    local x = cpu()["cpu.x"] & 0xFF
    if x >= 8 then return end
    local r = src[H.readByte(0x3ED8 + x)]
    if r ~= nil and r.saved == nil then r.saved = H.frame end
  end, emu.callbackType.exec, sm, sm)
  local pt = H.sym("Ot6PassTargeted")
  emu.addMemoryCallback(function()
    if cur and not cur.ended and (cpu()["cpu.x"] & 0xFF) == cur.seat * 2 then cur.passes = cur.passes + 1 end
  end, emu.callbackType.exec, pt, pt)
  local ag = H.sym("Ot6AssassinateGate")
  emu.addMemoryCallback(function(_, v)
    local p = pc(cpu())
    if cur and not cur.ended and p >= ag and p < ag + 0x60 and (v & 0x80) ~= 0 then cur.marks = cur.marks + 1 end
  end, emu.callbackType.write, 0x7E3DD4, 0x7E3DE7)
  local so = H.sym("Ot6StudyOne")
  emu.addMemoryCallback(function(addr, v)
    local p = pc(cpu())
    if cur and not cur.ended and p >= so and p < so + 96 then
      cur.studied = cur.studied | (v << (8 * (addr - 0x7E3A84)))
    end
  end, emu.callbackType.write, 0x7E3A84, 0x7E3A86)
  emu.addEventCallback(function() if cur ~= nil then closeAct() end end, emu.eventType.endFrame)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if cur == nil or cur.ended or (cpu()["cpu.x"] & 0xFF) ~= cur.seat * 2 then return end
    local s = cur.seat
    cur.ended = H.frame
    cur.blade = (emu.read(RUNICBLADE, emu.memType.snesMemory) & H.readByte(0x3018 + s * 2)) ~= 0
  end, emu.callbackType.exec, ae, ae)
end

-- ---- the arms ---------------------------------------------------------------------
-- Each arm: the owner's plain action (`src`, a kitBattle entry at 0 BP), the
-- copy it wants (cmd, atk), and `check(a)` on GOGO's action that copied it.
local got = {}         -- tag -> GOGO's action that counted
local function copyOf(arm, from)
  for i = #acts, from or 1, -1 do
    local a = acts[i]
    if a.copy and a.planned == arm.tag and a.copy.cmd == arm.cmd and (arm.atk == nil or a.copy.atk == arm.atk) and a.copy.pend == 3
       and (arm.counts == nil or arm.counts(a)) then
      return a
    end
  end
  return nil
end

local ROUNDS = {
  { tag = "M1", party = { GOGO, EDGAR, CELES, SHADOW }, cmds = { { 1, CMD.STEAL }, { 2, CMD.BLITZ }, { 3, CMD.RAGE } },
    arms = {
      { tag = "overclock", owner = EDGAR, cmd = CMD.TOOLS, atk = DEBIL,
        src = { who = EDGAR, cmd = CMD.TOOLS, row = DEBIL, boost = 0 },
        pre = function()
          H.assertEq(sw(0x68), 1, "M1 precondition: Overclock is learned (switch $0068, the Magitek factory in "
            .. "gen_esper_tubes)")
        end,
        check = function(a)
          H.assertEq(a.passes, 2, string.format("M1: GOGO's Mimic of EDGAR's 0-BP Debilitator, copied at 3 of his "
            .. "points, fires twice (Overclock; EDGAR's own ran at %d BP)", got.overclockSrc or -1))
        end },
      { tag = "blade", owner = CELES, cmd = CMD.RUNIC,
        src = { who = CELES, cmd = CMD.RUNIC, boost = 0, self = true },
        pre = function()
          H.assertEq(sw(0x68), 1, "M1 precondition: RunicBlade is learned (switch $0068)")
        end,
        check = function(a)
          H.assertEq(a.blade, true, "M1: GOGO's Mimic of CELES's 0-BP Runic, copied at 3 of his points, is a "
            .. "RunicBlade (his OT6_RUNICBLADE bit)")
        end },
      { tag = "assassinate", owner = SHADOW, cmd = CMD.THROW, atk = SHURIKEN,
        counts = function(a) return a.staged ~= nil and a.staged ~= 0 end,
        src = { who = SHADOW, cmd = CMD.THROW, row = SHURIKEN, boost = 0 },
        check = function(a)
          H.assertEq(a.marks > 0, true, string.format("M1: GOGO's Mimic of SHADOW's 0-BP Shuriken, copied at 3 of "
            .. "his points, marks Death on the Broken non-boss it hits (Assassinate; %d mark(s), staged $%02X)",
            a.marks, a.staged))
        end },
    } },
  { tag = "M2", party = { GOGO, TERRA, STRAGO, RELM }, cmds = { { 1, CMD.LORE }, { 2, CMD.STEAL }, { 3, CMD.BLITZ } },
    arms = {
      { tag = "ultima", owner = TERRA, cmd = CMD.MAGIC, atk = FIRE,
        src = { who = TERRA, cmd = CMD.MAGIC, spell = FIRE, boost = 0 },
        pre = function()
          H.assertEq(sw(0xBF), 1, "M2 precondition: TERRA has rejoined in the World of Ruin (switch $00BF, "
            .. "gen_wor_terra)")
        end,
        check = function(a)
          H.assertEq(a.atk, ULTIMA, "M2: GOGO's Mimic of TERRA's 0-BP Fire, copied at 3 of his points, runs as "
            .. "Ultima ($14), TERRA's fourth fold")
        end },
      { tag = "study", owner = STRAGO, cmd = CMD.MAGIC, atk = SCAN,
        counts = function(a) return a.want ~= 0 end,
        src = { who = STRAGO, cmd = CMD.MAGIC, spell = SCAN, boost = 0 },
        pre = function()
          local carries = false
          for r = 1, 3 do if gogoCmdByte(r) == CMD.LORE then carries = true end end
          H.assertEq(carries, true, "M2 precondition: GOGO carries Lore")
        end,
        check = function(a)
          H.assertEq(a.studied, a.want, string.format("M2: GOGO's Mimic of STRAGO's 0-BP Scan, copied at 3 of his "
            .. "points with Lore carried, studies: it adds exactly the lores the present species could teach that "
            .. "STRAGO lacks (want $%06X, wrote $%06X)", a.want, a.studied))
        end },
    } },
}

-- ---- the battle loop -------------------------------------------------------------
local battles, roundBattles = 0, 0
local plan, entryArm = {}, {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local function armDone(arm) return got[arm.tag] ~= nil end
local function roundDone(r)
  for _, arm in ipairs(r.arms) do if not armDone(arm) then return false end end
  return true
end
-- an arm's copy counted: record it (the check runs at the round's end)
local function settle()
  if cur ~= nil then closeAct() end
  for _, arm in ipairs(round.arms) do
    if not armDone(arm) then
      local a = copyOf(arm, got.battleActs)
      if a ~= nil then
        got[arm.tag] = a
        H.log(string.format("[gogomimic] %s: counted (GOGO's action at f%d)", arm.tag, a.f))
      end
    end
  end
end
local handed = nil
local function danger()
  if not H.battleActive() then return nil end
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
      local hp, mx, st1 = H.readWord(0x3BF4 + s * 2), H.readWord(0x3C1C + s * 2), H.readByte(0x3EE4 + s * 2)
      if mx > 0 and mx < 10000 and (hp == 0 or (st1 & 0xC2) ~= 0 or hp < mx * DANGER) then
        return string.format("seat %d at %d/%d HP, status1 $%02X", s, hp, mx, st1)
      end
    end
  end
  return nil
end
local skipStudy = false
local function decide()
  battles, roundBattles = battles + 1, roundBattles + 1
  H.assertEq(battles <= MAX_BATTLES, true, string.format("the two rounds within %d battles", MAX_BATTLES))
  if roundBattles > ROUND_BATTLES then
    local left = {}
    for _, arm in ipairs(round.arms) do if not armDone(arm) then left[#left + 1] = arm.tag end end
    H.assertEq(#left, 0, string.format("%s: every arm played within %d battles (never counted: %s)", round.tag,
      ROUND_BATTLES, table.concat(left, ", ")))
  end
  findSeats()
  handed, plan, entryArm, inflight, awaiting = nil, {}, {}, nil, nil
  got.battleActs = #acts + 1
  got.battleF0 = H.frame
  H.assertEq(gseat() ~= nil, true, "GOGO is seated")
  local s = gseat()
  local fw = H.formationWords()
  H.log(string.format("[gogomimic] battle %d, round %s (formation %04X %04X %04X %04X %04X %04X; $BE $%02X): GOGO "
    .. "seat %d, L%d, MP %d, bank %d", battles, round.tag, fw[1], fw[2], fw[3], fw[4], fw[5], fw[6],
    H.readByte(0xBE), s, K.lv(GOGO), mpOf(s), H.readByte(0x3E9C + s * 2)))
  skipStudy = false
  if round.tag == "M2" and not armDone(round.arms[2]) then
    -- the lores the present species cast (Ot6StudyTbl rows): STRAGO knows
    -- every one this plain's casters know, so the declared staging
    -- (state_write_waivers.txt, the battle_study expedient) unlearns them
    -- for the study to teach again
    local rows = 0
    for m = 0, 5 do if present(m) then rows = rows | studyRow(species(m)) end end
    if rows == 0 then
      skipStudy = true
      H.log("[gogomimic] no present species casts a lore: the study waits for another battle")
    elseif rows & ~lores() & 0xFFFFFF == 0 then
      got.studyCleared = rows & lores()
      for b = 0, 2 do
        H.writeByte(0x1D29 + b, H.readByte(0x1D29 + b) & ~((got.studyCleared >> (8 * b)) & 0xFF))
      end
      H.log(string.format("[gogomimic] staged: lores $%06X unlearned for the study -> $1D29 $%06X", got.studyCleared,
        lores()))
    end
  end
  for _, arm in ipairs(round.arms) do
    if not armDone(arm) and seatOf[arm.owner] ~= nil and not (arm.tag == "study" and skipStudy) then
      local p = {}
      for k, v in pairs(arm.src) do p[k] = v end
      plan[#plan + 1] = p
      entryArm[p] = arm
      -- GOGO's Mimic, once the owner's action has run in this battle and is
      -- the last one (the copy's source: SaveForMimic's $3F20)
      local m = { who = GOGO, cmd = CMD.MIMIC, boost = 3, self = true }
      m.openWhen = function()
        local r = src[arm.owner]
        local ok = r ~= nil and r.f >= got.battleF0 and r.saved ~= nil and H.frame > r.saved and r.cmd == arm.cmd and H.readByte(0x3F20) == arm.cmd
          and (arm.atk == nil or H.readByte(0x3F21) == arm.atk)
        if ok and inflight ~= arm.tag then
          inflight = arm.tag
          got[arm.tag .. "Src"] = r.pend
        end
        return ok
      end
      -- the owner's action ran but is no longer the last one (another
      -- member's action, or a counter -- SHADOW's Interceptor -- ran since):
      -- the copy would be of that, so this pair waits for another battle
      m.skip = function()
        local r = src[arm.owner]
        if r == nil or r.f < got.battleF0 or r.saved == nil or H.frame <= r.saved or inflight == arm.tag then
          return false
        end
        local gone = r.cmd ~= arm.cmd or H.readByte(0x3F20) ~= arm.cmd
          or (arm.atk ~= nil and H.readByte(0x3F21) ~= arm.atk)
        if gone then
          awaiting = nil
          H.log(string.format("[gogomimic] f%d %s: the owner's action is no longer the last one ($3F20 $%02X $%02X): "
            .. "played again next battle", H.frame, arm.tag, H.readByte(0x3F20), H.readByte(0x3F21)))
        end
        return gone
      end
      plan[#plan + 1] = m
      entryArm[m] = arm
    end
  end
  local tags = {}
  for _, p in ipairs(plan) do tags[#tags + 1] = (p.who == GOGO and "mimic:" or "") .. entryArm[p].tag end
  H.log(string.format("[gogomimic] battle %d plan: %s", battles, table.concat(tags, ", ")))
end
-- the plan has resolved: as many of GOGO's copies have run this battle as
-- it planned Mimics (a copy that did not count is played again next battle)
local function planDone()
  if cur ~= nil then return false end
  local want, ran = 0, 0
  for _, p in ipairs(plan) do if p.who == GOGO then want = want + 1 end end
  for i = got.battleActs, #acts do if acts[i].copy ~= nil then ran = ran + 1 end end
  return ran >= want
end

local A, B = nil, nil
local function worldBattle(tag)
  return H.seqStep({
    H.waitUntil(function() return H.worldMode() and H.worldHasControl() and H.worldSettled() end, 6000,
      tag .. ": world control", 5),
    H.call(function()
      if A ~= nil then return end
      local x, y = H.worldX(), H.worldY()
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } }) do
        local bx, by = x + d[1], y + d[2]
        if B == nil and H.worldPassable(bx, by) then A, B = { x, y }, { bx, by } end
      end
      H.assertEq(B ~= nil, true, string.format("%s: a passable world tile beside (%d,%d)", tag, x, y))
      H.log(string.format("[gogomimic] pacing world (%d,%d) <-> (%d,%d)", A[1], A[2], B[1], B[2]))
    end),
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return B[1] end, function() return B[2] end,
        { maxFrames = 4000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() A, B = B, A end),
    }, tag .. ": a random battle on the world map"),
    H.waitUntil(function() return H.battleActive() end, 1200, tag .. ": the battle is up", 2),
  })
end

local function playRound(r, first)
  return H.seqStep({
    H.call(function() roundBattles, round = 0, r end),
    regroup(r.party),
    liftOff(),
    H.waitUntil(function() return H.airshipControl() end, 3000, "the pilot's controls", 5),
    H.flyTo(LANDING[1], LANDING[2], { what = "the Falcon back by Maranda", fight = FIGHT }),
    H.waitUntil(function() return H.worldMode() and H.worldHasControl() end, 6000, "world control on the landing", 5),
    H.call(function() A, B = nil, nil end),
    H.lazy(function()
      local t = {}
      for i = 1, first and BURN or 0 do
        t[#t + 1] = worldBattle("BURN " .. i)
        t[#t + 1] = H.fightBattleByMenu(60000)
        t[#t + 1] = H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000,
          "BURN: back on the world map", 5)
        t[#t + 1] = H.call(function()
          H.log(string.format("[gogomimic] BURN %d: encounters used up; $1FA1-5 = %02X %02X %02X %02X %02X", i,
            H.readByte(0x1FA1), H.readByte(0x1FA2), H.readByte(0x1FA3), H.readByte(0x1FA4), H.readByte(0x1FA5)))
        end)
      end
      return H.seqStep(t)
    end),
    H.release(),
    H.waitFrames(10),
    gogoCommands(r.cmds, r.tag .. ": GOGO's commands"),
    H.call(function()
      for _, arm in ipairs(r.arms) do
        if arm.pre then arm.pre() end
        for i = 1, 3 do
          H.assertEq(gogoCmdByte(i) ~= arm.cmd, true, string.format("%s precondition: GOGO's own commands hold no "
            .. "$%02X (%s's copy comes from Mimic alone)", r.tag, arm.cmd, arm.tag))
        end
      end
    end),
    H.driveUntil(function()
      return roundDone(r) and not H.battleLoadStarted() and H.worldMode() and H.worldHasControl()
    end, 900000, {
      H.cond(function() return not H.battleLoadStarted() end, {
        H.fieldCare({ tag = r.tag .. ": care", threshold = 0.95, mpBand = 0.95 }),
        worldBattle(r.tag),
      }, {}),
      H.call(decide),
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 90000, planDone = planDone,
        -- no new Item care while a copy is in flight: an Item is mimicked too
        care = function() return inflight == nil and awaiting == nil end,
        giveUp = function()
          if handed == nil then handed = danger() end
          return handed ~= nil
        end }),
      H.call(function()
        settle()
        if handed then H.log(string.format("[gogomimic] battle %d handed to the fight driver: %s", battles, handed)) end
      end),
      H.cond(function() return H.battleLoadStarted() end, { H.fightBattleByMenu(60000) }, {}),
      H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000,
        "back on the world map", 5),
      H.call(function()
        settle()
        -- the study's settlement: lores the staging cleared that no study
        -- taught this battle are put back
        if got.studyCleared ~= nil and (lores() & got.studyCleared) ~= got.studyCleared then
          for b = 0, 2 do
            H.writeByte(0x1D29 + b, H.readByte(0x1D29 + b) | ((got.studyCleared >> (8 * b)) & 0xFF))
          end
          H.log(string.format("[gogomimic] lores $%06X put back", got.studyCleared))
        end
        got.studyCleared = nil
      end),
    }, r.tag .. ": every arm played"),
    H.call(function()
      for _, arm in ipairs(r.arms) do arm.check(got[arm.tag]) end
      H.log(string.format("[gogomimic] %s PASS", r.tag))
    end),
  })
end

local body = {
  H.bootCheckpoint("wor-colosseum-v1"),
  H.call(function()
    say("wor", "boot")
    install()
    H.assertEq(H.invCountOf(SHURIKEN) >= 2, true, "the bag holds two Shuriken (SHADOW's throw and the copy's)")
    H.assertEq(H.invCountOf(DEBIL) >= 1, true, "the bag holds a Debilitator (EDGAR's Tools)")
  end),
}
for i, r in ipairs(ROUNDS) do body[#body + 1] = playRound(r, i == 1) end
body[#body + 1] = H.call(function()
  H.log(string.format("[gogomimic] PASS: GOGO's 3-BP Mimic of Tools, Runic, Throw, Fire and Scan buys Overclock, "
    .. "RunicBlade, Assassinate, Ultima and Study, in %d battles", battles))
end)
H.run({ maxFrames = 1500000 }, body)
