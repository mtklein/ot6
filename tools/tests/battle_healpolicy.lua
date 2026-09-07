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
--   5. the swing model and the class/reflect bits the press rule (#156)
--      counts before it skips a heal;
--   6. the two #165 rules on the Rizopas seed $64 numbers: the kill-this-
--      turn estimate (H.killEstimate: hits to the last chip shielded, the
--      rest x4) that lets a press beat lethal-next-round care only when it
--      ends the fight, and the raise decision (H.raiseDecision: Fenix
--      Down's maxhp/8 against the enemy's smallest hit) that refuses a
--      raise into a certain re-kill;
--   7. that every case ran.
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

  -- 5. the swing half: what the press rule (#156) counts before it skips a
  -- heal.  The swing model is plain arithmetic (Ot6FightBoost: two swings
  -- per BP, alternating hands when both hold a weapon); the class and
  -- reflect bits are read out of this ROM's tables.
  H.call(function()
    local function swings(two, boost) return table.pack(H.fightSwings(two, boost)) end
    local s = swings(false, 0)
    H.assertEq(s[1] * 10 + s[2], 10, "one weapon, 0 BP: 1 swing")
    s = swings(false, 2)
    H.assertEq(s[1] * 10 + s[2], 50, "one weapon, 2 BP: 1 + 4 swings")
    s = swings(true, 0)
    H.assertEq(s[1] * 10 + s[2], 11, "Genji pair, 0 BP: one swing a hand")
    s = swings(true, 2)
    H.assertEq(s[1] * 10 + s[2], 33, "Genji pair, 2 BP: 3 + 3 swings (six chips on a two-class gauge)")
    H.assertEq(H.weaponClass(0x0F), 0x01, "ThunderBlade $0F is slashing")
    H.assertEq(H.weaponClass(0x05), 0x02, "Assassin $05 is piercing")
    H.assertEq(H.weaponClass(H.AUTOCROSSBOW), 0x02, "AutoCrossbow $AA is piercing")
    H.assertEq(H.weaponClass(0xFF), 0x04, "an empty hand is a bludgeoning fist")
    H.assertEq(H.spellReflectable(0x02), true, "Bolt $02 bounces off Reflect")
    H.assertEq(H.spellReflectable(0x0B), true, "Bolt 3 $0B (the 2-BP fold) bounces too")
    H.assertEq(H.spellReflectable(0x2D), true, "Cure $2D is reflectable (cast at allies, never at the monster)")
    H.assertEq(H.spellReflectable(0x38), false, "Shiva's summon attack $38 ignores Reflect")
    H.assertEq(H.spellReflectable(0x5D), false, "Pummel $5D ignores Reflect")
    H.assertEq(H.spellReflectable(0x8E), false, "Aqua Rake $8E ignores Reflect")
    H.log("battle_healpolicy: swing model, class and reflect bits checked")
  end),

  -- 6. the two #165 rules, on the Rizopas seed $64 numbers (care_i50.log
  -- of the lab: SABIN's Fight landed 74 a hit shielded; Rizopas at 553 HP
  -- behind 1 shield; CYAN 358 max HP raised to 44 and killed by a -44
  -- Battle four times).
  H.call(function()
    -- M.killEstimate: hits to the last chip land shielded, the rest x4
    local est, toBreak, broken = H.killEstimate({ per = 74, hits = 3, chips = 3, need = 1 })
    H.assertEq(est, 74 + 2 * 4 * 74, "SABIN's 1-BP Fight (3 swings, 74 a hit) into 1 shield: 74 shielded then two broken hits = 666")
    H.assertEq(toBreak * 10 + broken, 12, "one swing to the break, two broken")
    H.assertEq(est >= 553, true, "666 covers Rizopas's 553: a kill this turn")
    est = H.killEstimate({ per = 49, hits = 3, chips = 3, need = 1 })
    H.assertEq(est, 49 + 2 * 4 * 49, "the same volley at 49 a hit is 441")
    H.assertEq(est >= 553, false, "441 is short of 553: break but not kill, so care first")
    est = H.killEstimate({ per = 74, hits = 3, chips = 3, need = 0 })
    H.assertEq(est, 3 * 4 * 74, "a broken gauge puts every hit in the window: 888")
    est = H.killEstimate({ per = 74, hits = 1, chips = 1, need = 1 })
    H.assertEq(est, 74, "0 BP: one swing, the break itself, nothing broken")
    H.assertEq(H.killEstimate({ per = 74, hits = 3, chips = 1, need = 2 }), nil, "chips short of the shields: no estimate")
    H.assertEq(H.killEstimate({ per = 0, hits = 3, chips = 3, need = 1 }), nil, "nothing measured yet: no estimate")
    est, toBreak, broken = H.killEstimate({ per = 100, hits = 6, chips = 3, need = 2 })
    H.assertEq(toBreak * 10 + broken, 42, "a Genji pair with one chipping hand: 2 chips of 3 spread over 6 swings is 4 to the break, 2 broken")
    H.assertEq(est, 4 * 100 + 2 * 400, "priced accordingly: 1200")
    -- M.raiseDecision: Fenix Down's maxhp/8 against the smallest hit
    local raiseHp, ok = H.raiseDecision({ maxhp = 358, power = H.itemPower(0xF0), smallestHit = 44 })
    H.assertEq(raiseHp, 44, "Fenix Down raises CYAN (358) to 44 (measured: [raise] t=6113 entity 1 to 44 hp)")
    H.assertEq(ok, false, "a 44-HP raise into a 44 hit is a certain re-kill: refused")
    raiseHp, ok = H.raiseDecision({ maxhp = 358, power = 2, smallestHit = 42 })
    H.assertEq(ok, true, "a 42 hit leaves 2 HP: the raise stands")
    raiseHp, ok = H.raiseDecision({ maxhp = 358, power = 2, smallestHit = nil })
    H.assertEq(ok, true, "nothing measured yet: the raise stands (the old behaviour)")
    raiseHp, ok = H.raiseDecision({ maxhp = 1400, power = 2, smallestHit = 318 })
    H.assertEq(raiseHp * 10 + (ok and 1 or 0), 1750, "LOCKE (1400) raises to 175; Nerapa's 318 Battle re-kills it")
    H.assertEq(H.itemPower(0xF0), 2, "Fenix Down $F0 power byte is 2 (ItemProp +20; CalcRatio >> 4 = 1/8)")
    H.log("battle_healpolicy: kill estimate and raise decision checked")
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
