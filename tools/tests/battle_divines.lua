-- battle_divines.lua -- the kit-8 DIVINES whose gates are read at RESOLUTION.
--
--   tools/tests/run.sh tools/tests/battle_divines.lua
--
-- These finishers cannot be gated at command-SELECT time (their command is in
-- RetargetCmdTbl, so the target is cleared and re-chosen at resolution), so OT6
-- gates them where the attack lands. Each is once-per-battle via OT6_DIVINE_USED
-- ($3ECB, per-character bit).
--
-- OBLIVION (Cyan, Bushido tech 8, attack $5C). magic_prop already builds it as a
-- pure instant-death strike (power 0, Status-1 $80 Death). Ot6Oblivion (hooked
-- right after ChooseTarget in CalcAttackEffect -- the one seam where the
-- retargeted swdtech's target finally exists) reads the target's broken timer:
--   * Broken + killable   -> marks Death in the target's $3dd4 directly (a
--     GUARANTEED kill, applied by UpdateStatus regardless of the hit roll) and
--     SETS the once-per-battle latch.
--   * unbroken / Broken boss -> surgeries the loaded props to a Tempest hit in
--     place (power 70, Death cleared): the honest reduced fallback, latch CLEAR.
-- The attack id stays $5C either way -- the branch shows in the OUTCOME.
--
-- Two fresh battles (a mid-test state reload), each exercising ONE resolution as
-- a clean first action -- far more robust than chasing a second action across
-- the ATB hand-off:
--   BATTLE 1 -- selection + the unbroken fallback:
--     1. SELECTABLE + LATCH-DRIVEN: 8 techs, clear latch -> BP3 = Oblivion (7).
--        Poke the latch SET and the same open window drops to Tempest (6); clear
--        it and 7 returns (the once-per-battle SELECTION rule + its control).
--     2. UNBROKEN FALLBACK: Oblivion at an UNBROKEN guard leaves it ALIVE and the
--        latch CLEAR (the Death was surgeried off) -- the gate WITHHOLDS the kill.
--   BATTLE 2 -- the broken kill:
--     3. BROKEN KILL: Oblivion at a BROKEN, non-immune guard KILLS it and SETS
--        the acting character's latch -- the engine's own resolution spends the
--        divine. (Paired with step 2, this is the quiet-test control: the kill
--        is real, and the gate can also withhold it.)
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local KNOWN, BAR = 0x2020, 0x7B82
local ST_BUSHIDO = 0x37
local DIVINE_USED = 0x3ECB

local PARTY = { 0, 1, 2 }
local GUARDS = { 2, 3 }
local function SH(s)  return 0x3E38 + (8 + s * 2) end
local function TM(s)  return 0x3E88 + (8 + s * 2) end
local function DP(s)  return 0x3AA1 + (8 + s * 2) end
local function MHP(s) return 0x3BFC + s * 2 end
local function PRESENT(s) return 0x3AA8 + s * 2 end
local function ST3(e) return 0x3EF8 + e end

local function pend(s) return H.readByte(0x3E9D + s * 2) end
-- Death is Status-1 bit 7 ($80) at $3EE4 + entity offset. We read Death rather
-- than the present bit because the guards are pinned STOPPED to keep them off
-- the action queue, and a stopped monster at 0 HP lingers "present" (its removal
-- animation never runs) -- so Death, not removal, is the honest kill witness.
local function dead(s) return H.readByte(0x3EE4 + (8 + s * 2)) & 0x80 ~= 0 end
local function level() return H.readByte(BAR) // 32 end
local function inWindow() return H.readByte(MSTATE) == ST_BUSHIDO end
local function latchSet(slot) return (H.readByte(DIVINE_USED) & (1 << slot)) ~= 0 end
local function setLatch(slot) H.writeByte(DIVINE_USED, H.readByte(DIVINE_USED) | (1 << slot)) end
local function clrLatch(slot) H.writeByte(DIVINE_USED, H.readByte(DIVINE_USED) & (~(1 << slot) & 0xFF)) end

local OT6_SLASH = 0x01

local actor
local ceiling = 7
local pinPend = 3
local pinBp = true
local guardBroken = { [2] = false, [3] = false }
local guardImmune = { [2] = false, [3] = false }
local pinGuardHp = true                      -- off during a kill so it sticks
local guardHp = 4000

local function pinCyan()
  H.writeWord(KNOWN, ceiling)
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, 0x02)                 -- CHAR::CYAN
    local st1 = 0x3EE4 + s * 2
    H.writeByte(st1, H.readByte(st1) & 0xF7)          -- clear magitek
    H.writeByte(0x202E + s * 12, 0x07)                -- Bushido, alone
    H.writeByte(0x2031 + s * 12, 0xFF)
    H.writeByte(0x2034 + s * 12, 0xFF)
    H.writeByte(0x2037 + s * 12, 0xFF)
    H.writeByte(0x3BA4 + s * 2, H.readByte(0x3BA4 + s * 2) | 0x02)
    H.writeByte(0x3BA5 + s * 2, H.readByte(0x3BA5 + s * 2) | 0x02)
    H.writeWord(0x3BF4 + s * 2, 999)
  end
  if actor and pinBp then H.writeByte(0x3E9C + actor * 2, 5) end
  if actor and pinPend then H.writeByte(0x3E9D + actor * 2, pinPend) end
end

local function pinGuards()
  for _, s in ipairs(GUARDS) do
    if H.readByte(PRESENT(s)) & 1 == 1 then
      H.writeByte(0x3BE0 + (8 + s * 2), 0)
      H.writeByte(0x3E9C + (8 + s * 2), OT6_SLASH)
      -- pin the broken timer HIGH ($FF): at $10 it ticks to 0 (and recovers)
      -- between our re-pins, so the gate would momentarily read UNBROKEN.
      H.writeByte(TM(s), guardBroken[s] and 0xFF or 0)
      H.writeByte(SH(s), guardBroken[s] and 0 or 8)
      local dp = H.readByte(DP(s))
      H.writeByte(DP(s), guardImmune[s] and (dp | 0x04) or (dp & 0xFB))
      local st3 = ST3(8 + s * 2)
      H.writeByte(st3, H.readByte(st3) | 0x10)         -- stopped: nothing contests
      -- re-pinning HP every frame would REVIVE a guard the divine just killed;
      -- keep it on while guards must be durable, off once a kill must land.
      if pinGuardHp then H.writeWord(MHP(s), guardHp) end
    end
  end
end

local function pin() pinCyan(); pinGuards() end

local function parkBench(keep)
  for _, s in ipairs(PARTY) do
    if s ~= keep then H.writeByte(ST3(s * 2), H.readByte(ST3(s * 2)) | 0x10) end
  end
end

-- boot from the doorstep into the guard battle and install Cyan (inlined per
-- battle: a state reload restarts the whole preamble)
local function bootSteps()
  return {
    H.waitFrames(20),
    H.loadState(STATE),
    H.waitFrames(10),
    H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
      H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
      H.pressButtons({ "a" }, 4),
    }, "battle load"),
    H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
    H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
      H.call(pin), H.waitFrames(1),
    }, "a battle menu opens"),
    H.call(function() actor = H.readByte(ACTOR) end),
  }
end

-- open the active character's swdtech window (fresh)
local function openWindow(what)
  return H.driveUntil(inWindow, 1500, {
    H.call(function() pin(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, what)
end

local killed, killLatch = false, false

local steps = {}
local function add(t) for _, s in ipairs(t) do steps[#steps + 1] = s end end

-- ===================== BATTLE 1: selection + unbroken fallback ==============
add(bootSteps())
add({
  H.call(function()
    pinPend = 3
    H.log(string.format("battle 1: cyan in slot %d; latch $%02X", actor, H.readByte(DIVINE_USED)))
    H.assertEq(latchSet(actor), false, "divine latch clear at battle start")
  end),

  -- 1. SELECTABLE + latch drives the selection (one live open window)
  openWindow("swdtech window opens (selection)"),
  H.waitFrames(8),
  H.call(function()
    H.assertEq(level(), 7, "latch CLEAR: BP3 selects Oblivion (tech 7)")
    setLatch(actor)
  end),
  H.waitFrames(8),
  H.call(function()
    H.assertEq(level(), 6, "latch SET: BP3 falls back to Tempest (tech 6)")
    clrLatch(actor)
  end),
  H.waitFrames(8),
  H.call(function()
    H.assertEq(level(), 7, "latch cleared: Oblivion (7) returns")
    H.assertEq(latchSet(actor), false, "latch left clear for the fallback test")
    H.screenshot("divine_oblivion_selectable")
  end),

  -- 2. UNBROKEN FALLBACK: latch Oblivion at an unbroken guard -> a Tempest hit,
  -- the guard lives, the divine is not spent.
  H.call(function()
    guardBroken = { [2] = false, [3] = false }
    guardImmune = { [2] = false, [3] = false }
    pinGuardHp = true
    parkBench(actor); pin()
  end),
  H.driveUntil(function() return not inWindow() end, 900, {
    H.call(function() pin(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "latch Oblivion at the unbroken guard"),
  H.call(function() pinPend, pinBp = nil, false end),
  H.driveUntil(function() return pend(actor) == 0 end, 12000, {
    H.call(function()
      pin(); parkBench(actor)
      if H.readByte(MENU) ~= 0 and not inWindow() then H.setPad({ "a" }) end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(16),
  }, "the unbroken action resolves"),
  H.waitFrames(50),
  H.call(function()
    H.assertEq(dead(2), false, "the unbroken guard took NO Death (Tempest fallback)")
    H.assertEq(dead(3), false, "nor did the other guard")
    H.assertEq(H.readByte(PRESENT(2)) & 1, 1, "the unbroken guard is still present")
    H.assertEq(latchSet(actor), false, "the divine latch stays CLEAR on a fallback")
    H.screenshot("divine_oblivion_fallback")
  end),
})

-- ===================== BATTLE 2: the broken kill (fresh battle) =============
add(bootSteps())
add({
  H.call(function()
    pinPend, pinBp = 3, true
    ceiling = 7
    -- both guards Broken + killable so the swdtech's default target can't stall,
    -- and stop re-pinning HP so the guaranteed Death actually removes the guard
    guardBroken = { [2] = true, [3] = true }
    guardImmune = { [2] = false, [3] = false }
    pinGuardHp = false
    parkBench(actor); pin()
    H.log(string.format("battle 2: cyan in slot %d; latch $%02X", actor, H.readByte(DIVINE_USED)))
    H.assertEq(latchSet(actor), false, "the killing character's latch starts clear")
  end),
  openWindow("swdtech window opens (broken kill)"),
  H.waitFrames(8),
  H.call(function()
    H.assertEq(level(), 7, "Oblivion selectable at BP3 (latch clear)")
  end),
  H.driveUntil(function() return not inWindow() end, 900, {
    H.call(function() pin(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "latch Oblivion at the broken guard"),
  H.call(function() pinPend, pinBp = nil, false end),
  H.driveUntil(function()
    if (dead(2) or dead(3)) and not killed then
      killed = true
      if latchSet(actor) then killLatch = true end
    end
    return killed or pend(actor) == 0
  end, 12000, {
    H.call(function()
      pin(); parkBench(actor)
      if H.readByte(MENU) ~= 0 and not inWindow() then H.setPad({ "a" }) end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(16),
  }, "the broken-target action resolves"),
  H.waitFrames(60),
  H.call(function()
    if not killed then
      if dead(2) or dead(3) then killed = true end
      if latchSet(actor) then killLatch = true end
    end
    H.log(string.format("guard Death bits: %s %s ; actor latch %s",
      tostring(dead(2)), tostring(dead(3)), tostring(latchSet(actor))))
    H.assertEq(killed, true, "Oblivion inflicted Death on a Broken, non-immune guard")
    H.assertEq(killLatch, true, "the engine SET the divine latch on the kill")
    H.screenshot("divine_oblivion_kill")
  end),
})

H.run({ maxFrames = 90000 }, steps)
