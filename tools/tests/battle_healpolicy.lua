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
--   5. the swing/landed-hit model and the class/reflect bits the press
--      rule (#156) counts before it skips a heal.  The ladder is DERIVED
--      from this ROM's FightAttack and Ot6FightBoost rather than pinned as
--      a constant: #235 was a wrong constant nobody checked;
--   6. the two #165 rules on the Rizopas seed $64 numbers: the kill-this-
--      turn estimate (H.killEstimate: hits to the last chip shielded, the
--      rest x4) that lets a press beat lethal-next-round care only when it
--      ends the fight, and the raise decision (H.raiseDecision: Fenix
--      Down's maxhp/8 against the enemy's smallest hit) that refuses a
--      raise into a certain re-kill;
--   7. the refined raise gate (#168) on the battle-70 and map-269 numbers:
--      a raise the smallest hit re-kills stands when a kill is in reach
--      (the last monster inside the party's window) or when an ally's
--      gauge fills before the lethal monster's and their top-up lifts the
--      raise clear of the hit; the ATB read (H.atbEta) behind that; and
--      the Muddle rule (#170): Remedy's status-2 cure mask has no CONFUSE
--      bit (vanilla, byte for byte), a muddled ally gets a plain hit, a
--      muddled actor defers;
--   8. that every case ran;
--   9. the wipe verdict (#166, H.wipeVerdict) on gau_joined's stale-seat
--      bytes and the Narshe descent's seven-marked party: seats come from
--      the engine's actor table, LoseBattle's $3ebc bit 0 is a verdict on
--      its own, and bytes another module owns are never a wipe;
--  14. the target graph (#189, H.newTargetGraph) on the Air Force's
--      measured cursor, and a focus entry naming a part by species;
--  15. the kit's MP in a random battle (H.kitBudget): a quarter of max MP
--      kept for the next boss and a turn's boost rationed to a quarter,
--      on SABIN's Phantom Train numbers; an event battle spends as before.
--  17. which item a care turn spends (#370, H.itemChoice): the bag's
--      prices read off the ROM (a sold item's price word, an unsold one's
--      effect at the shops' gil per HP and MP), the cheapest item the lift
--      rule takes -- no item no shop sells on a top-up (wor_falcon's SABIN
--      at 905/1812 under 846), an X-Potion or an Elixir when it lifts a
--      member inside the round, the last few priced dearer -- the
--      Megalixir's party lift, the status cures in gil order, a heal in
--      flight, and the round's care turn kept after a confirm.
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
  -- The lift (#312): a drink that leaves the ally inside the round spends
  -- the turn and only delays the death -- 40 + 50 = 90 is still inside a
  -- 112 round -- so the actor acts instead (and the spend rule, counting
  -- only heals this policy takes, sees none that saves).  The Sand Horse
  -- lab lever: deaths 9 -> 0 over 42 keys.  (Before #312 this case read
  -- "covering an ally".)
  { name = "an ally the drink cannot lift clear of the round",
    hp = 40, maxhp = 168, restore = 50, roundCost = 112, allies = 1,
    threshold = 60, want = nil },
  -- ...one that it does lift clear is still covered: 70 + 50 = 120 > 112
  { name = "an ally the drink lifts clear of the round",
    hp = 70, maxhp = 168, restore = 50, roundCost = 112, allies = 1,
    threshold = 60, want = "covering an ally" },
  -- ...and the boundary: 62 + 50 = 112 is exactly the round, still dead
  { name = "an ally the drink lifts to exactly the round",
    hp = 62, maxhp = 168, restore = 50, roundCost = 112, allies = 1,
    threshold = 60, want = nil },
  -- the lift binds a cast as it binds a drink: a cure that leaves an
  -- endangered ally inside the round is a delay too (under the threshold
  -- or not), so `mp` does not reopen it
  { name = "a cure on an endangered ally that does not lift them",
    hp = 40, maxhp = 168, restore = 50, roundCost = 112, allies = 1,
    threshold = 60, mp = true, want = nil },
  -- Dullahan's opening priced at the old two-Pearls figure (2172 against
  -- a 1798 max): no Potion lifts anybody clear of that, so nobody drinks
  { name = "a round above max HP: no lift is possible",
    hp = 1175, maxhp = 1798, restore = 250, roundCost = 2166, allies = 3,
    threshold = 60, want = nil },
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
  -- heal.  The class and reflect bits are read out of this ROM's tables,
  -- and so, now, is the swing ladder itself.
  --
  -- #235: this block used to pin "one weapon, 2 BP: 1 + 4 swings" = 5 as a
  -- bare constant nobody checked against the machine, and the machine
  -- lands 3.  A constant no one checks is how that survived, so the numbers
  -- below are DERIVED from the two procs that make them, read out of the
  -- assembled ROM:
  --
  --   FightAttack   lda #$01 ... sta $3a70   (the vanilla swing count)
  --   Ot6FightBoost asl / clc / adc $3a70 / sta $3a70   (x2 per pending BP)
  --
  -- and the loop runs $3a70 + 1 passes (battle_main.asm:8392), alternating
  -- hands (:8285).  Change either proc and this fails, naming the byte.
  -- The remaining half of the claim -- that an empty hand's pass really
  -- whiffs -- is not arithmetic and is measured in play by battle_hits.lua,
  -- which counts swings and landed hits of a real 2-BP Fight.
  H.call(function()
    local FB = H.sym("Ot6FightBoost") & 0x3FFFFF
    local FA = H.sym("FightAttack") & 0x3FFFFF
    local function romBytes(base, n)
      local t = {}
      for i = 0, n - 1 do t[#t + 1] = H.readRomByte(base + i) end
      return t
    end
    -- Ot6FightBoost's arithmetic tail: `clc / adc $3a70 / sta $3a70`,
    -- preceded by the shifts that scale the pending BP.  40 bytes, the
    -- window battle_retaliate*.lua read: the proc's gates grew past 32 when
    -- a queued Rage stopped buying swings (kit-gau.md §6.2).
    local fb = romBytes(FB, 40)
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
    local perBp = 1 << asls
    H.assertEq(perBp, 2, string.format(
      "Ot6FightBoost adds %d swing(s) per pending BP (%d `asl` before the "
      .. "adc, at $%06X)", perBp, asls, H.sym("Ot6FightBoost")))
    -- FightAttack's vanilla count: the `lda #$01` the bcc falls through to.
    local fa = romBytes(FA, 24)
    local base = nil
    for i = 1, #fa - 4 do
      if fa[i] == 0xA9 and fa[i + 1] == 0x01 and fa[i + 2] == 0x90 then
        base = fa[i + 1]; break
      end
    end
    H.assertEq(base, 1, "FightAttack seeds $3a70 = 1 without an Offering")
    -- The loop runs $3a70 + 1 passes, so that is the swing count; the model
    -- must say the same thing, and the hand split must halve it for one
    -- weapon and keep all of it for a pair.
    for bp = 0, 3 do
      local passes = base + perBp * bp + 1
      H.assertEq(H.fightPasses(bp), passes, string.format(
        "a %d-BP Fight swings %d times (ROM: $3a70 = %d + %d*%d, loop runs "
        .. "$3a70 + 1 passes)", bp, passes, base, perBp, bp))
      local m, o = H.fightHits(1, bp)
      H.assertEq(m + o, passes // 2, string.format(
        "one weapon, %d BP: %d swings, %d LANDED hits -- the other half are "
        .. "empty-hand passes (battle_hits.lua measures this in play)",
        bp, passes, passes // 2))
      H.assertEq(o, 0, "one weapon: the off hand lands nothing")
      m, o = H.fightHits(2, bp)
      H.assertEq(m + o, passes, string.format(
        "a Genji pair, %d BP: %d swings, all %d landing, %d a hand",
        bp, passes, passes, passes // 2))
      H.assertEq(m == o, true, "a Genji pair splits its passes evenly")
    end
    -- and the shape the driver actually asks for: hands is a COUNT, so a
    -- caller still passing the old boolean is refused rather than answered
    H.assertEq(pcall(H.fightHits, false, 2), false,
      "fightHits refuses a boolean where the armed-hand count belongs")
    H.assertEq(H.weaponClass(0x0F), 0x01, "ThunderBlade $0F is slashing")
    H.assertEq(H.weaponClass(0x05), 0x02, "Assassin $05 is piercing")
    H.assertEq(H.weaponClass(H.AUTOCROSSBOW), 0x02, "AutoCrossbow $AA is piercing")
    H.assertEq(H.weaponClass(0xFF), 0x04, "an empty hand is a bludgeoning fist")
    -- ...but it is not a WEAPON, and this ROM will say it is if asked
    -- naively (#235).  $FF is the empty-slot sentinel, not an item id;
    -- ItemProp has thirty bytes at that index all the same, and the type
    -- byte there reads $01, "weapon, record in use".  The hand model
    -- (handsOf) reads exactly this to decide whether a Fight's hits
    -- double, so the guard is load-bearing -- and the check below shows
    -- BOTH halves: the raw record really does read as a weapon, and
    -- M.isWeapon refuses it anyway.
    local ITEM_TYPE_FF = H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + 0xFF * 30)
    H.assertEq((ITEM_TYPE_FF & 0x80) == 0 and (ITEM_TYPE_FF & 0x07) == 1, true,
      string.format("ItemProp[$FF] type byte is $%02X -- it DOES read as a "
        .. "weapon, which is why the empty slot is refused by id",
        ITEM_TYPE_FF))
    H.assertEq(H.isWeapon(0xFF), false,
      "an empty hand is not a weapon: $FF is the empty slot, not an item id")
    H.assertEq(H.isWeapon(0x0A), true, "MithrilBlade $0A is a weapon")
    H.assertEq(H.isWeapon(0x5A), false, "a Buckler $5A is not")
    H.assertEq(H.spellReflectable(0x02), true, "Bolt $02 bounces off Reflect")
    H.assertEq(H.spellReflectable(0x0B), true, "Bolt 3 $0B (the 2-BP fold) bounces too")
    H.assertEq(H.spellReflectable(0x2D), true, "Cure $2D is reflectable (cast at allies, never at the monster)")
    H.assertEq(H.spellReflectable(0x38), false, "Shiva's summon attack $38 ignores Reflect")
    H.assertEq(H.spellReflectable(0x5D), false, "Pummel $5D ignores Reflect")
    H.assertEq(H.spellReflectable(0x8E), false, "Aqua Rake $8E ignores Reflect")
    H.log("battle_healpolicy: swing/landed-hit model checked AGAINST THIS "
      .. "ROM's FightAttack and Ot6FightBoost; class and reflect bits checked")
  end),

  -- 6. the two #165 rules, on the Rizopas seed $64 numbers (care_i50.log
  -- of the lab: SABIN's Fight landed 74 a hit shielded; Rizopas at 553 HP
  -- behind 1 shield; CYAN 358 max HP raised to 44 and killed by a -44
  -- Battle four times).
  --
  -- `hits` is LANDED hits (#235).  SABIN carries one weapon at the falls,
  -- so the three-hit volley below is his 2-BP Fight -- six swings, three
  -- of them the empty hand's -- not the 1-BP one this block used to call
  -- it.  The tie to the model is asserted rather than described.
  H.call(function()
    local sabinHits = select(1, H.fightHits(1, 2)) + select(2, H.fightHits(1, 2))
    H.assertEq(sabinHits, 3,
      "SABIN, one weapon, 2 BP: three landed hits -- the volley priced below")
    -- M.killEstimate: hits to the last chip land shielded, the rest x4
    local est, toBreak, broken = H.killEstimate({ per = 74, hits = sabinHits, chips = 3, need = 1 })
    H.assertEq(est, 74 + 2 * 4 * 74, "SABIN's 2-BP Fight (3 landed hits, 74 a hit) into 1 shield: 74 shielded then two broken hits = 666")
    H.assertEq(toBreak * 10 + broken, 12, "one hit to the break, two broken")
    H.assertEq(est >= 553, true, "666 covers Rizopas's 553: a kill this turn")
    est = H.killEstimate({ per = 49, hits = 3, chips = 3, need = 1 })
    H.assertEq(est, 49 + 2 * 4 * 49, "the same volley at 49 a hit is 441")
    H.assertEq(est >= 553, false, "441 is short of 553: break but not kill, so care first")
    est = H.killEstimate({ per = 74, hits = 3, chips = 3, need = 0 })
    H.assertEq(est, 3 * 4 * 74, "a broken gauge puts every hit in the window: 888")
    est = H.killEstimate({ per = 74, hits = 1, chips = 1, need = 1 })
    H.assertEq(est, 74, "0 BP: one landed hit, the break itself, nothing broken")
    H.assertEq(H.killEstimate({ per = 74, hits = 3, chips = 1, need = 2 }), nil, "chips short of the shields: no estimate")
    H.assertEq(H.killEstimate({ per = 0, hits = 3, chips = 3, need = 1 }), nil, "nothing measured yet: no estimate")
    est, toBreak, broken = H.killEstimate({ per = 100, hits = 6, chips = 3, need = 2 })
    H.assertEq(toBreak * 10 + broken, 42, "a Genji pair with one chipping hand: 2 chips of 3 spread over 6 landed hits is 4 to the break, 2 broken")
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

  -- 7. the refined raise gate (#168) and the Muddle rule (#170).  The
  -- numbers are battle 70's (magicite_ifrit_shiva, 2026-09-07: SABIN 511
  -- max HP, Fenix Down to 63, Ifrit's smallest hit 68 -- the gate held
  -- through eight turns of a won fight) and map 269's (#171: LOCKE 447 max
  -- HP one-shot at full HP by a 447 hit).
  H.call(function()
    local raiseHp, ok, why = H.raiseDecision({ maxhp = 511, power = 2, smallestHit = 68 })
    H.assertEq(raiseHp, 63, "Fenix Down raises SABIN (511) to 63")
    H.assertEq(ok, false, "with nothing else known, a 63-HP raise into a 68 hit is still refused")
    H.assertEq(type(why), "string", "...and the decision names its reason: " .. tostring(why))
    raiseHp, ok, why = H.raiseDecision({ maxhp = 511, power = 2, smallestHit = 68, killInReach = true })
    H.assertEq(ok, true, "the last monster inside the party's window: the raise is free (" .. why .. ")")
    raiseHp, ok, why = H.raiseDecision({ maxhp = 511, power = 2, smallestHit = 68,
                                         topUpFirst = true, topUp = 250 })
    H.assertEq(ok, true, "an ally's gauge fills before Ifrit's: 63 + 250 = 313 survives the 68 (" .. why .. ")")
    raiseHp, ok, why = H.raiseDecision({ maxhp = 511, power = 2, smallestHit = 68,
                                         topUpFirst = false, topUp = 250 })
    H.assertEq(ok, false, "Ifrit's gauge fills first: nobody can top up in time -- refused (" .. why .. ")")
    raiseHp, ok, why = H.raiseDecision({ maxhp = 447, power = 2, smallestHit = 447,
                                         topUpFirst = true, topUp = 250 })
    H.assertEq(raiseHp * 10 + (ok and 1 or 0), 550,
      "map 269: LOCKE (447) to 55, and 55 + 250 = 305 is still one-shot by the 447 -- refused even with the top-up first (" .. why .. ")")
    raiseHp, ok, why = H.raiseDecision({ maxhp = 447, power = 2, smallestHit = 447,
                                         killInReach = true })
    H.assertEq(ok, true, "...unless the kill is in reach, when the raise costs nothing")
    raiseHp, ok = H.raiseDecision({ maxhp = 358, power = 2, smallestHit = 44 })
    H.assertEq(ok, false, "Rizopas seed $64 unchanged: 44 into 44, nothing else known, refused")
    -- the top-up branch prices against the round the lift rule will use
    -- (review of 4ff9b236; arms/armGL_dullB/genlab_base_k0_s0_w9.log.gz:
    -- SABIN 1710 to 213, smallest hit 299, a round costs 1083)
    local needs
    raiseHp, ok, why, needs = H.raiseDecision({ maxhp = 1710, power = 2, smallestHit = 299,
                                                topUpFirst = true, topUp = 250, roundCost = 1083 })
    H.assertEq(tostring(ok) .. "/" .. tostring(needs), "false/nil",
      "213 + 250 = 463 does not clear the 1083 round: no raise on a top-up the lift rule will refuse (" .. why .. ")")
    raiseHp, ok, why, needs = H.raiseDecision({ maxhp = 1710, power = 2, smallestHit = 299,
                                                topUpFirst = true, topUp = 250, roundCost = 400 })
    H.assertEq(tostring(ok) .. "/" .. tostring(needs), "true/true",
      "463 clears a 400 round: the raise stands and owes its top-up (" .. why .. ")")
    raiseHp, ok, why, needs = H.raiseDecision({ maxhp = 1710, power = 2, smallestHit = 150,
                                                topUpFirst = true, topUp = 250, roundCost = 1083 })
    H.assertEq(tostring(ok) .. "/" .. tostring(needs), "true/nil",
      "213 survives the 150 hit alone: raised, and no top-up is owed (" .. why .. ")")
    -- the ATB read behind topUpFirst: $3218,x is the 16-bit gauge the
    -- engine adds $3ac8,x to every tick and reads as full when its high
    -- byte is 0 (battle_main.asm `lda $3219,x / beq` "branch if atb
    -- gauge is full"; the overflow `stz $3219,x`)
    H.assertEq(H.atbEta(0x8000, 0x0100), 128, "half full at 256 a tick: 128 ticks to full")
    H.assertEq(H.atbEta(0xFF00, 0x0100), 1, "one tick short")
    H.assertEq(H.atbEta(0x0010, 0x0100), 0, "high byte 0 is a full gauge (the engine's own test)")
    H.assertEq(H.atbEta(0x8000, 0), nil, "a stopped gauge never fills")
    -- Muddle.  Remedy $F5's record is vanilla's byte for byte; its
    -- status-2 cure mask is SILENCE|SAP, no CONFUSE (bit 5), which is why
    -- battle_magicite measured two Remedies leave muddled Edgar muddled.
    H.assertEq(H.itemStatus2(0xF5), 0x48, "Remedy $F5 status-2 cure mask is $48 = SILENCE|SAP (ItemProp +22)")
    H.assertEq(H.itemStatus2(0xF5) & H.ST2_MUDDLE, 0, "...so a Remedy never cured Muddle: vanilla, not authored")
    H.assertEq(H.itemStatus1(0xF0), 0x80, "Fenix Down $F0 status-1 cure mask is DEAD (the same record shape)")
    local full = { [0] = 1, [1] = 1, [2] = 1, [3] = 1 }
    H.assertEq(H.muddleRule({ actor = 0, status2 = { [0] = 0, [1] = 0x20, [2] = 0, [3] = 0 },
                              hp = full, maxhp = full }), 1,
      "a muddled living ally: the actor Fights entity 1 to clear it")
    H.assertEq(H.muddleRule({ actor = 0, status2 = { [0] = 0x20, [1] = 0x20, [2] = 0, [3] = 0 },
                              hp = full, maxhp = full }), "defer",
      "a muddled actor never plans: its inputs are the game's own targeting")
    H.assertEq(H.muddleRule({ actor = 0, status2 = { [0] = 0, [1] = 0x20, [2] = 0, [3] = 0 },
                              hp = { [0] = 1, [1] = 0, [2] = 1, [3] = 1 }, maxhp = full }), nil,
      "a dead muddled ally is the raise rule's business, not a hit")
    H.assertEq(H.muddleRule({ actor = 2, status2 = { [0] = 0, [1] = 0, [2] = 0, [3] = 0 },
                              hp = full, maxhp = full }), nil, "nobody muddled: nothing to do")
    -- the floor (#320): the cure-hit is not aimed at an ally it would
    -- kill -- the lab's SABIN, Peace Ring on, killed CELES at 75/1595
    -- with it; the ally comes back as `held`, and one above it is hit
    local r, held = H.muddleRule({ actor = 1, status2 = { [0] = 0x20, [1] = 0, [2] = 0, [3] = 0 },
      hp = { [0] = 75, [1] = 1509, [2] = 0, [3] = 0 }, maxhp = { [0] = 1595, [1] = 1609, [2] = 0, [3] = 0 },
      floor = { [0] = 398 } })
    H.assertEq(r, nil, "a muddled ally at 75 under a floor of 398: no cure-hit")
    H.assertEq(held, 0, "...and it is said as held")
    H.assertEq(H.muddleRule({ actor = 1, status2 = { [0] = 0x20, [1] = 0, [2] = 0, [3] = 0 },
      hp = { [0] = 1134, [1] = 1509, [2] = 0, [3] = 0 }, maxhp = { [0] = 1595, [1] = 1609, [2] = 0, [3] = 0 },
      floor = { [0] = 398 } }), 0, "a muddled ally above the floor: hit it to clear it")
    -- the boundary: an ally standing exactly on the floor is one the
    -- measured hit would kill (hp - hit = 0), so it is held too
    r, held = H.muddleRule({ actor = 1, status2 = { [0] = 0x20, [1] = 0, [2] = 0, [3] = 0 },
      hp = { [0] = 398, [1] = 1509, [2] = 0, [3] = 0 }, maxhp = { [0] = 1595, [1] = 1609, [2] = 0, [3] = 0 },
      floor = { [0] = 398 } })
    H.assertEq(r, nil, "a muddled ally exactly at the floor (398 of a 398 hit): no cure-hit")
    H.assertEq(held, 0, "...and it is said as held")
    H.assertEq(H.muddleRule({ actor = 1, status2 = { [0] = 0x20, [1] = 0, [2] = 0, [3] = 0 },
      hp = { [0] = 399, [1] = 1509, [2] = 0, [3] = 0 }, maxhp = { [0] = 1595, [1] = 1609, [2] = 0, [3] = 0 },
      floor = { [0] = 398 } }), 0, "one HP above the floor: hit it")
    -- one cure-hit in flight (#348): the tomb's EDGAR planned a second
    -- hit on CELES while SETZER's was still queued, and SETZER's killed
    -- her; an ally whose hit is in flight is neither hit again nor held,
    -- and the next muddled ally is the one planned for
    local q4 = { [0] = 1000, [1] = 1500, [2] = 1200, [3] = 1400 }
    local m4 = { [0] = 1696, [1] = 1609, [2] = 1600, [3] = 1500 }
    r, held = H.muddleRule({ actor = 2, status2 = { [0] = 0x20, [1] = 0, [2] = 0, [3] = 0 },
      hp = q4, maxhp = m4, inFlight = { [0] = true } })
    H.assertEq(tostring(r) .. "/" .. tostring(held), "nil/nil",
      "a muddled ally with another member's cure-hit in flight: no second hit, not held")
    H.assertEq(H.muddleRule({ actor = 2, status2 = { [0] = 0x20, [1] = 0x20, [2] = 0, [3] = 0 },
      hp = q4, maxhp = m4, inFlight = { [0] = true } }), 1,
      "...and another muddled ally beside it is the one this actor hits")
    H.assertEq(H.muddleRule({ actor = 2, status2 = { [0] = 0x20, [1] = 0, [2] = 0, [3] = 0 },
      hp = q4, maxhp = m4 }), 0, "the same ally with nothing in flight: hit it")
    -- the floor's price (#348, H.allyFightMax), the engine's arithmetic
    -- worked by hand: bp 100, L30, vigor x2 80, defense 100 -- attack 180,
    -- 180 x 30 x 30 / 256 = 632, 100 + 1.5 x 632 = 1048, x255/256 + 1 =
    -- 1044, x155/256 + 1 = 633, halved for one party member on another: 316
    local base = { hands = { { bp = 100 } }, level = 30, vigor2 = 80, def = 100 }
    local f = H.allyFightMax(base)
    H.assertEq(f.max * 10000 + f.crit, 3160632, "a plain Fight on an ally priced at 316, a critical 632")
    H.assertEq(f.top, 632, "...and the floor is the critical's")
    base.tBackRow = true
    H.assertEq(H.allyFightMax(base).max, 158, "the ally in the back row halves it")
    base.tBackRow = nil
    -- every row of the weapon-effect class (review of f8f9ad66, M2): the
    -- same swing, worked by hand from the engine's paths (the comment at
    -- M.allyFightMax names each)
    local function fx(hand, extra)
      local o = { hands = { hand }, level = 30, vigor2 = 80, def = 100, magpow = 60 }
      for k, v in pairs(extra or {}) do o[k] = v end
      return H.allyFightMax(o)
    end
    -- a weapon spell (CheckWeaponMagic, 1 swing in 4): power 20 at magic
    -- power 60, L30: 80 + 60 x 20 x 30 / 32 = 1205, x255/256 + 1 = 1201,
    -- x255/256 + 1 (magic defense 0) = 1197, halved for an ally: 598, on
    -- top of the critical swing's 632
    f = fx({ bp = 100, spell = { power = 20, elem = 0 } })
    H.assertEq(f.max * 10000 + f.top, 3161230, "a hand that casts: max 316, the floor 632 + its spell 598")
    f = fx({ bp = 100, effect = 13 })
    H.assertEq(f.lethal ~= nil, true, "Scimitar/Zantetsuken (effect 13): instant death, lethal at any HP")
    f = fx({ bp = 100, effect = 9, dice = 2 })
    H.assertEq(f.max * 10000 + f.top, 21602160, "Dice (effect 9): no damage modification, 6 x 6 x L30 x 2 = 2160")
    f = fx({ bp = 100, effect = 9, dice = 3 })
    H.assertEq(f.top, 9999, "Fixed Dice, three dice: 216 x 7 (a triple) x L30 x 2 -> the 9999 cap")
    f = fx({ bp = 100, effect = 11, windSlash = { power = 60, elem = 0 } })
    H.assertEq(f.max * 10000 + f.top, 3161793,
      "Tempest (effect 11): 1 swing in 2 a Wind Slash (power 60: 1793) in place of the swing")
    f = fx({ bp = 100, effect = 12 })
    H.assertEq(f.top, 0, "Heal Rod (effect 12): heals, nothing to price")
    f = fx({ bp = 100, effect = 4 }, { human = true })
    H.assertEq(f.max * 10000 + f.top, 6320948, "Man Eater (effect 4) on a human: $bc+2, x2; a critical x3")
    f = fx({ bp = 100, effect = 7 })
    H.assertEq(f.max * 10000 + f.top, 6320632, "an MP critical (effect 7): x2 always, no second critical")
    f = fx({ bp = 100, effect = 2 }, { hp = 1600, maxhp = 1600 })
    H.assertEq(f.max * 10000 + f.top, 2450245, "Atma Weapon (effect 2): no defense, no critical, x(HP+1)L/(MaxHP+1)/64")
    f = fx({ bp = 100, effect = 10 }, { hp = 600, maxhp = 1600 })
    H.assertEq(f.max * 10000 + f.top, 10202040, "Valiant Knife (effect 10): no defense, + its missing 1000 HP")
    f = fx({ bp = 100, effect = 8 }, { tFloat = true })
    H.assertEq(f.max * 10000 + f.top, 9481264, "Sniper (effect 8) on a floater: $bc+4, x3; a critical x4")
    base.hands = { { bp = 100, effect = 3 } }
    H.assertEq(H.allyFightMax(base).lethal ~= nil, true,
      "the Trump's instant death (effect 3): lethal at any HP (the tomb's CELES, from 989/1696)")
    base.deathProof = true
    H.assertEq(H.allyFightMax(base).lethal, nil, "...unless the ally is proof against instant death")
    base.deathProof = nil
    base.hands = { { bp = 100, elem = 0x01 } }
    base.absorb = 0x01
    H.assertEq(H.allyFightMax(base).max, 0, "a weapon element the ally absorbs: nothing to price")
    H.log("battle_healpolicy: refined raise gate, ATB read and Muddle rule checked")
  end),

  -- 9. the wipe verdict (#166) on the bytes the old scan misread.  rows are
  -- the four battle seats { actor = $3ed8+2e, present = $3aa0+2e bit 0,
  -- hp = $3bf4+2e, maxhp = $3c1c+2e }; flags is $3ebc.  The rows are
  -- probe_wipe166's measured ones (2026-09-07; deleted in bd50a973, last
  -- version at 998278f3).
  H.call(function()
    local function row(a, hp, mx, hidden)
      return { actor = a, present = a ~= 0xFF and not hidden, hp = hp, maxhp = mx }
    end
    local EMPTY = row(0xFF, 0, 0)
    -- A Veldt random from falls_done: "seats=[a5:0/363 a2:0/358 a11:394/394
    -- -:0/0] $1850 marks 2 $3ebc=01 $3a74=00" -- seat 2 is GAU, the
    -- formation's hidden character AI, present bit clear, full HP; the
    -- #163 audit's gau_joined wipe read the same [0/363 0/358 394/394 0/0]
    local veldt = { row(5, 0, 363), row(2, 0, 358), row(11, 394, 394, true), EMPTY }
    H.assertEq(H.wipeVerdict(veldt, 0x00), true,
      "the Veldt: SABIN and CYAN at 0 with hidden GAU at 394/394 in seat 2 is a wipe (the HP half)")
    H.assertEq(H.wipeVerdict(veldt, 0x01), true, "...and with LoseBattle's flag up, still one")
    H.assertEq(H.wipeVerdict({ row(5, 0, 363), row(2, 40, 358), row(11, 394, 394, true), EMPTY }, 0x00), false,
      "...and CYAN at 40 is not")
    H.assertEq(H.wipeVerdict({ row(5, 0, 363), row(2, 0, 358), row(11, 394, 394), EMPTY }, 0x00), false,
      "a PRESENT third member at 394 is a survivor (the present bit is what separates him from GAU)")
    -- KEFKA from kefka_entry: "seats=[a0:0/306 a4:0/354 a6:0/310 -:0/0]
    -- $1850 marks 7 $3ebc=00 $3a74=02" -- the HP half, 212 frames before
    -- the flag; the verdict never consults the head count
    local narshe = { row(0, 0, 306), row(4, 0, 354), row(6, 0, 310), EMPTY }
    H.assertEq(H.wipeVerdict(narshe, 0x00), true, "KEFKA: three seated at 0 is a wipe however many $1850 marks")
    H.assertEq(H.wipeVerdict({ row(0, 1, 306), row(4, 0, 354), row(6, 0, 310), EMPTY }, 0x00), false,
      "TERRA at 1 HP: not a wipe")
    -- LoseBattle's own verdict: $3ebc bit 0 counts even with HP words up
    -- (an all-petrified party), and bit 0 only (the FC's measured $0D has it)
    H.assertEq(H.wipeVerdict({ row(0, 200, 400), row(4, 150, 380), EMPTY, EMPTY }, 0x01), true,
      "LoseBattle's bit 0 with HP words still up (petrify/zombie) is a wipe")
    H.assertEq(H.wipeVerdict({ row(0, 0, 400), row(4, 0, 380), EMPTY, EMPTY }, 0x0D), true,
      "the FC wipe's $3ebc=$0D counts")
    H.assertEq(H.wipeVerdict({ row(0, 200, 400), row(4, 150, 380), EMPTY, EMPTY }, 0x0C), false,
      "$0C -- bits 2/3 without bit 0 -- is not the game-over flag")
    -- the shape gate: bytes another module owns are never a wipe
    H.assertEq(H.wipeVerdict({ EMPTY, EMPTY, EMPTY, EMPTY }, 0x01), false,
      "no seat filled: nothing to judge, flag or not")
    H.assertEq(H.wipeVerdict({ row(11, 394, 394, true), EMPTY, EMPTY, EMPTY }, 0x01), false,
      "only a hidden seat: nothing to judge either")
    H.assertEq(H.wipeVerdict({ row(0, 0, 17732), EMPTY, EMPTY, EMPTY }, 0x00), false,
      "falls_done's boot words [54740/17732 ...]: a max over 9999 is not a battle table")
    H.assertEq(H.wipeVerdict({ row(0, 0, 0), EMPTY, EMPTY, EMPTY }, 0x00), false,
      "all-zero RAM (power-on): actor 0 with max 0 is not a seated character")
    H.assertEq(H.wipeVerdict({ row(0x80, 0, 300), EMPTY, EMPTY, EMPTY }, 0x00), false,
      "an actor byte out of 0..15 is not a battle table")
    H.log("battle_healpolicy: wipe verdict (#166) checked")
  end),

  -- 10. the cast guards' decision (#99, #156, #172) on battle 70's bytes:
  -- Ifrit $0109 (absorb $01 fire, null $FC) and Shiva $0108 (absorb $02
  -- ice, null $FC), MonsterProp +23/+24, read from this ROM; CELES's Ice
  -- $01 is element $02 and reflectable.  The stage is whoever is present
  -- and alive; the fight driver's activeSlots reads it from the live
  -- records, and the mask the old guard enumerated ($3F45, the
  -- formation's opening line-up) read $01 all fight, so Shiva in slot 1
  -- was never on its list.
  H.call(function()
    local IFRIT, SHIVA = 0x0109, 0x0108
    H.assertEq(H.monsterAbsorb(SHIVA), 0x02, "Shiva $0108 absorbs ice (MonsterProp +23)")
    H.assertEq(H.monsterAbsorb(IFRIT), 0x01, "Ifrit $0109 absorbs fire")
    H.assertEq(H.monsterNull(SHIVA), 0xFC, "Shiva nulls everything but fire/ice")
    H.assertEq(H.spellElement(0x01), 0x02, "Ice $01 is element $02")
    local function mon(slot, species, reflect)
      return { slot = slot, species = species, absorb = H.monsterAbsorb(species),
               null = H.monsterNull(species), reflect = reflect or false }
    end
    local ice, refl = H.spellElement(0x01), H.spellReflectable(0x01)
    local s, why = H.castVeto(ice, refl, { mon(0, IFRIT) })
    H.assertEq(s, nil, "Ifrit alone in the formation: Ice flows (his weakness)")
    s, why = H.castVeto(ice, refl, { mon(1, SHIVA) })
    H.assertEq(s and s.slot, 1, "Shiva in the formation in slot 1: Ice is refused")
    H.assertEq(why, "absorb", "...because she ABSORBS it")
    s, why = H.castVeto(ice, refl, { mon(0, IFRIT), mon(1, SHIVA) })
    H.assertEq(why, "absorb", "both in the formation: the absorber wins the veto")
    s, why = H.castVeto(ice, refl, {})
    H.assertEq(s, nil, "nobody in the formation (the fly-in): nothing to refuse")
    -- the live byte is what is judged, not the species: a slot whose record
    -- says no absorb passes even under Shiva's species word
    s, why = H.castVeto(ice, refl, { { slot = 1, species = SHIVA, absorb = 0, null = 0, reflect = false } })
    H.assertEq(s, nil, "a live record with no absorb passes whatever the species word says")
    -- the other two halves
    local bolt = H.spellElement(0x02)
    s, why = H.castVeto(bolt, H.spellReflectable(0x02), { mon(1, SHIVA) })
    H.assertEq(why, "null", "Bolt into Shiva: every element nulled ($FC) -- refused")
    s, why = H.castVeto(bolt, true, { mon(0, IFRIT, true) })
    H.assertEq(why, "reflect", "a reflectable cast at a Reflect bearer -- refused")
    s, why = H.castVeto(bolt, false, { mon(0, IFRIT, true) })
    H.assertEq(why, "null", "an unreflectable Bolt at Ifrit under Reflect: still nulled ($FC)")
    s, why = H.castVeto(0, false, { mon(0, IFRIT, true), mon(1, SHIVA) })
    H.assertEq(s, nil, "an elementless, unreflectable line (a summon, a lore) passes")
    H.log("battle_healpolicy: cast guards' decision (#172) checked")
  end),

  -- 11. the spend rule (#175, H.spendDecision) on the Rizopas care_i50
  -- numbers (SABIN 82/363 under a 244 round, CYAN dead, Potion +91
  -- measured, the driver spent eleven turns on care) and the wipe
  -- classification (H.wipeClass) the [wipe] line and audit_boost print.
  H.call(function()
    local v, why = H.spendDecision({ hp = 82, maxhp = 363, roundCost = 244, bp = 1,
      heals = { { what = "item $E9", restore = 91 } } })
    H.assertEq(v, "spend", "SABIN 82/363 under a 244 round with 1 BP: the Potion's 82 + 91 = 173 does not survive -- spend (" .. why .. ")")
    v, why = H.spendDecision({ hp = 82, maxhp = 363, roundCost = 244, bp = 0,
      heals = { { what = "item $E9", restore = 91 } } })
    H.assertEq(v, nil, "...with no pips there is nothing to spend (" .. why .. ")")
    v, why = H.spendDecision({ hp = 82, maxhp = 363, roundCost = 244, bp = 2,
      heals = { { what = "item $E9", restore = 250 } } })
    H.assertEq(v, nil, "a full Potion saves: 82 + 250 = 332 survives the 244 -- heal, keep the pips (" .. why .. ")")
    v, why = H.spendDecision({ hp = 82, maxhp = 363, roundCost = 244, bp = 2,
      heals = { { what = "cure $2D", restore = nil }, { what = "item $E9", restore = 91 } } })
    H.assertEq(v, nil, "an unmeasured cure may be the saving one: measure it first (" .. why .. ")")
    v, why = H.spendDecision({ hp = 300, maxhp = 363, roundCost = 244, bp = 3, heals = {} })
    H.assertEq(v, nil, "300 HP is outside the 244 round: not dying, the bank's business (" .. why .. ")")
    v, why = H.spendDecision({ hp = 363, maxhp = 363, roundCost = 0, bp = 3, heals = {} })
    H.assertEq(v, nil, "no round measured yet: nothing says next round is lethal (" .. why .. ")")
    v, why = H.spendDecision({ hp = 447, maxhp = 447, roundCost = 447, bp = 3, heals = {} })
    H.assertEq(v, "spend", "map 269: LOCKE at full 447 under a 447 one-shot with 3 BP and nothing to heal with -- spend (" .. why .. ")")
    -- a Potion the lift rule refused is named, not "nothing to heal with"
    -- (review of b490ce32: gate s5 "134/902 ... no heal saves it (nothing to
    -- heal with)" with 60 Potions in the bag)
    v, why = H.spendDecision({ hp = 134, maxhp = 902, roundCost = 418, bp = 3, heals = {},
      refused = { { what = "item $E9", restore = 250 } } })
    H.assertEq(v == "spend" and why:find("item $E9 +250 = 384, not lifting clear of the round", 1, true) ~= nil, true,
      "the refused Potion is named in the spend line (" .. why .. ")")
    -- and the spend line names why nothing saves (review of care-items
    -- cae71db9: "(nothing to heal with)" while the budget had closed care)
    H.assertEq(why:find("(the lift rule: item $E9", 1, true) ~= nil, true,
      "a heal the lift rule refused: the lift rule is the reason (" .. why .. ")")
    v, why = H.spendDecision({ hp = 447, maxhp = 447, roundCost = 447, bp = 3, heals = {} })
    H.assertEq(why:find("(the bag holds no heal)", 1, true) ~= nil, true,
      "an empty bag is said as one (" .. why .. ")")
    v, why = H.spendDecision({ hp = 144, maxhp = 820, roundCost = 286, bp = 1, heals = {},
      why = "the round's care turn went to actor 3",
      refused = { { what = "item $EA", restore = 676, note = "it would lift, but not this turn" } } })
    H.assertEq(v == "spend" and why:find("(the round's care turn went to actor 3: item $EA +676 = 820, "
      .. "it would lift, but not this turn)", 1, true) ~= nil, true,
      "the Gate's s5 LOCKE: the budget is the reason, and the X-Potion that would lift is named (" .. why .. ")")
    -- a heal in flight holds the others off its target only when it lifts
    -- them, or they are outside their round (re-review of cae71db9: SETZER at
    -- 25/902 under 413 on a queued Potion, an Elixir in the bag)
    H.assertEq(H.inFlightHolds({ restore = 250 }, 25, 413), false,
      "a queued Potion that leaves him at 275 under 413 does not hold the Elixir off")
    H.assertEq(H.inFlightHolds({ restore = 250 }, 231, 413), true,
      "...one that lifts him (231 + 250 = 481) does")
    H.assertEq(H.inFlightHolds({ restore = 250 }, 600, 413), true,
      "...and outside the round the guard holds whatever is queued")
    H.assertEq(H.inFlightHolds({}, 25, 413), true, "...as does a queued heal of unknown size")
    -- the budget reopens for a lift (review of care-items cae71db9)
    H.assertEq(H.liftReopens({ hp = 144, cost = 286, restores = { 250, 676 } }), true,
      "LOCKE at 144/820 inside a 286 round, an X-Potion's 676 in hand: the budget reopens")
    H.assertEq(H.liftReopens({ hp = 30, cost = 286, restores = { 250 } }), false,
      "...not for a heal that leaves him inside the round (30 + 250 = 280)")
    H.assertEq(H.liftReopens({ hp = 400, cost = 286, restores = { 676 } }), false,
      "...nor for a member outside the round: that is a top-up, the budget's to keep")
    -- the wipe class
    local d = function(tick, from, maxhp, bp, one)
      return { tick = tick, from = from, maxhp = maxhp, bp = bp, oneAction = one }
    end
    H.assertEq(H.wipeClass({ d(512, 447, 447, 1, true), d(513, 443, 443, 0, true) }),
      "one-shot early", "two L4 Flare one-shots at f+512: a level problem")
    H.assertEq(H.wipeClass({ d(5600, 284, 363, 3, false), d(5600, 221, 358, 4, false) }),
      "died with 4 BP banked", "El Nino at t=5600 with 3 and 4 pips held: a driver problem")
    H.assertEq(H.wipeClass({ d(512, 447, 447, 1, true), d(5600, 221, 358, 4, false) }),
      "one-shot early + died with 4 BP banked", "both shapes in one wipe are both reported")
    H.assertEq(H.wipeClass({ d(5600, 447, 447, 2, true) }),
      "worn down (no one-shot, no pips banked)", "a one-shot late in the fight is not 'early'; 2 BP is under the bar")
    H.assertEq(H.wipeClass({}), "no deaths recorded", "no records: says so")
    H.log("battle_healpolicy: spend rule and wipe class (#175) checked")
  end),

  -- 11b. the round price (#206, #194, H.roundCost): the enemy actions
  -- whose gauges fill inside the member's window, each at the worst
  -- single action that enemy has landed.  The numbers are the labs':
  -- the gate soldier's front-row seed 40 ([round] window 182 ticks, the
  -- soldier's gauge 167 of a 227-tick period) with seed 20's TekLaser
  -- 149, his worst on LOCKE, and the Air Force lab's bay_i12 EDGAR at
  -- 393/1048 with two Tek Lasers queued (207 and 196 landed on the party).
  H.call(function()
    local c, n, why = H.roundCost({ window = 182,
      enemies = { { slot = 0, eta = 167, period = 227, worst = 149 } } })
    H.assertEq(c * 10 + n, 1491, "solo soldier, one action inside LOCKE's window: 149, not the 262 "
      .. "a TekLaser plus a front-row Battle summed (" .. why .. ")")
    H.assertEq(H.spendDecision({ hp = 17, maxhp = 279, roundCost = c, bp = 3,
      heals = { { what = "item $E9", restore = 250 } } }), nil,
      "LOCKE at 17 under that 149 round: the Potion saves (17 + 250 = 267)")
    H.assertEq(H.healDecision({ hp = 17, maxhp = 279, restore = 250, roundCost = c,
      allies = 0, threshold = 60 }), "top-up",
      "...and the heal policy takes it: 250 outheals a 149 round (it refused it against 262)")
    local rate
    c, n, why, rate = H.roundCost({ window = 182,
      enemies = { { slot = 0, eta = 200, period = 227, worst = 149 } } })
    H.assertEq(c * 10 + n, 0, "the soldier's gauge fills after LOCKE's: nothing lands first")
    H.assertEq(rate, 149 * 182 // 227, "...but a count of rounds is priced at the steady rate: 149 x 182/227 = 119")
    c, n = H.roundCost({ window = 500,
      enemies = { { slot = 0, eta = 40, period = 227, worst = 149 } } })
    H.assertEq(c * 10 + n, 4473, "a window three refills long: 40, 267, 494 -- three actions, 447")
    c, n, why = H.roundCost({ window = 250,
      enemies = { { slot = 0, eta = 30, period = 300, worst = 207 },
                  { slot = 2, eta = 90, period = 300, worst = 196 },
                  { slot = 4, eta = 400, period = 300, worst = 235 } } })
    H.assertEq(c * 10 + n, 4032, "two Tek Lasers from two slots inside EDGAR's window: 207 + 196 = 403, "
      .. "the third gauge outside it (" .. why .. ")")
    H.assertEq(393 <= c, true, "EDGAR at 393 is inside that round; the largest single loss seen (382) said he was not")
    H.assertEq(H.spendDecision({ hp = 393, maxhp = 1048, roundCost = c, bp = 4, heals = {} }), "spend",
      "...holding 4 BP with no heal coming: spend")
    c, n, why = H.roundCost({ window = 250, fallback = 207,
      enemies = { { slot = 0, eta = 30, period = 300, worst = nil },
                  { slot = 1, eta = nil, period = nil, worst = 500 } } })
    H.assertEq(c * 10 + n, 2071, "an unmeasured enemy acting is priced at the battle's worst action; "
      .. "a gauge that cannot fill (Stop) adds nothing (" .. why .. ")")
    c, n = H.roundCost({ window = 250, enemies = { { slot = 0, eta = 30, period = 300 } } })
    H.assertEq(c * 10 + n, 1, "nothing measured anywhere: the action is counted, priced at 0")
    -- one enemy acting twice in the window (#312's Dullahan finding): its
    -- worst once and its typical action for the second.  The numbers are
    -- var1_k6_s0_w1's: a 202-tick window, his gauge full with a 139-tick
    -- period, Pearl 1086 his worst, and the mean of his landed actions
    -- there (195, 197, 460, 299, 202, 1083, 623, 1086) 518
    c, n, why = H.roundCost({ window = 202,
      enemies = { { slot = 0, eta = 0, period = 139, worst = 1086, typical = 518 } } })
    H.assertEq(c * 10 + n, 16042, "Dullahan twice in a window: 1086 + 518 = 1604, not 2 x 1086 = 2172 ("
      .. why .. ")")
    H.assertEq(c < 1798 and 2172 > 1798, true, "...under his targets' max HP, where the old price was above it")
    c, n = H.roundCost({ window = 202,
      enemies = { { slot = 0, eta = 0, period = 139, worst = 1086 } } })
    H.assertEq(c * 10 + n, 21722, "no typical measured: every action at the worst, as before")
    c, n = H.roundCost({ window = 100,
      enemies = { { slot = 0, eta = 0, period = 139, worst = 1086, typical = 518 } } })
    H.assertEq(c * 10 + n, 10861, "one action in the window: the worst alone")
    c, n = H.roundCost({ window = 500,
      enemies = { { slot = 0, eta = 40, period = 227, worst = 149, typical = 200 } } })
    H.assertEq(c * 10 + n, 4473, "a typical above the worst (a mean of misreads) never raises the price")
    H.log("battle_healpolicy: round price (#206, #194) checked")
  end),

  -- 12. the raise gate's floor: every measured hit, a level spell's
  -- included.  The #174 exemption was measured out (map269-random.md,
  -- 2026-09-16: 20 Fenix Downs against main's 12, no frames gained) and
  -- main's gate stands: LOCKE (447) raised to 55 under a measured 447
  -- (Trapper's L4 Flare) or 55 (its recurrence) is refused.
  H.call(function()
    local rHp, rOk = H.raiseDecision({ maxhp = 447, power = 2, smallestHit = 447 })
    H.assertEq(rHp * 10 + (rOk and 1 or 0), 550, "LOCKE to 55 under a measured 447 one-shot: no raise")
    rHp, rOk = H.raiseDecision({ maxhp = 447, power = 2, smallestHit = 55 })
    H.assertEq(rHp * 10 + (rOk and 1 or 0), 550, "LOCKE to 55 under a measured 55 recurrence: no raise")
    H.assertEq(H.hitFloorExempt, nil, "no level-spell exemption in the lib (#174, measured out)")
    H.log("battle_healpolicy: the raise gate's floor (#165) checked")
  end),

  -- 12b. the battle's layout (#176, H.battleLayout): which way the target
  -- cursor crosses, by battle type ($201F) and target group ($7ACE).  The
  -- directions are btlgfx's own jump tables (btlgfx_main.asm "move
  -- character target left/right jump table (1 per battle type)"): in a
  -- normal battle LEFT crosses to the monsters and RIGHT is an rts; in a
  -- back attack it is the other way round -- the J39-row hang.
  H.call(function()
    local L = H.battleLayout({ type = 0, group = 1 })
    H.assertEq(L.name .. ":" .. L.toMonsters[1] .. ":" .. L.toChars[1],
      "normal:left:right", "a normal battle: LEFT to the monsters, RIGHT back")
    H.assertEq(#L.toMonsters, 1, "...and only that one direction crosses")
    L = H.battleLayout({ type = 1, group = 1 })
    H.assertEq(L.name .. ":" .. L.toMonsters[1] .. ":" .. L.toChars[1],
      "back attack:right:left", "a back attack: RIGHT to the monsters (#176)")
    H.assertEq(#L.toMonsters, 1, "...and LEFT is not offered: it is an rts")
    L = H.battleLayout({ type = 2, group = 1 })
    H.assertEq(L.name .. ":" .. table.concat(L.toMonsters, ","),
      "pincer:left,right", "a pincer: monsters on both sides, either crosses")
    L = H.battleLayout({ type = 3, group = 1 })
    H.assertEq(L.name .. ":" .. L.toMonsters[1], "side attack:right",
      "a side attack with the cursor on the left party group ($7ACE=1): RIGHT")
    L = H.battleLayout({ type = 3, group = 3 })
    H.assertEq(L.toMonsters[1], "left",
      "...and on the rightmost group ($7ACE=3): LEFT (RIGHT returns there)")
    L = H.battleLayout({ type = 7, group = 0 })
    H.assertEq(L.name, "unknown", "an unread battle type says so rather than guessing quietly")
    H.log("battle_healpolicy: the battle layout's crossing directions (#176) checked")
  end),

  -- 12c. the turn-denying statuses (#187, H.turnDenied) and the preemptive
  -- strike (#186, H.battleLayout's `preemptive`), as arithmetic on the
  -- bytes: Stop is STATUS3 $10, Sleep STATUS2 $80, Berserk STATUS2 $10;
  -- Imp (STATUS1 $20) keeps its window and is not a denial.  The cure
  -- lookup (H.statusCure) reads the ROM's item records: Green Cherry
  -- $F8 STATUS1 $20, Remedy $F5 STATUS1 $65 / STATUS2 $48, so Imp has a
  -- cure and Berserk has none (ROM read 2026-09-16).
  H.call(function()
    H.assertEq(H.turnDenied({ s1 = 0, s2 = 0, s3 = 0x10 }), "Stop", "STATUS3 bit 4 is Stop")
    H.assertEq(H.turnDenied({ s1 = 0, s2 = 0x80, s3 = 0 }), "Sleep", "STATUS2 bit 7 is Sleep")
    H.assertEq(H.turnDenied({ s1 = 0, s2 = 0x10, s3 = 0 }), "Berserk", "STATUS2 bit 4 is Berserk")
    H.assertEq(H.turnDenied({ s1 = 0x20, s2 = 0, s3 = 0 }), nil, "Imp alone denies no turn")
    H.assertEq(H.turnDenied({ s1 = 0, s2 = 0x20, s3 = 0 }), nil, "Muddle is the Muddle rule's, not a denial")
    H.assertEq(H.turnDenied({ s1 = 0, s2 = 0x90, s3 = 0x10 }), "Stop", "Stop is named first when several stand")
    local bag = { [0xF8] = true }
    H.assertEq(H.statusCure({ byte = 1, bit = 0x20, has = function(i) return bag[i] end }), 0xF8,
      "an Imp with a Green Cherry in the bag: the Green Cherry")
    bag = { [0xF5] = true }
    H.assertEq(H.statusCure({ byte = 1, bit = 0x20, has = function(i) return bag[i] end }), 0xF5,
      "...with only Remedies: the Remedy (its record carries Imp)")
    H.assertEq(H.statusCure({ byte = 2, bit = 0x10, items = { 0xF5 },
      has = function(i) return bag[i] end }), nil,
      "Berserk with Remedies in the bag: nothing (Remedy's STATUS2 byte is $48)")
    H.assertEq(H.battleLayout({ type = 0, group = 1, preemptive = true }).preemptive, true,
      "a preemptive strike rides the layout")
    H.assertEq(H.battleLayout({ type = 0, group = 1 }).preemptive, false,
      "...and defaults off for a supplied type")
    H.log("battle_healpolicy: the turn-denying statuses (#187) and the preemptive flag (#186) checked")
  end),

  -- 12d. the two shapes of a denied window (#224, H.windowKept): Stop and
  -- Frozen keep the window the engine has open (CheckPlayerAction @091f
  -- cancels the menu for Sleep, Berserk and Petrify only), so a command
  -- entered there waits for the counter; Petrify (STATUS1 $40) and Frozen
  -- (STATUS4 $02) are denials, and a statue's cure is Soft $F4 then
  -- Remedy (ROM: Soft STATUS1 $40, Remedy $65; no item record carries
  -- Stop, Frozen or Condemned with the remove flag, read 2026-09-21).
  H.call(function()
    H.assertEq(H.turnDenied({ s1 = 0x40, s2 = 0, s3 = 0, s4 = 0 }), "Petrify", "STATUS1 bit 6 is Petrify")
    H.assertEq(H.turnDenied({ s1 = 0, s2 = 0, s3 = 0, s4 = 0x02 }), "Frozen", "STATUS4 bit 1 is Frozen")
    H.assertEq(H.turnDenied({ s1 = 0x40, s2 = 0x80, s3 = 0, s4 = 0x02 }), "Frozen",
      "Frozen is named before Petrify and Sleep (the kept-window shape first)")
    H.assertEq(H.windowKept("Stop"), true, "Stop keeps the window")
    H.assertEq(H.windowKept("Frozen"), true, "Frozen keeps the window")
    H.assertEq(H.windowKept("Sleep"), false, "Sleep does not (the engine cancels the menu)")
    H.assertEq(H.windowKept("Berserk"), false, "Berserk does not")
    H.assertEq(H.windowKept("Petrify"), false, "Petrify does not")
    H.assertEq(H.windowKept(nil), false, "no denial, no kept window")
    local bag = { [0xF4] = true, [0xF5] = true }
    H.assertEq(H.statusCure({ byte = 1, bit = 0x40, items = { 0xF4, 0xF5 },
      has = function(i) return bag[i] end }), 0xF4, "a statue with a Soft in the bag: the Soft")
    bag = { [0xF5] = true }
    H.assertEq(H.statusCure({ byte = 1, bit = 0x40, items = { 0xF4, 0xF5 },
      has = function(i) return bag[i] end }), 0xF5, "...with only Remedies: the Remedy (its record carries Petrify)")
    bag = { [0xF8] = true, [0xF5] = true }
    H.assertEq(H.statusCure({ byte = 2, bit = 0x01, has = function(i) return bag[i] end }), nil,
      "Condemned: nothing in the bag carries STATUS2 $01")
    H.log("battle_healpolicy: the kept-window shape (#224), Petrify and Frozen (#187) checked")
  end),

  -- 12e. the promoted generator reads (#190): Vanish/Image (H.dodges,
  -- gen_fc_alcove's gate -- STATUS1 $10 first, then STATUS2 $04) and the
  -- Condemned count and clock (H.doomCount / H.doomRule, gen_fc_escape's
  -- Nerapa log): $3B05 is the number shown plus one, one count is 128
  -- frames at normal speed, and a heal is thrown away on a member the
  -- Doom takes before their next turn.
  H.call(function()
    H.assertEq(H.dodges({ s1 = 0x10, s2 = 0 }), "Vanish", "STATUS1 bit 4 is Vanish")
    H.assertEq(H.dodges({ s1 = 0, s2 = 0x04 }), "Image", "STATUS2 bit 2 is Image")
    H.assertEq(H.dodges({ s1 = 0x10, s2 = 0x04 }), "Vanish", "both: Vanish is named")
    H.assertEq(H.dodges({ s1 = 0x20, s2 = 0x20 }), nil, "Imp and Muddle dodge nothing")
    H.assertEq(H.dodges({}), nil, "no bytes, no dodge")
    H.assertEq(H.doomCount({ s2 = 0x01, count = 0x1B }), 26, "$3B05 $1B under the bit shows 26")
    H.assertEq(H.doomCount({ s2 = 0x01, count = 0x01 }), 0, "...$01 shows 0 (the Doom's frame)")
    H.assertEq(H.doomCount({ s2 = 0x01, count = 0x00 }), nil,
      "the bit over a $00 byte: not counting yet (StartCondemn runs a beat after the status)")
    H.assertEq(H.doomCount({ s2 = 0x00, count = 0x1B }), nil, "no bit, no count")
    H.assertEq(H.COUNT_FRAMES, 128, "one count is 128 frames at normal speed")
    -- the Nerapa numbers: a member at 30 with a gauge 250 ticks (500
    -- frames) from full is 3,840 frames from the Doom -- not their last
    -- turn; at 3 (384 frames) it is
    H.assertEq(H.doomRule({ count = 30, turnFrames = 500 }), nil,
      "30 counts against a 500-frame turn: the member acts again first")
    H.assertEq(H.doomRule({ count = 3, turnFrames = 500 }), "last",
      "3 counts (384 frames) against a 500-frame turn: the last turn")
    H.assertEq(H.doomRule({ count = 4, turnFrames = 500 }), nil,
      "4 counts (512 frames) against a 500-frame turn: one more turn comes")
    H.assertEq(H.doomRule({ count = 4, turnFrames = nil }), "last",
      "a gauge that cannot fill: the last turn whatever the count")
    H.assertEq(H.doomRule({ count = 4, turnFrames = 500, framesPerCount = 256 }), nil,
      "...at Slow's 256 a count, 4 counts outlast the turn")
    H.assertEq(H.doomRule({ count = nil, turnFrames = 100 }), nil, "not condemned: nothing to say")
    H.log("battle_healpolicy: Vanish/Image and the Condemned clock (#190) checked")
  end),

  -- 13. the keyed line's boost (#174, H.keyBoost) on the map-269 trio
  -- (Trapper: 2 shields, BLUDG key) and Nerapa (5 shields, SLASH|PIERCE):
  -- chips per boost are the chip model's for each member's hands.
  H.call(function()
    -- LOCKE's Genji pair on a Trapper: ThunderBlade (bolt) chips, Guardian
    -- does not; swings alternate, so 0 BP = 1 chip, 1 BP = 2, 2 BP = 3
    local b, why = H.keyBoost({ need = 2, chipsAt = { [0] = 1, [1] = 2, [2] = 3, [3] = 4 }, bank = 3 })
    H.assertEq(b, 1, "LOCKE on a Trapper: one pip breaks this turn -- not the bank's three (" .. why .. ")")
    -- SABIN's Pummel: two bludgeoning hits whatever the boost
    b, why = H.keyBoost({ need = 2, chipsAt = { [0] = 2, [1] = 2, [2] = 2, [3] = 2 }, bank = 3 })
    H.assertEq(b, 0, "SABIN's Pummel on a Trapper breaks unboosted: the pip banks (" .. why .. ")")
    -- LOCKE on Nerapa: both hands chip, 2/4/6 chips at 0/1/2 BP
    b, why = H.keyBoost({ need = 5, chipsAt = { [0] = 2, [1] = 4, [2] = 6, [3] = 8 }, bank = 3 })
    H.assertEq(b, 2, "LOCKE on Nerapa: two pips reach five shields (" .. why .. ")")
    b, why = H.keyBoost({ need = 5, chipsAt = { [0] = 2, [1] = 4 }, bank = 1 })
    H.assertEq(b, 1, "...and with one pip in the bank, the one pip: the most the bank allows (" .. why .. ")")
    -- no key: CELES's MithrilBlade (slash) on a Trapper chips nothing
    b, why = H.keyBoost({ need = 2, chipsAt = { [0] = 0, [1] = 0, [2] = 0 }, bank = 2 })
    H.assertEq(b, nil, "no key held: the boost-Fight default keeps the turn (" .. why .. ")")
    b, why = H.keyBoost({ need = 0, chipsAt = { [0] = 2 }, bank = 2 })
    H.assertEq(b, nil, "a broken gauge is the unload's turn, not the key's (" .. why .. ")")
    H.log("battle_healpolicy: the keyed line's boost (#174) checked")
  end),

  -- 14. the target graph (#189, H.newTargetGraph) on the Air Force's
  -- measured cursor: gun $04 --left--> body $01, --right--> the party,
  -- up/down nothing; body $01 --down--> Missile Bay $10.  The rotation it
  -- replaced gave up three times from the gun; the graph lands in three
  -- presses and walks the known path on the next window.  And a focus
  -- entry names a part by species (H.focusSlots over $1CB's words).
  H.call(function()
    local truth = {
      ["mons=04"] = { left = "mons=01", right = "chars=01", up = "mons=04", down = "mons=04" },
      ["mons=01"] = { left = "mons=01", right = "mons=04", up = "mons=01", down = "mons=10" } }
    local G = H.newTargetGraph()
    local goal = function(n) return n:sub(1, 5) == "mons=" and (tonumber(n:sub(6), 16) & 0x10) ~= 0 end
    local mon = function(n) return n:sub(1, 5) == "mons=" end
    local order = { "left", "down", "up", "right" }   -- the crossing (right) last
    local cur, presses = "mons=04", {}
    for _ = 1, 8 do
      local d = G.route(cur, goal, mon, order)
      if d == nil then break end
      presses[#presses + 1] = d
      G.record(cur, d, truth[cur][d])
      cur = truth[cur][d]
      if goal(cur) then break end
    end
    H.assertEq(cur, "mons=10", "the graph reaches the Missile Bay from the gun")
    H.assertEq(table.concat(presses, ","), "left,left,left,down",
      "...by exploring the nearest node first (the body's LEFT no-op pressed twice to be believed)")
    local d, how, walk = H.newTargetGraph().route("mons=04", goal, mon, order)
    H.assertEq(how, "explore", "a fresh graph explores")
    d, how, walk = G.route("mons=04", goal, mon, order)
    H.assertEq(how .. " " .. walk, "path left,down", "the next window walks the known path")
    H.assertEq(G.record("mons=04", "left", "mons=01"), nil, "a confirmed edge is not news")
    H.assertEq(G.record("mons=04", "left", "mons=04"), "unconfirmed", "a no-op is not believed at once")
    H.assertEq(G.record("mons=04", "left", "mons=04"), "changed", "...but on its second sighting")
    -- H.focusStep: the old rotation's presses first (left leads) until the
    -- window cycles, a press the graph knows is wasted skipped, then the
    -- graph explores with the crossing (right) after every other
    -- direction, and a known path is walked
    local F, visited, hows, cycled = H.newTargetGraph(), {}, {}, false
    cur, presses = "mons=04", {}
    for _ = 1, 16 do
      visited[cur] = true
      local fd, fhow = H.focusStep(F, cur, goal, { "left", "right", "down", "up" }, {},
        visited, order, cycled, { right = true })
      if fd == nil then break end
      presses[#presses + 1] = fd; hows[#hows + 1] = fhow
      F.record(cur, fd, truth[cur][fd])
      local was = cur
      cur = truth[cur][fd]
      if cur ~= was and visited[cur] then cycled = true end
      if goal(cur) then break end
    end
    H.assertEq(cur, "mons=10", "focusStep reaches the Missile Bay from the gun")
    H.assertEq(table.concat(presses, ","), "left,left,left,right,down,down,up,up,left,down",
      "...left, left twice (moves nothing: believed on the second), right (back on "
      .. "the gun: cycled), then the gun's down and up (twice each), the walk to the body's down")
    H.assertEq(table.concat(hows, ","),
      "rotation,rotation,rotation,rotation,explore,explore,explore,explore,explore,explore",
      "...rotation first")
    local pd, phow = H.focusStep(F, "mons=04", goal, { "right" }, {}, {}, order)
    H.assertEq(pd .. " " .. phow, "left path", "a known path beats the rotation")
    local xd, xhow = H.focusStep(F, "mons=01", function() return false end,
      { "left", "down" }, {}, { ["mons=10"] = true }, order)
    H.assertEq(xhow, "explore", "a rotation the graph knows is wasted explores")
    H.assertEq(xd, "up", "...the body's untried direction")
    local words = { [0] = 0x113, [1] = 0xFFFF, [2] = 0x145, [3] = 0x146, [4] = 0x147, [5] = 0xFFFF }
    local fs = H.focusSlots({ { species = 0x147 }, { species = 0x146 }, { slot = 0, mask = 0x01 } }, words)
    H.assertEq(#fs, 3, "three focus entries resolve")
    H.assertEq(fs[1].slot .. "/" .. fs[1].mask, "4/16", "Missile Bay $147 is slot 4, mask $10")
    H.assertEq(fs[2].slot .. "/" .. fs[2].mask, "3/8", "Speck $146 is slot 3 before it enters")
    H.assertEq(fs[3].slot .. "/" .. fs[3].mask, "0/1", "the slot form still reads")
    H.log("battle_healpolicy: the target graph and species focus (#189) checked")
  end),

  -- 15. the kit's MP in a random battle (H.kitBudget into H.boostPlan) on
  -- the Phantom Train's numbers: SABIN 84/94 wanting a boost-3 Pummel in
  -- the first random, which unpriced by the budget cost 63 MP and left
  -- him 21 (then 3) for the Ghost Train's AuraBolt and Pummels.
  H.call(function()
    local PUMMEL = 0x5D
    H.assertEq(H.abilityCost(PUMMEL), 4, "Pummel's base price is 4 MP (Ot6AbilityCostTbl)")
    local res, ration, why = H.kitBudget({ random = true, maxPool = 94 })
    H.assertEq(res, 24, "a random keeps a quarter of 94, rounded up: 24 (" .. why .. ")")
    H.assertEq(ration, 4, "...and rations a turn's boost to a quarter of max")
    local eres, eration = H.kitBudget({ random = false, maxPool = 94 })
    H.assertEq(eres, 0, "an event battle keeps nothing back: the boss is what it was kept for")
    H.assertEq(eration, nil, "...and rations nothing")
    local function pummel(pool, random)
      local r, n = H.kitBudget({ random = random, maxPool = 94 })
      local b, ok, w, price = H.boostPlan({ id = PUMMEL, want = 3, pool = pool,
        maxPool = 94, reserve = r, ration = n })
      return b, ok, price, w
    end
    local b, ok, price, w = pummel(84, false)
    H.assertEq(b .. "/" .. price, "3/63", "the boss spends the bank's boost-3 Pummel, 63 MP (" .. w .. ")")
    b, ok, price, w = pummel(84, true)
    H.assertEq(b .. "/" .. price, "1/10",
      "a random at 84/94 buys the boost-1 Pummel, 10 MP: the ration's 23 over the reserve (" .. w .. ")")
    b, ok, price, w = pummel(30, true)
    H.assertEq(b .. "/" .. tostring(ok) .. "/" .. price, "0/true/4",
      "at 30/94 no boost fits over the reserve, but the unboosted Pummel does (" .. w .. ")")
    b, ok, price, w = pummel(27, true)
    H.assertEq(ok, false, "at 27/94 the Pummel would breach the 24 kept: SABIN Fights (" .. w .. ")")
    -- the ration alone (gen_narshe_battle's private fighter: EDGAR 57 MP,
    -- AutoCrossbow base 4, no reserve) prices as it did before the two met
    b = H.boostPlan({ id = H.AUTOCROSSBOW, want = 3, pool = 57, maxPool = 57, ration = 4 })
    H.assertEq(b, 1, "the descent's ration alone: 14 of 57 buys the boost-1 crossbow")
    -- spent down from 94 by the random rule, turn after turn at the bank's
    -- boost 3: what is left is the reserve's 24 or the few MP just above it
    local pool, spent = 94, 0
    for _ = 1, 20 do
      local bb, okk, pp = pummel(pool, true)
      if not okk then break end
      pool, spent = pool - pp, spent + 1
    end
    H.assertEq(pool >= 24, true, string.format(
      "a run of randoms leaves SABIN %d/94 after %d Pummels, never under the 24 kept", pool, spent))
    -- The wiring: H.kitBoost is the driver's own decision (every Blitz and
    -- Tools line calls it), reading the random flag OT6_RANDBTL ($57BD) and
    -- the caster's MP ($3C08) and max MP ($3C30) from the battle.  The
    -- battle here is a table of those bytes; every other byte reads 0, so
    -- the neighbouring $57BC (RANDPEND) reads clear.
    local function battle(random, mp, maxMp)
      local bytes = { [0x57BD] = random and 1 or 0 }
      local words = { [0x3C08] = mp, [0x3C30] = maxMp }
      return { byte = function(a) return bytes[a] or 0 end,
               word = function(a) return words[a] or 0 end }
    end
    local kb, kprice, kwhy = H.kitBoost(0, PUMMEL, 3, battle(true, 84, 94))
    H.assertEq(tostring(kb) .. "/" .. tostring(kprice), "1/10",
      "the driver's Pummel at 84/94 in a random: boost 3 steps down to 1 (" .. tostring(kwhy) .. ")")
    kb, kprice, kwhy = H.kitBoost(0, PUMMEL, 3, battle(false, 84, 94))
    H.assertEq(tostring(kb) .. "/" .. tostring(kprice), "3/63",
      "...and in an event battle the bank's boost 3, 63 MP (" .. tostring(kwhy) .. ")")
    -- the ration under the base price: EDGAR's Drill (base 16) at 30 of 57
    -- in a random -- the turn may spend min(30 - 15, 14) = 14, under 16,
    -- and the unboosted Drill would breach the 15 kept, so he Fights
    local DRILL = 0xA8
    H.assertEq(H.abilityCost(DRILL), 16, "the Drill's base price is 16 MP (Ot6AbilityCostTbl)")
    kb, kprice, kwhy = H.kitBoost(0, DRILL, 2, battle(true, 30, 57))
    H.assertEq(kb, nil, "the Drill at 30/57 in a random: nothing fits over the 15 kept, "
      .. "the line is not offered and EDGAR Fights (" .. tostring(kwhy) .. ")")
    kb, kprice = H.kitBoost(0, DRILL, 2, battle(false, 30, 57))
    H.assertEq(tostring(kb) .. "/" .. tostring(kprice), "0/16",
      "...the same pool in an event battle pays the unboosted Drill")
    H.log("battle_healpolicy: the kit's random-battle MP budget checked")
  end),

  -- 16. the hit ledger, the heal watch and the queued cure-hit as
  -- arithmetic (reviews of f8f9ad66 and bcf5240f: M4a-c and item 4-5 had
  -- only lab evidence).  Each rule is a plain function the driver calls.
  H.call(function()
    -- M4a: a status landing is no hit.  tomb_zombie's Zombie touch read the
    -- whole bar as the drop ("s0 1x1589 (worst)"): ZOMBIE newly set.
    H.assertEq(H.statusDrop(0x00, 0x02, 0x00, 0xEF), true,
      "a Fight that leaves its victim newly ZOMBIE is a status landing")
    H.assertEq(H.statusDrop(0x02, 0x02, 0x00, 0xEF), false,
      "a hit on a member already ZOMBIE is no status landing")
    H.assertEq(H.statusDrop(0x00, 0x40, 0x02, 0x00), true, "PETRIFY newly set is a status landing")
    H.assertEq(H.statusDrop(0x00, 0x80, 0x00, 0xEE, 0x01, 0x00), true,
      "a Condemned count running out (Condemned cleared, Wound set) is the Doom, a status landing")
    H.assertEq(H.statusDrop(0x00, 0x80, 0x00, 0xEE, 0x00, 0x00), false,
      "a killing blow on a member not Condemned is a hit (censored by the ledger, not dropped)")
    local mp = H.sym("MagicProp") & 0x3FFFFF
    local nopower = nil
    for id = 0, 0x35 do
      if nopower == nil and H.readRomByte(mp + id * 14 + 6) == 0 then nopower = id end
    end
    H.assertEq(nopower ~= nil, true, "precondition: a spell with no power in the black/white/grey list")
    H.assertEq(H.statusDrop(0x00, 0x00, 0x02, nopower), true,
      string.format("a cast of spell $%02X (power 0) is a status landing", nopower))
    H.assertEq(H.readRomByte(mp + 0x07 * 14 + 6) > 0, true, "precondition: Bolt 2 ($07) has power")
    H.assertEq(H.statusDrop(0x00, 0x00, 0x02, 0x07), false, "Bolt 2's drop is a hit")
    local L = H.ledgerCommit(nil, { cmd = 0x00, party = 0x02 },
      { { e = 1, drop = 1548, last = 1548, hp = 0, status = true } })
    H.assertEq(tostring(L.max) .. "/" .. tostring(L.min) .. "/" .. tostring(L.lb), "nil/nil/nil",
      "a Zombie touch (1548 -> 0) puts no hit, no smallest hit and no floor in the ledger")
    H.assertEq(L.actN .. "/" .. L.actSum, "1/0", "...and counts as one action of size 0 in the typical mean")
    -- M4b: a killing blow is a censored floor, never the smallest hit
    -- (vector_entry: "slot 2's smallest hit this fight so far: 75, on
    -- entity 2 (75 -> 0)" under a 544 Bolt 2)
    L = H.ledgerCommit(nil, { cmd = 0x02, party = 0x04 }, { { e = 2, drop = 544, last = 619, hp = 75 } })
    H.assertEq(L.min, 544, "a 619 -> 75 Bolt 2 is the smallest hit")
    L = H.ledgerCommit(L, { cmd = 0x02, party = 0x04 }, { { e = 2, drop = 75, last = 75, hp = 0 } })
    H.assertEq(tostring(L.min) .. "/" .. tostring(L.on[2]) .. "/" .. tostring(L.lb) .. "/" .. tostring(L.lbOn and L.lbOn[2]), "544/544/75/75",
      "the killing blow 75 -> 0 stays a floor (lb 75); the smallest hit stays 544")
    -- item 4: counters and buffs stay out of the typical mean; the mean waits
    local n0 = L.actN
    L = H.ledgerCommit(L, { cmd = 0x00, counter = true, party = 0x01 }, {})
    H.assertEq(L.actN, n0, "a counterattack that lands nothing is no action of the typical mean (never a zero)")
    L = H.ledgerCommit(L, { cmd = 0x00, counter = true, party = 0x01 }, { { e = 0, drop = 90, last = 500, hp = 410 } })
    H.assertEq(tostring(L.actN) .. "/" .. tostring(L.maxOn and L.maxOn[0]), (n0 + 1) .. "/90",
      "a counterattack that lands counts at its hit (Dullahan's Battle is his counter, $B1 bit 0)")
    n0 = L.actN
    L = H.ledgerCommit(L, { cmd = 0x02, party = 0x00, mon = 0x01 }, {})
    H.assertEq(L.actN, n0, "a buff on its own side (monster targets only, nothing dropped) is no action of the mean")
    L = H.ledgerCommit(L, { cmd = 0x12, party = 0x00, mon = 0x00 }, {})
    H.assertEq(L.actN .. "/" .. L.actSum, (n0 + 1) .. "/" .. L.actSum,
      "a do-nothing turn aimed at nobody is a turn that took nothing: a zero in the mean")
    n0 = L.actN
    L = H.ledgerCommit(L, { cmd = 0x2E, party = 0x01 }, {})
    H.assertEq(L.actN, n0, "the script's $2E is no action of the mean")
    local T = H.ledgerCommit(nil, { cmd = 0x00, party = 0x01 }, { { e = 0, drop = 100, last = 500, hp = 400 } })
    T = H.ledgerCommit(T, { cmd = 0x00, party = 0x01 }, {})
    H.assertEq(H.typicalOf(T), nil, string.format("two actions are under M.TYPICAL_MIN (%d): no typical yet",
      H.TYPICAL_MIN))
    T = H.ledgerCommit(T, { cmd = 0x00, party = 0x01 }, { { e = 1, drop = 200, last = 600, hp = 400 } })
    H.assertEq(H.typicalOf(T), 100, "three actions (100, a miss, 200): the typical action is 100")
    -- M4c and item 4: the heal watch.  vector_entry's cure on entity 2 at
    -- 75/619 (by entity 2), the member killed before it landed, then a
    -- Fenix Down by entity 1 raising it to 77.
    local w = { hp = 75, maxhp = 619, by = 2, until_ = 1000 }
    H.assertEq(H.healWatchStep(w, 0, 10), "fell",
      "the cure's target falls: the watch ends, and no later raise can be read as the cure")
    H.assertEq(H.healWatchStep(w, 325, 10), "measured",
      "a rise is the heal, whoever's command the frame shows (tomb_r7 k10_s0: entity 3's Potion landed "
      .. "during entity 2's command)")
    H.assertEq(H.healWatchStep(w, 619, 10), "full", "a rise to max HP is capped, not measured")
    H.assertEq(H.healWatchStep(w, 60, 10), "lower", "a drop moves the baseline")
    H.assertEq(H.healWatchStep(w, 75, 1001), "expired", "no rise inside the watch's ticks: it lapses")
    -- a cure's watch carries its ROM band; a Potion's 250 above the cast's
    -- most is not the cure (vector_entry at 15a54c03: "cure $2D restored 250
    -- hp on entity 3 ... [the ROM's least: 202]")
    local cw = { hp = 300, maxhp = 619, by = 2, until_ = 1000, lo = 202, hi = 230 }
    H.assertEq(H.healWatchStep(cw, 550, 10), "outside", "a +250 rise outside the cure's 202..230 is another heal")
    H.assertEq(H.healWatchStep(cw, 520, 10), "measured", "a +220 rise inside 202..230 is the cure")
    -- an item's band is its power byte exactly: the r10 labs read "item $E9
    -- restored 490" (two Potions summed) and "restored 236"
    local pw = H.itemPower(0xE9)
    local iw = { hp = 300, maxhp = 1600, by = 3, until_ = 1000, lo = pw, hi = pw }
    H.assertEq(H.healWatchStep(iw, 300 + pw, 10), "measured", string.format("a Potion's +%d is the Potion", pw))
    H.assertEq(H.healWatchStep(iw, 790, 10), "outside", "a +490 rise is not one Potion")
    H.assertEq(H.healWatchStep(iw, 536, 10), "outside", "a +236 rise is not one Potion")
    -- item 5 of f8f9ad66: a queued cure-hit that will not run is stale
    local q = { tick = 100 }
    H.assertEq(H.queuedHitStale(q, { hp = 0, tick = 110 }), "it fell", "a hitter who fell")
    H.assertEq(H.queuedHitStale(q, { hp = 500, denied = "SLEEP", tick = 110 }), "it is under SLEEP", "a hitter asleep")
    H.assertEq(H.queuedHitStale(q, { hp = 500, muddled = true, tick = 110 }), "it is Muddled", "a hitter muddled")
    H.assertEq(H.queuedHitStale(q, { hp = 500, ownWindow = true, tick = 110 }), "its own window is open again",
      "a hitter whose window is open again (its command ran or was dropped)")
    H.assertEq(H.queuedHitStale(q, { hp = 500, tick = 100 + 240 + 601 }), "it never ran", "RAISE_WAIT + 600 ticks on")
    H.assertEq(H.queuedHitStale(q, { hp = 500, tick = 110 }), nil, "...and otherwise it is in flight")
    -- review of bcf5240f, item 5: an unmeasured cure priced from the ROM's
    -- formula, at variance's low end: power 10, magic power 40, level 20
    -- -> 40 + 40 x 10 x 20 / 32 = 290, x 224/256 + 1 = 254
    -- the top-up a raise was planned on goes through whatever the round
    -- costs (#168; Dullahan arm B k0_s0_w9, review of ad048b29)
    H.assertEq(H.healDecision({ hp = 213, maxhp = 1710, restore = 250, roundCost = 1083, allies = 3, owed = true }),
      "the raise's top-up (#168)", "a raised member at 213/1710 owed its top-up gets it under a 1083 round")
    H.assertEq(H.healDecision({ hp = 213, maxhp = 1710, restore = 250, roundCost = 1083, allies = 3 }), nil,
      "...and without the raise behind it the lift rule refuses the same Potion")
    local lo, hi = H.cureRestoreMin({ power = 10, heal = true, flags2 = 0x20, level = 20, magpow = 40 })
    H.assertEq(lo .. ".." .. hi, "254..289", "a cure that ignores defense: 254 at least, 289 at most (290 x 255/256 + 1)")
    H.assertEq(H.cureRestoreMin({ power = 10, heal = true, flags2 = 0x00, level = 20, magpow = 40, mdef = 51 }),
      ((254 * 204) >> 8) + 1, "...through 51 magic defense when it does not")
    H.assertEq(H.cureRestoreMin({ power = 10, heal = false, level = 20, magpow = 40 }), nil, "no heal flag: no price")
    H.log("battle_healpolicy: the hit ledger, the heal watch, the queued cure-hit and the cure price checked")
  end),

  -- 17. which item a care turn spends (#370).  The prices are the ROM's:
  -- ItemProp +$1C for what a shop sells (ShopProp), and for what none sells
  -- (the price word reads 2) the effect at the shops' least gil per HP
  -- (Tonic 50 for 50) and per MP (Tincture 1500 for 50).
  H.call(function()
    local XPOT, ELIXIR, MEGALIXIR, MAGICITE = 0xEA, 0xEE, 0xEF, 0xF9
    H.assertEq(H.itemSold(POTION), true, "a shop sells the Potion")
    H.assertEq(H.itemSold(XPOT), false, "no shop sells the X-Potion")
    H.assertEq(H.itemSold(ELIXIR), false, "...nor the Elixir")
    H.assertEq(H.itemGil(POTION), 300, "the Potion costs its price word, 300")
    local r = H.shopRates()
    H.assertEq(r.hp, 1, "the shops' least gil per HP: the Tonic's 50 for 50")
    H.assertEq(r.mp, 30, "...and per MP: the Tincture's 1500 for 50")
    -- the scarcity of what no shop sells (review of a8df0a6f): 1 + legs to
    -- the next source / the count held, the horizon 10 legs with none known
    local function f4(x) return string.format("%.4f", x) end
    H.assertEq(f4(H.scarcity(7)), f4(1 + 10 / 7), "seven held, no source known: 1 + 10/7")
    H.assertEq(f4(H.scarcity(1)), f4(11), "the last one counts for more: 1 + 10/1")
    H.assertEq(f4(H.scarcity(7, 1)), f4(1 + 1 / 7), "a source on the next leg leaves little premium")
    local sabin = { hp = 905, maxhp = 1812, mp = 274, maxmp = 318 }
    H.assertEq(H.itemGil(XPOT, sabin, nil, 7), math.floor(1812 * (1 + 10 / 7) + 0.5),
      "an X-Potion on SABIN, seven in the bag: 1812 HP at 1 gil, times the scarcity")
    H.assertEq(H.itemGil(XPOT, sabin, nil, 1) > H.itemGil(XPOT, sabin, nil, 7), true,
      "...and the last one is dearer than one of seven")
    H.assertEq(H.itemGil(ELIXIR, sabin, nil, 7), math.floor((1812 + 318 * 30) * (1 + 10 / 7) + 0.5),
      "an Elixir on him: 1812 HP + 318 MP x 30, times the scarcity")
    local party = { sabin, { hp = 1798, maxhp = 1798, mp = 330, maxmp = 330 } }
    H.assertEq(H.itemGil(MEGALIXIR, sabin, party, 1),
      math.floor(((1812 + 318 * 30) + (1798 + 330 * 30)) * 11 + 0.5),
      "a Megalixir: the Elixir's worth on every member it reaches, the only one held")
    H.assertEq(H.itemGil(MAGICITE) >= 1000000000, true,
      "an unsold item with no HP or MP to price it by is priceless, never 0 (Magicite $F9)")
    H.assertEq(H.deathGil(1812), 500 + (1812 - 226), "SABIN's death: the Fenix Down's 500 and 1586 HP to buy back")
    local function bag(list)
      local t = {}
      for _, it in ipairs(list) do
        local id, restore = it[1], it[2]
        t[#t + 1] = { id = id, restore = restore, flat = (H.itemProps(id) & H.ITEM_RATIO) == 0,
                      unsold = not H.itemSold(id), gil = H.itemGil(id, sabin, party, 7) }
      end
      return t
    end
    local function choose(hp, cost, list, raw)
      local it, why, refused = H.itemChoice({ hp = hp, maxhp = 1812, roundCost = cost, allies = 3, threshold = 60,
        cap = H.deathGil(1812), items = raw or bag(list) })
      return it and string.format("$%02X %s", it.id, why) or "nothing", refused
    end
    -- wor_falcon r15: "actor=1 not healing entity 1 (905/1812): $E9 restores
    -- 250 and a round costs 846", 7 X-Potions in the bag, then "[death] f+4481
    -- entity 1 char 5 from 591/1812".  At 905 under 846 he is outside the
    -- round: an X-Potion there is a top-up, and no shop sells it
    local got, refused = choose(905, 846, { { POTION, 250 }, { XPOT, 907 }, { ELIXIR, 907 } })
    H.assertEq(got, "nothing", "SABIN at 905/1812 under an 846 round: no X-Potion on a top-up (none is sold)")
    H.assertEq(refused[2] and refused[2].why, "no shop sells it: kept for a member inside the round",
      "...the X-Potion is refused as irreplaceable, not as too weak")
    H.assertEq(choose(591, 846, { { POTION, 250 }, { XPOT, 1221 }, { ELIXIR, 1221 } }), "$EA top-up",
      "inside the round (591 under 846) the X-Potion that lifts him is spent")
    H.assertEq(choose(591, 846, { { POTION, 250 }, { ELIXIR, 1221 } }), "$EE top-up",
      "...and the Elixir when no X-Potion is held")
    H.assertEq(choose(600, 200, { { POTION, 250 }, { XPOT, 1212 } }), "$E9 top-up",
      "a Potion that does the job is the cheaper turn")
    H.assertEq(choose(1700, 846, { { POTION, 250 }, { XPOT, 112 }, { ELIXIR, 112 } }), "nothing",
      "chip damage (1700/1812, outside the round): nothing is spent")
    H.assertEq(choose(905, 846, nil, { { id = POTION, restore = 1000, flat = true, gil = 3000 } }), "nothing",
      "a sold heal dearer than the death (3000 against 2086) is no top-up either")
    H.assertEq(choose(100, 120, { { TONIC, 50 }, { POTION, 250 } }), "$E9 top-up",
      "a Tonic is not offered while a Potion is held (a turn buys a real heal)")
    H.assertEq(choose(100, 120, { { TONIC, 50 } }), "$E8 covering an ally",
      "...and is the last item standing")
    local it = H.itemChoice({ hp = 226, maxhp = 1812, roundCost = 1083, allies = 3, threshold = 60, owed = true,
      items = bag({ { POTION, 250 }, { XPOT, 1586 } }) })
    H.assertEq(it and it.id, XPOT, "a raise's owed top-up inside a 1083 round: the X-Potion that lifts, not the Potion")
    it = H.itemChoice({ hp = 900, maxhp = 1812, roundCost = 500, allies = 3, threshold = 60, owed = true,
      items = bag({ { POTION, 250 }, { XPOT, 912 } }) })
    H.assertEq(it and it.id, POTION, "...and outside the round the Potion: the X-Potion stays in the bag")
    -- the Megalixir: every member inside the round lifted, or no party turn
    H.assertEq(H.itemAllAllies(MEGALIXIR), true, "the Megalixir's targeting has no moveable cursor: the whole party")
    H.assertEq(H.itemAllAllies(XPOT), false, "...the X-Potion's does")
    H.assertEq(H.partyLift(MEGALIXIR, { { hp = 300, maxhp = 1812, cost = 846 }, { hp = 200, maxhp = 1798, cost = 900 } }),
      true, "two members inside their rounds, both lifted by a Megalixir")
    H.assertEq(H.partyLift(MEGALIXIR, { { hp = 300, maxhp = 1812, cost = 846 }, { hp = 200, maxhp = 800, cost = 900 } }),
      false, "...not when one's round is above its max HP")
    -- the status cures in gil order, off the ROM's records
    H.assertEq(table.concat(H.cureItems(1, 0x20), ","), string.format("%d,%d", 0xF8, 0xF5),
      "Imp: Green Cherry (150) before Remedy (1000)")
    H.assertEq(table.concat(H.cureItems(1, 0x40), ","), string.format("%d,%d", 0xF4, 0xF5),
      "Petrify: Soft (200) before Remedy")
    H.assertEq(table.concat(H.cureItems(1, 0x02), ","), string.format("%d", 0xF1), "Zombie: Revivify alone")
    -- a confirmed heal is in flight until its target's HP rises: wor_falcon
    -- at the head gave EDGAR at 86/1701 a second X-Potion planned on the
    -- HP the first was about to fill
    local q = { hp = 86, tick = 100 }
    H.assertEq(H.healInFlight(q, 86, 110), nil, "a heal confirmed at 86 HP is in flight while the HP stands")
    H.assertEq(H.healInFlight(q, 90, 130), "landed", "...and has landed when the HP rises")
    -- arm B k0_s0_w25: CELES's X-Potion confirmed on SABIN at 1208, a Pearl
    -- took him to 143 first, and the guard held every other heal
    H.assertEq(H.healInFlight({ hp = 1208, tick = 5588 }, 143, 5700), "hit",
      "a hit before the heal lands releases the others to plan on what they see")
    H.assertEq(H.healInFlight({ hp = 86, tick = 100 }, 0, 110), "fell", "a target that falls ends it")
    H.assertEq(H.healInFlight({ hp = 86, tick = 100 }, 86, 100 + 240 + 601), "lapsed",
      "no rise inside RAISE_WAIT + 600 ticks: it lapses")
    -- the round's care turn: a confirmed plan keeps it (review of a8df0a6f:
    -- dropPlan("confirm_attempt") refunded it from 11a8f6e3 on)
    H.assertEq(H.careRefund("confirm_attempt"), false, "a confirmed care turn is not refunded")
    H.assertEq(H.careRefund("back_out"), true, "...a plan backed out of before its confirm is")
    H.log("battle_healpolicy: the bag's prices and the item a care turn spends (#370) checked")
  end),

  -- 8. the table was not skipped
  H.call(function()
    H.assertEq(ran, #CASES, string.format(
      "all %d policy cases ran (a skipped table is the same green as a "
      .. "passed one)", #CASES))
    H.log(string.format("battle_healpolicy: %d cases", ran))
  end),
  H.logStep(function() return "battle_healpolicy complete" end),
})
