# Esper rework: spells while worn, bonuses for keeps

Scope: what an equipped esper gives, and what a character keeps from
having worn it. Tracks #328. The owner approved plan A on 2026-11-12 with
these calls: progress per character, the bench earns no Magic Points,
random battles pay double, kept bonuses take no slots, and half-cost spells
and permanent Haste are labbed before they ship.

**Built (v0.44):** plan A, in `ot6_esper.asm`: the Magic Points hook
(`Ot6EsperEarn`, `Ot6EsperMsg`), the progress store in expanded SRAM
([save-layout.md](save-layout.md)), the ladder folded into `UpdateEquip`
(`Ot6EsperFold`, `Ot6LadderTbl`, held to the table below by
`tools/esper_ladder.py`), the four new-code signatures (`Ot6EsperBattleInit`
for Facet and Rebirth, `Ot6EsperImmune` for Fenrir, `Ot6Conductor`), and the
Skills > Espers page's ladder column. Two departures from the table: rung 4
of Crusader is all four stats +1, like its rungs 1 and 2; and Sraphim's
signature is the Cure Ring's Regen, because *Grace* would do nothing (no code
clears a fallen character's boost bank, so it already survives a KO). The
rest of this doc is the design as proposed.

**Terms.** *Magic Points* are what a won battle awards toward the
equipped espers (FF3 US calls them Magic Points; other releases call them
AP, and so did the owner's proposal). They are not *MP*, the spell-casting
pool. This doc says "Magic Points" for the first and "MP" for the second
throughout.

## The proposal (owner, 2026-11-12)

> having just played final fantasy resonance and enjoyed its visions
> mechanic. let's try to make our espers work a bit like that by granting a
> few spell families and/or abilities only when equipped (as if they were
> the abilities of the esper) and then a list of permanent bonuses that must
> be earned with escalating AP. the idea is that a player should feel some
> tension between A) wanting to keep good and complementary espers equipped
> for their abilities; B) wanting to equip espers in non-complementary ways
> for diversity of abilities; C) wanting to fully master few espers for
> their top-end permanent bonuses; D) doing a sort of grand tour through the
> espers to pick up more low-end permanent bonuses. the permanent bonuses
> can be stat bumps, effects that normally come on equipment or relics,
> maybe other similar effects.

## Where OT6 stands today

- An equipped stone grants one to three base spells while worn, never
  taught (`GenjuProp`, checked by `tools/check_spell_grants.py`;
  [magicite.md](magicite.md)). Boost folds the tiers.
- It also adds a signed while-worn stat package, ±7 a stat
  (`Ot6EsperStatTbl`, applied by `Ot6EsperStatMod` in
  `UpdateEquipBattle`; `ot6_progression.asm`).
- The summon is vanilla's, once a battle.
- Vanilla's learn rates are all zero and every level-up bonus byte is
  `$FF`, so `LearnGenjuMagic` and `DoLevelUp`'s bonus call do nothing
  (`battle_main.asm`: `lda f:GenjuProp+10,x ; esper level up bonus` /
  `bmi @60f4 ; branch if no bonus`).
- Magic Points are still paid, and go nowhere. The victory code reads them
  straight from the formation (`lda f:BattleMagicPoints,x ; $fb = number
  of magic points gained from battle`; formations at `$200` and above pay
  none) and feeds only the morph gauge, which nothing reads since #427.
  OT6's random-battle reward multiplier (`Ot6RewardMulW`, 2x) applies to
  XP and gil, not to Magic Points, so with half the encounter rate
  (`Ot6DangerMulW`) a step earns half vanilla's Magic Points.
- DESIGN.md and magicite.md already plan one form of permanence, "passives
  learned by carrying the esper long enough" (a battle count, party-wide),
  and none of it is built: magicite-tube-six.md §12 lists "no passive
  channel" against five of its six stones.

The proposal fits this: the while-worn half exists, and the permanent half
was planned and never built. Plan A below builds it with Magic Points.

## Research

### Final Fantasy Resonance's Visions

Final Fantasy Resonance (Square Enix, HD-2D, released 22 October 2026)
builds characters out of *Visions*: crystals holding the spirit of a past
Final Fantasy hero, one equipped per character.

- **While equipped**, a Vision raises the wearer's stats and gives its
  skills and spells at once: "Equip a Vision to boost a party member's
  stats and learn its skills" (MeowDB); "You may use the magic and
  abilities of visions who fight alongside you" (Square Enix's details,
  via Gematsu). Visions and characters carry roles (Breaker, Medic,
  Commando) and "it's best to match the two together", but "there's no
  restriction on who can equip which Visions" (Pocket Tactics).
- **Kept for good**: "keep them equipped on one character long enough, and
  that party member will gain both permanent stat increases [and] passive
  perks" (Push Square). Learned skills stay after a swap, "but those skills
  must fit within your ability point limit" (MeowDB): an equip budget, and
  Nintendo Everything's reviewer mentions needing "enough slots and enough
  AP to equip them". So two tiers exist: what the Vision does while worn,
  and what the character keeps.
- **Progress** is Mastery Points, earned by the equipped Vision in each
  battle, per character and Vision ("each character earns a separate
  Mastery Rank with each Vision"). The cumulative ladder MeowDB transcribes
  is 10 / 35 / 95 / 195 / 395 / 695 / 1,195 / 2,195 / 4,195 for ranks 1–9:
  each step roughly doubles, and "the last rank alone costs 2,000, nearly
  as much as the first eight together". The top rank grants "a passive or
  ability, +8 AP, and the Vision's 'Spirit of' skill". Breaking an enemy
  (stagger) on the killing blow pays more.
- **A second, scarce axis**: Awakening spends magicite found in chests or
  won from optional bosses, in three stages; "magicite is limited — which
  visions to awaken is a choice you must make" (Gematsu).
- **Reception.** Reviewers single the system out: "It's just a great
  progression system... opens up so much potential for customisation"
  (Push Square); Pocket Tactics calls Visions the standout and advises
  cycling the lineup "every so often to spread the love". Criticisms: the
  Visions feel "slightly shoehorned" and come from Brave Exvius's gacha
  (Push Square); "the game's generosity can work against its difficulty"
  and grinding makes story fights "a breeze" on Normal (Nintendo
  Everything); VGC (3/5) finds the mobile origins limiting.

What could not be verified: the exact skill costs against the ability
point budget, whether permanent stat gains have a cap, and how many Visions
the full game hands out. MeowDB is a fan database, and part of its page
describes the demo. The two tiers, per-character mastery, an escalating
ladder with a heavy last step, and the reviewers' praise and complaints are
each confirmed by more than one source.

### The systems it descends from

- **FF6 itself.** An esper teaches each listed spell at a rate:
  each battle adds rate × Magic Points to the spell's percent, and 100
  learns it (`IncLearnMagic`). A level-up while wearing one adds its bonus
  (+1 or +2 to a stat, or a percent of HP or MP). Learning is permanent and
  everyone can eventually learn everything, which is what OT6's "nobody
  learns everything" pillar removed. Fan guides give the rates as
  multipliers (Siren: Sleep x10, Fire x6) and the bonuses (Ramuh Stamina
  +1, ZoneSeek Magic +2) (ArrPeeGeeZ, Thonky).
- **FF9.** Equipment grants abilities while worn and earns AP toward
  learning each one; once learned, a support ability is slotted with Magic
  Stones, a per-character budget (Caves of Narshe, Jegged). The AP cost
  varies by character (Auto-Life 70 from the Rebirth Ring on one list,
  130 for Zidane). This is the proposal's closest relative: use it now,
  keep it later, and pay a slot budget to run what you keep.
- **FF Tactics.** Job Points earned by acting buy that job's abilities for
  good; a unit then runs one secondary skill set and one each of reaction,
  support and movement from anything learned (Hack the Minotaur). Mastering
  a job opens others; the tension is breadth versus depth inside one
  character's slots.
- **FFX-2.** Dresspheres teach abilities through AP, and the learned
  commands are usable only while wearing that dressphere (StrategyWiki).
  Nothing travels: the clean "while worn" extreme.

The common thread: the interesting choice comes from two currencies of
time. What you wear decides what you can do now; what you wore decides what
you have kept. The systems that keep everything forever (vanilla FF6, FFT)
end with every character the same; the ones that keep nothing (FFX-2) have
no grand tour.

## The route's Magic Points

Evidence: `build/attempts/wt/esper-rework-plan/` (`route_ap.py`,
`logs_ap.py`, `route_ap.txt`, `late_ap_8bfc3e1a.txt`, `milestones.txt`).
Each won battle on a main-line leg's last attempt pays
`BattleMagicPoints[formation]` (`ff6/src/battle/battle_magic_points.dat`)
to every living seated member wearing an esper, so the running sum is what
one stone worn the whole way would earn. Power-on to the Ancient Castle is
read from this tree's `build/states` logs (the line as of 2026-10-28);
the dinosaur forest to Kefka from move 2's landed replay at 8bfc3e1a
(`build/attempts/wt/v042-leveling-move2/land/land-dino-to-kefka-logs.tgz`).
Two caveats: Kefka's Tower is three parties, so its 624 is shared among
them rather than earned by any one seat; and the line is the middle path,
so a player who grinds or takes side trips earns more.

| arrival on the line | espers | Magic Points so far | if random battles paid double |
|---|---|---|---|
| Zozo (`zozo_done`) | Ramuh, Siren, Stray, Kirin | 179 | 336 |
| Magitek factory | Ifrit, Shiva | 224 | 408 |
| the tube room | Shoat, Maduin, Bismark, Carbunkl, Phantom, Unicorn | 241 | 438 |
| end of the World of Balance (`fc_alcove`) | — | 384 | 678 |
| Tzen, World of Ruin (`wor_sabin`) | Sraphim | 440 | 771 |
| Mobliz (`wor_terra`) | Palidor, Fenrir | 523 | 925 |
| Narshe (`wor_tritoch`) | Terrato, Tritoch | 711 | 1,274 |
| Jidoor (`wor_owzer`, `wor_relm`) | ZoneSeek, Starlet | 781 | 1,400 |
| Phoenix Cave, Narshe (`wor_locke`, `wor_ragnarok`) | Phoenix, Ragnarok | 983 | 1,774 |
| Opera house (`wor_opera`) | Bahamut | 1,040 | 1,870 |
| Doma (`wor_doma`) | Alexandr | 1,073 | 1,923 |
| Ancient Castle (`wor_ancient`) | Raiden (Odin traded) | 1,122 | 2,011 |
| Kefka's Tower and Kefka | — | +624 (three parties) | +1,175 (three parties) |

The raw lines behind the rows (`route_ap.txt`, columns: leg | battles won
random/event/other | Magic Points | cumulative | levels | new espers):

```
zozo_done | 0/0/0 | 0 | 179 | LOCKE18 CYAN_14 EDGAR19 SABIN19 CELES18 GAU_15 | Ramuh,Siren,Stray,Kirin | rnd_ap=0
esper_tubes | 0/0/0 | 0 | 241 | LOCKE21 CYAN_14 EDGAR21 SABIN21 GAU_15 | Shoat,Maduin,Bismark,Carbunkl,Phantom,Unicorn | rnd_ap=0
fc_alcove | 7/0/0 | 28 | 384 | TERRA25 LOCKE27 ... | | rnd_ap=28
wor_terra | 0/3/0 | 0 | 523 | TERRA32 EDGAR32 SABIN33 CELES33 SETZER_31 | Palidor,Fenrir | rnd_ap=0
wor_ancient | 9/1/0 | 49 | 1122 | TERRA52 ... | Raiden | rnd_ap=39
```

and the late stretch (`late_ap_8bfc3e1a.txt`):

```
wor_kt_goddess.log | 1/1/0 | 13 | 624 | random 3 | cum if random paid double 1175
```

What this says:

- **The World of Balance is short on Magic Points.** From Zozo to the
  Floating Continent a seat earns 205 (342 with random battles doubled);
  after the tube room, 143 (240). Most single battles pay 1 to 5; bosses
  pay up to 10.
- **The World of Ruin pays several times more**: about 700 from the
  landing to the Ancient Castle (1,290 doubled), then Kefka's Tower.
- So any ladder that fits these numbers has the shape the proposal wants:
  the World of Balance is the grand tour (small bonuses from many stones),
  and the World of Ruin is where a character masters a few.
- Gau, Umaro and Gogo never wear espers (vanilla), and the bench earns
  nothing (vanilla pays only the battle's party).

## Plan A — spells while worn, a ladder for keeps (recommended)

### While worn

Unchanged from today: each stone's one to three base spells
([magicite.md](magicite.md)'s tables; boost folds the tiers) and its
summon, once a battle. No new verbs, and every base spell keeps the source
magicite.md promises.

The while-worn stat package retires. Its stats move into the ladder, where
they are kept rather than rented. A stone is then worn for its spells and
for the bonuses it is teaching, which are the proposal's tensions A and C.

### The ladder

Every esper has the same five rungs. Progress is per character and
per esper: a battle adds its Magic Points to the counter of each living
seated member for the stone that member wears. A rung once reached is kept
for good, whatever is worn later.

| rung | Magic Points (cumulative) | kind | what it holds |
|---|---|---|---|
| 1 | 10 | low | +1 to the esper's first stat |
| 2 | 30 | low | +1 to its second stat |
| 3 | 75 | low | a small effect: one status immunity, or a minor relic effect |
| 4 | 200 | top | +2 to its first stat |
| 5 | 500 | top | its signature: a relic-tier effect |

Rungs 1–3 cost 75 together, a mastery costs 500, and the last step (300)
costs more than the four before it together, as Resonance's does. The
numbers assume random battles pay double (below); without that, the same
ladder takes about 1.7 times as many battles.

The first and second stats are the stone's current package's two largest
(so Ifrit stays vigor, Shiva magic). Effects marked † need new code; the
rest are bits vanilla's relics already carry, applied the way a relic's are
(`CalcEquipEffect`: field, status-protection, auto-status and relic-effect
bytes, `ItemProp+5` to `+13`).

| Esper | while worn (today's) | stats (1st / 2nd) | rung 3 (75) | rung 5 (500), the signature |
|---|---|---|---|---|
| Ramuh | Bolt, Rasp | Stm / Mag | immune to Dark (Goggles) | †*Conductor*: the wearer's lightning spells take one more shield |
| Kirin | Cure, Regen | Mag / Stm | immune to Poison (Star Pendant) | Regen in every battle (Cure Ring) |
| Stray | Muddle, Imp | Mag / Spd | immune to Imp | steals succeed more often (Sneak Ring) |
| Siren | Mute, Sleep, Bserk | Spd / Mag | immune to Sleep | immune to Berserk and Muddle (Peace Ring) |
| Ifrit | Fire, Drain | Vig / Stm | max HP +12.5% (Green Beret) | Fight deals more damage (Atlas Armlet) |
| Shiva | Ice, Osmose, Shell | Mag / Spd | immune to Seizure | spells cost half MP (Gold Hairpin) |
| Maduin | Fire, Ice, Bolt | Mag / Stm | max MP +12.5% (Bard's Hat) | spells deal more damage (Earrings) |
| Shoat | Break, Doom | Spd / Stm | immune to Petrify | immune to Death and Doom (Safety Bit) |
| Phantom | Vanish, Demi | Spd / Mag | no back attacks (Back Guard) | Image at the start of every battle (Mirage Vest) |
| Carbunkl | Rflect, Safe | Stm / Mag | Shell when HP is low (Barrier Ring) | †*Facet*: starts every battle with 2 boost points |
| Bismark | Haste, Slow | Vig / Stm | Safe when HP is low (MithrilGlove) | max HP +25% (Red Cap) |
| Unicorn | Pearl, Remedy | Stm / Mag | immune to Zombie | immune to Dark, Zombie and Poison (Amulet) |
| Golem | Safe | Stm / Vig | immune to Muddle | covers allies at low HP (True Knight) |
| ZoneSeek | Shell, Haste | Mag / Stm | immune to Mute | Shell in every battle (Force Shld's bit) |
| Sraphim | Cure, Life | Stm / Mag | immune to Doom's countdown | †*Grace*: keeps its boost points when KO'd and revived |
| Palidor | Float, Slow | Spd / Vig | walks faster (Sprint Shoes) | Float in every battle (Cherub Down) |
| Fenrir | Stop, X-Zone | Spd / Mag | more pre-emptive strikes (Gale Hairpin) | †immune to Stop and Slow (vanilla's protection bytes cover neither) |
| Starlet | Cure, Regen, Remedy | Mag / Spd | immune to Berserk | max MP +25% (Minerva) |
| Alexandr | Dispel, Safe, Shell | Stm / Vig | immune to Death | Safe in every battle (Guard Ring) |
| Terrato | Quake, Quartr | Mag / Stm | counters physical attacks (Black Belt) | max HP +50% (Muscle Belt) |
| Tritoch | Ice, Bolt, Poison | Mag / Spd | +1 speed | immune to Dark and Petrify (Jewel Ring), and max MP +50% (Crystal Orb) |
| Odin / Raiden | Meteor, Bserk (Raiden: + Quick) | Vig / Spd | Fight never misses (Sniper Sight) | Haste in every battle (RunningShoes) |
| Bahamut | Flare, W Wind | Mag / Vig | max HP +25% (Red Cap) | Fight and spells deal more damage (Hero Ring) |
| Phoenix | Life, Antdot | Stm / Spd | immune to Doom's countdown and Zombie | †*Rebirth*: enters every battle under Life 3 |
| Ragnarok | Ultima, Warp | Vig / Mag | max MP +25% (Minerva) | Fight strikes four times (Offering's X-Fight) |
| Crusader | Merton, Meteor | all four +1 at rungs 1 and 2 | max HP +25% (Red Cap) | Gauntlet (two-handed grip) and Genji Glove (two weapons) both allowed |

Odin and Raiden share one counter: Raiden replaces Odin, and the progress
carries over.

**Overlaps are deliberate where the theme wants them** (Unicorn's Amulet
holds Kirin's Poison and Ramuh's Dark; Bahamut's rung 3 is Bismark's
signature). Where a character already has an effect, a second copy adds
nothing; the menu marks it "have" so a player tours toward new ones. Max
HP and max MP boosts are a special case: vanilla stores one HP boost and
one MP boost in two bits each (`$160b`/`$160f`, `and #$c000` in
`DoLevelUp`), so several cannot combine and the largest one applies.

**How big this gets.** A character who toured every stone to rung 3
(about 1,950 Magic Points, close to a whole game in one seat) would have
about +13 in each stat and most of a Ribbon. Vanilla FF6's level-up bonuses
reached several times that. A character who mastered three stones would
have +5 in two or three stats, three signatures, and less breadth. Both are
far from the strongest relic loadout, which is still the main source of
power in gear.

### The tensions, worked

**Zozo to the Magitek factory** (seats LOCKE, EDGAR, SABIN, CELES; four
stones; 72 Magic Points a seat with random battles doubled). CELES wants
Kirin for Cure (A: the healer the party needs). Kirin's ladder is a
caster's, so she is also the right person to keep it; the conflict is
SABIN, who has no spells and gains most from Ramuh's Bolt as a ranged
option. Taking Ramuh to rung 2 gives him Stamina and Magic he barely uses,
while Stray's Muddle on LOCKE lets the party lock a pair of enemies (B).
Most players will wear the spells they need and pick up rungs 1–2 on the
way. That is the point of a cheap low end.

**The tube room to the Floating Continent** (twelve stones, four seats,
240 a seat). Now the choice is real. Spending TERRA's 240 on Maduin
reaches rung 4 (+3 magic, +1 stamina, MP +12.5%), not rung 5. Spending
it across Maduin, Shiva and Ifrit reaches rung 3 on all three: +2 magic,
+2 stamina, +1 speed, +1 vigor, MP +12.5%, HP +12.5% and Seizure
immunity. The tour is broader and the mastery is not reachable yet. LOCKE
wears Unicorn for Pearl against the undead (A) and collects Zombie
immunity on the way (D); the cost is Phantom's Vanish, which he would like
for the bosses (B).

**The World of Ruin, Mobliz to the Fanatics' Tower** (about 475 a seat).
This is nearly one mastery, or six more rung-3 tours. CELES masters Shiva and
casts at half MP for the rest of the game (C), or tours Palidor, Fenrir,
Tritoch and Terrato for Sprint Shoes, Gale Hairpin, Speed and a counter
(D). Inside the magic-only tower both choices pay: Shiva's mastery in MP,
the tour in Magic and Speed. Whoever wears Tritoch for its three families
(A) is not wearing Shiva.

**Kefka's Tower** (three parties). Stones split three ways, but the kept
bonuses travel with their characters: a member who mastered Kirin keeps
Regen in whichever party they join, with or without a healing stone. This eases the
one-copy squeeze that made Starlet and Tritoch second copies.

### How it fits the rest of OT6

- **Kits and divines.** Untouched. Espers still grant base spells only, and
  divines still come from a full 3-BP boost. No rung grants a command a
  kit owns.
- **Boost points.** One rung touches the bank (Carbunkl's *Facet*). The
  one-a-turn pace that gates divines stays: starting with two points brings
  the first divine one turn earlier.
- **Break shields.** One rung touches the chip (Ramuh's *Conductor*).
  Everything else leaves the break loop alone, so the authored shield rows
  keep their meaning.
- **MP economy.** "MP tension is the target." Shiva's Gold Hairpin and
  the max-MP rungs are the levers that loosen it. Half-MP on one mastered
  character, won in the World of Ruin, is the same scale as the late
  Economizer the owner already accepted on one caster. It is the outer
  edge, and the first thing to lab.
- **The bench of strong characters (#497).** Only seated members earn
  Magic Points, as only they earn XP, so the leveling plan's seat moves are
  also Magic Point moves. A carrier who rides a grind banks rungs as well
  as levels. That argues for rotating the strong six to eight through the
  grinds, which the plan already does.
- **Leveling.** Character growth stays vanilla-shaped (HP and MP per
  level; stats flat). The ladder is now the only stat growth, which is
  #328's second half: growth comes from what a character wore, not from
  levels.
- **Ribbons.** Ribbons are still worth a detour. A full tour covers most
  statuses one at a time, but only after a whole game of Magic Points.

### What it retires

- Vanilla's per-spell learn rates and learn percentages for espers (already
  zero; `LearnGenjuMagic` is replaced, not just left idle).
- Vanilla's level-up bonus byte (already `$FF`) and `DoLevelUp`'s call
  through `GenjuBonusTbl`.
- OT6's while-worn stat packages: `Ot6EsperStatTbl`, `Ot6EsperStatMod`
  and the menu's package display; the stat column of
  `check_spell_grants.py` and the `battle_esperstats_*` suites. The FIELD /
  STORY / BOSS tiers go with them.
- DESIGN.md's unbuilt plan for battle-count passives and weapon permits.
- The morph gauge's last reader of Magic Points.

### Building it

In rough order. S is a day's work, M a few days, L a week or more.

1. **Pay random battles double Magic Points (S).** Where the victory code
   loads `BattleMagicPoints`, apply `Ot6RewardMulW` the way XP and gil do,
   for random battles only. This puts Magic Points per step back to
   vanilla's, as was done for XP.
2. **Store progress (M).** One counter per character and esper: 12
   characters × 27 espers. Two bytes each is 648 bytes; one byte in units
   of two Magic Points (the ladder tops out at 500) is 324. The vanilla
   save block has 20 free bytes, so this goes in expanded SRAM as one page
   per save slot plus the transient page, shaped like the weakness codex
   (`ot6_codex.asm`: a magic word, re-initialized when wrong). The codex
   page has 240 free bytes, not enough. The space past the codex's
   `$317000` bound is not claimed by anything in `ot6_memory.inc`; the
   implementer needs to confirm that against the cartridge's SRAM size.
   Add a row to save-layout.md, and `check_save_layout.py` enforces it.
   Also keep a per-character summary of everything earned (four signed stat
   deltas and the OR of the effect bytes, about 12 bytes × 12 characters),
   rebuilt whenever a rung is reached, so the equip code reads one record
   instead of 27.
3. **Earn at victory (M).** Replace `jsr LearnGenjuMagic` in the victory
   loop with a hook that adds `$fb` to the wearer's counter, detects a
   crossed rung, rebuilds that character's summary and queues a battle
   message ("CELES: Shiva, rank 3"). Show the "got N Magic Points" line
   whenever anyone wears a stone (today it shows only when something
   learns or Morph is available). New battle text is the fiddly part.
4. **Apply the summary (S–M).** Fold the summary in as one more relic: in
   the menu's equip recompute and in `UpdateEquipBattle`, exactly where
   `Ot6EsperStatMod` sits now, through `CalcEquipEffect`'s byte layout.
   Resolve the HP and MP boosts as "largest wins" instead of OR. This
   replaces `Ot6EsperStatMod`, so the battle path does not grow.
5. **The five new effects (S each).** *Conductor* (one more shield on
   lightning spells, in the chip path), *Facet* (the seeded bank at battle
   start), *Grace* (keep the bank through KO and revive), *Rebirth*
   (Life 3 status at battle start, using the Life 3 status code
   `ot6_boost.asm` already has) and Fenrir's Stop and Slow immunity (a
   mask where status 3 is set). Each one is optional; a vanilla bit can
   stand in for any of them.
6. **The esper page (L, the largest piece).** The Skills → Espers detail
   page already draws five spell rows, each with a per-character learn
   percent, and a level-up bonus line. It becomes: the worn spells; five
   rung rows, each with its cost, the selected character's progress and a
   mark when reached; "have" on an effect the character already holds. The
   status page could list kept bonuses too, but it can wait.
7. **Teaching and data checks (M).** A Narshe school line in plain words
   ("a stone teaches its wearer bonuses that stay"); a build check like
   `check_spell_grants.py` holding the ROM's ladder to this doc's table; a
   battle suite that earns a rung at a victory, sees the bonus with a
   different stone worn, sees it absent on another character, and reloads a
   save; release notes.
8. **Re-measure (M, machine time).** The ladder moves stats, so every
   tracked save past Zozo is re-cut (checkpoint freshness), and the boss
   grids are re-read for drift. The harness also needs a wearing policy (who
   wears what, and when to rotate), which is the same choice a player makes.

## Plan B — abilities while worn, the same ladder for keeps

The other reading of "spell families and/or abilities": a stone is worn
for one spell family and one ability, a relic-style verb or reaction, not
for a list of spells.

### While worn

| Esper | family | ability while worn |
|---|---|---|
| Ramuh | Bolt | Jump (Dragoon Boots: Fight becomes Jump) |
| Kirin | Cure | Regen in battle |
| Stray | Imp | steal rate up |
| Siren | Sleep | pre-emptive strikes up |
| Ifrit | Fire | Fight damage up |
| Shiva | Ice | spells at half MP |
| Maduin | Fire | X-Magic (Gem Box: two spells a turn) |
| Shoat | Break | Fight never misses |
| Phantom | Vanish | Image at battle start |
| Carbunkl | Rflect | Shell at low HP |
| Bismark | Haste | counter (Black Belt) |
| Unicorn | Pearl | immune to Dark, Zombie and Poison |
| Golem | Safe | cover (True Knight) |
| ZoneSeek | Shell | Safe at low HP |
| Sraphim | Life | keep boost points through KO |
| Palidor | Float | Jump, repeating (Dragon Horn) |
| Fenrir | Stop | no back attacks |
| Starlet | Cure | Regen in battle |
| Alexandr | Dispel | immune to Death |
| Terrato | Quake | Float in battle |
| Tritoch | Poison | spell damage up |
| Odin / Raiden | Meteor (+ Quick) | X-Fight (Offering) |
| Bahamut | Flare | Fight and spell damage up |
| Phoenix | Life | Life 3 at battle start |
| Ragnarok | Ultima | two-handed and dual wielding |
| Crusader | Merton | Haste in battle |

### For keeps

The same five rungs, holding stats and the smaller immunities. The
relic-tier effects move to the while-worn side, so the top rung is a
larger stat step (+3) and a minor effect.

### Why it is the weaker fit

- **It breaks the spell coverage OT6 depends on.** With one family a
  stone, Rasp, Osmose, Muddle, Mute, Bserk, Demi, Remedy, Regen, Slow,
  Haste, X-Zone, Quartr, W Wind, Antdot, Warp and Quick lose their only
  sources or most of them. magicite.md's "every base spell has a source"
  and the Fanatics' Tower plan would both need redoing.
- **Command grants are narrow in vanilla.** The relic morphs rewrite a
  command the character already has: Fight → Jump or X-Fight, Magic →
  X-Magic, Steal → Capture, Sketch → Control, Slot → GP Rain. Only the
  first three work for everyone, so a real "esper command" needs a new
  command row, the most expensive menu work in OT6.
- **It competes with relics.** Each while-worn ability copies a relic, so
  the stone becomes a third relic slot and the relics lose their pull.
- **It weakens tension D.** With the strong effects rented rather than
  kept, touring the stones yields mostly stat points.
- **What it does better** is tension A and B: picking between X-Magic,
  Jump, Counter and Cover is a sharper choice than picking between spell
  lists. If the owner wants that, a smaller version fits inside Plan A: a
  stone's signature rung could also be its while-worn bonus before it is
  mastered (FF9's "use it now, keep it later").

### Building it

Everything in Plan A's list, plus: rewriting all 27 `GenjuProp` rows and
re-planning spell coverage (M of design, S of data); a while-worn effect
path (the same one-extra-relic fold, keyed on the worn stone: S); and, for
anything beyond the five vanilla morphs, a new command row (L).

## Recommendation

**Plan A.** It keeps every pillar: distinct kits, base spells while worn,
boost for tiers, one copy of each stone. It builds the permanent half
DESIGN.md already planned, with the currency vanilla already pays, and its
pacing falls out of the route's own numbers: a grand tour in the World of
Balance and masteries in the World of Ruin. It is also smaller: the menu
page is the only large piece.

## Questions for the owner

**Should progress belong to each character, or be shared by the party?**
DESIGN.md leaned party-wide to keep the save small. Per character is what
makes "master a few" mean anything, because a mastery then belongs to
someone, and it is how Resonance does it. I recommend per character. The
storage is a few hundred bytes of expanded SRAM.

**Should the while-worn stat packages go entirely?** Keeping a smaller
rented package beside the ladder would make each stone's identity show
from the first battle. It would also muddy tension A, because a stone
would be worn for its stats as well as its spells. I recommend retiring
them and putting all stat growth in the ladder.

**How strong may a signature be?** The table goes as far as Regen, Shell,
Safe, Float or Haste in every battle, spells at half MP, X-Fight, and
both grips. These are relic effects, held on one character after 500
Magic Points, mostly late in the World of Ruin. Half MP and Haste are the
two that could flatten MP tension and the battle pace. I recommend shipping
them and labbing those two first, then pulling any that make the late
bosses easy.

**Should benched characters earn Magic Points?** Vanilla pays only the
battle's party. Paying the bench (say, half) would let a player tour
without seating everyone, but it removes the choice of who sits in the
grinds. I recommend no. The leveling plan already rotates the strong six
to eight through the grinds, and the rungs follow.

**Should random battles pay double Magic Points, as they pay double XP?**
Without it a step earns half of vanilla's, and the World of Balance
reaches rung 3 on only two or three stones per seat. I recommend doubling
and sizing the ladder to it, as above.

**Should kept bonuses take slots?** DESIGN.md caps a character at four
passives, and Resonance makes learned skills fit an ability-point budget.
Slots would add a loadout choice and a menu. I recommend no slots in the
first build, with everything earned always active. The ladder's cost
limits power, and the non-stacking HP and MP boosts and repeat effects
keep stacking modest. Revisit slots if a fully toured character is too
strong.

**Does Plan B's sharper "which ability" choice matter enough to pay for?**
I recommend Plan A now. If the stones feel like spell lists and nothing
more, the cheap middle path is to make each stone's signature active
while worn before it is mastered.

## Sources

- Gematsu, "Final Fantasy Resonance details Zoldaad Empire, Mysidia, more
  characters, Visions, espers, and completionist elements" (2026-08):
  https://www.gematsu.com/2026/08/final-fantasy-resonance-details-zoldaad-empire-mysidia-more-characters-visions-espers-and-completionist-elements
- MeowDB, Final Fantasy Resonance, "Visions and abilities" and
  "Strengthening visions":
  https://meowdb.com/db/final-fantasy-resonance/mechanics/visions-and-abilities ,
  https://meowdb.com/db/final-fantasy-resonance/tutorials/strengthening-visions-visionability
- Push Square review: https://www.pushsquare.com/reviews/ps5/final-fantasy-resonance
- Pocket Tactics review: https://www.pockettactics.com/final-fantasy-resonance/review
- Nintendo Everything review: https://nintendoeverything.com/?p=927462
- VGC review (3/5): https://videogameschronicle.com/review/final-fantasy-resonance
- FF9: Caves of Narshe, support abilities,
  https://www.cavesofnarshe.com/ff9/support-abilities.php ; Jegged,
  learning abilities,
  https://jegged.com/Games/Final-Fantasy-IX/Tips-and-Tricks/Learning-New-Abilities.html
- FFT: Hack the Minotaur, jobs guide,
  https://hacktheminotaur.com/final-fantasy-tactics-the-ivalice-chronicles/ultimate-jobs-guide-for-final-fantasy-tactics-remaster/
- FFX-2: StrategyWiki, dresspheres,
  https://strategywiki.org/wiki/Final_Fantasy_X-2/Dresspheres
- FF6: Thonky, https://www.thonky.com/final-fantasy-vi/how-to-use-espers ;
  ArrPeeGeeZ, https://www.arrpeegeez.com/2014/08/final-fantasy-vi-walkthrough-magicite.html ;
  and the ROM source (`battle_main.asm`: the victory loop, `LearnGenjuMagic`,
  `IncLearnMagic`, `DoLevelUp`; `item_prop_en.dat` for the relic bits).
