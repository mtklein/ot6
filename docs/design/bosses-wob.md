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
  Kefka's camp flees, Chupon's Sneeze, the espers crashing Ultros's
  bridge party — fire regardless of break state. The gauge is a
  combat system, not a story editor.
- **Proposed ruling: counters sleep while Broken.** A Broken enemy
  loses its counters along with its turns (Whelk's shell goes quiet
  for the window). Octopath-faithful; driver call, open question 1.
- **A shieldless nameplate is information.** Scripted set-pieces
  (Tritoch, Guardian) draw no gauge at all — the HUD's silence tells
  the player this one is theater.

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
| 6 | Kefka ×2 | Imperial Camp (Sabin) | 3 |
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
Pummel (and AuraBolt, if the climb got him to 10).

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
  break him without the monk.
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

**Shields:** 5 · **Weak:** bolt, ice + piercing. Bolt is vanilla's
machine bit and neither of them can cast it — codex trivia today,
payoff later. Ice is added: Celes's join spell needs a socket, and
"frozen coolant lines" reads fine on a digging machine.

- **Telegraph:** the drill spools down and the tunnel groans → its
  buried quake (Magnitude8 — audit list). **Runic eats it.** The
  fight has two right answers — Runic the quake (vanilla's tutorial)
  or break the machine first (ours) — and the best answer is both,
  since Runic converts the telegraph into +1 BP ✦ (kits.md): the
  boss's biggest move literally funds the break.
- **Break story:** Mug and daggers pierce-chip, Ice chips, and 5
  shields across two bodies lands the break right around the first
  fuse. Small fight, complete grammar.

### 6–7. Imperial Camp (Sabin, with Shadow drifting in and out)

**Kefka ×2:** 3 shields · poison + slashing. The gag fights — he
takes a few hits and flees, twice, waiter line intact. No telegraph;
he isn't staying. 3 shields is gag tier on purpose: breakable if you
rush, and the flee script fires either way — scripts beat state. A
break here is worth nothing but the pleasure of it, which is worth
plenty.

**Telstar:** 4 shields · bolt + bludgeoning (Dobermans 2 · piercing).
- **Telegraph:** its antenna sparks and it radios for backup → a
  Doberman wave piles in next turn. Break to jam the call — the
  first *summon-prevention* break; the verb returns at FlameEater.
- **Jank:** a treasure chest that fights back stays a treasure chest
  that fights back.

### 8. GhostTrain — the Phantom Train (Sabin, Cyan, Shadow)

**Shields:** 6 · **Weak:** fire, holy + bludgeoning.

- **Telegraph:** the whistle screams down the corridor → **Evil
  Toot**, party-wide status roulette. Break the boiler before the
  note lands; Acid Rain between fuses keeps the healing honest.
- **Break story:** the scenario's gifts are the keys — AuraBolt is
  holy chip at range, Pummel ×2 grinds, Shadow's elemental skeans
  probe fire. Cyan can't chip his own scenario's capstone, and
  that's deliberate: the Phantom Train farewell is where **Oblivion**
  unlocks (kits.md), and Oblivion wants Broken targets — the train
  is his divine's first legal kill. Break it FOR him.
- **Jank ✦: Suplexable, forever.** The most famous jank in the game
  is now also mechanically *correct* — Suplex is bludgeoning, the
  train is bludgeon-weak; the system canonizes the meme. The undead
  flag stays too: one Fenix Down ends it instantly, break state be
  damned. Cheese outranks systems; house rule.

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

## Zozo

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
| Left Crane | 6 | fire + piercing |
| Right Crane | 6 | bolt + piercing |

(The opposed fire/bolt pair is vanilla's; which element sits on
which side gets verified against the bestiary at data entry.)

- **The Cranes taught FF6 to telegraph ✦.** Vanilla already prints
  its charge counters — fire charging, bolt charging — and detonates
  **Fireball** / **Giga Volt** a few turns later. OT6 doesn't add
  their telegraph; it *inherits* it, verbatim, as the system it
  always wanted to be. Break cancels the charge.
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

**Shields:** 5 · **Weak:** fire, holy + slashing, piercing.

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
| Chupon's Sneeze, Kefka's camp flees, Vargas's finish | in their blocks above: scripts beat state |

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
   element sides; Nerapa's full script; the poison bits on
   Marshal/Vargas/Kefka/Dadaluma; Telstar's reinforcement call;
   Guardian's WoB location.
