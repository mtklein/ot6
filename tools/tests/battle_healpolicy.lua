-- @suite
-- battle_healpolicy.lua -- when the fight driver drinks and when it swings.
--
--   tools/tests/run.sh tools/tests/battle_healpolicy.lua
--
-- (Not to be confused with field_healpolicy, which is about H.fieldCare
-- preferring a cure spell to an item in a corridor.  This one is the
-- in-battle decision: whether spending this turn on a heal is worth the turn.)
--
-- The rule, owner 2026-08-12: "the best healing policy is to heal when you
-- expect to get approximately full value out of the heal.  if a tonic heals
-- 50 hp, heal when you have 50 hp or more to heal, etc.  hard to know with
-- magic... in that case just heal everyone to max."  So the question a heal
-- decision asks is how much of the heal would be thrown away, not what
-- fraction of their health the target has left.  H.healDecision is the rule
-- and the reasoning lives with it in lib/ot6.lua.
--
-- The two defects it stands between.
--
-- The heal-lock, measured 2026-08-11 on battle 11, the South Figaro gate
-- soldier, with solo LOCKE: 168 max HP, five Tonics restoring about 50 each,
-- a soldier dealing 55 to 112 a round.  He landed one Fight per attempt,
-- dropped under the old 60% threshold, and every action after that was an
-- item.  He healed, took more than he healed, healed again, and lost on
-- attrition with the soldier at 489 of 495 HP.  opts.healer, the existing way
-- out, hands healing to a second character and so cannot help a party of one.
-- Alone with a heal smaller than a round, he swings.
--
-- The waste, which is what the fraction rule the old policy fell through to
-- produced.  Measured 2026-08-12 on the Zozo clock puzzle: the party arrived
-- at 28%, a round cost about 45% of maximum, so nobody ever climbed clear of
-- the threshold, nobody ever spent a turn attacking, and the step burned
-- 30000 frames losing.  A fraction gate also gets it wrong the other way: a
-- 400-HP character at 87% is a whole Tonic down and would never have been
-- offered one.
--
-- What this file checks:
--   1. the two power bytes the policy starts from are what the ROM says
--      ($E8 Tonic 50, $E9 Potion 250), so a retune lands here and not in a
--      lost fight;
--   2. the value rule in both directions -- a heal that mostly lands is
--      taken, a heal that mostly spills is refused;
--   3. the battle-11 case, which is the regression: the old fraction rule
--      wanted a heal (59% is under 60) and the policy declines it.  The test
--      asserts the fraction rule's condition too, so this stays a case the
--      old behaviour got wrong rather than a case nobody would have healed;
--   4. the cases that must still heal -- the sustainable top-up, the opening
--      turn before any round has been measured, and the character standing
--      inside one round of death with a heal big enough to change that.
--      Without these, "never heal" would pass the file, and never healing
--      loses battle 70;
--   5. that the danger clause is capped: a character the worst round could
--      kill from full HP is not topped up on a promise no heal can keep,
--      which is what stops "in danger" turning back into the heal-lock;
--   6. the one clause a CAST is exempt from, and the one it is not.  Nobody
--      can say in advance what a cure restores, so the owner's answer is to
--      heal to maximum, and MP pays for it because OT6 refunds MP at every
--      level up.  The solo heal-lock is about spending TURNS, and a cast
--      spends one exactly as a drink does, so `mp` must not reach it -- an
--      `mp` flag that leaked in there would put battle 11's heal-lock back;
--   7. that every case ran.  A table-driven test that skips its table
--      reports the same green as one that passed it.
--
-- Changed here on 2026-08-12 when the rule was replaced, and worth naming
-- because these are assertions that used to say something else:
--   * "a party top-up the item cannot sustain" (200/400, Tonic, 150 round)
--     was nil and is now a heal.  Under the old rule a party refused any heal
--     that could not out-run the damage, on the argument that the bag is a
--     fixed supply.  The value rule answers that argument directly instead: a
--     Tonic into a 200-point hole wastes nothing, so it is not the bag being
--     squandered, and refusing it left EDGAR at 63/398 for a whole fight.
--   * the reasons are new strings ("full value", "to full") where the
--     decision did not change.  The two ally cases still heal; they heal
--     because the drink lands in full, not because somebody needs covering.
local H = dofile("tools/tests/lib/ot6.lua")

local TONIC, POTION = 0xE8, 0xE9

-- who, and why the numbers are these numbers
local CASES = {
  -- Battle 11, solo LOCKE.  The heal-lock: a Tonic against a soldier's round.
  { name = "solo LOCKE, Tonic 50 against a 112 round",
    hp = 100, maxhp = 168, restore = 50, roundCost = 112, allies = 0,
    want = nil },
  -- The same arithmetic with somebody to cover.  The heal-lock clause is
  -- about being the only attacker, so it does not apply, and 68 points of
  -- hole takes a 50-point Tonic in full.
  { name = "the same drink with an ally present",
    hp = 100, maxhp = 168, restore = 50, roundCost = 112, allies = 1,
    want = "full value" },
  -- The old rule healed here to keep an ally standing; the new one heals
  -- here because 128 points of hole is two and a half Tonics.  Same turn,
  -- different reason.
  { name = "an ally the drink cannot lift clear of the worst round",
    hp = 40, maxhp = 168, restore = 50, roundCost = 112, allies = 1,
    want = "full value" },
  -- Alone, the same character swings: the drink costs him more attacking
  -- time than it buys, whatever the hole is, because he is the only attacker.
  { name = "the same character alone",
    hp = 40, maxhp = 168, restore = 50, roundCost = 112, allies = 0,
    want = nil },
  -- A party top-up the item cannot sustain.  The old rule refused this one;
  -- see the note in the header.  200 points of hole is four Tonics, so the
  -- Tonic is not being wasted, and the fight has to be lost some other way.
  { name = "a party top-up the item cannot sustain",
    hp = 200, maxhp = 400, restore = 50, roundCost = 150, allies = 2,
    want = "full value" },
  -- The value rule's other direction, and the one the whole change is for.
  -- 12 points down with a 50-point Tonic throws three quarters of it away.
  { name = "a Tonic into a 12-point hole",
    hp = 388, maxhp = 400, restore = 50, roundCost = 0, allies = 2,
    want = nil },
  -- And the slack, which is the reason the test is not "hole >= heal": at 40
  -- points down a Tonic still lands 80% of itself, and waiting for the last
  -- ten points means waiting a turn the enemy also gets to use.
  { name = "a Tonic into a 40-point hole, inside the slack",
    hp = 360, maxhp = 400, restore = 50, roundCost = 0, allies = 2,
    want = "full value" },
  -- The same 12-point hole cast rather than drunk.  A cure's size is not
  -- knowable in advance, so there is no hole to weigh it against and the
  -- answer is to heal to maximum; MP comes back at every level up and a
  -- Tonic does not.  This is also the minecart ride (#92) -- eight Tonics for
  -- six fights with no field access between them, and 100+ MP a member
  -- unspent.
  { name = "the same small hole cast instead of drunk",
    hp = 388, maxhp = 400, restore = 50, roundCost = 0, allies = 2,
    mp = true, want = "to full" },
  -- And `mp` must not reach the SOLO refusal, which is an argument about
  -- spending turns rather than about what the heal costs: a cast spends a
  -- turn exactly as a drink does.  Battle 11's numbers, cast instead of
  -- drunk, still nil.
  { name = "a cure alone that cannot out-heal the damage",
    hp = 100, maxhp = 168, restore = 50, roundCost = 112, allies = 0,
    mp = true, want = nil },
  -- Battle 70's opening, from the mrf-save-room battery: EDGAR at 108/354,
  -- nothing measured yet because nobody has been hit.  246 points of hole
  -- takes 246 of a Potion's 250.
  { name = "the opening turn, hurt, before any round has been measured",
    hp = 108, maxhp = 354, restore = 250, roundCost = 0, allies = 3,
    want = "full value" },
  { name = "the opening turn at full HP",
    hp = 168, maxhp = 168, restore = 50, roundCost = 0, allies = 0,
    want = nil },
  -- The Phantom Train's shape (#74's triage doctrine): a medic whose Potion
  -- covers a round outright, on a target halfway down.  150 of 250 spills,
  -- so the value rule refuses -- and he is standing on exactly one round of
  -- death and the Potion takes him clear of it, so he is healed anyway.
  { name = "a medic whose Potion covers the round, on a half-dead target",
    hp = 150, maxhp = 300, restore = 250, roundCost = 150, allies = 2,
    want = "in danger" },
  -- One round from death with a small hole: 48 of a Potion's 250 lands, and
  -- the value rule alone would let him die at 71% of maximum.
  { name = "a small hole, and still one round from death",
    hp = 120, maxhp = 168, restore = 250, roundCost = 130, allies = 1,
    want = "in danger" },
  -- The cap on that clause.  A round that can kill this character from full
  -- HP makes him permanently "endangered", and roundCost is the worst round
  -- seen rather than the usual one, so without the cap the clause would hand
  -- him every turn in the fight for a 21-point sliver of a Tonic.  These are
  -- the Zozo street's measured numbers: LOCKE 249 max against a round
  -- measured at 249.
  { name = "endangered by a round no heal can lift him clear of",
    hp = 220, maxhp = 249, restore = 50, roundCost = 249, allies = 3,
    want = nil },
  -- A downed member is the Fenix Down branch's business, above this one.
  { name = "a downed member is not a heal candidate",
    hp = 0, maxhp = 300, restore = 250, roundCost = 150, allies = 2,
    want = nil },
  -- A heal that restores nothing is never worth a turn, whoever holds it.
  { name = "a heal measured at zero",
    hp = 100, maxhp = 400, restore = 0, roundCost = 50, allies = 2,
    want = nil },
}

local ran = 0

H.run({ maxFrames = 3000 }, {
  H.waitFrames(10),

  -- 1. the priors, read out of this ROM's item records
  H.call(function()
    H.assertEq(H.itemPower(TONIC), 50, "Tonic $E8 heal power is 50")
    H.assertEq(H.itemPower(POTION), 250, "Potion $E9 heal power is 250")
  end),

  -- 2-6. the policy itself
  H.call(function()
    for _, c in ipairs(CASES) do
      local got = H.healDecision(c)
      H.assertEq(tostring(got), tostring(c.want), string.format(
        "%s: %d/%d hp, heal %d into a hole of %d, round costs %d, %d allies "
        .. "-> %s", c.name, c.hp, c.maxhp, c.restore, c.maxhp - c.hp,
        c.roundCost, c.allies, tostring(c.want)))
      ran = ran + 1
    end
  end),

  -- 3 (the other half).  The battle-11 case is one the old fraction rule
  -- wanted to heal.  Without this the first case could be passing because
  -- nothing would ever have healed there, and the regression is not pinned.
  H.call(function()
    local c = CASES[1]
    H.assertEq(c.hp * 100 // c.maxhp < 60, true, string.format(
      "battle 11's case really is one the old 60%% top-up asked for: %d/%d "
      .. "is under 60%%, and the policy declines it anyway", c.hp, c.maxhp))
  end),

  -- The retired knob is refused rather than ignored.  A caller that goes on
  -- passing a fraction is tuning something that no longer exists, and a
  -- number quietly dropped is how it would never find out.
  H.call(function()
    local ok = pcall(H.newFightDriver, "healpolicy", { healPercent = 60 })
    H.assertEq(ok, false, "newFightDriver refuses opts.healPercent")
  end),

  -- 7. the table was not skipped
  H.call(function()
    H.assertEq(ran, #CASES, string.format(
      "all %d policy cases ran (a skipped table is the same green as a "
      .. "passed one)", #CASES))
    H.log(string.format("battle_healpolicy: %d cases", ran))
  end),
  H.logStep(function() return "battle_healpolicy complete" end),
})
