-- battle_assassinate.lua -- Shadow's divine: instant-kill a Broken non-boss.
--
--   tools/tests/run.sh tools/tests/battle_assassinate.lua
--
-- STATUS: scaffold, NOT yet in suite.sh. Ot6Assassinate's gate logic is a
-- verified near-copy of Oblivion's (battle_divines proves the shared $3e88
-- Broken / $3aa1.2 boss / $3dd4 kill / OT6_DIVINE_USED latch machinery), but
-- this harness cannot yet DRIVE Shadow's installed Fight to LAND on a guard --
-- the diagnostic showed characters cycling turns with the guards' HP never
-- moving, so the fight never reaches CalcAttackEffect against a broken target.
-- The open item is the fight-DELIVERY drive (or wiring Shadow's real kit),
-- not the proc. See the final report.
--
-- Ot6Assassinate (ot6.asm) is hooked at the same seam Oblivion uses -- just
-- after ChooseTarget in CalcAttackEffect, where the target finally exists -- and
-- fires when SHADOW (char id $03) lands an attack on a Broken ($3e88 nonzero)
-- non-boss ($3aa1 bit 2 clear -- the instant-death-protection bit a boss carries)
-- while his once-per-battle divine (OT6_DIVINE_USED, $3ECB) is unspent. It marks
-- Death in the target's $3dd4 (SetStatus1's byte, applied by UpdateStatus
-- regardless of the hit roll) and spends the latch. Any other target -- a boss,
-- an unbroken enemy, or once the latch is spent -- is left to the ordinary
-- attack. Shadow's kit is a sketch, so the milestone gates on the attacker being
-- Shadow (any attack he lands, simplest faithful reading of the sketch);
-- narrowing to his Throw signature is a one-line change once his kit is built.
--
-- Shadow is not recruitable here, so he is INSTALLED into the guard fight the
-- way the balance labs pin state: every slot gets CHAR::SHADOW ($03) and a Fight
-- command, and Shadow simply FIGHTS -- a driveable action that reaches the same
-- CalcAttackEffect his divine hooks. Three fresh battles (a state reload each),
-- so every case is a clean run:
--   1. BROKEN NON-BOSS: a Broken, killable guard takes Shadow's fight -> DEATH,
--      and a Shadow latch is SET. The core kill + the once-per-battle spend.
--   2. BOSS GATE (loud): both guards Broken but DEATH-IMMUNE. Shadow's fights
--      land (the guards lose HP -- the loud control that he actually acted) but
--      inflict NO Death and set NO latch: a boss is never assassinated.
--   3. ONCE PER BATTLE (loud): Broken non-boss guards, but every Shadow's latch
--      is pre-SET. His fights land (HP falls) yet inflict NO Death: a spent
--      divine does not fire again.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local MENU, ACTOR = 0x7BCA, 0x62CA
local DIVINE_USED = 0x3ECB
local SHADOW = 0x03

local PARTY = { 0, 1, 2 }
local GUARDS = { 2, 3 }
local function SH(s)  return 0x3E38 + (8 + s * 2) end
local function TM(s)  return 0x3E88 + (8 + s * 2) end
local function DP(s)  return 0x3AA1 + (8 + s * 2) end
local function MHP(s) return 0x3BFC + s * 2 end
local function PRESENT(s) return 0x3AA8 + s * 2 end
local function ST3(e) return 0x3EF8 + e end
local function dead(s) return H.readByte(0x3EE4 + (8 + s * 2)) & 0x80 ~= 0 end
local function hp(s) return H.readWord(MHP(s)) end
local function latchByte() return H.readByte(DIVINE_USED) end

local OT6_SLASH = 0x01

local guardBroken = { [2] = true, [3] = true }
local guardImmune = { [2] = false, [3] = false }
local hp0 = { 0, 0 }
local guardHp = 0xF000              -- durable: a fight must NOT damage-remove a
                                    -- broken guard before the Death status (our
                                    -- kill witness) is even set. Set once per
                                    -- battle; not re-pinned, so a fight's damage
                                    -- still SHOWS (the loud control for negatives).
local pinGuardHp = false
local presetLatch = false           -- battle 3: pre-spend every Shadow's divine

local function pinShadow()
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, SHADOW)                -- CHAR::SHADOW
    local st1 = 0x3EE4 + s * 2
    H.writeByte(st1, H.readByte(st1) & 0xF7)           -- clear magitek
    H.writeByte(0x202E + s * 12, 0x00)                 -- Fight, alone
    H.writeByte(0x2031 + s * 12, 0xFF)
    H.writeByte(0x2034 + s * 12, 0xFF)
    H.writeByte(0x2037 + s * 12, 0xFF)
    H.writeWord(0x3BF4 + s * 2, 999)                   -- nobody on the bench dies
    if presetLatch then
      H.writeByte(DIVINE_USED, H.readByte(DIVINE_USED) | (1 << s))
    end
  end
end

local function pinGuards()
  for _, s in ipairs(GUARDS) do
    if H.readByte(PRESENT(s)) & 1 == 1 then
      H.writeByte(0x3BE0 + (8 + s * 2), OT6_SLASH)     -- weak, so the fight bites
      H.writeByte(0x3E9C + (8 + s * 2), OT6_SLASH)
      H.writeByte(TM(s), guardBroken[s] and 0xFF or 0)
      H.writeByte(SH(s), guardBroken[s] and 0 or 8)
      local dp = H.readByte(DP(s))
      H.writeByte(DP(s), guardImmune[s] and (dp | 0x04) or (dp & 0xFB))
      if pinGuardHp then H.writeWord(MHP(s), guardHp) end
    end
  end
end

local function pin() pinShadow(); pinGuards() end

-- give both guards a big HP pool ONCE (not re-pinned): durable against a fight's
-- damage so the Death status is what ends them, yet damage still visibly lands.
local function setGuardHp()
  for _, s in ipairs(GUARDS) do
    if H.readByte(PRESENT(s)) & 1 == 1 then H.writeWord(MHP(s), guardHp) end
  end
end

-- boot from the doorstep into the guard battle and install Shadow (inlined per
-- battle: a reload restarts the preamble)
local function bootSteps()
  return {
    H.waitFrames(20),
    H.loadState(STATE),
    H.waitFrames(10),
    H.enterEncounter(),
    H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
      H.call(pin), H.waitFrames(1),
    }, "a battle menu opens"),
  }
end

-- tap A to drive Shadow fights (each fight lands on the default guard); a short
-- press because $04 is the repeat-mode button word
local fightDrive = {
  H.call(function() pin(); if H.readByte(MENU) ~= 0 then H.setPad({ "a" }) end end),
  H.waitFrames(3),
  H.call(function() H.setPad({}) end),
  H.waitFrames(9),
}

local steps = {}
local function add(t) for _, s in ipairs(t) do steps[#steps + 1] = s end end

-- ===================== BATTLE 1: broken non-boss -> kill + latch ============
add(bootSteps())
add({
  H.call(function()
    guardBroken = { [2] = true, [3] = true }
    guardImmune = { [2] = false, [3] = false }   -- both killable
    presetLatch = false
    pinGuardHp = false
    pin(); setGuardHp()
    H.log(string.format("battle 1: shadow party; latch $%02X", latchByte()))
    H.assertEq(latchByte(), 0, "divine latch clear at battle start")
  end),
  H.driveUntil(function() return dead(2) or dead(3) end, 20000, fightDrive,
    "a Shadow fight assassinates a broken non-boss guard"),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("battle 1: Death %s/%s, latch $%02X",
      tostring(dead(2)), tostring(dead(3)), latchByte()))
    H.assertEq(dead(2) or dead(3), true, "a Broken non-boss guard was assassinated")
    H.assertEq(latchByte() ~= 0, true, "a Shadow's once-per-battle latch is SET")
    H.screenshot("assassinate_kill")
  end),
})

-- ===================== BATTLE 2: boss gate (loud) ===========================
add(bootSteps())
add({
  H.call(function()
    guardBroken = { [2] = true, [3] = true }
    guardImmune = { [2] = true, [3] = true }      -- both Broken BOSSES
    presetLatch = false
    pinGuardHp = false
    pin(); setGuardHp()
    hp0 = { hp(2), hp(3) }
    H.log(string.format("battle 2: boss guards hp %d/%d latch $%02X", hp0[1], hp0[2], latchByte()))
    H.assertEq(latchByte(), 0, "latch clear at battle 2 start")
  end),
  -- fight for a while; a boss must never take Death, but the fights must LAND
  H.driveUntil(function() return hp(2) < hp0[1] or hp(3) < hp0[2] end, 20000, fightDrive,
    "Shadow's fights land on the boss guards"),
  H.repeatN(60, fightDrive),
  H.call(function()
    H.log(string.format("battle 2: hp %d/%d (was %d/%d), Death %s/%s, latch $%02X",
      hp(2), hp(3), hp0[1], hp0[2], tostring(dead(2)), tostring(dead(3)), latchByte()))
    H.assertEq(hp(2) < hp0[1] or hp(3) < hp0[2], true,
      "Shadow's fights actually LANDED on a boss (loud control)")
    H.assertEq(dead(2), false, "a Broken BOSS took no Death")
    H.assertEq(dead(3), false, "nor did the other Broken boss")
    H.assertEq(latchByte(), 0, "and no divine was spent on a boss")
    H.screenshot("assassinate_boss")
  end),
})

-- ===================== BATTLE 3: once-per-battle (loud) =====================
add(bootSteps())
add({
  H.call(function()
    guardBroken = { [2] = true, [3] = true }
    guardImmune = { [2] = false, [3] = false }   -- Broken non-boss...
    presetLatch = true                           -- ...but every divine pre-spent
    pinGuardHp = false
    pin(); setGuardHp()
    hp0 = { hp(2), hp(3) }
    H.log(string.format("battle 3: latch pre-set $%02X, guards hp %d/%d", latchByte(), hp0[1], hp0[2]))
    H.assertEq(latchByte() ~= 0, true, "every Shadow's divine is pre-spent")
  end),
  H.driveUntil(function() return hp(2) < hp0[1] or hp(3) < hp0[2] end, 20000, fightDrive,
    "Shadow's fights land while the divine is spent"),
  H.repeatN(60, fightDrive),
  H.call(function()
    H.log(string.format("battle 3: hp %d/%d (was %d/%d), Death %s/%s",
      hp(2), hp(3), hp0[1], hp0[2], tostring(dead(2)), tostring(dead(3))))
    H.assertEq(hp(2) < hp0[1] or hp(3) < hp0[2], true,
      "Shadow's fights LANDED on the broken non-boss guards (loud control)")
    H.assertEq(dead(2), false, "a spent divine does not assassinate (guard 2)")
    H.assertEq(dead(3), false, "nor guard 3 -- once per battle holds")
    H.screenshot("assassinate_spent")
  end),
})

H.run({ maxFrames = 120000 }, steps)
