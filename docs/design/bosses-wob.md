# WoB bosses, boss by boss — design dive v1 (2026-07-16)

Scope: every boss and miniboss from Whelk through the Floating
Continent, in story order. Shield counts and weakness rows here are the
M6 hand-authored table (replacing the demo's 2+level/8 formula for
these fights). Nothing is locked except explicit ✦, and most ✦ below
are jank preservations the house rule already demands.

## The boss contract

Stated once, assumed by every block:

- **One telegraph per boss.** The boss announces its big move on its
  turn ("gathering power" register) and fires it on its next turn, so
  the fuse is one full ATB cycle. **Breaking the boss during the fuse
  cancels the move**; the charge does not resume when the boss
  recovers, and has to be started again. Everything else in the fight
  stays vanilla AI.
- **Bosses get no exemption from breaks.** Turn loss and ×2 apply to
  AtmaWeapon the same way they apply to a Lobo. Shields are the only
  value tuned per boss.
- **Owner decision (2026-07-28, rc1 playtest): the Vargas triple-tutorial
  stays verbatim, permanently.** Menu-Blitz made the in-battle input
  tutorial mechanically unnecessary. It stays anyway, for its charm
  ("i always found the original charming and you've kept it exactly,
  even maybe more so"). No cleanup pass removes it.

- **Scripts run regardless of break state.** Vargas's Pummel finish,
  Chupon's Sneeze and the espers interrupting Ultros on the bridge
  all fire whether or not the boss is Broken. The gauge changes
  combat, not scripted story events. (Kefka's camp flees used to head
  this list. They have no state to override, because they have no
  monster and no gauge; see 6.)
- **Proposed ruling: counters are disabled while Broken.** A Broken
  enemy loses its counters along with its turns, so Whelk's shell does
  not counter during the window. This matches Octopath; it is a driver
  decision, open question 1.
- **A nameplate with no shields is itself information.** Scripted
  set-pieces (Tritoch, Guardian, the Imperial Camp Kefka) draw no
  gauge at all, which tells the player the fight is scripted.

Numbers below are shields only; boss HP falls under the global
−25–35% cut and is tuned in M6. Elemental rows keep vanilla's bits
wherever they exist ✦ (weapon-classes.md); every *added* element or
class is justified by the coverage rule: the party the story gives you
must be able to chip. Before Zozo the proofs rely on kits.md's learn
schedules; from Zozo on, magicite makes fire/ice/bolt roughly
party-independent, and the proofs rely on both.

Recurring bosses rely on the codex. Ultros keeps one weakness row
through all four fights, revealed at the Lete River and revealed from
then on; only his shield count grows.

## The curve at a glance

| # | Boss | Where | Shields |
|---|---|---|---|
| 1 | Whelk (head) | Narshe intro | 4 |
| 2 | Marshal | Narshe escape | 4 (Lobos 3) |
| 3 | Vargas | Mt. Kolts | 5 (Ipoohs 2) |
| 4 | Ultros ① | Lete River | 5 |
| 5 | TunnelArmor | Locke scenario | 5 |
| 6 | Kefka ×2 | Imperial Camp (Sabin) | — (no gauge) |
| 7 | Telstar | Imperial Camp (Sabin) | 4 (Dobermans 2) |
| 8 | GhostTrain | Phantom Train (Sabin) | 6 |
| 9 | Rizopas | Baren Falls (Sabin) | 5 (Piranhas 1) |
| 10 | Kefka | Narshe defense | 6 |
| 11 | Dadaluma | Zozo | 6 (Iron Fists 2) |
| 12 | Ultros ② | Opera house | 6 |
| 13 | Ifrit & Shiva | Magitek factory | 6 + 6 |
| 14 | Number 024 | Magitek factory | 7 |
| 15 | Number 128 | minecart escape | 7 (blades 3 each) |
| 16 | Left & Right Cranes | airship escape | 6 + 6 |
| 17 | Ultros ③ | Esper Mountain (v0.8 — corrected 2026-07-28; battle 125's only call site is the Relm-joining scene, see thamasa-route.md §3.1) | 7 |
| 18 | FlameEater | Thamasa | 7 (Balloons 1) |
| 19 | Ultros ④ + Chupon | FC approach | 7 + 4 |
| 20 | AirForce | FC approach | 8 (pods 3/3, Speck 1) |
| 21 | AtmaWeapon | Floating Continent | 11 |
| 22 | Nerapa | FC escape | 5 |

The curve runs 4 shields at the start and 6 at the scenario capstones,
then a 6–7 plateau through act two where difficulty comes from parts
and from fighting several bodies at once (the Cranes are 12 shields of
monster across two gauges) rather than from a larger single count.
After that come one 8, an 11 at the peak, and a deliberate 5 at the
end under a timer. No single WoB gauge exceeds 11; 12 and above is
reserved for the WoR.

---

## Narshe intro

### 1. Whelk — the mines

Party: Terra between Vicks and Wedge, all Magitek (fire/bolt/ice
beams; Terra adds TekMissile and Bio Blast).

| part | shields | weak |
|---|---|---|
| Head | 4 | fire + piercing |
| Shell | — (no gauge) | — |

- **Telegraph:** the Whelk draws into its shell and the shell charges
  → **MegaVolt** hits the party. Break the head during the fuse to
  cancel it.
- **Break story:** the guards warn you away from the shell, and Fire
  Beam is the probe the game points you at. Three beams and a
  TekMissile break the game's first boss within two rounds, which
  teaches the whole sequence: probe, chip, break, dump.
- **Jank ✦:** hitting the shell triggers the MegaVolt counter, exactly
  as in vanilla, and it is still lethal at level 1. Under the proposed
  ruling the counter is disabled only during the head's break window.

### Tritoch — (scene, not a fight)

The frozen esper one-shots the Magitek trio. It is a cutscene that
uses the battle screen. No shields and no gauge are drawn, which is
the first time the game shows that an empty HUD means a scripted
scene.

## Narshe escape

### 2. Marshal — the moogle defense

Party: Locke, Mog, and ten moogles in three squads.

**Shields:** 4 · **Weak:** poison + piercing. Lobos: 3 · fire +
piercing.

- **Telegraph:** the Marshal levels his blade and calls the Lobos in
  → next turn he and both Lobos attack one target. Break him and the
  Lobos attack without coordination.
- **Break story:** twelve bodies generate BP quickly and damage
  slowly. Moogle spears chip him steadily, and the break protects
  whichever squad he is attacking. Piercing is the featured class,
  matching the gear the moogles carry.
- **Jank:** the three-squad control scheme stays byte-for-byte,
  including vanilla's unusual moogle gear; losing all squads is still
  a game over.

## Mt. Kolts

### 3. Vargas (+ two Ipoohs)

Party: Terra, Locke, Edgar. Sabin joins at the midpoint with Pummel
and, at vanilla level 6, AuraBolt, so the fight is planned assuming
holy chip is available.

MEASURED, in `battle_vargas.lua` off the tier-2 fixtures: he seeds
**5/5 with class row $04 (bludgeoning)**, the Ipoohs 2/2 slash-weak,
and his weak byte reads **$28 — poison|holy**, the holy bit being
`Ot6ElemAddTbl`'s add on top of vanilla's poison. Sabin's arrival is
structural rather than descriptive: he gets **no turns at all** until
Vargas's own reaction script fires `battle_event $07/$08`
(hp ≤ 10880, then ≤ 10368, `ai_script.asm:4392-4404`) and knocks the
trio out of the fight. He joins at level 9 on this route, so AuraBolt
is present as planned. AuraBolt takes a shield and reveals holy,
Pummel takes another and reveals the bludgeon class, and the same
Pummel kills him.

Edgar's BioBlaster is measured now as well, and the measurement
corrects the break story below. The poison chip works as planned: item
`$a4` resolves to attack `$7d`, element `$08`, and it takes a shield
and reveals poison, while the same party's plain weapon swings hit
Vargas without moving the gauge (`battle_vargas.lua`'s control).
**BioBlaster cannot reach him while an Ipooh is alive.** Its item
targeting byte is `$6a`, which is group-targeting with `$01 MANUAL`
clear, so the cursor cannot be moved off the group, and
`key_target_2`'s INIT_GROUP branch (`btlgfx_main.asm @7875`) aims at
monster group A and falls through to group B only when A is empty.
This formation has the Ipoohs in A and Vargas alone in B. Measured
over one fight: seven consecutive BioBlasters went into the Ipoohs'
group ($06, then $04 once the first died) before the eighth reached
him ($01), about 9500 frames in.

**Shields:** 5 · **Weak:** poison, holy + bludgeoning. Ipoohs: 2 ·
fire + slashing.

- **Telegraph:** he drops into his wind stance → **Gale Cut** hits
  the party. This is the same move the script later uses to knock the
  trio out of the fight; it is his only named move, and it is used as
  the fuse.
- **Break story:** phase one gives the trio very little chip.
  BioBlaster's poison is their only key and takes Vargas down 1 while
  the script has the fight going against you. Sabin then arrives with
  Pummel ×2 for bludgeoning and AuraBolt for holy, which supplies the
  chip; Vargas cannot be broken before Sabin joins. **The escorts
  block the key** (measured, above): the spray goes to the Ipoohs'
  target group until both are down, so phase one is clear the adds
  first, then spend the tool. That ordering was not planned, and it
  needs no extra work.
- **Jank ✦: the Blitz requirement stays.** Doom Fist's Condemned
  countdown on Sabin and the Pummel-input finish are unchanged; he
  dies to the script rather than to HP. Breaking him does not end the
  fight. What the ×2 window buys is free turns to enter the Blitz
  input while he is Broken. Killing him by damage instead (11,600 HP
  at level 10) is still possible.

## Lete River

### 4. Ultros ①

Party: Terra, Locke, Edgar, Sabin, Banon (Health is a free party
heal; his death is a game over).

**Shields:** 5 · **Weak:** fire, bolt + slashing, piercing — the row
he keeps all game.

- **Telegraph:** two tentacles rise → **Tentacle** hits Banon. Break
  during the fuse to cancel it.
- **Break story:** Banon's Health makes stalling survivable, so the
  fight teaches banking: probe fire (he has a scripted line about
  seafood), hold at 2–3 BP, break on the fuse, and dump with boosted
  Fight. This is the first fight where failing to cancel the fuse can
  lose the game. AutoCrossbow does heavy damage to him; that is fine,
  because this fight is meant to be easy.
- **Jank ✦:** Ink inflicts Dark, and Dark does nothing because of the
  evade bug. It stays doing nothing. The scripted line on fire fires
  every time, and he flees at the end of the fight.

## The split — three scenarios, three proofs

This is the stress test for the coverage rule (weapon-classes.md).
Terra and Banon's segment through the caves has no boss; that party is
tested at the Narshe defense instead. Per-party notes below.

### 5. TunnelArmor — South Figaro escape (Locke + Celes)

**Shields:** 5 · **Weak:** bolt, water, ice + piercing. (Decoded, not
recalled: `$104` weak = **bolt|water** — `monster_prop.dat` +25 reads
`$84` — and +23/+24 are both `$00`, so it absorbs nothing and nulls
nothing. An earlier draft printed the bolt bit and silently dropped
the water one, against the "keep vanilla's bits ✦" rule at the top of
this doc; same slip logged at Nerapa below.) Bolt *and* water are
vanilla's machine bits and this party can produce neither — the only
water in the WoB this early is a thrown Water Edge, Throw is Shadow's
✦ and he is two scenarios away, and Locke's list is verbs, not
elements (kits.md) — so both bits are codex trivia today, payoff
later. Ice is the add: Celes's join spell needs a socket, and "frozen
coolant lines" reads fine on a digging machine. **The ice row is
authored** (`Ot6ElemAddTbl` `$0104` + `$02`, weak byte resolves
`$84` → `$86`); the 5 shields and piercing were already in
`Ot6ShieldTbl`. Inert to the suite until a Locke+Celes fixture reaches
`battle 67` (event_main.asm:21005).

- **Telegraph:** the drill spools down and the tunnel shakes → its
  quake (Magnitude8 — audit list). **Runic absorbs it.** The fight has
  two valid answers, Runic the quake (vanilla's tutorial) or break the
  machine first (ours), and doing both is best, since Runic converts
  the telegraph into +1 BP ✦ (kits.md), so the boss's biggest move
  pays for the break.
- **Break story:** Mug and daggers chip with piercing, Ice chips as an
  element, and 5 shields across two bodies puts the break at about the
  first fuse. It is a small fight that uses every part of the system.
  The coverage rule here rests on the added Ice and the piercing
  class, because both vanilla element bits are unreachable for this
  duo. Narrowing either one leaves the fight with no way to chip at
  all.

### 6–7. Imperial Camp (Sabin, with Shadow drifting in and out)

**Kefka ×2: no gauge, because there is no monster in this fight.**
(Decoded, not recalled.) Both scenes run `battle 56, IMP_CAMP`
(event_main.asm :40683 and :40743). Group 56 in
`event_battle_group.dat` points both its slots at **formation 504**,
and formation 504 in `battle_monsters.dat` (+`$1d88`) is `00 00 ff ff
ff ff ff ff 00 00 00 00 00 00 3f`: the present mask is **`$00`**, and
all six id slots are `$ff` with byte 14 = `$3f` setting every high
bit, which gives six copies of `$1ff`, vanilla's empty-slot sentinel
(battle_main.asm:7720). Nothing is loaded. What `battle_prop.dat`
(+`$7e0`) enables instead is **character AI script `$04`**,
`kefka_imp_camp_1`, whose slot 0 is
`CHAR_PROP::KEFKA_1|CHAR_AI_FLAG_ENEMY_CHAR` (char_ai.asm:163). The
event has already set a party slot to him on the way in:
`char_prop VICKS, KEFKA_1` (event_main.asm:40675; CHAR::VICKS = 15,
CHAR_PROP::KEFKA_1 = `$29`).

The Kefka fought at the camp is therefore a **character entity** using
Kefka's name, sprite and palette, flipped to the enemy side and
running monster AI script `$016f`. He has character HP, which is why
the event can revive and refill him between rounds with `clr_status
VICKS, DEAD` / `max_hp VICKS` (event_main.asm:40739). No `MonsterProp`
record is read for him, so there is no weak byte, no absorb byte and
no shield seed. `Ot6SeedShields` is reached only from the monster/rage
load and returns immediately for character entity offsets in any case
(`ff6/src/battle/ot6_break.asm:6-9`).

A gauge cannot be implemented here: there is no monster entity to
attach a species row to, and gauging a character entity would need a
new per-formation hook rather than a table row.

That matches the intent: both scenes are scripted and should read as
scripted. He takes a few hits and flees, twice, with the waiter line
unchanged, and the empty HUD says so from the start, which is the same
rule as Tritoch one scenario earlier. If a future pass wants a
breakable Kefka here, that is new code and belongs in the roadmap, not
in the shield table.

**Telstar:** 4 shields · bolt, water + bludgeoning (Dobermans 2 · fire +
piercing). (Decoded, not recalled: `$044` weak = **bolt|water** —
`monster_prop.dat` +25 reads `$84`, the same byte TunnelArmor and the whole
AirForce assembly carry — and `$01a` Doberman weak = **fire**. An earlier
draft printed only the bolt bit here and left the Dobermans' element off
entirely.)
- **Telegraph:** its antenna sparks and it radios for backup → a
  Doberman wave arrives next turn. Break to stop the call. This is the
  first break that prevents a summon; the same use returns at
  FlameEater.
- **Jank:** the treasure chest that turns out to be a monster is
  unchanged.

### 8. GhostTrain — the Phantom Train (Sabin, Cyan, Shadow)

**Shields:** 6 · **Weak:** fire, bolt, holy + bludgeoning ·
**absorbs poison.** (Decoded, not recalled: `$106` weak =
**fire|bolt|holy** — `monster_prop.dat` +25 reads `$25` — and +23
reads **`$08`, poison absorbed**; +24 is `$00`. An earlier draft
dropped vanilla's bolt bit and never mentioned the absorb at all.)

- **Telegraph:** the whistle sounds down the corridor → **Evil
  Toot**, a party-wide random status attack. Break the boiler before
  the move lands; Acid Rain between fuses keeps pressure on your
  healing.
- **Break story:** the keys are the abilities the scenario gives you.
  AuraBolt is holy chip at range, Pummel ×2 chips repeatedly, and
  Shadow's elemental skeans reach two of the three element bits rather
  than one: Fire Skean is fire (item `$ab` → spell `$51`) and Bolt
  Edge is bolt (`$ad` → `$53`), both legal chips once vanilla's bolt
  bit is restored to the row. Cyan cannot chip his own scenario's
  boss, which is deliberate: the Phantom Train farewell is where
  **Cleave** unlocks (kits.md), and Cleave requires a Broken target,
  so the train is the first target it can be used on. Another
  character has to break it for him.
- **Jank ✦: Suplex still works.** It is also mechanically consistent
  now: Suplex is bludgeoning and the train is bludgeon-weak. The
  undead flag stays as well, so one Fenix Down kills the train
  instantly regardless of break state. By house rule, vanilla
  shortcuts take precedence over the break system.
- **Jank ✦: poison heals the Phantom Train.** This is vanilla
  behaviour and it stays, but it needs to be written down where an
  author will find it. Edgar's Bio Blaster is poison: the Throw/Tools
  table maps item `$a4` to spell `$7d` (battle_main.asm:6577) and that
  spell's element byte is `$08`. The Narshe school's tier-2 seed once
  presented that tool as the answer to armored enemies ("Every armor
  fears one right tool", narshe-school.md); the v0.5 break pass
  retired that framing and the seed's own rewrite has dropped it (see
  "The imperial soldier line"), but the poison heal here is vanilla
  and applies regardless. If Bio Blaster is used on this boss,
  vanilla's absorb branch flips the damage sign and skips past the
  weakness branch that contains the shield chip
  (battle_main.asm:1850, chip at :1872), so the hit heals the train
  and chips nothing. Nothing is broken today, because Edgar is on
  Terra's segment and this party carries no poison, so the problem is
  latent rather than live. Do not build a poison beat around the
  Phantom Train, and re-read this before routing Edgar onto it.
- **Poison fails on this train twice, on the boss and on the chest.**
  Decoded while authoring the armor line: `$0156` Specter, the
  monster-in-a-box in this same scenario (map 153, treasure 114 →
  event battle group 34 → formation 476), also **absorbs poison**
  (+$2ad7 = `$08`), and is fire|holy weak in vanilla (+$2ad9 = `$21`).
  The one element the v0.3 arc teaches is therefore the one element
  that fails twice here. Specter gets **no authored row**: vanilla's
  fire and holy are both usable keys here (Shadow's Fire Skean and
  Sabin's AuraBolt, the same two the break story above uses), and
  adding poison would put a chip trigger on an absorber, which is the
  error caught in draft at Nerapa and the Cranes.

### 9. Rizopas, after the Piranha school — Baren Falls (Sabin + Cyan)

**Shields:** 5 (Piranhas 1) · **Weak:** bolt + slashing, bludgeoning.

- **Telegraph:** the falls swell backward → **El Nino** hits the
  party.
- **Break story:** this fight is the clearest case for the coverage
  rule. Bolt is vanilla's weakness here and neither character can cast
  it, so the weapon classes carry the fight: Pummel and Dispatch/Slash
  chip regardless, and Quadra Slam (if the scenario got Cyan to level
  15) chips 4 at a time. When the party has no usable element, the
  classes are what remains.
- **Jank:** the Piranha wave stays a wave. They do small damage, die
  quickly, and teach the player to use AoE. Gau and the dried meat
  come one screen later.

## The reunion — Narshe defense

### 10. Kefka and the raiding party

Party: all seven, three squads on the snowfield.

**Shields:** 6 · **Weak:** poison, fire + piercing, slashing.

**Authored: the whole row is an add.** `$014a`'s vanilla weak byte
(`monster_prop.dat` +$2959) is `$00`, so the arc's final boss shipped
with no weakness of any kind, and `Ot6ElemAddTbl` carries `$09`
(poison|fire) outright. +$2957/+$2958 are both `$00`, so nothing is
absorbed or nulled. The 6 shields and the two classes were already in
`Ot6ShieldTbl`. Kefka's own row is deliberately broad (poison|fire +
piercing, slashing), so any squad you route to him can break him. His
waves (Trooper, HeavyArmor, Rider) used to rely on the same poison the
school taught, which only the Edgar squad could cast; the v0.5 pass
gave them slash\|pierce class rows so every player-assigned squad has a
key (see "The imperial soldier line" below).

- **Telegraph:** he giggles and frost crawls the ground → **Ice 2**
  across the engaged squad.
- **Break story:** the waves drain resources before Kefka himself, so
  the fight teaches banking across a sequence of fights: earn BP on
  the waves, arrive holding 4–5 BP, and break him on the first fuse.
  The broad row means any squad you route to him can break him, and
  the squad layer makes the routing the player's decision.
- **Jank:** the strategy layer is untouched, and his spell list stays
  low-tier, matching where he is in the story.

## The imperial soldier line — every party gets a key

These are not bosses. They are documented here because this is where
the weakness data lives, and because the v0.5 break-coverage pass
changed the design. (This section replaces the old "one right tool"
writeup, which is kept in git history.)

**The previous design.** The Narshe school's tier-2 seed said "their
armored machines shrug off blade and fire alike… Every armor fears one
right tool" (narshe-school.md), and the tool was Edgar's Bio Blaster
(poison, `$08`). Four species were given a poison `Ot6ElemAddTbl` add
so that the dialog would be accurate. That made poison the only key to
the imperial line.

**Why that did not work.** The fixed-party audit walked every forced
section and found that the parties that fight this line do not include
Edgar, and so have no poison. Cyan's solo Doma duel is slash-only,
Sabin's whole scenario has no poison, Locke solo in occupied South
Figaro is pierce-only, and the Narshe defense is a player-assigned
3-way split where at most one squad holds Edgar. "One right tool =
poison" therefore left the imperial line unbreakable by the exact party
the game gives you.

**The fix: a weapon class, chosen per the forced party.** Poison is no
longer special; it is one Edgar-reachable key among several. Each
species gets an `Ot6ShieldTbl` row whose class *every party that fights
it* can reach:

| species | id | shields · class | forced party → its key | thematic |
|---|---|---|---|---|
| Soldier | `$0001` | 2 · slash\|pierce | Cyan duel (slash) · Sabin+Shadow camp `b44` (Shadow pierce) | cut, or seam |
| Templar | `$0002` | 3 · pierce (+bolt) | Sabin+Shadow camp `b44` (Shadow throw / Bolt Edge) | elite plate; blade in the gap, metal conducts |
| Leader | `$014E` | 3 · slash | Cyan SOLO Doma duel `b46` | the samurai out-cuts the commander |
| Grunt | `$014F` | 2 · slash\|bludg | Doma defense `b13` (Cyan slash + Sabin bludg) | two heroes overwhelm a footman |
| Cadet | `$0176` | 3 · slash\|bludg | Doma defense `b14` (same two) | ditto, a bigger body |
| Officer | `$0175` | 2 · pierce | Locke SOLO S.Figaro `b9` | the thief's dagger finds the seam |
| Trooper | `$0065` | 2 · slash\|pierce | Narshe waves — any squad | slash for Cyan/Sabin, pierce for Locke/Gau |
| Rider | `$003F` | 3 · slash\|pierce | Narshe waves — any squad | ditto (fire still breaks it on the train) |
| HeavyArmor | `$009F` | 3 · slash\|pierce | Locke SOLO `b11` (pierce) + Narshe wave (slash) | heavy plate; a blade at the seams |

Shields track the early-war stretch (2 basic infantry, 3 for the elite /
heavier / duel bodies). **Class chips ignore absorb/null**, so
HeavyArmor's vanilla water-absorb and everyone's stray element bits
never interfere with the break; the class is always a legal key.

**The palette (owner's choice).** Armored soldiers are **pierce**, on
the reading that a blade finds the gaps in armor, with **bolt** where a
party can cast it: the machines (M-TekArmor, HeavyArmor) are natively
bolt-weak in vanilla, and Templar gains bolt (`$04`) here for Shadow's
Bolt Edge at the camp. The Cyan solo duel is **slash**, so it plays as
a swordfight. Sabin's fights add **bludg**. The rows are varied rather
than uniform: the key is whichever character is fighting the enemy.

**Element table, after the pass.** M-TekArmor and HeavyArmor keep their
poison adds, on top of vanilla bolt, because a party that fights them
can cast poison (Shadow's bolt at the camp; Edgar at the Narshe waves).
**Leader and Grunt lost their poison adds.** Those were the "one tool"
artifacts, the two species with *no* vanilla weakness at all, and
poison is unreachable in both of their forced fights (a solo duel; a
Cyan+Sabin defense), so the add was dead data that also produced an
unresolvable `?` on a fight the class row already answers. Templar's
row was verified `$00/$00` at +$17/+$18 before authoring, as the rest
of the table was.

**Trooper and Rider changed direction.** The old writeup left them
element-only ("vanilla already agrees, no row needed") because they are
poison-weak in vanilla. But the Narshe defense assigns squads by player
choice, and a Cyan+Sabin or Locke+Gau squad reaches neither poison nor
any vanilla element on these bodies. v0.5 therefore gives both a
slash\|pierce class row: vanilla poison stays the Edgar squad's key,
and the class is every other squad's. Formation 88
(Trooper+HeavyArmor, `battle 23`, event_main.asm:108505) is now
breakable by whatever a squad holds, not by Edgar alone.

**M-TekArmor gets no new row.** It is already breakable by the party
that fights it (Shadow's Bolt Edge, or the Magitek bolt beam at the
camp), so it was never a gap; it carries the bolt half of the palette
in vanilla.

**The school seed now matches the data.** The tier-2 dialog ($0276) was
rewritten under the school's own story/dialog sanction
(narshe-school.md) to teach the new version: armor turns a careless
blow aside, but every plate has a seam, and no two are the same, so
bring the weapon that fits. Both of the old claims are gone. A precise
blade *is* an answer (pierce/slash), and there are several tools rather
than one. The class rows are the mechanic; `school.lua` now pins the
new dialog bytes, so text and data fail separately if either drifts.

**The one place coverage overrode the theme.** The palette's default for
armored soldiers is pierce+bolt, but the Doma courtyard defense party
(Sabin bludg + Cyan slash) can field neither pierce nor bolt. Grunt and
Cadet therefore take slash\|bludg rather than the default, using the
owner's rule that Sabin's fights are bludgeon. This is recorded so a
future author does not change them back to pierce and re-open the
gap.

## The Serpent Trench — three aquatics, three keys

Sabin + Cyan + Gau ride the trench (`battle 19`/`20`/`21`, UNDERWATER,
event_main.asm:21194+; the party is placed together at the ride's entry
`_ca8ae3`). The classes they can field are **bludg** (Sabin's fists and
Blitz, Gau's bare hands) and **slash** (Cyan's katana and SwdTech,
Sabin's claws once he owns a pair), and nothing else. Every trench
aquatic was a formula species whose vanilla element the party cannot
reach: Anguiform is bolt-only and the party has no bolt, and
Actaneon/Aspik are fire-weak but Sabin's Fire Dance needs level 15. All
three **absorb water**, so an element add would heal them. Class rows
are the answer, and the two keys are split across the three creatures
to match the party, which has two bludgeon users and one slash user:

| species | id | shields · class | thematic |
|---|---|---|---|
| Anguiform | `$003A` | 2 · slash | a slippery eel, cut by Cyan's blade |
| Actaneon | `$005E` | 2 · bludg | a shelled crustacean, cracked by Sabin's fists |
| Aspik | `$0059` | 2 · bludg | a constrictor, crushed by a monk's fists |

Vanilla bits are kept (dead or level-locked for this party, live for a
later party that carries the element); class chips ignore the
water-absorb.

## Break coverage — the free-roam floor (#6)

- **The free-roam tail now has a floor.** `Ot6SeedShields`' `@formula`
  fallback used to clear the class-weak mask (`$3e9c`), which left an
  un-authored enemy breakable only by whatever element it happened to
  carry, and unbreakable if it carried none. It now seeds a per-species
  **floor class** instead: `sta $3e9c,y` reads `OT6_FLOOR_CLASS[species]`,
  a build-time table generated by `ff6/tools/gen_break_floor.py` from the
  monster names, so every un-authored body is breakable by some weapon
  class. The palette follows the authored rows:
  armored/mechanical/dragon/insect → **pierce**, brute/ooze/golem/monk →
  **bludgeon**, and beasts/humanoids/casters → **slash** (the remainder).
  Authored `Ot6ShieldTbl` rows still take precedence (the `@hit` path
  overwrites the mask); the floor only fills the gap.
  `battle_breakfloor` is the regression test, and it asserts that all 384
  species carry a breakable class. The pacing effect of universal
  breakability, which is more breaks, is a playtest and balance matter,
  like the Kolts shield-count sweep.
- **Tentacle_2 / Tentacle_3 (`$013D`/`$013E`) are out of WoB scope,
  deliberately.** They belong to the World-of-Ruin Figaro engine room,
  which is outside this document's World-of-Balance scope. The floor gives
  them a class like any other species, but their fight is in the WoR, so
  revisit their break design with the WoR pass rather than treating it as
  a WoB gap.

### 11. Dadaluma

Party: any four of the seven.

**Shields:** 6 (Iron Fists 2) · **Weak:** poison + piercing,
bludgeoning — every possible pick of four holds at least one of the
two classes; most hold both.

- **Telegraph:** he crouches to jump → **Jump**, which is
  untargetable and lands on one character. Break him during the
  crouch and he does not leave the ground.
- **Break story:** he calls in Iron Fists at half health and uses his
  own potions. Chip through the adds with AoE piercing
  (AutoCrossbow), bank BP, and break him during the crouch.
- **Jank:** the mid-fight item use stays, and it suits Zozo. Jump's
  airborne phase stays as vanilla has it.

## Opera → Vector → the factory

### 12. Ultros ② — the opera stage

Party: Locke + three (Celes is mid-aria).

**Shields:** 6 · **Weak:** the row ✦ (fire, bolt, slashing,
piercing — revealed at the Lete, still revealed; the codex working
as designed).

- **Telegraph:** the same tentacle wind-up as before. He is a
  recurring boss with a remembered weakness row and a higher shield
  count each time.
- **Break story:** there is no Banon to protect this time, and the
  tentacle targets whoever is most costly to lose. One more shield
  than the Lete River fight, and no free healer.
- **Jank:** the battle takes place on the opera stage and the scene
  continues around it.

### 13. Ifrit & Shiva — Magitek Research Facility

Party: Locke, Celes + two.

| part | shields | weak |
|---|---|---|
| Ifrit | 6 | ice + piercing |
| Shiva | 6 | fire + slashing |

- This is vanilla's tag fight: they swap in and out. Each keeps its
  own gauge across swaps, and a swapped-out sibling's break timer
  keeps running; it is not frozen behind the `$3aa0.0` presence gate.
- **"Breaking pins them on stage" is an intent, not the fight as it
  stands.** Nothing implements a tag lock. The effect would have to
  come from `Ot6Gate` (`ot6_break.asm:1655`, consulted at
  `battle_main.asm:1419`) refusing to queue a broken monster's turn,
  and the swap is one of the turns that passes that gate. The tag is
  the first branch of Ifrit's own main AI script
  (`if_battle_var_greater 3, 5 / kill_monsters_wait MONSTER_1 /
  show_monsters MONSTER_2`, `ff6/src/battle/ai_script.asm:4566-4571`),
  so it needs a main-script turn, and main-script turns run while
  Broken: 103 executions with the broken timer up in one battle-70
  run, including 7 casts of Fire from `attack BATTLE, FIRE, FIRE`
  (`ai_script.asm:4577`) in the same script the tag branch heads. The
  counter the tag reads is also advanced by `add_battle_var 3, 1` in
  the `if_hit` retaliation block (`ai_script.asm:4613`), 50 of those
  103, so chipping a Broken sibling still advances its swap timer.
  **UNVERIFIED:** nobody has watched a Broken sibling complete a
  tag-out; what is observed is that the script containing the swap
  runs while Broken. `Ot6MayAct` (preserved on `wt/ifritbreak`, commit
  `945b9ed`) drops 103 → 2 and would make the pinning true, but it
  cannot land while `battle_trueknight` 6a stands.

- **Telegraph:** Ifrit inhales and the air shimmers → **Fire 2**;
  Shiva does the same with **Ice 2**. Whichever one is on the field
  runs its own fuse.
- **Break story:** this is the first fight that requires reading
  absorbs, because fire heals Ifrit. Celes can chip both siblings by
  herself, with Ice into Ifrit and her sword into Shiva. The fight
  still ends by script rather than by killing them; the Ramuh script
  stays.

### 14. Number 024 — the specimen guard

Party: Locke, Celes + two.

**Shields:** 7 · **Weak:** *rotating* — WallChange re-rolls the
elemental wall every few turns and re-hides the element row when it
does. Classes fixed: slashing + piercing, the handhold while the
wall spins.

- **Telegraph:** the wall changes to a color → the matching tier-2
  spell (Fire 2 / Ice 2 / Bolt 2). The fuse also tells you the current
  wall, and therefore the current absorb, so probe with a different
  element.
- **Break story:** this boss works against the codex. Physical chip is
  steady, magic requires reading the current wall, and a break keeps
  the current wall revealed until the next WallChange re-rolls it. It
  is the only enemy in the WoB whose element row does not stay
  revealed once found.
- **Jank:** WallChange stays random, including back-to-back rolls of
  the same wall.

### 15. Number 128 — the minecart

Party: **three**, on rails. Celes is separated partway through the
Facility, so this fight and the Crane escape run one character short of
the party that walked in. (Owner account; §16's "the factory four" is
likewise one too many. This is flagged rather than rewritten, because
the exact roster here is runtime state and is to be measured at the
fixture, not read out of the event dump. An attempt to derive it from
`event_main.asm` opcode adjacency produced a badly wrong answer; see
the Beat B note in `wob-route.md`.)

| part | shields | weak |
|---|---|---|
| body | 7 | bolt, water + piercing |
| Left/Right blades | 3 each | bolt + slashing |

- Blades regenerate a few turns after dying (vanilla ✦), and regrown
  blades return at full shields. Their weakness row stays revealed.
- **Telegraph:** both blades rise → the whole-side sweep (Gale Cut —
  audit list). Breaking *either blade* cancels it. This is the first
  fight where breaking a part is the answer.
- **Break story:** this is the first battle after Zozo gives you four
  espers, and a Ramuh bearer casting Bolt into the body is the first
  use of the sub-job system (magicite.md's storm-lancer).
- **Jank:** regrowth timing stays vanilla; the minecart shooter
  around it stays byte-for-byte.

### 16. Left & Right Cranes — the Blackjack's rigging

Party: the factory four (Setzer is flying the airship).

| part | shields | weak |
|---|---|---|
| Left Crane ($10D) | 6 | water + piercing |
| Right Crane ($10E) | 6 | bolt, water + piercing |

(Decoded from `monster_prop.dat` +25, not recalled: `$10D` weak =
water, absorbs bolt; `$10E` weak = bolt|water, absorbs fire. An
earlier draft here read the opposed fire/bolt pair as vanilla's
weaknesses — that pair is in the ABSORB bytes, and neither Crane is
fire-weak. Vanilla's shared weakness is water.)

- **The Cranes' vanilla charge is element-driven rather than a
  fuse.** Read from `ai_script.asm`: both counters are in the COUNTER
  half of the script, gated on `if_element FIRE` / `if_element
  LIGHTNING`. The level rises only when the player hits a Crane with
  the element it absorbs, and the results are **Fire 3** and **Giga
  Volt**. There is a separate timer move (`if_battle_timer 60` →
  Magnitude8). This is not the one-ATB-cycle fuse the boss contract
  defines above, and an earlier draft claiming OT6 "inherits it,
  verbatim" was wrong. Giving the Cranes a telegraph that matches the
  contract is work that has not been done. "Break cancels the charge"
  is a design intent to build, not a vanilla behavior to inherit.
- **Break story:** this is the WoB's effective 12-shield fight: two
  live gauges with two fuses on independent clocks. Focus one Crane
  and the other's charge lands. Use the wrong element and you heal its
  sibling, since vanilla's absorbs are unchanged. The elemental key
  here is **water**, the shared vanilla weakness, plus **bolt on the
  Right Crane only**; the espers the factory has just paid out are the
  wrong answer.
  (An earlier draft of this line called "Ifrit's fire and Ramuh's
  bolt" the factory's own boss keys. Both heal: `$10E` absorbs fire
  and `$10D` absorbs bolt — `monster_prop.dat` +23, absorb, verified
  against +25, weak. That contradicted the decode note 18 lines above
  in this same section, which had it right.)
- **Jank:** they climb the hull mid-battle, and the wrong-element
  heal stays as the 1994 original shipped it.

## Esper Mountain

### 17. Ultros ③ — the rope bridge

Party: Terra + three.

**Shields:** 7 · **Weak:** the row ✦, third verse.

- **Telegraph:** tentacles again. By this point the player knows the
  pattern and breaks him without probing.
- **Break story:** the espers interrupt and end the fight on the
  script's schedule, regardless of break state. Breaking him before
  they arrive has no mechanical effect.
- **Jank:** the bridge drops him and not the party, as in vanilla.

## Thamasa

### 18. FlameEater — the burning house

Party: Terra, Locke, Strago (Shadow keeps the dog outside).

**Shields:** 7 (Balloons 1 each) · **Weak:** ice, water + piercing.
Balloons: 1 · ice, water.

(Decoded, not recalled: in vanilla `$116` weak = **ice only** —
`monster_prop.dat` +25 reads `$02` — with +24 `$6c` nulling
bolt|poison|holy|earth and +23 `$01` **absorbing fire**. Water above is
an OT6 add, not vanilla. `$0de` Balloon weak = `$82` = ice|water. An
earlier draft merged the two rows and gave the FlameEater the Balloons'
water bit *as vanilla*, which it never was.)

- **Telegraph:** it absorbs the room's fire and turns white →
  **Fireball** across the party. Break during the fuse to cancel it.
- **Break story:** this is Strago's first fight. **Analyze** reads the
  full row on turn one, and Aqua Breath is both the water chip *and*
  the AoE that clears the Balloons before they chain Exploder. The
  adds need AoE and the boss needs focused damage, so the fight
  alternates between the two. Terra's Fire heals the boss; this is the
  first mainline boss where the party's usual attack is the wrong
  one.
- **Jank:** Balloons still Exploder for their full HP, and the house
  burns down on the script's schedule regardless of how the fight
  goes.

## The Floating Continent approach

### 19. Ultros ④ + Chupon — the airship deck

Party: your chosen three (Shadow is waiting on the continent).

| part | shields | weak |
|---|---|---|
| Ultros ④ | 7 | fire, bolt, **poison** + slashing, piercing — the row, one bit *added* |
| Chupon | 4 | ice, water + bludgeoning |

(Decoded, not recalled: Ultros ④ is a **different species** from the
first three — `$168`, where the Lete/opera/gate fights are `$12c`/`$12d`/
`$12e` — and vanilla did not give it the same row. `monster_prop.dat` +25
reads `$09` = **fire|poison**, not the `$05` = fire|bolt the other three
carry; +23 still `$80`, water absorbed. So "the row, one last time" was
true of the classes, which `Ot6ShieldTbl` authors identically at
slash|pierce, and false of the elements: the bolt half of the family row
is an `Ot6ElemAddTbl` row, `$0168` `.byte $04`. Water is NOT added and
must not be — `$168` absorbs water, as does every Ultros record
(`+23 = $80`, all four). `$12f` Chupon weak = `$82` = ice|water.)

- **Telegraph:** Ultros's tentacles, for the last time. Chupon has no
  telegraph of his own. When Ultros has taken enough damage, Chupon
  inhales → **Sneeze**, and a character leaves the battle with no
  saving throw and no way to prevent it. The script runs regardless of
  break state, so the fight ends by script rather than by winning.
- **Break story:** this fight teaches not to hold BP. A sneezed
  character leaves with banked BP unspent, so spend it first. Break
  Ultros before the first Sneeze if you can (7 shields across three
  bodies, which is tight) and dump everything. Chupon's 4-shield gauge
  is optional, and not every lineup can break it, because it needs
  bludgeon.
- **Jank:** Sneeze still removes a character with no lasting penalty,
  and Chupon still has no dialogue.

### 20. AirForce — imperial air superiority

Same three, straight from the deck.

| part | shields | weak |
|---|---|---|
| AirForce | 8 | bolt, water + piercing |
| Laser Gun | 3 | bolt, water + piercing |
| MissileBay | 3 | bolt, water + piercing |
| Speck | 1 | bolt, water + any physical class |

(Decoded, not recalled: all four parts share one vanilla byte —
`monster_prop.dat` +25 = **`$84` = bolt|water** on `$113`, `$145`, `$147`
and `$146` alike, with +23/+24 both `$00`, so the assembly absorbs and
nulls nothing. An earlier draft dropped the water bit from three rows and
gave the MissileBay **fire**, which it has never been weak to. The Speck's
row is the one that differs: it is bolt|water-weak like the rest, but
the authored answer is still one shield and any physical class, because
the Speck's purpose is to absorb spells.)

- **Telegraph:** the missile bay racks and locks → **Launcher**
  barrage. Breaking the *bay* cancels it; breaking the body does not.
  This is one step up from Number 128.
- **Break story:** kill both pods and it deploys the Speck, which
  absorbs every spell you cast. That is vanilla behaviour and is
  preserved whole ✦. The answer is the Speck's single shield: any
  weapon in the game breaks it instantly, and the ×2 window then kills
  it. Bolt is the key throughout (Ramuh, or anyone who kept a bolt
  line), with piercing for lineups that did not.
- **Jank:** the IAF shooter sequence before it is unchanged.

## The Floating Continent

### 21. AtmaWeapon

Party: three + Shadow (forced).

**Shields:** 11 · **Weak:** fire, ice, bolt + slashing, piercing.
Vanilla has *no* weaknesses here; the whole row is added, and wide on
purpose — the FC party is a free pick plus Shadow, and any lineup must
hold at least two of these five axes. The capstone examines rhythm, not
roster.

- **Telegraph:** it gathers light for a full cycle → **Flare Star**.
  Its opening speech is flavour and has no mechanical effect. Mind
  Blast stays untelegraphed and can arrive mid-rotation, exactly as
  vanilla dealt it.
- **Break story:** 11 shields takes two to three full break cycles,
  with the fuse returning every rotation. Bank BP, break *on* the
  fuse, dump during the ×2 window, survive Mind Blast, and rebuild.
  The fight uses every lesson since Narshe (fuse-cancel, banking,
  absorbs) except part-breaks, since AtmaWeapon has no parts. It is
  the last WoB test of the system.
- **Jank ✦: the MP kill stays.** He has roughly 5,000 MP and dies at
  zero, so Rasp remains a valid but very slow answer. Breaks affect
  turns, not this.

### 22. Nerapa — the escape's doorman

Party: your three, during the continent's collapse.

**Shields:** 5 · **Weak:** ice, bolt, holy + slashing, piercing.
(Decoded, not recalled: `$118` weak = ice|bolt|holy and **absorbs
fire**. An earlier draft listed fire as a weakness — authoring that
would put a chip trigger on an absorber, where vanilla reverses the
damage sign — and dropped vanilla's ice and bolt, against the
"keep vanilla's bits ✦" rule at the top of this doc.)

- The fight opens *untelegraphed*, with **Condemned** on the whole
  party before your first input. That is vanilla's ambush, preserved.
  The Condemned countdown runs at the same time as the Floating
  Continent's own escape timer.
- **Telegraph:** it gathers the curse again → Condemned is reapplied,
  undoing any cleanses (script details on the audit list). Break to
  stop the countdown being reset.
- **Break story:** 5 shields on purpose. After Atma's 11, the low
  gauge sets the pacing: a short fight run under two timers,
  Condemned and the escape clock. Break fast, kill faster, and run.
  Shadow's wait-or-jump choice comes shortly afterwards and is
  outside this document's scope.

## Scripted set-pieces (no gauge drawn)

| scene | why it opts out |
|---|---|
| Tritoch (Narshe intro) | one-shots the trio; cutscene in battle clothes |
| Guardian (Vector) | invincible in the WoB — its script says come back later, and the silent HUD says so up front (confirm its WoB palace encounter at data entry) |
| Kefka ×2 (Imperial Camp) | no monster entity at all — formation 504 is empty and the fight runs on character AI `$04`; see 6 above |
| Chupon's Sneeze, Vargas's finish | in their blocks above: scripts beat state |

## Open questions for the driver

1. **Broken counters:** the proposal is that counters are disabled
   during Break, so Whelk's shell does not counter during the window.
   That matches Octopath, but it weakens the shell's lesson. Keep it,
   or let counters fire during Break?
2. **Ifrit/Shiva pinning:** a Broken sibling cannot tag out (Stop
   rules). Confirm this, or should a break force the swap instead and
   hand the window to the sibling?
3. **024's element row:** WallChange re-hides the element row
   mid-fight. Keep that or not? (Classes stay revealed either way.)
4. **Atma's added row:** fire/ice/bolt + slash/pierce is broad by
   design, because the party is a free pick. Narrowing it risks a
   lineup that cannot chip the fight at all.
5. **Chupon:** keep the 4-shield gauge, or draw him shieldless like
   Tritoch, given that Sneeze ends the fight regardless?
6. **Part-break feeding:** should breaking a limb chip the body 1
   (128, Cranes, AirForce)? v1 says no: parts pay in cancels, not in
   chip.
7. **Vanilla-script audit** (M6 data entry): TunnelArmor's quake =
   Magnitude8; Number 128's sweep = Gale Cut; Crane left/right
   element sides; Nerapa's full script; Telstar's reinforcement call;
   Guardian's WoB location. The poison bits on
   Marshal/Vargas/Kefka/Dadaluma are audited (decoded from
   `monster_prop.dat` +25, not recalled — the file is byte-identical
   to vanilla `$CF0000`):

   | species | id | weak byte | verdict |
   |---|---|---|---|
   | Marshal | $0064 | $08 poison | vanilla agrees — no add |
   | Vargas | $0103 | $08 poison | poison vanilla; **holy is an add** — authored (`Ot6ElemAddTbl`) |
   | Kefka (Narshe) | $014a | $00 — | **poison is an add** — authored (`Ot6ElemAddTbl`, `$09` with fire) |
   | Dadaluma | $0107 | $08 poison | vanilla agrees — no add |

   ($14a is the **Narshe defense** Kefka and nothing else. A scan of
   all 576 formation records puts him in exactly two, 489 (with the
   Ice Dragon) and 505, and 505 is what group 57 / `battle 57` reaches
   at event_main.asm:106362, the fight he "won't forget." The camp
   scenes share no record with him because they carry no monster at
   all; see 6 above. The $11a/$12a Kefka records are the level-83 and
   level-71 endgame ones, which are out of WoB scope.
   From the same pass: Ipooh $014d reads $01 fire, so the fire weak
   above is vanilla and not an add, and the chip keys are confirmed in
   the data, with AuraBolt ($5e) carrying $20 holy and BioBlaster's
   attack ($7d) carrying $08 poison in the vanilla spell records.)
