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
--      measured cursor, and a focus entry naming a part by species.
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
    -- preceded by the shifts that scale the pending BP.
    local fb = romBytes(FB, 32)
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
    H.log("battle_healpolicy: refined raise gate, ATB read and Muddle rule checked")
  end),

  -- 9. the wipe verdict (#166) on the bytes the old scan misread.  rows are
  -- the four battle seats { actor = $3ed8+2e, present = $3aa0+2e bit 0,
  -- hp = $3bf4+2e, maxhp = $3c1c+2e }; flags is $3ebc.  The rows are
  -- probe_wipe166's measured ones (2026-09-07).
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
  -- and alive; the fight driver's stageSlots reads it from the live
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
    H.assertEq(s, nil, "Ifrit alone on stage: Ice flows (his weakness)")
    s, why = H.castVeto(ice, refl, { mon(1, SHIVA) })
    H.assertEq(s and s.slot, 1, "Shiva on stage in slot 1: Ice is refused")
    H.assertEq(why, "absorb", "...because she ABSORBS it")
    s, why = H.castVeto(ice, refl, { mon(0, IFRIT), mon(1, SHIVA) })
    H.assertEq(why, "absorb", "both on stage: the absorber wins the veto")
    s, why = H.castVeto(ice, refl, {})
    H.assertEq(s, nil, "nobody on stage (the fly-in): nothing to refuse")
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

  -- 8. the table was not skipped
  H.call(function()
    H.assertEq(ran, #CASES, string.format(
      "all %d policy cases ran (a skipped table is the same green as a "
      .. "passed one)", #CASES))
    H.log(string.format("battle_healpolicy: %d cases", ran))
  end),
  H.logStep(function() return "battle_healpolicy complete" end),
})
