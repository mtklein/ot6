-- @suite savestate=vargas_entry slow
-- battle_retaliate.lua -- #236: a character the player is NOT driving banks
-- BP normally and, once something has hurt it, dumps the whole bank on its
-- next attack.
--
-- THE GAP THIS CLOSES, measured before it was closed
-- (build/lab/uncontrolled/probe_bank.log, retained as
-- build/attempts/<branch>/lab/uncontrolled/probe_bank.log): every writer of
-- OT6_BOOST_REVEALED was a player-driven path, so Ot6ActionEnd took its
-- @gain arm on every turn an uncontrolled actor took.  A berserked EDGAR in
-- this very fight banked 1-2-3-4-5 over four engine-chosen Fights while
-- being hit the whole way, Ot6FightBoost saw pending 0 at every one of them,
-- and the charge arm ran zero times.  The bank filled to the cap and stopped.
--
-- WHAT IS STAGED, AND IT IS EXACTLY ONE BYTE.  The Berserk bit (STATUS2 bit
-- 4, const.inc) is written onto the subject once, at a chosen moment, and
-- nothing else in this file writes emulated state.  Berserk is the cheapest
-- member of the class the issue names -- Umaro, Berserk, Muddle, the
-- Colosseum -- and the only one reachable in the World of Balance at all:
-- Umaro and the Colosseum are World of Ruin content and the route qualifies
-- through the end of the WoB, so they are designed and reasoned from the
-- ROM, never claimed as route coverage (see the header of Ot6Retaliate).
-- Everything downstream of that one bit is the engine's: the engine chooses
-- the action, the monsters choose their targets, and the swing count,
-- the hit count and the charge are all read out of the machine.
--
-- THE SHAPE OF THE RUN, in three phases in one battle (battle 66, VARGAS):
--
--   A. the PLAYER drives the subject to a full bank.  Real Fight commands
--      through the real command window, no R press, so Ot6ActionEnd's gain
--      arm runs four times and the bank climbs 1 -> 5.  This is also the
--      negative control: every one of those turns must write $3a70 = 1 and
--      leave the pending byte at 0, and OT6_UNCTL's bit must stay clear.
--   B. the Berserk lands.  The engine now chooses the subject's actions,
--      and the first Fight it chooses after something has hurt him must
--      spend: pending = 3 (the bank is 5, the spend caps at 3), $3a70 = 7,
--      the loop runs 8 passes, a one-weapon character lands 4 of them, and
--      Ot6ActionEnd charges 3 off the bank, leaving 2.
--   C. the retaliation tally is CONSUMED.  The dump is armed while he stands BELOW
--      the hp line his own last turn drew (OT6_HPMARK), and the same frame
--      moves that line down to where he stands, so one hurt buys one dump
--      and the next needs a new hit.
--
-- EVERY EXPECTED NUMBER IS DERIVED from the built ROM, never pinned: the
-- swing ladder out of FightAttack's `lda #$01` and Ot6FightBoost's `asl`
-- run (battle_healpolicy.lua's derivation, reused), the spend cap out of
-- Ot6Retaliate's own `cmp #$04 / lda #$03`, and the armed-hand count out of
-- the subject's character record.  Each assertion also names the number it
-- must NOT be -- 1 swing, 2 passes, 1 landed hit, a bank that did not move
-- -- which are precisely what the old behaviour produced here, so this file
-- cannot pass on a ROM without the feature.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/vargas_entry.mss.lua"

local SUBJ = 0                          -- EDGAR's entity index at vargas_entry
local BERSERK = 0x10                    -- STATUS2 bit 4 (const.inc)
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F
local ST_TRANS, ST_CMD, ST_TGT = 0x01, 0x05, 0x38
local CMD_FIGHT = 0x00
local BANK_CAP = 5                      -- Ot6ActionEnd's ceiling

local function hp(e)   return H.readWord(0x3BF4 + e * 2) end
local function bp(e)   return H.readByte(0x3E9C + e * 2) end
local function pend(e) return H.readByte(0x3E9D + e * 2) end
local function st2(e)  return H.readByte(0x3EE5 + e * 2) end
local function cmdRow(slot, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + slot * 12 + r * 3) == cmd then return r end
  end
  return nil
end

-- ---------------------------------------------------------- the machine --
-- Derived once the ROM is readable; asserted, never assumed.
local D = {}                            -- base, perBp, cap, unctl, mark, hands

-- the run's ledger
local L = {
  phase = "A",
  playerFights = 0,                     -- phase A actions that resolved
  swings = {},                          -- every $3a70 write, tagged with phase
  dumps = {},                           -- every pending write > 0 by the ROM
  hurts = 0,                            -- times the subject's hp really fell
  markWrites = {},                      -- every write to his own hp line
  charges = {},                         -- Ot6ActionEnd charge arms for him
  unctlDuringA = 0,                     -- OT6_UNCTL bit seen set in phase A
}
-- the ONE action under the microscope: opened by the ROM's own dump write
-- (which happens inside Ot6FightBoost, before it touches $3a70) and closed
-- by SaveForMimic -- battle_hits.lua's window, hooked into the dump
local W = { open = false, closed = false, swings = 0, hits = 0,
            hand = { [0] = 0, [1] = 0 }, bank = nil }

H.run({ maxFrames = 150000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),

  -- ================================================================== --
  -- the ROM's own arithmetic, before a single button is pressed
  -- ================================================================== --
  H.call(function()
    local function romBytes(base, n)
      local t = {}
      for i = 0, n - 1 do t[#t + 1] = H.readRomByte(base + i) end
      return t
    end
    -- FightAttack's vanilla swing count and Ot6FightBoost's per-BP shift:
    -- battle_healpolicy.lua's derivation, reused rather than re-pinned.
    local fb = romBytes(H.sym("Ot6FightBoost") & 0x3FFFFF, 40)
    local tail = nil
    for i = 1, #fb - 6 do
      if fb[i] == 0x18 and fb[i + 1] == 0x6D and fb[i + 2] == 0x70
         and fb[i + 3] == 0x3A and fb[i + 4] == 0x8D and fb[i + 5] == 0x70
         and fb[i + 6] == 0x3A then tail = i; break end
    end
    H.assertEq(tail ~= nil, true,
      "Ot6FightBoost still ends in clc / adc $3a70 / sta $3a70")
    local asls = 0
    while tail - 1 - asls >= 1 and fb[tail - 1 - asls] == 0x0A do
      asls = asls + 1
    end
    D.perBp = 1 << asls
    local fa = romBytes(H.sym("FightAttack") & 0x3FFFFF, 24)
    for i = 1, #fa - 4 do
      if fa[i] == 0xA9 and fa[i + 1] == 0x01 and fa[i + 2] == 0x90 then
        D.base = fa[i + 1]; break
      end
    end
    H.assertEq(D.base, 1, "FightAttack seeds $3a70 = 1 without an Offering")
    -- Ot6Retaliate's own spend ceiling: `cmp #$04 / bcc / lda #$03`.
    local rt = romBytes(H.sym("Ot6Retaliate") & 0x3FFFFF, 64)
    for i = 1, #rt - 4 do
      if rt[i] == 0xC9 and rt[i + 2] == 0x90 and rt[i + 4] == 0xA9 then
        D.cap = rt[i + 5]
        H.assertEq(rt[i + 1], D.cap + 1, string.format(
          "Ot6Retaliate's ceiling is one test and one constant "
          .. "(cmp #$%02X / lda #$%02X)", rt[i + 1], rt[i + 5]))
        break
      end
    end
    H.assertEq(D.cap, 3, "the spend caps at 3, read out of Ot6Retaliate")
    H.assertEq(D.cap < BANK_CAP, true,
      "the cap really is a cap here: a full bank of " .. BANK_CAP
      .. " cannot all be spent at once, so the dump is testable")
    -- the two latch cells, read out of the assembled symbols rather than
    -- copied into this file
    D.unctl = 0x7E0000 + (H.sym("OT6_UNCTL") & 0xFFFF)
    D.mark  = 0x7E0000 + (H.sym("OT6_HPMARK") & 0xFFFF) + SUBJ * 2
    H.assertEq(D.mark - SUBJ * 2, D.unctl + 1,
      "ot6_memory.inc keeps the latch and the hurt line adjacent")
    H.log(string.format("[rom] $3a70 = %d + %d*bp; spend cap %d; "
      .. "OT6_UNCTL $%06X, subject's hurt line $%06X",
      D.base, D.perBp, D.cap, D.unctl, D.mark))

    -- ---------------------------------------------------------------- --
    -- THE WORLD-OF-RUIN HALF, reasoned from this ROM and not played.
    -- Umaro and the Colosseum are World of Ruin content and the route
    -- qualifies through the end of the WoB, so nothing below is a route
    -- claim.  What IS checkable here is the structure the rule rests on.
    --
    -- 1. Umaro is refused a command window BY NAME.  CheckPlayerAction's
    --    third refusal is `lda $3ed8,x / cmp #CHAR::UMARO / beq`, so he
    --    never queues a player command, never leaves $32cc valid, and
    --    therefore reaches QueueAction's no-pending-action arm -- which,
    --    with no Dance, Rage or Magitek status, is `jsr RandCharAction`,
    --    the one site Ot6UnctlMark hooks into.
    -- 2. His action script does NOT route wholly through FightAttack.
    --    UmaroAttackTbl has four entries and exactly ONE of them is
    --    FightAttack; the other three (Throw, Storm, Charge) are his own
    --    arms and carry no Ot6FightBoost, which is why the dump is armed
    --    at his chooser, before the roll (Ot6UmaroRetaliate, #237), and
    --    not inside FightAttack alone.  battle_retaliate_umaro.lua stages
    --    him and measures all four arms; this file only pins the table
    --    shape that reasoning rests on.  The share of relic-less rolls
    --    that take the plain swing is read out of the ROM's own rate table
    --    rather than guessed.
    local cp = {}
    local CPA = H.sym("CheckPlayerAction") & 0x3FFFFF
    for i = 0, 47 do cp[#cp + 1] = H.readRomByte(CPA + i) end
    local umaroRefusal = nil
    for i = 1, #cp - 5 do
      if cp[i] == 0xBD and cp[i + 1] == 0xD8 and cp[i + 2] == 0x3E
         and cp[i + 3] == 0xC9 and cp[i + 5] == 0xF0 then
        umaroRefusal = cp[i + 4]; break
      end
    end
    H.assertEq(umaroRefusal, 0x0D, string.format(
      "CheckPlayerAction still refuses character $%02X (UMARO) a command "
      .. "window by name, which is what puts him on RandCharAction's arm",
      umaroRefusal or 0xFF))

    local TBL = H.sym("UmaroAttackTbl") & 0x3FFFFF
    local FAW = H.sym("FightAttack") & 0xFFFF
    local arms, plain = {}, 0
    for i = 0, 3 do
      arms[i] = H.readRomByte(TBL + i * 2) | (H.readRomByte(TBL + i * 2 + 1) << 8)
      if arms[i] == FAW then plain = plain + 1 end
    end
    H.assertEq(plain, 1, string.format(
      "exactly one of Umaro's four arms is FightAttack ($%04X %04X %04X "
      .. "%04X vs FightAttack $%04X): the swings half of the dump reaches "
      .. "only his plain swing, so Throw, Storm and Charge need the dump "
      .. "armed ahead of the roll (#237)",
      arms[0], arms[1], arms[2], arms[3], FAW))
    H.assertEq(arms[3], FAW, "and it is the last slot, the one the "
      .. "relic-less roll shares with Charge")
    local RATE = H.sym("RandBitRateTbl") & 0x3FFFFF
    local r0, r1 = H.readRomByte(RATE), H.readRomByte(RATE + 1)
    H.log(string.format("[rom/wor] Umaro with no relics: RandBitWithRate "
      .. "row 0 weights $%02X/$%02X, so %d of %d rolls (%.1f%%) take the "
      .. "plain FightAttack arm and the rest take Charge; the dump reaches "
      .. "both since #237 -- REASONED from this ROM, not played: the WoR "
      .. "is not routed", r0, r1, r0, r0 + r1, 100.0 * r0 / (r0 + r1)))
    -- 3. The Colosseum is a MODE, $3a97, and RandCharAction is where
    --    vanilla folds it in beside Berserk, Muddle and Charm -- so it
    --    arrives at the same latch with no extra test here.  Nothing in
    --    the WoB can enter it, so that is all this file says about it.
  end),

  -- one interaction -> the scene -> battle 66
  H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
    H.call(function() H.setPad((H.frame % 8 < 4) and { a = true } or {}) end),
  }, "the VARGAS scene reaches battle 66"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 3000, "battle up", 10),
  H.waitFrames(120),

  H.call(function()
    H.assertEq(cmdRow(SUBJ, CMD_FIGHT) ~= nil, true,
      "the subject really carries Fight on a command row")
    H.assertEq(st2(SUBJ), 0, "the subject starts this fight clean")
    H.assertEq(bp(SUBJ), 1, "and opens with Ot6InitBP's one pip")
    H.assertEq(H.readByte(D.unctl), 0,
      "OT6_UNCTL starts the battle clear (InitBP)")
    H.assertEq(H.readWord(D.mark), 0,
      "the subject's hurt line starts the battle at 0 = 'has not acted' "
      .. "(InitBP), so nothing stale can read as a retaliation tally")

    -- the subject's armed hands, READ off his character record
    local c = H.readByte(0x3ED8 + SUBJ * 2)
    local rh = H.readByte(0x1600 + 37 * c + 0x1F)
    local lh = H.readByte(0x1600 + 37 * c + 0x20)
    D.hands = (H.isWeapon(rh) and 1 or 0) + (H.isWeapon(lh) and 1 or 0)
    if D.hands == 0 then D.hands = 1 end        -- an empty main hand is a fist
    H.log(string.format("[seed] subject e%d char $%02X hands=%d "
      .. "(R $%02X, L $%02X) hp=%d bank=%d",
      SUBJ, c, D.hands, rh, lh, hp(SUBJ), bp(SUBJ)))

    -- ---- observers (reads only) ------------------------------------ --
    local sAE = H.sym("Ot6ActionEnd")
    local sWC, sHJ = H.sym("Ot6WeaponClass"), H.sym("Ot6HitJoin")
    local sSF = H.sym("SaveForMimic")

    -- Every write to the swing count.  The multi-attack loop DECREMENTS
    -- $3a70 as it runs and several of those land on the arming frame, so
    -- the arming value is the frame's MAXIMUM, never its last write -- a
    -- "last write wins" read of this ledger passed at shift 0 and read 6
    -- and 5 at shifts 15 and 52 (build/sweeps/retaliate-lastwrite/).
    emu.addMemoryCallback(function(_, v)
      if v == 0 or v == 0xFF then return end    -- 0 = InitGfxScript's clear,
      L.swings[#L.swings + 1] = { f = H.frame, v = v, phase = L.phase }
      if W.open and not W.closed and v > (W.a70 or 0) then W.a70 = v end
    end, emu.callbackType.write, 0x7E3A70, 0x7E3A70)            -- $ff = wrap

    -- The dump itself.  Ot6Retaliate is the only writer of a NONZERO
    -- pending byte for an actor nobody boosted (Ot6ActionEnd writes the 0),
    -- and it writes it from inside Ot6FightBoost -- so this callback is
    -- also where the measurement window OPENS: the `sta $3a70` that carries
    -- the boosted count, every Ot6WeaponClass pass and every Ot6HitJoin
    -- landing of this one action all follow it, and SaveForMimic closes it.
    local revAddr = 0x7E3E9D + SUBJ * 2
    emu.addMemoryCallback(function(_, v)
      if v == 0 then return end
      L.dumps[#L.dumps + 1] = { f = H.frame, v = v, bank = bp(SUBJ),
        phase = L.phase, mark = L.markAtStart, hp = hp(SUBJ) }
      if not W.open and not W.closed then
        W.open, W.bank, W.pend = true, bp(SUBJ), v
      end
      H.log(string.format("[dump] f%d pending <- %d off a bank of %d "
        .. "(phase %s)", H.frame, v, bp(SUBJ), L.phase))
    end, emu.callbackType.write, revAddr, revAddr)

    -- every real drop in the subject's hp: the provocations, counted off
    -- the machine rather than off a flag of ours
    local lastHp = nil
    emu.addEventCallback(function()
      local h = hp(SUBJ)
      if lastHp ~= nil and h < lastHp then L.hurts = L.hurts + 1 end
      lastHp = h
      -- and the line as it stands at the START of the frame, before any of
      -- the frame's own writes: Ot6Retaliate moves the line BEFORE it arms
      -- the pending byte, so the dump callback would otherwise read the
      -- moved line and compare a number with itself (it did, once:
      -- build/attempts/retaliate-hpline.log, "138 against a line of 138")
      L.markAtStart = H.readWord(D.mark)
    end, emu.eventType.startFrame)

    -- and every write to his hurt line: Ot6ActionEnd draws it at the end of
    -- each of his turns, and Ot6Retaliate moves it down when it spends a
    -- retaliation tally.  The dump callback below necessarily still sees the OLD line,
    -- because Ot6Retaliate arms the pending byte after it moves the line --
    -- so both halves are read here, from the writes themselves.
    -- a 16-bit store fires this once per byte, so the cell is re-read
    -- after each one; the LAST record of a frame carries the whole word
    emu.addMemoryCallback(function()
      L.markWrites[#L.markWrites + 1] = { f = H.frame, v = H.readWord(D.mark) }
    end, emu.callbackType.write, D.mark, D.mark + 1)

    emu.addMemoryCallback(function()
      local x = emu.getState()["cpu.x"] & 0xFFFF
      if x ~= SUBJ * 2 then return end
      local p = pend(SUBJ)
      if p > 0 then
        L.charges[#L.charges + 1] = { f = H.frame, p = p, bank = bp(SUBJ),
                                      phase = L.phase }
      elseif L.phase == "A" then
        L.playerFights = L.playerFights + 1
      end
    end, emu.callbackType.exec, sAE, sAE)

    -- the per-action swing/hit counters, battle_hits.lua's shape
    emu.addMemoryCallback(function()
      if not W.open or W.closed then return end
      local x = emu.getState()["cpu.x"] & 0xFFFF
      if (x & 0xFFFE) ~= SUBJ * 2 then return end
      W.swings = W.swings + 1
      W.hand[x & 1] = W.hand[x & 1] + 1
    end, emu.callbackType.exec, sWC, sWC)

    emu.addMemoryCallback(function()
      if not W.open or W.closed then return end
      if (emu.getState()["cpu.y"] & 0xFFFF) < 8 then return end
      W.hits = W.hits + 1
    end, emu.callbackType.exec, sHJ, sHJ)

    emu.addMemoryCallback(function()
      if W.open and W.swings > 0 then W.closed = true end
    end, emu.callbackType.exec, sSF, sSF)

    emu.addEventCallback(function()
      if L.phase == "A" and (H.readByte(D.unctl) & 0x01) ~= 0 then
        L.unctlDuringA = L.unctlDuringA + 1
      end
    end, emu.eventType.startFrame)
  end),

  -- ================================================================== --
  -- PHASE A: the player fights, unboosted, until the bank is full
  -- ================================================================== --
  H.driveUntil(function()
    return bp(SUBJ) >= BANK_CAP or (not H.battleLoadStarted()) or hp(SUBJ) == 0
  end, 40000, {
    H.call(function()
      if H.readByte(MENU) == 0 then
        H.setPad((H.frame % 8 < 4) and { a = true } or {})
        return
      end
      if (H.frame % 8) >= 4 then H.setPad({}); return end
      local st = H.readByte(MSTATE)
      if st == ST_TRANS then H.setPad({}); return end
      local act = H.readByte(ACTOR) & 3
      if act ~= SUBJ then
        H.setPad(st == ST_CMD and { x = true } or { b = true })
        return
      end
      if st == ST_CMD then
        local want, cur = cmdRow(SUBJ, CMD_FIGHT), H.readByte(CMDROW + SUBJ) & 3
        if cur == want then H.setPad({ a = true })
        else H.setPad(cur < want and { down = true } or { up = true }) end
      elseif st == ST_TGT then
        H.setPad({ a = true })
      else
        H.setPad({ b = true })
      end
    end),
  }, "the player banks the subject to a full bank with plain Fights"),

  H.call(function()
    H.setPad({})
    H.assertEq(H.battleLoadStarted(), true,
      "battle 66 is still up at the end of the banking phase")
    H.assertEq(bp(SUBJ), BANK_CAP, string.format(
      "the player's own unboosted Fights banked the subject to %d "
      .. "(Ot6ActionEnd's gain arm, %d of his actions resolved)",
      BANK_CAP, L.playerFights))
    H.assertEq(L.unctlDuringA, 0,
      "OT6_UNCTL never set while the PLAYER was driving him: the latch is "
      .. "the engine's decision, not a status read")
    H.assertEq(#L.dumps, 0,
      "and nothing dumped: a player's unboosted Fight spends no pips")
    -- the negative control, in numbers: every swing count his own turns
    -- wrote was the bare 1, never the boosted ladder
    local mine, maxv = 0, 0
    for _, s in ipairs(L.swings) do
      if s.phase == "A" then
        mine = mine + 1
        if s.v > maxv then maxv = s.v end
      end
    end
    H.assertEq(maxv, D.base, string.format(
      "every swing count written in the banking phase was the unboosted %d "
      .. "(%d write(s), highest %d)", D.base, mine, maxv))
    L.phase = "B"
    -- ---- THE ONE STATE WRITE IN THIS FILE ---------------------------- --
    H.writeByte(0x3EE5 + SUBJ * 2, st2(SUBJ) | BERSERK)
    H.assertEq(st2(SUBJ) & BERSERK, BERSERK,
      "the staged Berserk is on the subject")
    H.log(string.format("[stage] f%d BERSERK on e%d; bank=%d, "
      .. "already hurt %d time(s) this fight (hp %d against a line of %d)",
      H.frame, SUBJ, bp(SUBJ), L.hurts, hp(SUBJ), H.readWord(D.mark)))
  end),

  -- ================================================================== --
  -- PHASE B: the engine drives him, and his next Fight after a hit dumps
  -- ================================================================== --
  H.driveUntil(function()
    return (#L.charges > 0 and W.closed)
        or (not H.battleLoadStarted()) or hp(SUBJ) == 0
  end, 40000, {
    H.call(function()
      if H.readByte(MENU) == 0 then
        H.setPad((H.frame % 8 < 4) and { a = true } or {})
        return
      end
      if (H.frame % 8) >= 4 then H.setPad({}); return end
      local st = H.readByte(MSTATE)
      if st == ST_TRANS then H.setPad({}); return end
      H.setPad(st == ST_CMD and { x = true } or { b = true })
    end),
  }, "the engine-chosen Fight that dumps the bank"),

  -- ================================================================== --
  -- the verdict
  -- ================================================================== --
  H.call(function()
    H.setPad({})
    -- FIRST, because it is the whole claim and because it is exactly what a
    -- ROM without the feature cannot do: the negative control
    -- (build/attempts/retaliate-negative-control.log, the same file against
    -- a build with Ot6Retaliate's `jsr` nop'd out) reaches this line with
    -- zero dumps after three thousand more frames of the same fight.
    H.assertEq(#L.dumps >= 1, true, string.format(
      "the uncontrolled, hurt subject dumped at least once (%d "
      .. "hp drop(s) counted, bank %d, subject hp %d): a ROM whose "
      .. "uncontrolled actors never spend arrives here with 0",
      L.hurts, bp(SUBJ), hp(SUBJ)))
    H.assertEq(hp(SUBJ) > 0, true, "the subject survived to be measured")
    local d = L.dumps[1]
    local want = math.min(BANK_CAP, D.cap)
    H.assertEq(d.v, want, string.format(
      "the dump spent %d pip(s) off a bank of %d -- min(bank, cap %d), and "
      .. "NOT the 0 the old behaviour left in the pending byte",
      d.v, d.bank, D.cap))
    H.assertEq(d.bank, BANK_CAP, "it dumped off the full bank it had banked")

    -- the swing count this action queued: the window's own maximum
    local a70 = W.a70
    local wantA70 = D.base + D.perBp * want
    H.assertEq(a70, wantA70, string.format(
      "the provoked swing queued $3a70 = %d (ROM: %d + %d*%d), and NOT the "
      .. "%d an unboosted Fight queues", wantA70, D.base, D.perBp, want,
      D.base))

    -- the passes the loop really ran, and the hits they really landed
    local wantPasses = H.fightPasses(want)
    H.assertEq(W.closed, true, "the provoked action resolved (SaveForMimic)")
    H.assertEq(W.swings, wantPasses, string.format(
      "the multi-attack loop ran %d passes for the %d-pip dump ($3a70 + 1), "
      .. "and NOT the %d an unboosted Fight runs",
      wantPasses, want, H.fightPasses(0)))
    H.assertEq(W.hand[0] == W.hand[1], true, string.format(
      "the passes alternate hands: %d main, %d off", W.hand[0], W.hand[1]))
    local main, off = H.fightHits(D.hands, want)
    H.assertEq(main + off, wantPasses // 2, string.format(
      "H.fightHits(%d, %d) = %d landed hits, half the %d passes: the other "
      .. "half are the EMPTY hand (#235)", D.hands, want, main + off,
      wantPasses))
    -- What the volley LANDED.  A whole action can miss (battle_hits.lua's
    -- measured shape: 0 or all, never between, because the whiffing half is
    -- the empty hand and not a die roll), so the measurement is asserted as
    -- that shape.  It is still the real check: 1 -- the count this exact
    -- turn produced before the feature -- is neither 0 nor 4 on this ROM.
    H.assertEq(W.hits == 0 or W.hits == main + off, true, string.format(
      "the provoked volley landed 0 or %d hits and nothing between "
      .. "(measured %d); one landed hit is the OLD behaviour and is "
      .. "unreachable here", main + off, W.hits))
    H.assertEq(W.hits ~= H.fightHits(D.hands, 0), true, string.format(
      "and it is not the %d an unboosted Fight lands",
      (H.fightHits(D.hands, 0))))

    -- the pips really left the bank
    H.assertEq(#L.charges >= 1, true,
      "Ot6ActionEnd took its CHARGE arm for the dump")
    local c = L.charges[1]
    H.assertEq(c.p, want, "and it charged exactly the pips that were armed")
    H.assertEq(bp(SUBJ) <= BANK_CAP - want, true, string.format(
      "the bank fell from %d to %d: the pips LEFT it, they were not merely "
      .. "flagged", BANK_CAP, bp(SUBJ)))

    -- it was a RETALIATION: he really stood below the line his own last
    -- turn drew, and the same frame moved that line down to where he
    -- stands, so one hurt buys one dump
    H.assertEq(d.mark > d.hp, true, string.format(
      "the dump was armed while the subject stood at %d against a line of "
      .. "%d: it is a retaliation, not a free boost", d.hp, d.mark))
    local moved = nil
    for _, w in ipairs(L.markWrites) do
      if w.f == d.f then moved = w end
    end
    H.assertEq(moved ~= nil and moved.v == d.hp, true, string.format(
      "and the same frame moved the line down onto where he stands, %d "
      .. "(hurt-line writes near f%d: %s)", d.hp,
      d.f, (function()
        local t = {}
        for _, w in ipairs(L.markWrites) do
          if math.abs(w.f - d.f) <= 2 then
            t[#t + 1] = string.format("f%d=%d", w.f, w.v)
          end
        end
        return #t > 0 and table.concat(t, " ") or "none"
      end)()))
    H.assertEq(moved.v < d.mark, true, string.format(
      "the line fell from %d to %d: the retaliation tally was spent, not re-armed",
      d.mark, moved.v))
    H.assertEq(#L.dumps <= L.hurts, true, string.format(
      "%d dump(s) over %d hp drop(s): a dump is never conjured out of a "
      .. "turn nothing hurt", #L.dumps, L.hurts))

    H.log(string.format("[result] bank %d -> %d; pending %d; $3a70 %d; "
      .. "%d passes (%d main, %d off); %d landed of a possible %d; "
      .. "%d hp drop(s), %d dump(s)",
      BANK_CAP, bp(SUBJ), d.v, a70, W.swings, W.hand[0], W.hand[1],
      W.hits, main + off, L.hurts, #L.dumps))
    H.screenshot("retaliate_dump")
  end),
})
