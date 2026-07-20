# Character kits & learn schedules — design dive v2 (2026-07-16)

Scope: World of Balance (kits complete or nearly so by its end; WoR
deepens via magicite, not new lists). Locked items are marked ✦.

## The organizing principles

**Native learning verbs.** FF6 already tells us *how* each character
learns; OT6 keeps each verb and reshapes the lists to exactly 8:

| Verb | Characters | Vanilla precedent |
|---|---|---|
| **By level** | Sabin (Blitz), Cyan (Bushido), Terra & Celes (natural magic — the vanilla table, largely verbatim) | preserved |
| **By item** | Edgar (Tools are objects you find/buy) | preserved |
| **By deed** | Mog (dance per terrain), Strago (lore by observation), Gau (rage by capture) | preserved |
| **By story** | every signature (free at join ✦) and most divines | — |

**No JP, probably ✦-leaning.** The native verbs may carry the entire
schedule — everything below is scriptable with zero menu-bank work.
Octopath's early-game arc (develop one job, feel it complete, then
branch into subjobs and open up) falls out naturally: kits fill
through the WoB, then magicite arrives late-WoB/WoR as the breadth
layer. JP returns only if playtesting wants a pacing knob.

**Curated kits (the Ochette/Hikari model).** Two characters learn
MORE than 8 and equip a curated subset (~5 slots): Gau and Strago.
Everyone else's 8 are fixed. Curating IS their identity — same verb
family, different collection method.

Boost-tier folding means kits list **base spells only** — Fire is a
kit entry; Fire 2/3 are what boosting does to it.

Physical chip classes are **slashing / piercing / bludgeoning /
special ¤** (see weapon-classes.md v2.1); the weapon sets Fight's
class while abilities carry their own, and some attacks are
deliberately **null-break** — big dumb damage that chips nothing,
the physical cousin of non-elemental magic.

---

## The constrained three

### Edgar — Machinist (piercing: spear)

The 8 Tools, verbatim ✦ — learned by acquisition.

| # | Tool | MP | Chip | Source (WoB) |
|---|---|---|---|---|
| 1 | AutoCrossbow ✦ | 4 | piercing ×4 | join (signature) |
| 2 | NoiseBlaster | 6 | — (confuse) | Figaro shop |
| 3 | BioBlaster | 8 | poison | Figaro shop |
| 4 | Flash | 6 | — (blind) | Figaro shop, restocked South Figaro |
| 5 | Drill | 16 | piercing | Figaro castle, after the sand dive |
| 6 | Chainsaw | 18 | slashing | Zozo chest (vanilla) |
| 7 | Debilitator | 10 | adds + reveals a random weakness ✦ | Vector shop |
| 8 | **Overclock** ✦ (divine) | Σ | — | Magitek factory (story) |

The MP column is mp-economy.md's "scaled by tier 3–20" (AutoCrossbow 3–4,
Drill/Chainsaw 12–20, Debilitator 8–12): gil buys the tool once, MP is the
per-use operating cost. It lives in `Ot6AbilityCostTbl` keyed by **tool item
id** ($a3–$aa, the same keying ot6_class.asm uses for tool classes), charged
under `OT6_MP_COSTS`. The mid-kit gag Air Anchor ($a9, the findable harpoon)
is costed 14 alongside them. **Overclock** fires two tools, so it has no single
price — its cost is the **sum (Σ)** of the two it fires, wired the day Overclock
is built (it is not yet).

- Divine locked ✦: **Overclock** — use two tools in one action. Air
  Anchor stays a findable *item* mid-kit gag, not the capstone.
- AutoCrossbow ×4 piercing = the first shield shredder; Drill the
  armored-boss answer; Chainsaw covers slashing so Edgar alone spans
  two physical classes through tools.
- Passive candidates: *Tinkerer* (tools ignore blind), *Royal
  Discount* (shops half price), *Overcharge* (+1 AutoCrossbow hit
  per 2 BP).

### Sabin — Monk (bludgeoning: fists; claws buy slashing)

The 8 Blitzes, verbatim ✦ — vanilla level table preserved ✦, button
inputs stay. Fists are the heart of the **bludgeoning** class
(fists, staves, rods) — Pummel-as-blade never sat right. Equipping
claws switches his *Fight* to slashing ✦, but blitz classes are
immutable: Pummel with claws on is still bludgeoning. The weapon
slot is his second class, the ability list is his first.

Levels below are `BlitzLevelTbl` (`field/event.asm:1240`), read out, not
recalled — an earlier draft of this table was wrong in six of eight rows
while still marked "vanilla preserved ✦".

| # | Blitz | MP | Chip | Level |
|---|---|---|---|---|
| 1 | Pummel ✦ | 2 | bludgeoning ×2 | 1 (has it at join) |
| 2 | AuraBolt | 5 | holy | 6 |
| 3 | Suplex | 7 | bludgeoning | 10 |
| 4 | Fire Dance | 9 | fire | 15 |
| 5 | Mantra | 8 | — (heal) | 23 |
| 6 | Air Blade | 12 | wind | 30 |
| 7 | Spiraler | 18 | — | 42 |
| 8 | **Bum Rush** (divine) | 30 | bludgeoning ×8 | 70 / Duncan |

The MP column is mp-economy.md's "scaled by tier 2–30" made concrete (Pummel
the 2-MP signature, mid-kit 5–12, Bum Rush the 30-MP capstone); it lives in
`Ot6AbilityCostTbl` keyed by attack id $5d–$64, charged under `OT6_MP_COSTS`.

- Passive candidates: *Iron Fist* (unarmed counts as a bludgeon
  weapon), *Discipline* (+1 BP when striking a Broken enemy),
  *Second Wind* (Mantra also grants 1 BP).

### Cyan — Samurai (slashing: katana)

The 8 Bushido priced in BP ✦ (charge gauge deleted ✦). Katana now
lives inside **slashing** with swords — Cyan is a slashing
*specialist* (multi-hit slash chips nobody else matches), not a
mandatory key for katana-only locks. Vanilla level schedule kept.

| # | Tech | BP | MP | Chip | Level |
|---|---|---|---|---|---|
| 1 | Fang ✦ | 0 | 1 | slashing | join |
| 2 | Sky | 1 | 2 | — (counter stance) | 6 |
| 3 | Tiger | 1 | 3 | slashing | 12 |
| 4 | Flurry | 2 | 4 | slashing ×4 | 15 |
| 5 | Dragon | 2 | 5 | — (drain) | 24 |
| 6 | Eclipse | 3 | 6 | slashing, all enemies | 34 |
| 7 | Tempest | 3 | 7 | wind ×4 | 44 |
| 8 | **Oblivion** (divine) | 3, target must be Broken | 8 | — | Phantom Train farewell (story) |

**The MP column (proposed v0.4, was TBD).** mp-economy.md priced Bushido "BP
tier + discounted MP 1–8" and deferred the numbers to Cyan's playtest; this is
that column, proposed from the BP-tier structure so the charge-side groundwork
had data to carry. It is monotonic with the BP band (0→1, 1→2–3, 2→4–5, 3→6–8)
and rides ~⅓ of a comparable Blitz/Tool — Flurry's slashing ×4 costs 4 MP where
Sabin's Air Blade costs 12 and Edgar's Drill 16 — because, per the ruling, the
**banked-BP requirement is the real price and the MP only prices the cast**.
Fang is the cheapest row of any kit (1 MP, the "free-to-learn is not
free-to-use" floor); Oblivion tops the band at 8 even though it is out of the
current boost ladder (priced ready for the divine pass). Cyan's ~18-MP L5 pool
affords the low ladder (Fang/Sky/Tiger/Flurry = 1/2/3/4) and outgrows the rest
on his level schedule, so a light column keeps him acting while the bank
builds — the whole point of the one kit where banking BP has intrinsic purpose.
These numbers live in `Ot6AbilityCostTbl` (ff6/src/battle/ot6.asm), charged
only under the `OT6_MP_COSTS` build flag (default off until the menu can
display them — see mp-economy.md).

**Shipped (M3).** `Ot6BushidoTier` (ff6/src/battle/ot6.asm) replaces the
charge gauge's clock in `UpdateMenuState_37`; the window, its numerals,
the grey-out of unlearned techs, the A-button latch, `FixPlayerAttack`'s
`+$55` and `Cmd_07` are all vanilla and untouched. The BP column above
is read as a *band*, and boost selects the band: the table names each
band's top tech and vanilla's own `$2020` (techs known - 1, the value
that used to cap the bar) drops it to the best one Cyan has learned.

| BP | band | selects |
|---|---|---|
| 0 | Fang | Fang |
| 1 | Sky, Tiger | Tiger from L12, Sky before |
| 2 | Flurry, Dragon | Dragon from L24, Flurry before |
| 3 | Eclipse, Tempest | Tempest from L44, Eclipse before |

Consequences, all deliberate and all data-editable (the bands are a
4-byte table, not code):

- **The lower tech of a band is transitional** — Sky is reachable L6-11,
  Flurry L15-23, Eclipse L34-43. A band's expression upgrading as Cyan
  levels is the spell fold's grammar one rung up (Fire is Fire until a
  boost makes it Fira). The cost is that Flurry's multi-hit shredder
  role goes quiet L24-43 until Tempest restores it.
- **Oblivion is out of the ladder.** Its gate is "target must be
  Broken", and that cannot be read at command-latch time — swdtech is in
  `RetargetCmdTbl`, so no target exists yet. It waits on the divine pass
  (Terra's Trance, summon-once-per-battle); shipping it ungated would
  also have retired Eclipse and Tempest. Cyan learns it off the Phantom
  Train regardless, far past the rung-3 gate this unblocked.
- **BP is read, never written.** `Ot6ActionEnd` consumes the spend and
  skips that turn's regen exactly as for any other action, and the ≤3 /
  never-past-bank caps stay `Ot6Boost`'s. Bushido is excluded from
  `Ot6BoostDmg`'s multiplier for the same reason folded spells are: the
  points bought the tech, so they must not also buy damage. Spend the
  ladder cannot use (three points at L1 still buys Fang) is spent, not
  refunded — the deal a mage already takes on a third point on Fire.

Note the Chip column above is finer-grained than what ships: the class
table (`ot6_class.asm:185-192`) marks all eight slashing, per
weapon-classes.md's "Cyan is a slashing specialist". Sky's and Dragon's
"—" and Tempest's wind are unbuilt refinements, not a contradiction.

Gate: `tools/tests/battle_bushido.lua`.

- Passive candidates: *Vengeance* (+1 BP whenever any enemy Breaks),
  *Retort* (vanilla counter as a passive), *Zanshin* (Sky chips 1
  when it counters).

---

## The middle three

### Terra — Esper mage (slashing: sword, fire lean)

Vanilla's natural-magic table, trimmed to base tiers with the levels
compressed so the list completes late-WoB. Vanilla makes her the
game's only natural raise-learner (Life at 18) — kept, so revival
lives on Terra, Fenix Downs, and Sraphim, and nowhere else.

| # | Spell | Level |
|---|---|---|
| 1 | Fire ✦ (hides Ultima — see below) | join (vanilla 3) |
| 2 | Cure | join (vanilla 1) |
| 3 | Drain | 12 (vanilla) |
| 4 | Life | 18 (vanilla) |
| 5 | Break | 24 |
| 6 | Pearl | 30 |
| 7 | Merton | 33 |
| 8 | **Trance** (divine) | Zozo awakening (story) |

- **Ultima is the fourth fold, not a slot ✦.** Vanilla's table
  already teaches Terra Ultima at level 99 — a birthright nobody
  ever meets. OT6 makes it real without spending a menu row: after a
  very-late story unlock, Terra casting Fire at 3 BP folds past
  Firaga into **Ultima**. It never appears in her list until the
  moment the fold preview renders it. Everyone else gets Ultima the
  expected way — equip Ragnarok.
- **Trance keeps the divine slot**: her esper-state apex — usable
  only while an enemy is Broken, or costing the full 5-BP bank
  (DESIGN.md's two candidates; playtest decides in M6).
- Passive candidates: *Esperkin* (spells chip 2 on weakness),
  *Mag-Armor* (magic taken −25%), *Afterglow* (first cast each
  battle costs 0 MP).

### Locke — Thief (piercing: dagger)

Story-verb learner. More than steal-steal-steal: probe, redistribute,
corrode — and a little merchant blood (he'd say TREASURE HUNTER).

| # | Skill | Effect | Source |
|---|---|---|---|
| 1 | Steal ✦ | vanilla steal | join |
| 2 | Mug | steal + piercing damage | South Figaro escape |
| 3 | Trickshot | piercing chip at range (thrown coin) | Lete River |
| 4 | Filch | steal 1 BP from the target | Opera house |
| 5 | Bestow | give an ally 1 BP | Vector (merchant beat) |
| 6 | Dismantle | armor corrode: −defense, piercing chip | Sealed Gate |
| 7 | Appraise | reveal one enemy's full weakness row | Thamasa |
| 8 | **Master's Mark** (divine) | steal from all enemies + reveal everything | Floating Continent |

- Filch/Bestow make him the economy's hands: take BP from enemies,
  hand it to allies. Tactically he's tempo, not just loot.
- Passive candidates: *Sticky Fingers* (failed steal keeps the
  turn's BP gain), *First Strike* (battle opens +1 BP for Locke),
  *Fence* (steals sell for more).

**Boost-tiered Steal (shipped M3).** Steal is the party's first *chance verb*:
it rolls dice, so BP buys certainty, not potency (DESIGN.md's canon rule — "on
chance verbs boost guarantees"). Each point tilts BOTH axes of the vanilla
gamble — the success chance and the common-vs-rare pick — monotonically, and the
full spend converts it:

| BP | Success | Item pick |
|----|---------|-----------|
| 0 | **vanilla, to the byte** — level+50−targetLevel, Sneak Ring doubles it | vanilla: 1/8 rare, 7/8 common; an empty picked slot still yields nothing |
| 1 | +40 to the effective level (a hard steal → a coin flip; a coin flip → a near-lock) | 3/8 rare when both present; never "nothing" on a hit (takes whichever slot is filled) |
| 2 | +90 (level parity now auto-succeeds) | 3/4 rare when both present; same fallback |
| 3 | **guaranteed** (the level clamps to $ff, so the roll is skipped entirely) | **rare if present, else the common** — taken outright, no roll |

Rulings that fall out of the vanilla math (see `tools/tests/battle_steal.lua`):

- **Sneak Ring** keeps helping the un-boosted and partial tiers — it doubles the
  residual success chance at 0–2 BP exactly as in vanilla. At 3 BP it is moot:
  the level clamp overflows *before* the chance value is ever formed, so the ring
  is never consulted. Nobody stacks a relic onto a certainty.
- **Boost never conjures loot.** An enemy with nothing to steal, or one already
  looted (both slots cleared), yields vanilla's "nothing" at every tier — the
  $ffff top-check drops out before the tier logic runs. 3 BP guarantees a steal
  *if there is something to steal*, and "rare if present" falls back to the
  common when there is no rare (guarantee ≠ conjuring).
- **No damage, no multiplier.** Steal deals none, and the Ot6BoostDmg command
  gate ($05) makes sure boost never sneaks one in: a chance verb answers to
  guarantee, not the ×2/×4/×8 a damage verb takes. This is what keeps the two
  axes legible — and it pre-declares **Mug's** ruling. Mug is *steal + piercing
  damage*: when it ships, boost drives exactly ONE axis (the damage multiply OR
  the steal guarantee, TBD by playtest), never both, or the canon rule stops
  reading cleanly. The steal half rides its unboosted vanilla odds unless boost
  is spent on it.

### Celes — Rune Knight (slashing: sword, ice lean)

Vanilla natural-magic levels nearly verbatim — the table was already
a rune knight's: sensing, warding, hastening. Deliberately mirrors
Terra: both share Cure; fire/life/transcendence against
ice/order/tempo. The duality reads clearer than vanilla ever made it.

| # | Spell/Skill | Level |
|---|---|---|
| 1 | Runic ✦ (absorbs next spell → **+1 BP** ✦) | join |
| 2 | Ice | join (vanilla 1) |
| 3 | Cure | 4 (vanilla) |
| 4 | Imp | 13 (vanilla) |
| 5 | Scan | 18 (vanilla) |
| 6 | Safe | 22 (vanilla) |
| 7 | Haste | 32 (vanilla) |
| 8 | **RunicBlade** (divine, leaning) | Opera / Magitek factory (story) |

- **Row 1 is code now, not only design** (`Ot6RunicBP`, ot6.asm, hooked
  into vanilla's `RunicEffect`): the absorb still becomes MP and now
  also banks 1 BP. Rulings, all covered by `battle_runic.lua` — an
  absorb at a full bank is **capped, never wrapped**; the
  no-regen-after-boost rule does **not** gate it, because that rule
  governs a turn's own end-of-action tick while the absorb is paid
  during the *caster's* action, so boosting the turn she raises Runic
  still gets paid for what she catches; and only the Runic *command*
  pays, not the separate "enemy runic" stance a raging Gau can carry.
  Vanilla's own gate is untouched — what Runic can eat is still the
  spell's `MagicProp` absorb flag, which excludes every esper and every
  MagiTek beam. The Narshe school's $026F now names the BP.
- Divine leaning ✦-ward: **RunicBlade** — a Runic stance that also
  *reflects* what it eats (absorb the MP as BP, bounce the spell).
  Absolute Zero stays the listed alternate until playtest.
- Passive candidates: *Rune Eater* (Runic feeds 2 BP), *Cold Blood*
  (ice chips +1), *Aegis* (magic taken at 0 pending −20%).

---

## Sketches (join order, WoB)

- **Shadow — Assassin (piercing, thrown)**: Throw ✦ signature; smoke
  and exit tricks; divine **Assassinate** — instant kill a Broken
  non-boss. Interceptor is a passive.
- **Setzer — Gambler/Merchant (special ¤: dice, cards; darts =
  piercing)**: Slots ✦ signature; Coin Toss, Hired Help (pay GP for
  effects) carry the merchant house; divine **Jackpot** — a
  Fixed-Dice triple payoff, never Slots itself ✦. Ordinary dice and
  cards chip ¤; the wildest oddballs (Fixed Dice) are null-break —
  huge numbers, no chip, row ignored (vanilla charm, preserved ✦).
- **Mog — Dancer (piercing: spear)**: the 8 Dances verbatim ✦,
  learned by dancing on each terrain ✦; divine **Water Rondo**, kept
  WoB-missable, vanilla-style. Easy and perfect.
  - **Boost-tiered Dance (design canon — awaiting Mog's rung to build).**
    Dance is a *chance verb* like Steal, so boost buys certainty in the dance's
    own vocabulary (DESIGN.md canon rule). **Keep the possession** — Mog still
    dances on his own once it starts; that loss of control IS the dance. Boost
    spent at dance-start buys choreography: **1–2 BP removes the stumble** (the
    ~1/16 wrong-terrain misfire) and shifts the four-move weights toward the
    stronger moves; **3 BP = the dance's best move every turn for the whole
    trance** — fully choreographed, no roll. Same shape as Steal: 0 BP is
    vanilla to the byte, each point narrows the gamble, the full spend converts
    it. This is approved-verbatim design, not yet coded — it lands when Mog's kit
    does (WoB), reusing the same pending-BP read + Ot6ActionEnd charge Steal
    already proves out.

**The chance-verb family.** Steal (shipped) and Dance (above) are the first two;
**Sketch (Relm), Slot (Setzer), and Rage (Gau)** answer to the SAME rule when
their rungs arrive — each rolls dice, so each spends BP on certainty in its own
terms (a chosen sketch, a fixed reel, a picked rage) rather than on a potency it
doesn't have. Held in reserve deliberately: coupling steal odds to a *broken*
enemy (revisit after the v0.3 break-uptime playtest).

## Curated kits (the Ochette/Hikari pair)

Both learn an open-ended collection and **equip ~5** — the player
prunes the kit all game. Same model, different collection verbs:

- **Gau — Beast Tamer (piercing: fangs)**: Leap→**Capture** ✦
  (H'aanit/Ochette). Captured beasts' signature moves fill his
  stable; he equips 5 as controllable skills. The 250-entry berserk
  Rage table retires; the stable is curated in M6. Divine: TBD, a
  capstone beast.
- **Strago — Scholar (bludgeoning: rod)**: Lores by observation ✦
  (Cyrus/Hikari). Aqua Breath free ✦; **Analyze** cheap and early ✦
  (full weakness reveal — the party's scout tool). Learns every lore
  he witnesses, equips 5. Divine: a taught-only capstone lore
  (Grand Train candidate, WoR).

- **Relm — Painter (special ¤: brush)**: Sketch ✦ signature (bug
  preserved ✦ — it eats a save now and then, and that's canon);
  support/trickster kit TBD.

## Open questions for the driver

1. Trance's gate: Broken-enemies-only, the full 5-BP bank, or
   either? (It kept the divine slot now that Ultima rides Fire.)
2. Gau's divine: a specific capstone beast, or the stable's 5th slot
   upgraded to hold anything?
3. Curated-kit slot count: 5 for both Gau and Strago, or asymmetric
   (Gau 5, Strago 6)?
4. Does Bestow (Locke) step on Hired Help (Setzer), or is
   BP-vs-GP economy distinct enough?
