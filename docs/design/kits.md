# Character kits & learn schedules — design dive v1 (2026-07-16)

Scope: World of Balance. WoR is more work, not different work.
Status: **proposal for review** — locked items are marked ✦.

## The organizing principle: native learning verbs

FF6 already tells us *how* each character learns — it just never
committed to it as identity. OT6 keeps each character's native
learning verb and reshapes the lists to exactly 8:

| Verb | Characters | Vanilla precedent |
|---|---|---|
| **By level** | Sabin (Blitz), Cyan (Bushido), Terra & Celes (natural magic) | the vanilla tables, preserved |
| **By item** | Edgar (Tools are objects you find/buy) | vanilla tool possession |
| **By deed** | Mog (dance per terrain), Strago (lore by observation), Gau (rage by capture) | vanilla mechanics, preserved |
| **By story** | every signature (free at join ✦) and most divines | — |

JP (M4) is the **accelerator, not the gate**: spending JP buys the
next unlock early (a blitz before its level, a tool before its shop).
Until the JP menu exists, the native verbs carry the whole schedule —
nothing blocks on menu-bank work.

Boost-tier folding means kits list **base spells only** — Fire is a
kit entry, Fire 2/3 are what boosting does to it.

Passives unlock at 2/4/6/8 skills learned (M4+; candidates listed,
none locked).

---

## The constrained three

### Edgar — Machinist (spear)

The 8 Tools, verbatim ✦ — learned by acquisition (buy/find), the most
literal "learn by item" in the game.

| # | Tool | Chip | Source (WoB) |
|---|---|---|---|
| 1 | AutoCrossbow ✦ | ranged ×4 hits | join (signature) |
| 2 | NoiseBlaster | — (confuse) | Figaro shop |
| 3 | BioBlaster | poison | Figaro shop |
| 4 | Flash | — (blind) | Figaro shop, restocked South Figaro |
| 5 | Drill | spear | Figaro castle, after the sand dive |
| 6 | Chainsaw | sword | Zozo chest (vanilla) |
| 7 | Debilitator | sets a random weakness ✦ | Vector shop |
| 8 | **Air Anchor** (divine) | — | Magitek factory find |

- AutoCrossbow's 4 hits × ranged chip = the party's first shield
  shredder; Drill pierces armored shields (spear-weak).
- Debilitator is the proto-OT6 tool — in OT6 it *adds* a weakness to
  the enemy's set and reveals it.
- Divine note: Air Anchor as-found is vanilla jank (death sentence);
  candidate true divine instead: **Overclock** — use two tools in one
  action. Air Anchor stays the *item*, Overclock the apex verb. TBD.
- Passive candidates: *Tinkerer* (tools ignore blind), *Royal
  Discount* (shops half price — vanilla joke preserved as a passive),
  *Overcharge* (+1 AutoCrossbow hit per 2 BP).

### Sabin — Monk (blade)

The 8 Blitzes, verbatim ✦ — vanilla level table preserved ✦ (jank and
all): button inputs stay.

| # | Blitz | Chip | Level |
|---|---|---|---|
| 1 | Pummel ✦ | blade ×2 | join (6) |
| 2 | AuraBolt | holy | 10 |
| 3 | Suplex | — | 15 |
| 4 | Fire Dance | fire | 21 |
| 5 | Mantra | — (heal) | 26 |
| 6 | Air Blade | wind | 33 |
| 7 | Spiraler | — | 42 |
| 8 | **Bum Rush** (divine) | blade ×8 | 51 / Duncan (WoR) |

- WoB naturally yields 4-6 blitzes — the kit *grows through* the WoB
  and finishes in WoR, which is the right pacing for a level verb.
- Chip logic: multi-hit blitzes are Sabin's shredders; elemental
  blitzes are his probes.
- Passive candidates: *Iron Fist* (unarmed counts as blade weapon),
  *Discipline* (+1 BP when striking a Broken enemy), *Second Wind*
  (Mantra also grants 1 BP).

### Cyan — Samurai (katana)

The 8 Bushido priced in BP ✦ (charge gauge deleted ✦) — the BP
economy showcase. Vanilla level schedule preserved.

| # | Tech | BP | Chip | Level |
|---|---|---|---|---|
| 1 | Fang ✦ | 0 | katana | join |
| 2 | Sky | 1 | — (counter stance) | 6 |
| 3 | Tiger | 1 | katana | 12 |
| 4 | Flurry | 2 | katana ×4 | 15 |
| 5 | Dragon | 2 | — (drain) | 24 |
| 6 | Eclipse | 3 | katana, all enemies | 34 |
| 7 | Tempest | 3 | wind ×4 | 44 |
| 8 | **Oblivion** (divine) | 3, target must be Broken | — | Phantom Train farewell (story) |

- Oblivion at the Doma grief beat: the one divine that's both story
  AND the system lesson (it *requires* a Break).
- Passive candidates: *Vengeance* (+1 BP whenever any enemy Breaks),
  *Retort* (vanilla counter, rebadged as a passive), *Zanshin* (Sky
  also chips 1 when it counters).

---

## The middle three

### Terra — Esper mage (sword, fire lean)

Natural-magic verb (level table, trimmed to the kit). Base spells
only — boost folds the tiers.

| # | Spell | Level |
|---|---|---|
| 1 | Fire ✦ | join |
| 2 | Cure | join |
| 3 | Poison | 6 |
| 4 | Drain | 12 |
| 5 | Slow | 18 |
| 6 | Break | 24 |
| 7 | Pearl | 33 |
| 8 | **Trance** (divine) | Zozo awakening (story) |

- Trance: usable only while an enemy is Broken OR with a full 5-BP
  bank (DESIGN.md's two candidates — playtest decides, M6).
- Passive candidates: *Esperkin* (spells chip 2 SP on weakness),
  *Mag-Armor* (magic damage taken −25%), *Afterglow* (first cast each
  battle costs 0 MP).

### Locke — Thief (blade)

Story-verb learner (his kit grows at heists and rescues, not levels).

| # | Skill | Effect | Source |
|---|---|---|---|
| 1 | Steal ✦ | vanilla steal | join |
| 2 | Mug | steal + blade damage | South Figaro escape |
| 3 | Trickshot | ranged chip (thrown coin arc) | Lete River |
| 4 | Filch | steal 1 BP from the target | Opera house |
| 5 | Dismantle | armor corrode: −defense, chips blade | Vector |
| 6 | Smokescreen | party dodge up, exit cover | Sealed Gate |
| 7 | Appraise | reveal one enemy's full weakness row | Thamasa |
| 8 | **Master's Mark** (divine) | steal from all enemies + reveal everything | Floating Continent |

- The BP-theft (user's idea, DESIGN.md TBD) lands as *Filch* —
  economy-vs-economy is the thief fantasy in this system.
- Passive candidates: *Sticky Fingers* (failed steal keeps the turn's
  BP gain), *Treasure Sense* (field: chest count on map), *First
  Strike* (battle opens with +1 BP for Locke).

### Celes — Rune Knight (sword, ice lean)

Natural-magic verb like Terra; defense converted into tempo.

| # | Spell/Skill | Level |
|---|---|---|
| 1 | Runic ✦ (absorbs next spell → **+1 BP** ✦) | join |
| 2 | Ice | join |
| 3 | Cure | 8 |
| 4 | Scan | 14 |
| 5 | Safe | 20 |
| 6 | Haste | 26 |
| 7 | Imp | 32 |
| 8 | **Absolute Zero** (divine) | Opera / Magitek factory (story) |

- Absolute Zero: heavy ice, all enemies, double chip vs revealed
  ice-weakness. Candidate alternative: *RunicBlade* stance (Runic
  that also reflects). TBD.
- Passive candidates: *Rune Eater* (Runic feeds 2 BP instead of 1 at
  6 skills), *Cold Blood* (ice spells chip +1), *Aegis* (magic taken
  while at 0 pending −20%).

---

## Sketches (join order, WoB)

- **Shadow — Assassin (blade, thrown/ranged)**: Throw ✦ signature;
  kit of smoke/exit/dog tricks; divine **Assassinate** — instant kill
  a Broken non-boss. Interceptor is a passive, not a skill.
- **Setzer — Gambler (ranged)**: Slots ✦ signature; Coin Toss, Hired
  Help (GP-for-effects economy pieces); divine **Jackpot** — a
  Fixed-Dice triple payoff, never Slots itself ✦.
- **Mog — Dancer (spear)**: the 8 Dances verbatim ✦, learned by
  dancing on each terrain ✦ (vanilla verb preserved exactly); divine
  = **Water Rondo** kept WoB-missable, vanilla-style.

## Deliberately last (flexible, light until the systems above prove out)

- **Gau — Beast Tamer (innate fangs)**: Leap→Capture (H'aanit model):
  captured beasts become his 8 equipable skills. The 250-rage table
  retires; a curated stable ships in M6. Direction only for now.
- **Strago — Scholar (arcana)**: 8 Lores by observation ✦ (vanilla
  verb); Aqua Breath free signature; **Analyze** cheap at #2 (the
  Cyrus role: full weakness reveal). List TBD after the bestiary's
  weakness spread lands.
- **Relm — Painter (arcana)**: Sketch ✦ signature (bug preserved ✦ —
  it's charming right up until it eats a save, and that's canon);
  support/trickster kit TBD.

## Open questions for the driver

1. Edgar's divine: Air Anchor-as-found vs Overclock-as-apex?
2. Terra's Trance gate: Broken-only, 5-BP bank, or either?
3. Celes: Absolute Zero vs RunicBlade as the divine?
4. Locke's Trickshot: is a ranged-chip probe on the thief right, or
   should he stay pure blade and trade Trickshot for a second
   steal-flavor skill?
