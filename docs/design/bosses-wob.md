# WoB bosses, boss by boss — design dive v1 (2026-07-16)

Scope: every boss and miniboss from Whelk through the Floating
Continent, in story order. **Status: v1 proposal for review** —
shield counts and weakness rows here are the first draft of the M6
hand-authored table (replacing the demo's 2+level/8 formula for
these fights). Nothing is locked except explicit ✦, and most ✦ below
are jank preservations the house rule already demands.

## The boss contract

Stated once, assumed by every block:

- **One telegraph per boss.** The boss announces its big move on its
  turn ("gathering power" register), and it detonates on its next —
  one full ATB cycle of fuse. **Breaking the boss during the fuse
  cancels the move outright**; the charge does not resume on
  recovery, it must be re-lit. Everything else in the fight stays
  vanilla AI.
- **Breaks don't get a boss nerf.** Turn loss and ×2 apply to
  AtmaWeapon exactly as to a Lobo. Shields are the only boss knob.
- **Scripts beat state.** Scripted beats — Vargas's Pummel finish,
  Chupon's Sneeze, the espers crashing Ultros's bridge party — fire
  regardless of break state. The gauge is a combat system, not a
  story editor. (Kefka's camp flees used to head this list. They
  turned out to have no state to beat — no monster, no gauge; see 6.)
- **Proposed ruling: counters sleep while Broken.** A Broken enemy
  loses its counters along with its turns (Whelk's shell goes quiet
  for the window). Octopath-faithful; driver call, open question 1.
- **A shieldless nameplate is information.** Scripted set-pieces
  (Tritoch, Guardian, the Imperial Camp Kefka) draw no gauge at all —
  the HUD's silence tells the player this one is theater.

Numbers below are shields only; boss HP falls under the global
−25–35% cut and is tuned in M6. Elemental rows keep vanilla's bits
wherever they exist ✦ (weapon-classes.md); every *added* element or
class is justified by the coverage rule — the party the story hands
you must be able to chip. Before Zozo the proofs lean on kits.md's
learn schedules; from Zozo on, magicite makes fire/ice/bolt roughly
party-independent, and the proofs lean on both.

Recurring bosses lean on the codex: Ultros keeps one weakness row
through all four fights — revealed at the Lete, remembered forever —
and his shields grow instead. The player learns; Ultros doesn't.

## The curve at a glance

| # | Boss | Where | Shields |
|---|---|---|---|
| 1 | Whelk (head) | Narshe intro | 4 |
| 2 | Marshal | Narshe escape | 4 (Lobos 2) |
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
| 17 | Ultros ③ | Sealed Gate | 7 |
| 18 | FlameEater | Thamasa | 7 (Balloons 1) |
| 19 | Ultros ④ + Chupon | FC approach | 7 + 4 |
| 20 | AirForce | FC approach | 8 (pods 3/3, Speck 1) |
| 21 | AtmaWeapon | Floating Continent | 11 |
| 22 | Nerapa | FC escape | 5 |

The shape: 4s at the start, scenario capstones at 6, an act-two
plateau of 6–7 where difficulty scales by *parts and simultaneity*
(the Cranes are 12 shields of monster across two gauges) before raw
size does, one 8, the 11-shield apex, then a deliberate 5-shield
coda under a timer. No single WoB gauge exceeds 11 — 12 is WoR
headroom.

---

## Narshe intro

### 1. Whelk — the mines

Party: Terra between Vicks and Wedge, all Magitek (fire/bolt/ice
beams; Terra adds TekMissile and Bio Blast).

| part | shields | weak |
|---|---|---|
| Head | 4 | fire + piercing |
| Shell | — (no gauge) | — |

- **Telegraph:** the Whelk draws into its shell and the shell hums
  with charge → **MegaVolt** sweeps the party. Break the head during
  the fuse to ground it.
- **Break story:** the guards warn you off the shell; Fire Beam is
  the guided probe. Three beams and a TekMissile and the game's
  first boss is Broken inside two rounds — the tutorial is the
  pillar in miniature: probe, chip, break, dump.
- **Jank ✦:** touch the shell, eat the MegaVolt counter — exactly
  vanilla, still lethal at level 1. Under the proposed ruling it
  sleeps only during the head's break window.

### Tritoch — (scene, not a fight)

The frozen esper one-shots the Magitek trio: a cutscene in battle
clothes. No shields, no gauge drawn — the system's first
demonstration that a silent HUD means theater.

## Narshe escape

### 2. Marshal — the moogle defense

Party: Locke, Mog, and ten moogles in three squads.

**Shields:** 4 · **Weak:** poison + piercing. Lobos: 2 · fire +
piercing.

- **Telegraph:** the Marshal levels his blade and whistles the pack
  in → next turn he and both Lobos converge on one target. Break him
  and the dogs mill around leaderless.
- **Break story:** twelve bodies means BP everywhere and damage
  nowhere; moogle spears chip him steadily and the break saves
  whichever squad he's mauling. Mog's fight, Mog's class — piercing
  featured, exactly the snowfield's armory.
- **Jank:** the three-squad control scheme stays byte-for-byte,
  weird vanilla moogle gear included; all squads down is still a
  game over.

## Mt. Kolts

### 3. Vargas (+ two Ipoohs)

Party: Terra, Locke, Edgar — Sabin storms in at the midpoint with
Pummel and, at vanilla level 6, almost certainly AuraBolt too. (An
earlier draft put AuraBolt at level 10 and treated it as a maybe; it
is level 6, so plan the fight assuming holy chip is present.)

MEASURED, in `battle_vargas.lua` off the rung-2 fixtures: he seeds
**5/5 with class row $04 (bludgeoning)**, the Ipoohs 2/2 slash-weak,
and his weak byte reads **$28 — poison|holy**, the holy bit being
`Ot6ElemAddTbl`'s add on top of vanilla's poison. "Storms in at the
midpoint" is literal and structural, not flavour: Sabin gets **no
turns at all** until Vargas's own reaction script fires
`battle_event $07/$08` (hp ≤ 10880, then ≤ 10368,
`ai_script.asm:4392-4404`) and blows the trio offstage. He joins at
level 9 on this route, so AuraBolt is present as planned; AuraBolt
takes a shield and reveals holy, Pummel takes another and reveals the
bludgeon class, and that same Pummel is what kills him.

Edgar's BioBlaster is measured too now, and it carries a correction to
the break story below. The poison chip itself works exactly as planned —
item `$a4` resolves to attack `$7d`, element `$08`, and it takes a
shield and reveals poison, while the same party's plain weapon swings
land on Vargas and move nothing (`battle_vargas.lua`'s control). But
**it cannot reach him while an Ipooh is alive.** BioBlaster's item
targeting byte is `$6a` — group-targeting with `$01 MANUAL` *clear*, so
the cursor cannot be walked — and `key_target_2`'s INIT_GROUP branch
(`btlgfx_main.asm @7875`) aims at monster group A and only falls
through to group B when A is empty. This formation is Ipoohs in A,
Vargas alone in B. Measured over one fight: seven straight BioBlasters
into the Ipoohs' group ($06, then $04 once the first died) before the
eighth found him ($01), ~9500 frames in.

**Shields:** 5 · **Weak:** poison, holy + bludgeoning. Ipoohs: 2 ·
fire + slashing.

- **Telegraph:** he drops into his wind stance → **Gale Cut** rakes
  the party (the same sweep the script later uses to blow the trio
  offstage — his one named move, promoted to the fuse).
- **Break story:** phase one is deliberately low-chip — BioBlaster's
  poison spray is the trio's only key, chipping Vargas 1 through the
  bear screen while the script insists you're losing. Then Sabin
  arrives and the chip engine starts: Pummel ×2 bludgeoning,
  AuraBolt for holy. Mechanics and narrative agree: you couldn't
  break him without the monk. **The escorts gate the key** (measured,
  above): the spray goes to the Ipoohs' target group until both are
  down, so phase one reads clear the adds, *then* spend the tool —
  which is a better beat than the design assumed, and free.
- **Jank ✦: the Blitz gate stays.** Doom Fist's Condemned countdown
  on Sabin, the Pummel-input finish, all of it — he dies to the
  script, not to HP. Breaking him is setup, not checkmate: what the
  ×2 window buys is calm — free turns to land the input while he
  stands there Broken. And the absurd for-real kill (11,600 HP at
  level 10) stays possible, because of course it does.

## Lete River

### 4. Ultros ①

Party: Terra, Locke, Edgar, Sabin, Banon (Health is a free party
heal; his death is a game over).

**Shields:** 5 · **Weak:** fire, bolt + slashing, piercing — the row
he keeps all game.

- **Telegraph:** two tentacles rise dripping → **Tentacle** slams
  Banon. Break to save the old man.
- **Break story:** Banon makes stalling survivable, so the fight
  teaches banking: probe fire — he yowls about seafood — sit at 2–3
  BP, break on the fuse, boosted-Fight dump. First fight where the
  fuse-cancel has a loss condition attached. (Yes, AutoCrossbow
  shreds him. He's the tutorial's victory lap; let him fall over.)
- **Jank ✦:** Ink inflicts Dark, and Dark — evade bug — does
  nothing. It stays doing nothing. The fire yelp fires every time;
  he flees, as always, undefeated in his own mind.

## The split — three scenarios, three proofs

The coverage rule's stress test (weapon-classes.md). Terra and
Banon's leg through the caves is the deliberate breather: no boss —
their exam is the Narshe defense. Per-party notes below.

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

- **Telegraph:** the drill spools down and the tunnel groans → its
  buried quake (Magnitude8 — audit list). **Runic eats it.** The
  fight has two right answers — Runic the quake (vanilla's tutorial)
  or break the machine first (ours) — and the best answer is both,
  since Runic converts the telegraph into +1 BP ✦ (kits.md): the
  boss's biggest move literally funds the break.
- **Break story:** Mug and daggers pierce-chip, Ice chips, and 5
  shields across two bodies lands the break right around the first
  fuse. Small fight, complete grammar. Note what the coverage rule is
  actually resting on here: both vanilla element bits are dead keys
  for this duo, so the whole proof is the added Ice plus the piercing
  class. Narrow either and the fight has no chip engine at all.

### 6–7. Imperial Camp (Sabin, with Shadow drifting in and out)

**Kefka ×2: no gauge — there is no monster in this fight.** (Decoded,
not recalled.) Both gags run `battle 56, IMP_CAMP` (event_main.asm
:40683 and :40743). Group 56 in `event_battle_group.dat` points both
its slots at **formation 504**, and formation 504 in
`battle_monsters.dat` (+`$1d88`) is `00 00 ff ff ff ff ff ff 00 00 00
00 00 00 3f`: the present mask is **`$00`** and all six id slots are
`$ff` with byte 14 = `$3f` setting every high bit — six copies of
`$1ff`, vanilla's empty-slot sentinel (battle_main.asm:7720). Nothing
is loaded. What `battle_prop.dat` (+`$7e0`) enables instead is
**character AI script `$04`**, `kefka_imp_camp_1`, whose slot 0 is
`CHAR_PROP::KEFKA_1|CHAR_AI_FLAG_ENEMY_CHAR` (char_ai.asm:163) — and
the event has already dressed a party slot as him on the way in:
`char_prop VICKS, KEFKA_1` (event_main.asm:40675; CHAR::VICKS = 15,
CHAR_PROP::KEFKA_1 = `$29`).

So the clown you punch at the camp is a **character actor** wearing
Kefka's name, sprite and palette, flipped to the enemy side and
running monster AI script `$016f`. He has character HP, which is why
the event can revive and refill him between rounds with `clr_status
VICKS, DEAD` / `max_hp VICKS` (event_main.asm:40739). No `MonsterProp`
record is ever read for him: no weak byte, no absorb byte, no shield
seed — `Ot6SeedShields` is reached only from the monster/rage load and
returns immediately for character entity offsets in any case
(ot6.asm:43).

**An earlier draft gave these fights 3 shields · poison + slashing.
That is unimplementable as written** — there is no monster entity to
hang a species row on, and the per-formation hook that would be needed
to gauge a character actor is a feature, not a table row.

Which is the right answer anyway: the gags are theater and should read
as theater. He takes a few hits and flees, twice, waiter line intact,
and the silent HUD says so up front — Tritoch's rule, one scenario
later. If a future pass genuinely wants a breakable clown here, that
is new machinery and belongs in the roadmap, not in the shield table.

**Telstar:** 4 shields · bolt + bludgeoning (Dobermans 2 · piercing).
- **Telegraph:** its antenna sparks and it radios for backup → a
  Doberman wave piles in next turn. Break to jam the call — the
  first *summon-prevention* break; the verb returns at FlameEater.
- **Jank:** a treasure chest that fights back stays a treasure chest
  that fights back.

### 8. GhostTrain — the Phantom Train (Sabin, Cyan, Shadow)

**Shields:** 6 · **Weak:** fire, bolt, holy + bludgeoning ·
**absorbs poison.** (Decoded, not recalled: `$106` weak =
**fire|bolt|holy** — `monster_prop.dat` +25 reads `$25` — and +23
reads **`$08`, poison absorbed**; +24 is `$00`. An earlier draft
dropped vanilla's bolt bit and never mentioned the absorb at all.)

- **Telegraph:** the whistle screams down the corridor → **Evil
  Toot**, party-wide status roulette. Break the boiler before the
  note lands; Acid Rain between fuses keeps the healing honest.
- **Break story:** the scenario's gifts are the keys — AuraBolt is
  holy chip at range, Pummel ×2 grinds, and Shadow's elemental skeans
  probe two of the three element bits, not one: Fire Skean is fire
  (item `$ab` → spell `$51`) and Bolt Edge is bolt (`$ad` → `$53`),
  both legal chips once vanilla's bolt bit is back in the row where it
  belongs. Cyan can't chip his own scenario's capstone, and
  that's deliberate: the Phantom Train farewell is where **Oblivion**
  unlocks (kits.md), and Oblivion wants Broken targets — the train
  is his divine's first legal kill. Break it FOR him.
- **Jank ✦: Suplexable, forever.** The most famous jank in the game
  is now also mechanically *correct* — Suplex is bludgeoning, the
  train is bludgeon-weak; the system canonizes the meme. The undead
  flag stays too: one Fenix Down ends it instantly, break state be
  damned. Cheese outranks systems; house rule.
- **Jank ✦: poison HEALS the Phantom Train.** Vanilla, so it stays —
  but it needs writing down where an author will hit it. Edgar's Bio
  Blaster is poison: the Throw/Tools table maps item `$a4` to spell
  `$7d` (battle_main.asm:6577) and that spell's element byte is `$08`.
  The Narshe school's rung-2 seed once teased that tool as the answer to
  armored things ("Every armor fears one right tool", narshe-school.md) —
  a framing the v0.6 break pass retired and the seed's own rewrite has
  since dropped (see "The imperial soldier line"), but the poison-heal
  trap here is vanilla and stands regardless. Point
  Bio Blaster at this boss and vanilla's absorb branch
  flips the damage sign and jumps clear past the weakness branch where
  the shield chip lives (battle_main.asm:1850, chip at :1872): the hit
  heals the train *and* chips nothing. Nothing is broken today —
  Edgar is on Terra's leg and this party carries no poison — so the
  trap is latent, not live. Do not hang a poison beat on the Phantom
  Train, and re-read this before routing Edgar onto it.
- **The train is a poison dead zone, boss *and* chest.** Decoded while
  authoring the armor line: `$0156` Specter — the monster-in-a-box in
  this same scenario (map 153, treasure 114 → event battle group 34 →
  formation 476) — also **absorbs poison** (+$2ad7 = `$08`), and is
  fire|holy weak in vanilla (+$2ad9 = `$21`). So the one element the
  v0.3 arc teaches is the one element that fails twice on this train.
  Specter gets **no authored row**: vanilla's fire and holy are both
  live keys here (Shadow's Fire Skean, Sabin's AuraBolt — the same two
  the break story above already leans on), and adding poison would put
  a chip trigger on an absorber, the exact error caught in draft at
  Nerapa and the Cranes.

### 9. Rizopas, after the Piranha school — Baren Falls (Sabin + Cyan)

**Shields:** 5 (Piranhas 1) · **Weak:** bolt + slashing, bludgeoning.

- **Telegraph:** the falls swell backward → **El Nino** crashes the
  party.
- **Break story:** the poster child of the coverage rule. Bolt is
  vanilla's fish bit and *neither man can cast it* — so the weapon
  byte carries the fight: Pummel and Fang/Tiger chip regardless, and
  Flurry (if the scenario got Cyan to 15) shreds 4 at a time. When
  the story strands you without an element, the classes are the
  floor under your feet.
- **Jank:** the Piranha chum-wave stays a wave — they nibble, they
  die, they teach AoE. Gau and the dried meat are waiting one screen
  later.

## The reunion — Narshe defense

### 10. Kefka and the raiding party

Party: all seven, three squads on the snowfield.

**Shields:** 6 · **Weak:** poison, fire + piercing, slashing.

**Authored, and the whole row is an add.** `$014a`'s vanilla weak byte
(`monster_prop.dat` +$2959) is `$00` — the arc's final boss shipped with
no weakness of any kind — so `Ot6ElemAddTbl` carries `$09` (poison|fire)
outright; +$2957/+$2958 are both `$00`, so nothing is absorbed or
nulled. The 6 shields and the two classes were already in
`Ot6ShieldTbl`. Kefka himself stays **wide** — poison|fire + piercing,
slashing — so any squad you route to him can break him. His **waves**
(Trooper, HeavyArmor, Rider) used to lean on the same poison the school
sold, which only the Edgar squad could cast; the v0.6 pass gave them
slash\|pierce class rows so every player-assigned squad has a key (see
"The imperial soldier line" below).

- **Telegraph:** he giggles and frost crawls the ground → **Ice 2**
  across the engaged squad.
- **Break story:** the waves drain resources before the man himself,
  so the fight teaches banking across a gauntlet — earn BP on trash,
  arrive at the clown holding 4–5, break him on the first fuse. The
  wide row (his snow-mage kit inverted: melt him, poke him, cut him)
  means any squad you route to him can do it — but the squad layer
  makes it *your* routing problem, which is the whole charm.
- **Jank:** the strategy layer stays untouched, and his spell list
  stays court-mage petty. He hasn't eaten any gods yet.

## The imperial soldier line — every party gets a key

Not bosses, but authored here because this is where the weakness data
lives, and because the **v0.6 break-coverage pass rewrote the whole
idea.** (This section replaces the old "one right tool" writeup, kept in
git history.)

**The doctrine that was.** The Narshe school's rung-2 seed promised "their
armored machines shrug off blade and fire alike… Every armor fears one
right tool" (narshe-school.md), the tool being Edgar's Bio Blaster
(poison, `$08`). Four species got a poison `Ot6ElemAddTbl` add so the
seed would not be a lie. It made **poison the sole key to the imperial
line.**

**Why that broke.** The fixed-party audit walked every forced section and
found the hole: **the parties that actually fight this line carry no
Edgar, so no poison.** Cyan's solo Doma duel is slash-only; Sabin's whole
scenario has no poison; Locke solo in occupied South Figaro is
pierce-only; the Narshe defense is a player-assigned 3-way split where at
most one squad holds Edgar. So "one right tool = poison" left the
imperial line **unbreakable by the exact party the game hands you.**

**The fix: a weapon class, chosen per the forced party.** Poison is no
longer special — it is one Edgar-reachable key among several. Each
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

Shields track the early-war band (2 basic infantry, 3 for the elite /
heavier / duel bodies). **Class chips ignore absorb/null**, so
HeavyArmor's vanilla water-absorb and everyone's stray element bits never
sour the break — the class is a clean, always-legal key.

**The palette (owner's taste).** Armored soldiers read as **pierce** (a
blade finds the gaps) with **lightning** where a party can conduct it:
the machines (M-TekArmor, HeavyArmor) are natively bolt-weak in vanilla,
and Templar gains bolt (`$04`) here for Shadow's Bolt Edge at the camp.
The Cyan SOLO duel is **slash** — the samurai out-cuts them, and it reads
as a swordfight. Sabin's brawls add **bludg** — a monk caves the plate.
Deliberately *varied*, not a blanket row: the key is whichever hero is
standing in front of the enemy.

**Element table, after the pass.** M-TekArmor and HeavyArmor keep their
poison adds — a party that fights them can cast it (Shadow's bolt at the
camp; Edgar at the Narshe waves), on top of vanilla bolt. **Leader and
Grunt lost their poison adds**: those were the pure "one tool" artifacts,
the two species with *no* vanilla weakness at all, and poison is
unreachable in both their forced fights (a solo duel; a Cyan+Sabin
defense), so the add was dead data that also drew an unresolvable `?` on
a fight the class row already answers. Templar's row verified `$00/$00`
at +$17/+$18 before authoring, the same discipline the rest of the table
holds to.

**Trooper and Rider are the reversal worth naming.** The old writeup left
them element-only ("vanilla already agrees, no row needed") because they
are poison-weak in vanilla. But the Narshe defense is *semi-free* —
squads are player-assigned, and a Cyan+Sabin or Locke+Gau squad reaches
neither poison nor any vanilla element on these bodies. So v0.6 gives
both a slash\|pierce class row: vanilla poison stays the Edgar squad's
key, the class is every other squad's. Formation 88 (Trooper+HeavyArmor,
`battle 23`, event_main.asm:108505) now opens to whatever a squad holds,
not to Edgar alone.

**M-TekArmor gets no new row** — it is already breakable by the party
that fights it (Shadow's Bolt Edge / the Magitek bolt beam at the camp),
so it was never a gap; it carries the bolt half of the palette natively.

**The school seed now matches, by design.** The rung-2 dialog ($0276) was
rewritten under the school's own story/dialog sanction (narshe-school.md's
fence) to teach the new fiction — armor turns a careless blow aside, but
every plate has a seam, and no two are the same; bring the weapon that
fits. Both of the old promises are gone: a precise blade *is* the answer
(pierce/slash), and there are several tools, not one. The class rows are
the mechanic; `school.lua` now pins the new dialog bytes, so text and data
fail separately if either drifts.

**The one place theme bent to coverage.** The palette's default for
armored soldiers is pierce+bolt, but the Doma courtyard defense party
(Sabin bludg + Cyan slash) can cast *neither* pierce nor bolt. Grunt and
Cadet therefore take slash\|bludg rather than the default — the owner's
"Sabin's brawls are bludgeon" rule is exactly the escape hatch. Called
out so a future author doesn't "correct" them back to pierce and re-open
the gap.

## The Serpent Trench — three aquatics, three keys

Sabin + Cyan + Gau ride the trench (`battle 19`/`20`/`21`, UNDERWATER,
event_main.asm:21194+; the party is placed together at the ride's entry
`_ca8ae3`). Their melee ring is **bludg** (Sabin), **slash** (Cyan) and
**pierce** (Gau's Hardened). Every trench aquatic was a formula species
whose vanilla element the party can't reach — Anguiform is bolt-only (no
bolt in the party) and Actaneon/Aspik are fire-weak but Sabin's Fire
Dance is L15-gated — and all three **absorb water**, so a careless
element add would heal them. Class is the clean answer, and the trio's
three keys map one-to-one onto the three creatures:

| species | id | shields · class | thematic |
|---|---|---|---|
| Anguiform | `$003A` | 2 · slash | a slippery eel, cut by Cyan's blade |
| Actaneon | `$005E` | 2 · bludg | a shelled crustacean, cracked by Sabin's fists |
| Aspik | `$0059` | 2 · pierce | a coiled asp, punctured by Gau's fanged strike |

Vanilla bits are kept (dead or level-gated for this party, live for a
later party that carries the element); class chips ignore the
water-absorb.

## Break coverage — the free-roam floor (#6)

- **The free-roam tail — now floored.** `Ot6SeedShields`' `@formula`
  fallback used to *clear* the class-weak mask (`$3e9c`), leaving an
  un-authored enemy breakable only by whatever element it happened to carry
  (and unbreakable with none). It now seeds a per-species **floor class**
  instead: `sta $3e9c,y` reads `OT6_FLOOR_CLASS[species]`, a build-time table
  generated by `ff6/tools/gen_break_floor.py` from the monster names, so
  *every* un-authored body is breakable by some weapon class. The palette
  follows the authored taste — armored/mechanical/dragon/insect → **pierce**,
  brute/ooze/golem/monk → **bludgeon**, beasts/humanoids/casters → **slash**
  (the honest remainder). Authored `Ot6ShieldTbl` rows still win (the `@hit`
  path overwrites the mask); the floor only fills the gap. `battle_breakfloor`
  is the regression gate — it asserts all 384 species carry a breakable class.
  Pacing impact (universal breakability = more breaks) is a playtest/balance
  matter, like the Kolts shield-count sweep.
- **Tentacle_2 / Tentacle_3 (`$013D`/`$013E`) — out of WoB scope, by
  intent.** They trace to the World-of-Ruin Figaro engine room, past this
  document's World-of-Balance frontier. The floor gives them a class like any
  other species, but their fight lives in the WoR; revisit their break design
  with the WoR pass, not as a WoB gap.

### 11. Dadaluma

Party: any four of the seven.

**Shields:** 6 (Iron Fists 2) · **Weak:** poison + piercing,
bludgeoning — every possible pick of four holds at least one of the
two classes; most hold both.

- **Telegraph:** he coils for the rafters → **Jump**, untargetable,
  lands on a skull. Break the crouch and he never leaves the ground
  — canceling a Jump by breaking the jumper is the most satisfying
  sentence in this document.
- **Break story:** thugs at half health, potions from his own
  pockets — chip through the screen with AoE piercing
  (AutoCrossbow), bank, break the crouch.
- **Jank:** the mid-fight self-care stays; a boss rummaging for a
  Tincture is Zozo in one image. Jump's airborne vanish stays
  vanilla jump jank.

## Opera → Vector → the factory

### 12. Ultros ② — the opera stage

Party: Locke + three (Celes is mid-aria).

**Shields:** 6 · **Weak:** the row ✦ (fire, bolt, slashing,
piercing — revealed at the Lete, still revealed; the codex working
as designed).

- **Telegraph:** the same tentacle wind-up — the player greets it
  like an old friend. Recurring boss, remembered row, rising gauge:
  the running gag lives *inside* the telegraph system now.
- **Break story:** no Banon to babysit this time; the tentacle aims
  at whoever you can least afford. One more shield than the river,
  minus the free healer — same fight, honest difficulty.
- **Jank:** the battle happens on stage and the show absorbs it; the
  Impresario would call the break window "act three."

### 13. Ifrit & Shiva — Magitek Research Facility

Party: Locke, Celes + two.

| part | shields | weak |
|---|---|---|
| Ifrit | 6 | ice + piercing |
| Shiva | 6 | fire + slashing |

- Vanilla's tag fight: they swap in and out; each keeps its own
  gauge across swaps. **A Broken sibling can't tag out** — the swap
  is a turn, and Broken have none. Breaking pins them on stage.
- **Telegraph:** Ifrit inhales, the air shimmering → **Fire 2**;
  Shiva mirrors with **Ice 2**. Whoever's out runs their own fuse.
- **Break story:** the first hard absorb lesson — feed Ifrit fire
  and he thanks you. Celes chips both siblings alone (Ice into
  Ifrit, sword into Shiva): the Rune Knight against the elements, on
  brand. The fight still ends in recognition, not death — the Ramuh
  script stays.

### 14. Number 024 — the specimen guard

Party: Locke, Celes + two.

**Shields:** 7 · **Weak:** *rotating* — WallChange re-rolls the
elemental wall every few turns and re-hides the element row when it
does. Classes fixed: slashing + piercing, the handhold while the
wall spins.

- **Telegraph:** the wall hums to a color → the matching tier-2
  spell (Fire 2 / Ice 2 / Bolt 2). The fuse is also intel: it casts
  its own wall, so the charge names the current *absorb* — invert
  your probe from there.
- **Break story:** the anti-codex boss. Physical chip is steady;
  magic is a read-the-wall minigame; a break locks the current wall
  revealed until the next WallChange scrambles it. The one enemy in
  the WoB whose homework doesn't stay done.
- **Jank:** WallChange stays truly random, back-to-back same-wall
  rolls included. The RNG owes you nothing.

### 15. Number 128 — the minecart

Party: same four, on rails.

| part | shields | weak |
|---|---|---|
| body | 7 | bolt, water + piercing |
| Left/Right blades | 3 each | bolt + slashing |

- Blades regenerate a few turns after dying — vanilla ✦ — and
  regrown blades return at full shields (their row stays revealed;
  codex).
- **Telegraph:** both blades rise and hum → the whole-side sweep
  (Gale Cut — audit list). Breaking *either blade* drops the pitch
  and cancels it: the first fight where a part-break is the answer.
- **Break story:** first battle after Zozo hands you four espers — a
  Ramuh bearer casting Bolt into the body is the sub-job system's
  opening statement (magicite.md's storm-lancer, right on cue).
- **Jank:** regrowth timing stays vanilla; the minecart shooter
  around it stays byte-for-byte.

### 16. Left & Right Cranes — the Blackjack's rigging

Party: the factory four (Setzer is flying the getaway).

| part | shields | weak |
|---|---|---|
| Left Crane ($10D) | 6 | water + piercing |
| Right Crane ($10E) | 6 | bolt, water + piercing |

(Decoded from `monster_prop.dat` +25, not recalled: `$10D` weak =
water, absorbs bolt; `$10E` weak = bolt|water, absorbs fire. An
earlier draft here read the opposed fire/bolt pair as vanilla's
weaknesses — that pair is in the ABSORB bytes, and neither Crane is
fire-weak. Vanilla's shared weakness is water.)

- **The Cranes' vanilla charge is element-driven, not a fuse.** Read
  from `ai_script.asm`: both counters live in the COUNTER half of the
  script, gated on `if_element FIRE` / `if_element LIGHTNING` — the
  level rises only when the player hits a Crane with the element it
  absorbs, and the payoffs are **Fire 3** and **Giga Volt**. There is
  a separate genuine timer move (`if_battle_timer 60` → Magnitude8).
  So this is NOT the one-ATB-cycle fuse the boss contract defines
  above, and an earlier draft claiming OT6 "inherits it, verbatim"
  was wrong. Giving the Cranes a contract-shaped telegraph is real
  work, not free. "Break cancels the charge" is a design intent to
  build, not a vanilla behavior to inherit.
- **Break story:** the WoB's effective-12 moment: two live gauges,
  two fuses on independent clocks. Tunnel one Crane and the other's
  charge lands. Splash the wrong element and you heal its sibling —
  vanilla's absorbs, unsoftened. The factory paid out its own boss
  keys: Ifrit's fire and Ramuh's bolt, acquired two fights ago.
- **Jank:** they climb the hull mid-battle; the wrong-element heal
  stays exactly as rude as 1994 shipped it.

## Sealed Gate

### 17. Ultros ③ — the rope bridge

Party: Terra + three.

**Shields:** 7 · **Weak:** the row ✦, third verse.

- **Telegraph:** tentacles, again. By now the player breaks him on
  reflex, which is the joke — he's a tutorial that believes he's a
  capstone.
- **Break story:** the espers crash the party and end the fight on
  their own schedule (scripts beat state); breaking him before the
  stampede arrives is pure style points. Award yourself them.
- **Jank:** the bridge drops him, not you. Octopus priorities stay
  vanilla.

## Thamasa

### 18. FlameEater — the burning house

Party: Terra, Locke, Strago (Shadow keeps the dog outside).

**Shields:** 7 (Balloons 1 each) · **Weak:** ice, water + piercing.

- **Telegraph:** it drinks the room's fire and swells white →
  **Fireball** across the party. Break to swallow the flame with it.
- **Break story:** Strago's debut showcase — **Analyze** reads the
  full row on turn one (the party's scout tool, working its first
  boss), and Aqua Breath is both the water chip *and* the AoE that
  clears Balloons before their Exploder cascade. Adds want AoE, the
  boss wants focus: the housefire juggle. Terra learns the other
  lesson — her beloved Fire heals it. First mainline boss that
  punishes the favorite button.
- **Jank:** Balloons still Exploder for their full HP; the house
  burns down on schedule regardless of your elegance.

## The Floating Continent approach

### 19. Ultros ④ + Chupon — the airship deck

Party: your chosen three (Shadow is waiting on the continent).

| part | shields | weak |
|---|---|---|
| Ultros ④ | 7 | the row, one last time |
| Chupon | 4 | bludgeoning |

- **Telegraph:** Ultros's tentacles, final verse. Chupon doesn't
  telegraph — Chupon *is* the telegraph: when Ultros has had enough,
  the pink one inhales → **Sneeze**, and someone leaves the battle,
  no save, no appeal. Scripts beat state; this fight cannot be won,
  only survived with panache.
- **Break story:** the BP tax lesson. Sneezed characters exit with
  their banked BP unspent — so spend it. Break Ultros before the
  first Sneeze if you can (7 shields, three bodies: tight), dump
  everything, exit laughing. Chupon's 4-shield gauge is a joke your
  lineup isn't guaranteed to be able to tell — no bludgeon, no
  bragging rights.
- **Jank:** Sneeze stays total and harmless; Chupon stays wordless.
  The gag outranks the reward.

### 20. AirForce — imperial air superiority

Same three, straight from the deck.

| part | shields | weak |
|---|---|---|
| AirForce | 8 | bolt + piercing |
| Laser Gun | 3 | bolt + piercing |
| MissileBay | 3 | fire + piercing |
| Speck | 1 | any physical class |

- **Telegraph:** the missile bay racks and locks → **Launcher**
  barrage. Breaking the *bay* — not the body — is the cancel:
  part-break graduation, one step up from Number 128.
- **Break story:** kill both pods and it deploys the Speck, which
  eats every spell you cast — vanilla's meanest gimmick, preserved
  whole ✦. The system's answer is one shield: any weapon in the
  game breaks the Speck instantly, then ×2 deletes it. The meanest
  gimmick meets the cleanest counter. Bolt keys throughout (Ramuh,
  or anyone who kept a bolt line), piercing for lineups that
  didn't.
- **Jank:** the IAF trash gauntlet before it stays the game's only
  shmup.

## The Floating Continent

### 21. AtmaWeapon

Party: three + Shadow (forced).

**Shields:** 11 · **Weak:** fire, ice, bolt + slashing, piercing.
Vanilla has *no* weaknesses here; the whole row is added, and wide
on purpose — the FC party is a free pick plus Shadow, and any
lineup must hold at least two of these five axes. The capstone
examines rhythm, not roster.

- **Telegraph:** the speech is the lore; the charge is the law. It
  gathers light for a full cycle → **Flare Star**. Mind Blast stays
  an untelegraphed mid-rotation nuisance, exactly as vanilla dealt
  it.
- **Break story:** 11 shields is a commitment — two to three full
  break cycles, the fuse returning every rotation. Bank, break *on*
  the fuse, dump the ×2 window, weather Mind Blast, rebuild. Every
  lesson since Narshe (fuse-cancel, banking, absorbs, part-breaks
  removed — no parts to lean on here) sits in one gauge. The WoB
  final exam.
- **Jank ✦: the MP kill stays.** Roughly 5,000 MP and death at
  zero — Rasp remains a legitimate, hilarious, extremely slow
  answer. Breaks guard turns, not cheese.

### 22. Nerapa — the escape's doorman

Party: your three, with the continent collapsing behind them.

**Shields:** 5 · **Weak:** ice, bolt, holy + slashing, piercing.
(Decoded, not recalled: `$118` weak = ice|bolt|holy and **absorbs
fire**. An earlier draft listed fire as a weakness — authoring that
would put a chip trigger on an absorber, where vanilla reverses the
damage sign — and dropped vanilla's ice and bolt, against the
"keep vanilla's bits ✦" rule at the top of this doc.)

- The curse opens *untelegraphed*: **Condemned** on the whole party
  before your first input — vanilla's ambush, preserved. The
  countdown is the real boss, and the FC's own escape timer is
  counting behind it.
- **Telegraph:** it gathers the curse again → re-Condemned, undoing
  any cleanses (script details on the audit list). Break to keep
  your counters where you put them.
- **Break story:** 5 shields on purpose. After Atma's 11, the low
  gauge *is* the pacing: a sprint fight under three timers —
  Condemned, the escape clock, your patience. Break fast, kill
  faster, run. Shadow's cruel wait-or-jump choice is thirty seconds
  away and no business of this document's.

## Scripted set-pieces (no gauge drawn)

| scene | why it opts out |
|---|---|
| Tritoch (Narshe intro) | one-shots the trio; cutscene in battle clothes |
| Guardian (Vector) | invincible in the WoB — its script says come back later, and the silent HUD says so up front (confirm its WoB palace encounter at data entry) |
| Kefka ×2 (Imperial Camp) | no monster entity at all — formation 504 is empty and the fight runs on character AI `$04`; see 6 above |
| Chupon's Sneeze, Vargas's finish | in their blocks above: scripts beat state |

## Open questions for the driver

1. **Broken counters:** the proposal says counters sleep during
   Break (Whelk's shell goes quiet for the window).
   Octopath-faithful, but it softens the shell's famous lesson —
   keep, or let counters pierce Break?
2. **Ifrit/Shiva pinning:** Broken can't tag out (Stop rules).
   Confirm — or should a break force the swap instead, handing the
   window to the sibling?
3. **024's anti-codex:** WallChange re-hiding the element row
   mid-fight — delightful or dishonest? (Classes stay revealed
   either way.)
4. **Atma's added row:** fire/ice/bolt + slash/pierce is generous by
   design (free-pick party). Narrow it and risk a lineup that can't
   chip the capstone at all?
5. **Chupon:** keep the 4-shield bragging-rights gauge, or draw him
   shieldless like Tritoch since Sneeze ends it regardless?
6. **Part-break feeding:** should breaking a limb chip the body 1
   (128, Cranes, AirForce)? v1 says no — parts pay in cancels, not
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
   all 576 formation records puts him in exactly two — 489 (with the
   Ice Dragon) and 505, and 505 is what group 57 / `battle 57` reaches
   at event_main.asm:106362, the fight he "won't forget." The camp
   gags share no record with him because they carry no monster at all;
   see 6 above. The $11a/$12a Kefka records are the level-83/71
   endgame ones, out of WoB scope.
   Same pass, adjacent claims: Ipooh $014d reads $01 fire — the fire
   weak above is vanilla, no add — and the chip keys are real data,
   AuraBolt ($5e) carrying $20 holy and BioBlaster's attack ($7d)
   $08 poison in the vanilla spell records.)
