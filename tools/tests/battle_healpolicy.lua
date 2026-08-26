-- @suite
-- battle_healpolicy.lua -- when the fight driver drinks and when it swings.
--
--   tools/tests/run.sh tools/tests/battle_healpolicy.lua
--
-- (Not to be confused with field_healpolicy, which is about H.fieldCare
-- preferring a cure spell to an item in a corridor.  This one is the
-- in-battle decision: whether spending this turn on a heal is worth the turn.)
--
-- H.healDecision (lib/ot6.lua): a heal buys back restore/roundCost of a turn
-- and spends a whole one, so a character who cannot out-heal the damage
-- swings instead, unless the drink is keeping an ALLY alive, which buys
-- back a whole turn stream.
--
-- Both numbers it weighs are measured in the fight rather than assumed: the
-- round cost from the HP a member loses between two of the deciding actor's
-- turns, and the restore from the item's power byte, replaced by the HP the
-- first landed use actually put back.
--
-- What this file checks:
--   1. the two power bytes the policy starts from are what the ROM says
--      ($E8 Tonic 50, $E9 Potion 250);
--   2. the battle-11 case: the fraction rule wants a heal (59% is under 60)
--      and the policy declines it;
--   3. the cases that must still heal -- ally cover, the sustainable
--      top-up, the opening turn before any round has been measured, and
--      the character standing inside one round of death with a heal big
--      enough to matter;
--   4. the one clause a CAST is exempt from, and the one it is not.  A heal
--      that cannot keep up is refused in a party because the bag is a fixed
--      supply and MP is not, so a caster tops up where a drinker would not.
--      Alone the refusal is about spending turns instead, and a cast spends
--      one exactly as a drink does, so `mp` changes nothing there;
--   5. that every case ran.
local H = dofile("tools/tests/lib/ot6.lua")

local TONIC, POTION = 0xE8, 0xE9

-- who, and why the numbers are these numbers
local CASES = {
  -- Battle 11, solo LOCKE.  The heal-lock: a Tonic against a soldier's round.
  { name = "solo LOCKE, Tonic 50 against a 112 round",
    hp = 100, maxhp = 168, restore = 50, roundCost = 112, allies = 0,
    threshold = 60, want = nil },
  -- The same arithmetic with somebody to cover.  A turn spent keeping an ally
  -- up buys back their whole remaining turn stream, so it is worth it.
  { name = "the same drink, but it is keeping an ally up",
    hp = 100, maxhp = 168, restore = 50, roundCost = 112, allies = 1,
    threshold = 60, want = "covering an ally" },
  -- A party still covers an ally the drink cannot lift clear of the WORST
  -- round: 40 + 50 loses to a 112 round and survives the 55 the same soldier
  -- also throws, and roundCost is the worst seen rather than the usual one.
  { name = "an ally the drink cannot lift clear of the worst round",
    hp = 40, maxhp = 168, restore = 50, roundCost = 112, allies = 1,
    threshold = 60, want = "covering an ally" },
  -- Alone, the same character swings: the drink costs more attacking time
  -- than it buys, and there is nobody else's turns to buy back.
  { name = "the same character alone",
    hp = 40, maxhp = 168, restore = 50, roundCost = 112, allies = 0,
    threshold = 60, want = nil },
  -- A party does not spend the bag on a routine top-up it cannot sustain:
  -- above one round of danger, with an item that cannot keep up, act.
  { name = "a party top-up the item cannot sustain",
    hp = 200, maxhp = 400, restore = 50, roundCost = 150, allies = 2,
    threshold = 60, want = nil },
  -- The same numbers cast rather than drunk.  MP is not a fixed supply the
  -- way the bag is (OT6 refunds it at every level up), so a party's caster
  -- tops up with a cure that cannot keep up, where it would have left the
  -- Tonic in the bag.
  { name = "the same top-up cast instead of drunk",
    hp = 200, maxhp = 400, restore = 50, roundCost = 150, allies = 2,
    threshold = 60, mp = true, want = "top-up" },
  -- And `mp` must not reach the SOLO refusal, which is an argument about
  -- spending turns rather than about the bag: a cast spends a turn exactly
  -- as a drink does.  Battle 11's numbers, cast instead of drunk, still nil.
  { name = "a cure alone that cannot out-heal the damage",
    hp = 100, maxhp = 168, restore = 50, roundCost = 112, allies = 0,
    threshold = 60, mp = true, want = nil },
  -- The opening turn: nothing measured yet because nobody has been hit.
  -- This is the clause that keeps the driver's opening behaviour.
  { name = "the opening turn, hurt, before any round has been measured",
    hp = 108, maxhp = 354, restore = 250, roundCost = 0, allies = 3,
    threshold = 60, want = "top-up" },
  { name = "the opening turn at full HP",
    hp = 168, maxhp = 168, restore = 50, roundCost = 0, allies = 0,
    threshold = 60, want = nil },
  -- A medic whose Potion covers a round outright: healing is sustainable, so
  -- the fraction rule governs.
  { name = "a medic whose Potion covers the round",
    hp = 150, maxhp = 300, restore = 250, roundCost = 150, allies = 2,
    threshold = 75, want = "top-up" },
  -- Sustainable, above the threshold, but one round from death: 120 is more
  -- than 60% of 168 and less than the 130 a round takes.  A fraction alone
  -- would let him die at 71%.
  { name = "above the threshold and still one round from death",
    hp = 120, maxhp = 168, restore = 250, roundCost = 130, allies = 1,
    threshold = 60, want = "in danger" },
  -- A downed member is the Fenix Down branch's business, above this one.
  { name = "a downed member is not a heal candidate",
    hp = 0, maxhp = 300, restore = 250, roundCost = 150, allies = 2,
    threshold = 60, want = nil },
}

local ran = 0

H.run({ maxFrames = 3000 }, {
  H.waitFrames(10),

  -- 1. the priors, read out of this ROM's item records
  H.call(function()
    H.assertEq(H.itemPower(TONIC), 50, "Tonic $E8 heal power is 50")
    H.assertEq(H.itemPower(POTION), 250, "Potion $E9 heal power is 250")
  end),

  -- 2/3. the policy itself
  H.call(function()
    for _, c in ipairs(CASES) do
      local got = H.healDecision(c)
      H.assertEq(tostring(got), tostring(c.want), string.format(
        "%s: %d/%d hp, heal %d, round costs %d, %d allies -> %s",
        c.name, c.hp, c.maxhp, c.restore, c.roundCost, c.allies,
        tostring(c.want)))
      ran = ran + 1
    end
  end),

  -- 2 (the other half).  The battle-11 case is one the fraction rule wanted
  -- to heal.
  H.call(function()
    local c = CASES[1]
    H.assertEq(c.hp * 100 // c.maxhp < c.threshold, true, string.format(
      "battle 11's case really is one opts.healPercent asked for: %d/%d is "
      .. "under %d%%, and the policy declines it anyway",
      c.hp, c.maxhp, c.threshold))
  end),

  -- 4. the table was not skipped
  H.call(function()
    H.assertEq(ran, #CASES, string.format(
      "all %d policy cases ran (a skipped table is the same green as a "
      .. "passed one)", #CASES))
    H.log(string.format("battle_healpolicy: %d cases", ran))
  end),
  H.logStep(function() return "battle_healpolicy complete" end),
})
