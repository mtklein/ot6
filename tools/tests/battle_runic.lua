-- @suite slow
-- battle_runic.lua -- Celes's signature: a Runic absorb pays MP *and* a
-- boost point.
--
--   tools/tests/run.sh tools/tests/battle_runic.lua
--
-- Vanilla already does the MP half.  Cmd_0b (battle_main.asm:4079-4085)
-- sets $3E4C.2 on the actor and ends her turn; the next runic-able attack
-- to resolve runs RunicEffect (:8483), which sweeps all ten entities,
-- clears the stance bit, drops anyone CheckStatus rejects, enrolls the
-- survivors in $EE and retargets the whole attack into an MP restore
-- aimed at them (:8517-8523).  OT6 adds one instruction's worth of hook
-- at the enrolment point, Ot6RunicBP (ot6.asm), so the same absorb
-- also banks +1 BP, capped at 5 like every other BP source.
--
-- Celes is not recruitable until the v0.3 arc, so she is installed the
-- way battle_bushido installs Cyan: CHAR::CELES ($06) into $3ED8, a
-- Runic-only command list ($202E, stride 12), and magitek status cleared.
-- She enters the stance through battle_fold's muddle idiom (a confused
-- character with a one-command list runs RandCharAction into that command,
-- with no menu input) and is un-muddled the moment the stance
-- bit appears, so nothing re-queues it (QueueAction :496-498 would clear
-- $3E4C.2 on her next action, which also serves as this test's guard that
-- she never took a turn mid-measurement).  She is then held off the turn
-- order by her ATB byte rather than by stop status, because stop is the one
-- thing RunicEffect's CheckStatus gate rejects, so stopping her would
-- delete the mechanic under test.  See pin().
--
-- The raise itself is made absorb-proof rather than left to chance: the caster
-- is disarmed to the beam family and her queue drained before the stance
-- goes up, so no runic-able spell can be in flight while it does.  That
-- guard is the fifth scaffolding fact and the one that causes the most
-- trouble when it is missing; the full measurement is at enterRunic().
--
-- The control is the important part.  Terra casts twice into the same standing
-- stance; the only difference is the spell's own runic-able flag,
-- MagicProp byte 3 bit 3, the gate RunicEffect tests at :8486-8488.
-- Every id that reaches $3410 is classified by reading that byte out of
-- the ROM (MagicProp via H.sym, so C4 segment growth never stales it), so
-- the test asserts against the shipped data rather than a hardcoded list:
--   negative: magitek status left on, so muddle rolls MagiTek beams
--     (bit 3 clear across the whole range; runs land on $81/$84).
--     The stance stays up, MP is flat, and BP is flat.
--   positive: magitek cleared and a Magic-only list, so she rolls real
--     magic (Fire $00 and Cure $2D, bit 3 set).  The stance clears, MP
--     rises, and BP goes up by 1.
-- Same character, same stance, same turn state, same measurement, so a
-- +1 that showed up in both would be a turn-tick regen rather than an absorb,
-- and the negative phase fails.  An Ot6RunicBP that incremented
-- unconditionally, or one hooked before RunicEffect's gates, fails there.
--
-- ---- #59: boost buys the stance a duration ----
--
-- The v0.9 half.  Runic was the last shipped kit verb with no boost
-- behaviour at all, and the rule it lands is a third category: on reactive
-- verbs, boost buys duration (DESIGN.md).  Boost N means N of Celes's own turns
-- during which the stance stands and she acts normally.
--
-- Three phases at the end of this file, and the middle one is the reason the
-- issue asked for care:
--
--   6. the raise latches a duration, per tier.  Cmd_0b -> Ot6RunicRaise
--      banks the pending boost into OT6_RUNICTURNS.  Three arms at 1/2/3 in
--      battle_slots.lua's shape: the same drive each time, one
--      pending byte different, and the latched duration the only thing that
--      moves.  Unboosted stays 0, which is phases 1-5 above: those are the
--      regression check that vanilla Runic is untouched to the byte.
--
--   7. the milking test, the BP loop, measured rather than assumed.  Runic
--      already banks +1 per absorb (v0.3), so an extended stance is not just
--      more absorbs, it is more BP earned from an ability BP paid for.  Here
--      the stance is held up while the caster lands several absorbable
--      spells inside one round of Celes's, and the bank must move by exactly
--      +1, which is the once-per-round cap #37 put on the True Knight cover,
--      itself taken from Runic's own code.  The same phase
--      checks the other half of duration: an absorb no longer ends the
--      stance, so the stance is still standing after all of them.
--      Measured A/B, same fixture and same casts: +1 with the latch, +2 on
--      a control ROM with the latch nop'd out.  (+2 rather than +4 because
--      the counter below counts absorbable casts that resolved, an upper
--      bound on absorb events rather than an exact count, and because
--      this fixture has exactly one caster.  The direction is what the
--      ruling turns on: uncapped, the earn scales with absorbs and with
--      how many things are casting; capped, it does not scale at all.)
--
--   8. and it expires.  She takes turns, the counter ticks down at each
--      QueueAction (Ot6RunicHold, which also puts back the bit vanilla's
--      :511 clear just took), and on the turn after the last one the stance
--      drops.  This is the assertion that the duration is a
--      duration rather than permanent.
--
-- Also asserted:
--   - the bank cap: an absorb at 5 BP stays 5.  It must not wrap to 0
--     (a plain inc) and must not create a 6th pip Ot6Boost would let her
--     spend (`cmp $3e9c`, ot6.asm).
--   - the HUD moves: the party-window pip glyph for Celes's own
--     menu row is read out of VRAM and must equal Ot6PipCellTbl's cell
--     for her new bank.  The pips stage from live $3E9C at window_open
--     (btlgfx_main.asm:9514-9516 -> DrawCharNames -> Ot6PipGlyph_ext),
--     so this is the assert that the absorb is visible to a player and
--     not only true in RAM.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"

local CELES = 0x06                   -- character id, $3ED8 stride 2
local CMD_RUNIC, CMD_MAGIC = 0x0b, 0x02
local RUNIC_BIT = 0x04               -- $3E4C.2, set by Cmd_0b
local MAGIC_PROP = H.sym("MagicProp") & 0x3FFFFF   -- PRG offset, survives C4 growth
local MUDDLE, MAGITEK, STOP = 0x20, 0x08, 0x10
-- Ot6PipCellTbl (ot6.asm): pip cluster cell per spendable bp 0-5
local PIP = { [0] = 0x72, 0x73, 0x75, 0x76, 0x77, 0x79 }

-- #59: OT6_RUNICTURNS / OT6_RUNICPAID (ot6_memory.inc), in the shadow tail
local RUNICTURNS, RUNICPAID = 0xed8e, 0xed96
local CMD_FIGHT = 0x00

local function bp(s)     return H.readByte(0x3e9c + s * 2) end
local function turns(s)  return H.readByte(RUNICTURNS + s * 2) end
local function pend(s)   return H.readByte(0x3e9d + s * 2) end
local function mp(s)     return H.readWord(0x3c08 + s * 2) end
local function hp(s)     return H.readWord(0x3bf4 + s * 2) end
local function stance(s) return H.readByte(0x3e4c + s * 2) & RUNIC_BIT ~= 0 end
local function st1(s)    return 0x3ee4 + s * 2 end   -- status 1 (magitek)
local function st2(s)    return 0x3ee5 + s * 2 end   -- status 2 (muddle)
local function st3(s)    return 0x3ef8 + s * 2 end   -- status 3 (stop)

-- the spell's own absorb flag, read out of the shipped table
local function runicable(id)
  return H.readRomByte(MAGIC_PROP + id * 14 + 3) & 0x08 ~= 0
end

-- party-window pip cell for an arbitrary menu row.  lib's pipWord() is
-- row 0 only; Ot6Boost derives the same address as $7800 + (1+row*2)*32
-- + 20 words, which is byte 0x68 + row*0x80 from the map base.
local function pipWordRow(row)
  local reg = H.readByte(0x897f)
  local base = ((reg - (reg % 4)) * 256) * 2
  return emu.readWord(base + 0x68 + row * 0x80, emu.memType.snesVideoRam)
end

local function rowOf(slot)
  for r = 0, 3 do
    if H.readByte(0x64d6 + r) == slot then return r end
  end
  return nil
end

local terra, celes = nil, nil
local spells, mark, cycles = {}, 0, 0
local holdCeles = false   -- see pin(): keeps her in the stance, off the queue
-- #59: while nonzero, pin() keeps this many BP pending on Celes so that
-- whatever turn she next takes is a boosted one.  battle_fold measured this
-- idiom: the boost is read at the action rather than at the menu,
-- and stray stale actions consume an armed pending, so it is re-armed every
-- frame until the thing under test has happened.  It is cleared the moment it
-- has, or she would boost every subsequent turn too.
local armBoost = 0
-- the single command pin() keeps in Celes's list.  Runic for every phase that
-- needs her to raise the stance, and Fight for #59's expiry walk, where she has
-- to take ordinary turns; a Runic-only list would re-raise the stance on each
-- one and the duration could never be observed running out.
local celesCmd = CMD_RUNIC
local droppedEarly = false

-- Frames on which Celes's stance bit went from set to clear.  Exactly two
-- sites in the ROM clear $3E4C.2, QueueAction (battle_main.asm:496-498,
-- her own next action) and RunicEffect (:8497-8499, an absorb), and
-- ot6.asm never writes $3E4C at all, so pairing this list against the
-- resolved-id list tells them apart with no PC guessing and no ROM
-- addresses to go stale: a clear with an absorbable id in the same window
-- is RunicEffect doing its job, and a clear without one is a turn she was
-- supposed to be held out of.  That distinction answers the
-- fixture-versus-product question this test would otherwise leave open.
local stanceClears = {}
local stanceUp = false    -- shadow of $3E4C.2, kept from the written value


-- the newest resolved id of the requested class since the phase mark
local function sawClass(want)
  for i = mark + 1, #spells do
    if runicable(spells[i]) == want then return spells[i] end
  end
  return nil
end

local function countClass(want, from)
  local n = 0
  for i = from + 1, #spells do
    if runicable(spells[i]) == want then n = n + 1 end
  end
  return n
end

local function idList(from)
  local out = {}
  for i = from + 1, #spells do
    out[#out + 1] = string.format("%02x%s", spells[i],
      runicable(spells[i]) and "*" or "")
  end
  return table.concat(out, " ")
end

-- held every frame: guards never act, nobody dies out from under a
-- measurement, and Celes keeps her installed identity
local function pin()
  H.writeByte(0x3f04, H.readByte(0x3f04) | STOP)
  H.writeByte(0x3f06, H.readByte(0x3f06) | STOP)
  H.writeWord(0x3c00, 3000)
  H.writeWord(0x3c02, 3000)
  for s = 0, 3 do
    if hp(s) > 0 then H.writeWord(0x3bf4 + s * 2, 400) end
  end
  -- keep the caster solvent.  She casts on a muddle roll repeatedly,
  -- and intro-stat MP runs out quickly; a broke caster still writes her
  -- chosen spell to $3410 but the action never resolves, so the phase
  -- either times out or reports a spell that no RunicEffect ever
  -- saw.  Celes's MP is not pinned, because it is the measurement.
  if terra then H.writeWord(0x3c08 + terra * 2, 200) end
  -- Hold Celes out of the turn order once she is in the stance.  She must
  -- not act, because a turn would clear $3E4C.2 and pay a regen, but she also
  -- must not be stopped, because RunicEffect's CheckStatus gate drops a
  -- stopped runic-er (battle_main.asm:8500-8503), which would delete the
  -- thing under test.  So her ATB is held un-ready instead: $3219,X
  -- counts down and 0 means full (UpdateBattleTime, battle_main.asm:2680),
  -- so a nonzero pin keeps her off the queue while leaving every flag
  -- RunicEffect reads untouched.  Without this she takes a turn,
  -- opens a menu, and that open menu parks the whole action queue, so the
  -- caster never casts (measured: 24000 frames with nobody acting).
  if holdCeles and celes then H.writeByte(0x3219 + celes * 2, 0x60) end
  if armBoost > 0 and celes then
    H.writeByte(0x3e9c + celes * 2, 5)          -- a bank she can spend from
    H.writeByte(0x3e9d + celes * 2, armBoost)   -- ...and the pending spend
  end
  if celes then
    -- give her a pool to absorb into.  The slot Celes is installed over
    -- belongs to a Narshe-raid trooper whose max MP ($3C30,X, "max mp",
    -- battle_main.asm:13326) is 0, so vanilla's restore clamps straight
    -- back to 0 and the MP half of the absorb is invisible (measured:
    -- mp 1 -> 0 across a confirmed absorb).  Max only; her current MP is
    -- the measurement and is never pinned.
    H.writeWord(0x3c30 + celes * 2, 99)
    H.writeByte(0x3ed8 + celes * 2, CELES)
    H.writeByte(st1(celes), H.readByte(st1(celes)) & ~MAGITEK & 0xff)
    H.writeByte(0x202e + celes * 12, celesCmd)
    H.writeByte(0x2031 + celes * 12, 0xff)
    H.writeByte(0x2034 + celes * 12, 0xff)
    H.writeByte(0x2037 + celes * 12, 0xff)
  end
end

-- park everyone who is neither the caster nor the rune knight
local function benchOthers()
  for s = 0, 3 do
    if s ~= terra and s ~= celes and hp(s) > 0 then
      H.writeByte(st3(s), H.readByte(st3(s)) | STOP)
    end
  end
end

-- a wait that keeps holding the pins (plain waitFrames does not)
local function pinnedWait(n)
  return H.repeatN(n, { H.call(pin), H.waitFrames(1) })
end

-- Service other characters' menus while waiting.  A ready character's open
-- menu parks the action queue: measured, every ATB byte sat full ($3219,X = 0)
-- for 24000 frames with one menu up and nobody acting.  Confirming it
-- lets the queue move so the muddled caster can cast.  Never Celes's own
-- menu, which would spend her turn and drop the stance.
local function serviceWait(cycles_)
  return H.repeatN(cycles_, {
    H.call(function()
      pin()
      if H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) ~= celes then
        H.setPad({ "a" })
      end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(26),
  })
end

local function muddle(s, on)
  local v = H.readByte(st2(s))
  H.writeByte(st2(s), on and (v | MUDDLE) or (v & ~MUDDLE & 0xff))
end

-- arm Terra to roll one class of attack: beams (magitek status left on)
-- or real magic (magitek cleared, Magic-only list)
local function armTerra(magic)
  local v = H.readByte(st1(terra))
  H.writeByte(st1(terra), magic and (v & ~MAGITEK & 0xff) or (v | MAGITEK))
  H.writeByte(0x202e + terra * 12, magic and CMD_MAGIC or 0x0f)
  H.writeByte(0x2031 + terra * 12, 0xff)
  H.writeByte(0x2034 + terra * 12, 0xff)
  H.writeByte(0x2037 + terra * 12, 0xff)
end

-- drive Celes into the stance for real, then freeze her there.
-- (repeatN(1, ...) is the public way to fold a step LIST into the single
-- step object H.run's sequencer expects.)
--
-- Raising the stance is the fragile moment, so the window is made
-- absorb-proof before it opens.
--
-- The hazard is this test's own scaffolding.  Both drives below service
-- other characters' menus by tapping A, which they must do, or a ready
-- character's open menu parks the action queue and muddled Celes never gets
-- the turn she needs (see serviceWait).  But the character whose menu they
-- service is the caster, and after a positive phase she is still armed with a
-- Magic-only list.  So the servicing taps commit real, runic-able spells,
-- and whether one of them resolves before or after Cmd_0b sets $3E4C.2
-- depends on ROM timing.  If it resolves first, RunicEffect clears the stance
-- the moment it goes up, which is correct behaviour, and the next
-- assert downstream reports a missing stance with no indication of why.
--
-- Measured, at the commit this guard was written for (probe trace of every
-- $3E4C write with the writing PC): the "capped" raise took 3003 frames
-- with a Cure ($2d) committing every few hundred frames throughout; the
-- stance went up at f5746 (pc C2/1973 = Cmd_0b, battle_main.asm:4083) with
-- the caster's pending-action pointer $32CC already live at $7e; that Cure
-- resolved 113 frames later at f5859 and cleared the stance from C2/3572
-- (RunicEffect, :8499), inside the following baseline's settle.  The
-- "first" raise took 157 frames with $32CC = $ff and never saw it.
--
-- So: disarm the caster to the family that cannot be absorbed, then drain
-- what she already committed, and only then raise.  Both halves are
-- derived rather than timed.  The disarm rests on the same MagicProp
-- classifier the install phase checks is meaningful (magitek beams have byte 3
-- bit 3 clear across the whole range); the drain rests on $32CC,x = $ff meaning
-- "nothing queued" (battle_main.asm:254, and CreateNormalAction:@4ecb
-- tests it the same way).  After this the only thing the caster can put in
-- flight is a beam, which RunicEffect's own gate ($11A3 bit 3, :8486-8488)
-- refuses, which is what the negative control checks.
local function enterRunic(label)
  return H.repeatN(1, {
    H.call(function()
      muddle(terra, false)
      armTerra(false)           -- beams only: nothing absorbable can commit
    end),
    H.driveUntil(function() return H.readByte(0x32cc + terra * 2) == 0xff end,
      6000, { H.call(pin), H.waitFrames(1) },
      "the caster has nothing absorbable queued (" .. label .. ")"),
    -- she needs a turn to raise the stance, so let her back onto the
    -- queue for exactly as long as that takes
    H.call(function() holdCeles = false end),
    H.driveUntil(function()
      return H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) ~= celes
    end, 6000, {
      H.call(function()
        pin()
        if H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) == celes then
          H.setPad({ "a" })
        end
      end),
      H.waitFrames(4),
      H.call(function() H.setPad({}) end),
      H.waitFrames(20),
    }, "a menu that is not Celes's (" .. label .. ")"),
    H.driveUntil(function() return stance(celes) end, 8000, {
      H.call(function()
        pin(); muddle(celes, true)
        -- muddled, she owns no menu, but somebody else's open menu will
        -- park the queue and starve her of the turn she needs
        if H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) ~= celes then
          H.setPad({ "a" })
        end
      end),
      H.waitFrames(4),
      H.call(function() H.setPad({}) end),
      H.waitFrames(16),
    }, "Celes raises Runic (" .. label .. ")"),
    H.call(function()
      muddle(celes, false)
      holdCeles = true          -- stance is up: freeze her out of the turn order
      H.log(string.format("%s: runic up ($3e4c=$%02x), bp=%d mp=%d",
        label, H.readByte(0x3e4c + celes * 2), bp(celes), mp(celes)))
    end),
  })
end

-- run one cast phase: arm Terra, wait for an attack of the wanted class
-- to resolve, and hand back what changed
local function castPhase(want, label, maxFrames)
  return H.repeatN(1, {
    H.call(function()
      mark = #spells
      armTerra(want)
    end),
    H.driveUntil(function() return sawClass(want) ~= nil end, maxFrames, {
      H.call(function()
        pin(); benchOthers(); muddle(terra, true)
        if H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) ~= celes then
          H.setPad({ "a" })
        end
        cycles = cycles + 1
        if cycles % 50 == 0 then    -- only chatters if a phase is dragging
          H.log(string.format("  %s waiting: menu=$%02x actor=%d "
            .. "caster[atb=$%02x mp=%d] celes[atb=$%02x stance=%s] ids=%s",
            label, H.readByte(0x7bca), H.readByte(0x62ca),
            H.readByte(0x3219 + terra * 2), mp(terra),
            H.readByte(0x3219 + celes * 2), tostring(stance(celes)),
            idList(mark)))
        end
      end),
      H.waitFrames(4),
      H.call(function() H.setPad({}) end),
      H.waitFrames(16),
    }, label .. ": a " .. (want and "runic-able" or "non-runic-able")
       .. " attack resolves"),
    H.call(function() muddle(terra, false) end),
    serviceWait(8),                    -- let the action finish resolving
  })
end

-- #59: raise the stance with N boost points pending, so Ot6RunicRaise latches
-- N turns of duration.  Wraps enterRunic rather than copying it: every one of
-- that function's five scaffolding facts (absorb-proof window, drained caster
-- queue, foreign-menu servicing, the muddle idiom, the un-muddle) applies
-- unchanged, and the only difference is that a pending is armed across the
-- raise.  armBoost is cleared the instant the stance is up; left set, every
-- turn she takes afterwards would be a boosted one, which would corrupt the
-- expiry walk and the bank measurement alike.
--
-- Between A/B arms the stance is reset to the state a fresh battle starts in
-- (InitBP zeroes OT6_RUNICTURNS; the bit would go on her next unshielded
-- turn anyway).  This matters: without it the next arm's driveUntil(stance)
-- is satisfied immediately by the previous arm's still-standing stance, she
-- never takes the turn under test, and the latch assertion below reads the
-- old tier, so it passes or fails for reasons unrelated to the raise.
local function resetStance()
  H.writeByte(RUNICTURNS + celes * 2, 0)
  H.writeByte(0x3e4c + celes * 2,
    H.readByte(0x3e4c + celes * 2) & ~RUNIC_BIT & 0xff)
end

local function enterRunicBoosted(n, label)
  return H.repeatN(1, {
    H.call(function() resetStance(); armBoost = n end),
    enterRunic(label),
    H.call(function()
      armBoost = 0
      H.log(string.format("%s: runic up with %d pending -> OT6_RUNICTURNS=%d",
        label, n, turns(celes)))
      H.assertEq(turns(celes), n, string.format(
        "Ot6RunicRaise latched %d turns of stance from a %d-BP raise", n, n))
    end),
  })
end

-- let the caster land N absorbable spells into a standing stance.  This is
-- castPhase's twin, but it waits for a count rather than for one, because the
-- milking phase is about what several absorbs do to one bank.
local function milkPhase(n, label, maxFrames)
  return H.repeatN(1, {
    H.call(function()
      mark = #spells
      armTerra(true)
    end),
    H.driveUntil(function() return countClass(true, mark) >= n end, maxFrames, {
      H.call(function()
        pin(); benchOthers(); muddle(terra, true)
        if H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) ~= celes then
          H.setPad({ "a" })
        end
        cycles = cycles + 1
        if cycles % 50 == 0 then
          H.log(string.format("  %s waiting: %d/%d absorbed so far, "
            .. "celes[bp=%d mp=%d stance=%s turns=%d] ids=%s",
            label, countClass(true, mark), n, bp(celes), mp(celes),
            tostring(stance(celes)), turns(celes), idList(mark)))
        end
      end),
      H.waitFrames(4),
      H.call(function() H.setPad({}) end),
      H.waitFrames(16),
    }, label .. ": " .. n .. " absorbable spells resolve into the stance"),
    H.call(function() muddle(terra, false) end),
    serviceWait(8),
  })
end

-- drive Celes through ordinary turns, watching that the shield holds
local function turnWalk(untilFn, label, maxFrames)
  return H.driveUntil(untilFn, maxFrames, {
    H.call(function()
      pin(); benchOthers(); muddle(celes, true)
      if not stance(celes) then droppedEarly = true end
      if H.readByte(0x7bca) ~= 0 and H.readByte(0x62ca) ~= celes then
        H.setPad({ "a" })
      end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(16),
  }, label)
end

local before = {}
local function snapshot()
  before = { bp = bp(celes), mp = mp(celes), stance = stance(celes) }
end

-- Baseline the bank, but only after her own Runic turn has finished
-- paying out.  Cmd_0b sets $3E4C.2 while the action executes, and the turn's
-- +1 regen lands later, at EndAction (Ot6ActionEnd), so a bank pinned
-- the instant the stance appears gains one point out from under the
-- measurement, which is how the first draft of this test read
-- +1 in its own negative control.  Settle, pin, then re-read: the assert
-- makes a stray turn tick fail here rather than
-- becoming the +1 a later phase would credit to the absorb.
local function baseline(value)
  local at, from = 0, 0
  return H.repeatN(1, {
    H.call(function() at, from = #spells, H.frame end),
    pinnedWait(180),
    H.call(function()
      H.writeByte(0x3e9c + celes * 2, value)
      H.writeByte(0x3e9d + celes * 2, 0)
      H.writeWord(0x3c08 + celes * 2, 1)   -- room for an absorb to show
    end),
    pinnedWait(90),
    H.call(function()
      -- Name the cause before the symptom.  An absorb landing inside the
      -- settle is the one event that clears the stance without moving the
      -- bank, because at a full bank Ot6RunicBP's +1 is capped away
      -- (ot6.asm, `cmp #$05 / bcs done`), so the bank assert below cannot
      -- see it at baseline(5), and the stance assert reports only
      -- that the stance is gone.  That is how a stray cast from this
      -- test's own menu servicing read as "Runic ended early".  Check the
      -- ids that resolved in the window instead.
      local stray = nil
      for i = at + 1, #spells do
        if runicable(spells[i]) then stray = spells[i] end
      end
      H.assertEq(stray and string.format("$%02x", stray) or "none", "none",
        "nothing absorbable resolved while the baseline settled")
      H.assertEq(bp(celes), value,
        "the bank settled at the baseline (no stray turn tick in the window)")
      -- and with the absorb ruled out above, any clear left in this window
      -- is a turn the ATB pin was supposed to prevent.  The bank assert
      -- cannot see that one at baseline(5), because the turn's +1 regen is
      -- capped away at a full bank, which is why this used to show up as
      -- an unexplained missing stance.
      local drops = 0
      for _, f in ipairs(stanceClears) do
        if f >= from then drops = drops + 1 end
      end
      H.assertEq(drops, 0,
        "and she took no turn while it settled (the ATB pin held)")
      H.assertEq(stance(celes), true, "and Runic is still standing")
      snapshot()
      H.log(string.format("baseline: bp=%d mp=%d stance=%s",
        before.bp, before.mp, tostring(before.stance)))
    end),
  })
end

H.run({ maxFrames = 200000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),

  -- ---------------------------------------------------------- install --
  H.call(function()
    for s = 0, 3 do
      if H.readByte(0x3ed8 + s * 2) == 0 then terra = s end
    end
    H.assertEq(terra ~= nil, true, "found Terra (the only natural caster here)")
    for s = 0, 3 do
      if s ~= terra and hp(s) > 0 and celes == nil then celes = s end
    end
    H.assertEq(celes ~= nil, true, "found a live slot to install Celes into")
    pin()
    benchOthers()
    emu.addMemoryCallback(function(_, v) spells[#spells + 1] = v end,
      emu.callbackType.write, 0x7e3410, 0x7e3410)
    -- Edge-detect off the written value rather than a read-back: whether a
    -- Mesen write callback runs before or after the store lands is not
    -- something this test should depend on, and a wrong guess would
    -- make the counter always zero, which is a check that passes because
    -- it never ran.  Shadowing the byte needs no such assumption.
    stanceUp = stance(celes)
    emu.addMemoryCallback(function(_, v)
      local was = stanceUp
      stanceUp = v & RUNIC_BIT ~= 0
      if was and not stanceUp then stanceClears[#stanceClears + 1] = H.frame end
    end, emu.callbackType.write, 0x7e3e4c + celes * 2, 0x7e3e4c + celes * 2)
    H.log(string.format("terra=slot %d, celes=slot %d (char id $%02x)",
      terra, celes, H.readByte(0x3ed8 + celes * 2)))
    -- the classifier itself must do something: check it separates the
    -- two families before anything depends on it
    H.assertEq(runicable(0x00), true, "MagicProp says Fire is runic-able")
    H.assertEq(runicable(0x2d), true, "MagicProp says Cure is runic-able")
    H.assertEq(runicable(0x17), false, "MagicProp says Merton is not")
    H.assertEq(runicable(0x8a), false, "MagicProp says TekMissile is not")
  end),

  -- ------------------------------------------------- 1. enter the stance --
  enterRunic("first"),
  H.call(function()
    H.assertEq(stance(celes), true, "Cmd_0b really set $3E4C.2")
    H.screenshot("runic_stance")
  end),
  baseline(2),                           -- a bank with room to grow

  -- ------------------------------- 2. negative control: an unabsorbable hit --
  castPhase(false, "negative", 20000),
  H.call(function()
    H.log("negative phase ids: " .. idList(mark)
      .. string.format("  | bp %d -> %d, mp %d -> %d, stance %s",
        before.bp, bp(celes), before.mp, mp(celes), tostring(stance(celes))))
    local id = sawClass(false)
    H.assertEq(id ~= nil, true, "a non-runic-able attack really resolved")
    H.assertEq(sawClass(true), nil,
      "and nothing runic-able slipped into the control window")
    -- the stance is untouched, which also shows Celes never took a turn
    -- (QueueAction would have cleared $3E4C.2), so the flat BP below is
    -- a real negative rather than a turn she happened not to get
    H.assertEq(stance(celes), true,
      "an unabsorbed attack leaves Runic standing (and Celes never acted)")
    H.assertEq(bp(celes), before.bp,
      "an attack Runic cannot eat banks NO bp")
    H.assertEq(mp(celes), before.mp,
      "and restores no mp either -- nothing was absorbed")
  end),

  -- ------------------------------------- 3. positive: the absorb pays both --
  baseline(2),
  castPhase(true, "positive", 24000),
  H.call(function()
    H.log("positive phase ids: " .. idList(mark)
      .. string.format("  | bp %d -> %d, mp %d -> %d, stance %s",
        before.bp, bp(celes), before.mp, mp(celes), tostring(stance(celes))))
    local id = sawClass(true)
    H.assertEq(id ~= nil, true, "a runic-able spell really resolved")
    H.assertEq(stance(celes), false,
      "RunicEffect consumed the stance ($3E4C.2 cleared)")
    -- positive control for the stance-clear watch itself.  The baselines
    -- assert that watch saw nothing; if it were miswired it would report
    -- nothing here too, and every one of those asserts would pass
    -- for the wrong reason.  A real absorb just happened, so it must have
    -- caught at least one edge.
    H.assertEq(#stanceClears > 0, true,
      "the stance-clear watch registered this absorb (it is not blind)")
    H.assertEq(mp(celes) > before.mp, true,
      "the vanilla half still happens: the spell became MP")
    H.assertEq(bp(celes), before.bp + 1,
      "and the OT6 half: the absorb banked exactly +1 bp")
    H.assertEq(pend(celes), 0, "with nothing pending to spend")
    H.screenshot("runic_absorbed")
  end),

  -- ------------------------------------------------ 4. the player can see it --
  H.driveUntil(function()
    return H.readByte(0x7bca) ~= 0 and rowOf(celes) ~= nil
  end, 6000, {
    H.call(pin), H.waitFrames(4),
  }, "a battle menu open with Celes on screen"),
  H.waitFrames(30),
  H.call(function()
    local row = rowOf(celes)
    local w = pipWordRow(row)
    H.log(string.format("celes menu row %d: pip word $%04x (bank %d wants $%02x)",
      row, w, bp(celes), PIP[bp(celes)]))
    H.assertEq(w >> 8, 0x21, "the pip cell carries the pip palette")
    H.assertEq(w & 0xff, PIP[bp(celes)],
      "the party window shows the post-absorb bank, so the +1 is visible")
    H.screenshot("runic_pips")
  end),

  -- ------------------------------------------------------ 5. the bank cap --
  enterRunic("capped"),
  baseline(5),                           -- a full bank
  castPhase(true, "capped", 24000),
  H.call(function()
    H.log("capped phase ids: " .. idList(mark)
      .. string.format("  | bp %d -> %d, mp %d -> %d",
        before.bp, bp(celes), before.mp, mp(celes)))
    H.assertEq(sawClass(true) ~= nil, true, "a runic-able spell resolved again")
    H.assertEq(stance(celes), false, "and was absorbed")
    H.assertEq(mp(celes) > before.mp, true, "mp still restored at a full bank")
    -- a bare `inc` would read 6 here; a wrapped byte would read 0
    H.assertEq(bp(celes), 5, "an absorb at 5 bp stays 5 -- capped, not wrapped")
    -- and the regression check for #59: everything above was an unboosted
    -- Runic, and it behaved as it did before boost bought a duration.
    -- That is by construction: Ot6RunicRaise latches 0, Ot6RunicHold reads 0
    -- and does nothing, and Ot6RunicBP's stance restore is gated on the same
    -- 0.  Vanilla Runic is untouched to the byte, and this is where that is
    -- established before anything below depends on the new code.
    H.assertEq(turns(celes), 0,
      "an UNBOOSTED Runic latches no duration (phases 1-5 were vanilla)")
  end),

  -- ============================== #59: boost buys the stance a duration ==
  --
  -- ------------------------------------ 6. the raise latches a duration --
  -- Per tier, in battle_slots.lua's shape: the same drive three times,
  -- with one pending byte different, and the latched duration is the only
  -- thing that moves.  On the pre-change ROM every arm reads 0, because there
  -- was no cell to latch into, so all three fail and none can pass by accident.
  enterRunicBoosted(1, "boost1"),
  enterRunicBoosted(2, "boost2"),
  enterRunicBoosted(3, "boosted"),

  -- --------------------------- 7. the milking test: the BP loop, measured --
  -- Runic already banked +1 per absorb before any of this (v0.3), so a stance
  -- that survives its absorb is a stance that can be farmed: BP paid once,
  -- refunded once per spell the enemy casts.  #59 names three possible
  -- rulings and says to measure rather than assume; this is the measurement.
  --
  -- Celes is held off the turn order throughout (enterRunic leaves holdCeles
  -- set), so no ActionEnd of hers fires and the whole phase is one round.
  -- Several absorbs, one round: the bank must move by exactly +1.
  baseline(2),
  milkPhase(3, "milked", 40000),
  H.call(function()
    local absorbs = countClass(true, mark)
    H.log(string.format("milked phase ids: %s  | %d absorbs, bp %d -> %d, "
      .. "mp %d -> %d, stance %s, turns %d", idList(mark), absorbs,
      before.bp, bp(celes), before.mp, mp(celes),
      tostring(stance(celes)), turns(celes)))
    -- first, check the phase did enough work: a phase that absorbed once
    -- would pass the +1 below for the wrong reason, and a phase that absorbed
    -- none would pass the stance assert too
    H.assertEq(absorbs >= 3, true,
      "several absorbable casts really landed on the standing stance")
    -- duration, half one: an absorb no longer ends the stance.  Before #59
    -- RunicEffect's clear at :8671 was final and the second spell would have
    -- found nothing to absorb.
    H.assertEq(stance(celes), true,
      "the stance is STILL standing after all of them (absorbs no longer "
      .. "end it -- that is what the duration bought)")
    -- the ruling: once per round, which is #37's cap applied to the verb it
    -- was copied from.  On a control build with the OT6_RUNICPAID latch
    -- removed this reads before.bp + absorbs instead, which is the
    -- self-funding loop #59 was concerned about: three points spent, three or
    -- more refunded.  (The count is of absorbable casts that resolved, an
    -- upper bound on absorb events rather than an exact count.  What matters
    -- is the A/B, and it is clear: same fixture, same casts, +1 with the
    -- latch and +2 without it.  One caster is the floor; the loop scales with
    -- how many things are casting and how long the stance stands.)
    H.assertEq(bp(celes), before.bp + 1, string.format(
      "%d absorbable casts inside one round bank exactly ONE bp -- the earn "
      .. "is capped per round, so an extended stance cannot refund the boost "
      .. "that bought it", absorbs))
    -- and the cap is on the BP only.  The MP half is per absorb, untouched
    -- and uncapped: that is vanilla's own restore, and it is why a rune
    -- knight wants a caster boss.
    H.assertEq(mp(celes) > before.mp, true,
      "while every absorb still paid its MP -- only the BP earn is capped")
    H.screenshot("runic_milked")
  end),

  -- ------------------------------------------- 8. and it runs out --
  -- The duration is spent by Celes taking turns, one per QueueAction
  -- (Ot6RunicHold), which is also the only place the stance can survive her
  -- acting at all.  So she is put back on the queue with a Fight-only list;
  -- Runic-only would re-raise the stance every turn and the counter could
  -- never be watched running out.
  --
  -- The caster is disarmed to beams for the whole walk: with nothing
  -- absorbable in flight, RunicEffect never runs, so the only thing that can
  -- touch $3E4C.2 here is her own QueueAction.  That is what makes "the
  -- stance survived her turn" a statement about Ot6RunicHold rather than
  -- about chance.
  H.call(function()
    armTerra(false)               -- beams: nothing absorbable can interfere
    celesCmd = CMD_FIGHT          -- ordinary turns, not re-raises
    H.writeByte(0x202e + celes * 12, CMD_FIGHT)
    droppedEarly = false
    holdCeles = false             -- ...and let her onto the queue at last
    H.log(string.format("expiry walk begins: turns=%d stance=%s",
      turns(celes), tostring(stance(celes))))
  end),
  turnWalk(function() return turns(celes) == 0 end,
    "Celes spends all three shielded turns", 40000),
  H.call(function()
    H.log(string.format("counter ran out: turns=%d stance=%s bp=%d",
      turns(celes), tostring(stance(celes)), bp(celes)))
    H.assertEq(droppedEarly, false,
      "the stance stood through every one of the turns it paid for")
    H.assertEq(stance(celes), true,
      "and is still standing on the last of them -- she ACTED under it, "
      .. "which vanilla's QueueAction clear (:511) never allowed")
  end),
  turnWalk(function() return not stance(celes) end,
    "the turn AFTER the last one drops it", 40000),
  H.call(function()
    H.log(string.format("expired: turns=%d stance=%s", turns(celes),
      tostring(stance(celes))))
    H.assertEq(stance(celes), false,
      "3 BP bought three turns of shield, not a permanent one")
    H.assertEq(turns(celes), 0, "and the counter stays spent")
    H.screenshot("runic_expired")
  end),
})
