# Ifrit & Shiva — magicite sub-job designs (v0.6) — design dive v1 (2026-07-26)

Scope: issue #16, the two magicite the Magitek Research Facility pays out.
This is a **design pass**: no assembly, no data edits. Every table edit this
document asks for is listed literally in §10 so the build pass is transcription,
not interpretation.

**Canon boundary (issue #16).** The shipped **while-equipped** spell/stat model
is the v0.6 baseline: equip grants the spell list live, the stat mod exists only
while the stone is worn, nothing is learned, the summon is the once-per-battle
divine. The proposed *learned-passive* system (magicite.md §3) is **not** assumed
anywhere below. Neither esper carries a named passive, because the passive
channel does not exist in the ROM — see §12.

**Evidence rule (CONTRIBUTING.md).** Every mechanical claim below cites the file
and line it was read from, or is labelled **UNVERIFIED**. Numbers taken out of
`.dat` files name the record and byte offset.

---

## 1. The constraint budget — what the shipped machinery can actually express

Read before designing, because it is much narrower than magicite.md's roster
table implies.

| Channel | Shipped? | Shape | Evidence |
|---|---|---|---|
| Spell grant | ✅ | **≤ 5 spell ids** per esper, from the vanilla esper record | `ot6_progression.asm:142-181` (`Ot6EsperSpellKnown`, scans `GenjuProp+1,+3,+5,+7,+9`) and `:203-252` (`Ot6UnionEspers`, seeds the union so a spell nobody knows still gets a list slot) |
| Stat mod | ✅ | **exactly one** stat, **unsigned**, magnitude **1–15** (low nibble); selector is one of vigor / speed / stamina / mag.pwr | `ot6_progression.asm:314-384` + `Ot6EsperStatTbl` `:391-419`. Packed byte = `[sel:4][mag:4]`; `$00` = no mod |
| Summon | ✅ (vanilla) | one attack record per esper, `id = esper + $36`; once per battle **per character** | `FixPlayerAttack` sets the character's bit in `$3f2e` (`battle_main.asm:12739-12747`); the Magic menu's esper row is disabled when that bit is set (`battle_main.asm:14436-14439`) |
| Boost-tier folding | ✅ | **8 families only**: fire, ice, bolt, poison→bio, cure, life, slow, haste | `Ot6FoldTbl`, `ot6_boost.asm:340-348`; scanned with a hard `cpx #$0018` bound at `:255`, `:317` |
| Boost on non-folding actions | ✅ | ×2/×4/×8 on base damage; exempted commands are fight `$00`, capture `$06`, bushido `$07`, steal `$05` — **summons (`$19`) are not exempt** | `Ot6BoostDmg`, `ot6_kits.asm:1190-1256` |
| Ability MP cost | ✅ live | Magic prices on the vanilla ruler (`GetMPCost`); `Ot6AbilityCostTbl` only keys blitz/bushido/tool ids | `ot6_boost.asm:352-400` (`Ot6AbilityCost` header); mp-economy.md "Where it lands" |
| **Weapon permit** | ❌ **not built** | no equip-side consumer exists | `ot6_class.asm:17` names equip permits as a *future* consumer; nothing reads a permit anywhere in `ff6/src` |
| **Named passives** | ❌ **not built** | no passive pool, no slots, no learning meter | ROADMAP M4 lists "Passives unlock at 2/4/6/8" as ⬜ |
| **Esper menu copy** | ❌ **not touched** | the detail screen still draws vanilla learn-% and the "at level up:" bonus line | `skills.asm:2570-2645` — reads `GenjuProp` learn-rate bytes (all zeroed by M5) and blanks the bonus line when the byte is `$ff` (which M5 made universal) |

**Two consequences that shape everything below.**

1. **A magicite's identity has to live in its spell list, its one stat, and its
   summon.** There is no passive channel and no permit channel to gesture with.
   magicite.md's *Kindling* / *Frostbite* passives and its claw/rod permits are
   design sketches with no ROM behind them; this document does not depend on
   them.
2. **Boost folding + the live MP economy make base-tier elemental grants the
   most efficient actions in the game.** `Ot6QueueFold` runs *after* `GetMPCost`
   has already banked the **base** spell's MP (`ot6_boost.asm:211-215` header;
   mp-economy.md, "Boost never raises MP cost"). So:

   | granted spell | MP charged | at 2 BP casts as | vanilla MP of that tier |
   |---|---|---|---|
   | Fire (`$00`) | **4** | Fire 3 (`$09`, power 121) | 51 |
   | Ice (`$01`) | **5** | Ice 3 (`$0a`, power 122) | 52 |

   (MP and power read from `magic_prop_en.dat`, 14-byte records, +0x05 / +0x06.)
   A base-tier elemental grant is therefore worth roughly *ten times* its price
   to a boosting caster. That is the intended shipped behaviour, and it is why
   neither esper below needs a tier-2 spell — and why the **current** vanilla
   rows for both are wrong.

**The current rows are placeholders and they are actively broken** (`ff6/src/menu/genju_prop.asm:85-90`):

```
; 1: ifrit
make_genju_prop {FIRE, 0}, {FIRE_2, 0}, {DRAIN, 0}, {}, {}
; 2: shiva
make_genju_prop {ICE, 0}, {ICE_2, 0}, {RASP, 0}, {OSMOSE, 0}, {CURE, 0}
```

The granted `FIRE_2` / `ICE_2` rows are dead weight for exactly the reason the
Kirin pass already documented: a pre-folded tier "would otherwise sit as an
un-foldable dead tier beside the foldable" base spell (`genju_prop.asm:130-137`).
They cost 20/21 MP for what the base spell delivers at 4/5 MP under one boost.
Both must go.

---

## 2. Where the player is standing

### 2.1 The party

The Facility party, from the repo's own route work:

- **`Locke, Celes + two`** for Ifrit & Shiva and Number 024; **"the factory
  four"** (fixed) for Number 128 and the Cranes — `wob-route.md` §3 and
  `bosses-wob.md` §13–16.
- At the v0.4 tail fixture the *active* party is measured as **Locke + Celes
  only** (`$1850` read, `wob-route.md` "Beat A — measured corrections").
- **Terra is not in this dungeon.** ROADMAP's v0.6 line ends "…the Cranes, the
  escape, and **Terra's return**", and `wob-route.md`'s beat table puts "Terra
  recovers her will" in **Beat C / v0.7**. Either way her return is *after* the
  Facility, not before it. Any design premised on "Terra has just rejoined" is
  premised on the wrong beat. **MARK: the two docs disagree by one release on
  when exactly she is playable again; confirm against the Beat B fixture when it
  mints.**

So the roster the two new stones are competing inside is Locke (pierce, thief),
Celes (slash, ice + Runic), and two of {Edgar, Sabin, Cyan, Gau, Setzer}.
**MARK UNCERTAIN:** the exact *available* set at Vector was not read out of the
event source for this pass; `wob-route.md` §3's list is the authority used here.

What that party already brings:

| need | who covers it today |
|---|---|
| ice | **Celes**, innate at join (kits.md, vanilla natural magic) |
| fire | **Sabin**'s Fire Dance (blitz #4, L15, 9 MP — kits.md); **Siren** currently grants base Fire as a leftover vanilla row (`genju_prop.asm:95-96`) |
| bolt | **Ramuh** (Bolt + Rasp, `genju_prop.asm:82-83`) |
| heal | **Kirin** (Cure/Regen/Antdot/Scan, `genju_prop.asm:138`) |
| pierce chip | Locke, Edgar (AutoCrossbow ×4) |
| slash chip | Celes, Cyan (Flurry ×4), Sabin-with-claws |
| **MP sustain** | **nobody** |
| **magic mitigation** | **nobody** (Celes's Safe is L22 and is physical mitigation) |

Six magicite exist by the end of the Facility (Ramuh, Kirin, Siren, Stray,
Ifrit, Shiva) for four party slots. **The design target is that Ifrit and Shiva
each win a slot from a different incumbent** — Ifrit from Siren (the fire slot),
Shiva from Stray (the utility slot) — while Ramuh and Kirin stay obviously
good. That is the "meaningful choice, not a single answer" acceptance criterion.

### 2.2 The dungeon is hostile to both of their elements

Decoded from `monster_prop.dat` (32-byte records; +0x17 absorb, +0x18 null,
+0x19 weak; element mask $01 fire / $02 ice / $04 bolt / $08 poison / $10 wind /
$20 holy / $40 earth / $80 water):

| body | id | weak | absorb | null |
|---|---|---|---|---|
| Shiva | `$108` | fire | **ice** | $fc (everything but fire/ice) |
| Ifrit | `$109` | ice | **fire** | $fc |
| Number 024 | `$10a` | — | — | — |
| Number 128 | `$10b` | — | **ice** | — |
| Blades | `$13f/$140` | — | **ice** | — |
| Left Crane | `$10d` | water | **bolt** | — |
| Right Crane | `$10e` | water, bolt | **fire** | — |

Two findings the design has to answer:

- **After the fight that grants them, fire is right against nothing and ice is
  right against nothing.** Ice is *absorbed* by Number 128 and both blades; fire
  is *absorbed* by the Right Crane. Number 024 has no vanilla element weakness
  at all and re-hides its row (`bosses-wob.md` §14). Water is the Cranes' key
  and nobody in the WoB casts it (DESIGN.md: water has no base spell; Mog's
  Water Rondo is missable).
- **`bosses-wob.md` §16's line "the factory paid out its own boss keys: Ifrit's
  fire and Ramuh's bolt" is wrong on the fire half**, and contradicts the decode
  written eight lines above it in the same section. The Right Crane *absorbs*
  fire; neither Crane is fire-weak. Ramuh's bolt is a real key on the Right
  Crane only, and the Left Crane absorbs it. Flagged for a correction pass; not
  edited here (issue #16 is Ifrit/Shiva only).

The trash is no kinder — §2.5 finds exactly one fire-weak species in the whole
Facility and not a single ice-weak one.

**Therefore: neither esper may be designed as "the fire button" or "the ice
button".** A reward whose headline is dead for the remaining four boss fights of
the dungeon that granted it is a bad reward. Both kits must carry
**element-independent value that works inside the Facility**, with their element
as the payload the player carries *out*.

### 2.3 Boss shield/class rows (already authored)

`Ot6ShieldTbl`, `ot6_hud.asm:1542-1557`: Ifrit 6·pierce, Shiva 6·slash, Number
024 7·slash|pierce, Number 128 7·pierce, both Cranes 6·pierce. Every Facility
boss is **class-breakable by the party's existing weapons** — Locke pierces,
Celes slashes. The class axis is the dungeon's real handhold, and that is a
design lever: **anything that makes ordinary weapon swings hit harder is worth
more in this dungeon than any element.**

### 2.4 Boss MP pools

From `monster_prop.dat` +0x0A/0B: Shiva 500, Ifrit 600, Number 024 777, Number
128 810, each Crane 447. Party pools at this level sit near 40–60 MP
(mp-economy.md, "Early pools"). This matters a great deal in §6.

### 2.5 The random-encounter set — and the hole in it

Decoded for this pass by walking `sub_battle_group.dat` (`$CF5600`, one byte per
map id) → `rand_battle_group.dat` (`$CF4800`, 8 bytes per group, slot picked
5/16 · 5/16 · 5/16 · 1/16 — the dispatch is at `ff6/notes/ff3u.asm:23211-23233`)
→ the 15-byte formation records in `battle_monsters.dat` (`$CF6200`; layout
corroborated by the worked example at `ot6_hud.asm:1253-1256`) →
`monster_prop.dat`. Map titles from `map_prop.dat` +0 against
`map_title_en.json`; the random-battle enable is `$0525` bit 7
(`field/battle.asm:332`).

**Vector town has no random encounters at all** — every Vector map (`$0F1`–`$0FD`)
has the enable bit clear and battle group `$00`. The whole stretch's trash lives
in the Facility (`$106`–`$113`).

| id | species | lvl | HP | weak | absorb / null |
|---|---|---|---|---|---|
| `$0C7` | Commando | 18 | 580 | bolt \| water | — |
| `$0CB` | Garm | 19 | 615 | bolt \| water | — |
| `$165` | ProtoArmor | 19 | 670 | **bolt** | — |
| `$041` | Pipsqueak | 18 | 250 | bolt \| water | — |
| `$02D` | Trapper | 19 | 555 | bolt \| water | — |
| `$0A0` | Chaser | 19 | 1202 | bolt \| water | — |
| `$047` | Flan | 19 | 255 | **fire** | nulls poison/wind/holy/earth/water |
| `$066` | General | 19 | 650 | **poison** | — |
| `$088` | Gobbler | 19 | 470 | **none** | — |
| `$075` | Rhinox | 19 | 800 | **none** | **absorbs bolt** |

(Three MRF rooms — `$109`, `$10B`, `$10C` — have the enable bit set but battle
group `$00`, which resolves to table entry 0: Leafer `$017` / Dark Wind `$028`,
level-5 Narshe formations. **MARK: whether those rooms are reachable in a state
where the check runs was not verified.** If they are, they are a bug worth a
separate issue, not a balance input.)

**None of these species appear in `Ot6ElemAddTbl`** (`ot6_break.asm:334-428`;
the table's full id set stops at v0.4's search corridor) **or in
`Ot6ShieldTbl`** (`ot6_hud.asm:1273-1595`). So the element authoring for this
entire stretch is unwritten, and every trash body here takes formula shields plus
the generated weapon-class break floor.

**The finding that matters for this design:**

> Across the Facility's ten trash species, **exactly one is fire-weak** (Flan,
> and only in group `$68`) and **not one is ice-weak**. Six are bolt-weak — and
> Rhinox *absorbs* bolt.

So the coverage picture for the whole Vector/MRF stretch is: **Ramuh's bolt is
the near-skeleton key, and both of the release's headline rewards chip almost
nothing in the dungeon that grants them.** That is a real problem, and §9.3
turns it into an authoring ask rather than pretending the kits solve it.

---

## 3. The design call

> **Ifrit is weight. Shiva is economy. Neither is an element button.**

The pair is acquired together, in one fight, in a dungeon full of machines that
shrug off both of their elements. Designing them as a mirrored fire/ice pair —
which is what the vanilla rows and magicite.md's roster line currently do — buys
nothing: it gives the player two stones that do the same thing in opposite
colours, both of which are dead until Beat C.

The complementary reading the fight itself hands us is **the absorb lesson**.
The Ifrit & Shiva fight is, per `bosses-wob.md` §13, "the first hard absorb
lesson — feed Ifrit fire and he thanks you." The lesson is *the enemy's own
resources are on the table*. Both kits are built out of that lesson, on the two
axes the game tracks:

- **Ifrit takes HP off the enemy and keeps it** — Drain, plus the biggest raw
  body bonus in the game so far. He is the stone you hang on a *fighter* so
  they hit harder and stop needing a healer's turn.
- **Shiva takes MP off the enemy and keeps it** — Osmose, plus the mitigation
  that survives the dungeon's telegraph contract. She is the stone you hang on a
  *caster or support* so the party stops running dry.

Held together they close a loop: Shiva refuels the party's pools, Ifrit refills
the front line's HP, and the party can chain Facility encounters without an inn
trip. Held apart they are a damage stone and a support stone. Neither is
mandatory; both are obviously good at something the current four are bad at.

That is also why they take **different stats and different carriers** — the
Octopath sub-job question is "*who* does this complete?", and the answer must be
different people. Ifrit completes Sabin/Cyan/Edgar. Shiva completes Celes (or
Locke, or Setzer). Because there is one copy of each, that is a real party
puzzle rather than a stat check.

**On the roadmap's fire coverage hole.** ROADMAP M6 flags "Fire is a coverage
hole this stretch (Terra is the search target, absent)" for Zozo. Terra stays
absent through the Facility (§2.1). Ifrit is the deliberate answer — but the
answer lands *after* the dungeon, not inside it, and the doc says so rather than
pretending otherwise. Related recommendation, **out of scope for issue #16**:
Siren's grant list still carries a vanilla `FIRE` in slot 4
(`genju_prop.asm:95-96`) that magicite.md's own roster table does not list. When
Siren gets her redesign, drop it — fire should be Ifrit's deliberate key, not a
leftover on the control esper.

---

## 4. Ifrit — **the Furnace**

> *Menu line:* **IFRIT** — *The forge-beast. Bearer strikes far harder, and
> feeds on what it wounds.*

| channel | value |
|---|---|
| Grants | **Fire**, **Drain** |
| Stat (while equipped) | **+5 vigor** |
| Summon (divine) | **Inferno** — fire, all enemies (vanilla record, unchanged) |
| Weapon permit | **none** (§7) |

### 4.1 The two spells

| spell | id | MP | at 1 BP | at 2–3 BP | boost behaviour |
|---|---|---|---|---|---|
| Fire | `$00` | **4** | Fire 2 (pow 60) | Fire 3 (pow 121) | **folds** (`Ot6FoldTbl` row 0); excluded from the ×N multiplier by the tier-family scan at `ot6_kits.asm:1229-1239` |
| Drain | `$04` | **15** | ×2 | ×4 / ×8 | **multiplies** — not in any fold family, deals damage, so it takes `Ot6BoostDmg` in full |

Drain is non-elemental (`magic_prop_en.dat` spell `$04`, +0x01 = `$00`) and
drain-flagged (+0x04 bit `$02`), power 38, hit 120. It works on every machine in
the Facility, chips nothing (correct — non-elemental magic is the magic cousin
of null-break, DESIGN.md), and turns a fighter's turn into damage *and* healing.

**Why two spells and not three or five.** Ramuh — the previous marquee,
boss-scene esper — ships with exactly two (`genju_prop.asm:82-83`), so the
precedent exists. More importantly the empty slots *are* the design: Ifrit is
the stone you hold for the body, not the book, and a short list is what makes
that read at a glance. His third "slot" is the +5 vigor. If playtest wants a
third spell, the reserved candidate is **Bserk** (`$21`, 16 MP) for a full
berserker read — held back deliberately because it removes player control, which
is a worse fit for a stone meant to make a fighter *better*, not automatic.

**Deliberately not granted:**
- *Fire 2* — the dead pre-folded tier the current row carries. Deleted for the
  Kirin reason (`genju_prop.asm:130-137`).
- *Poison/Bio* — folds for 3 MP, which is enormous value, but poison is Edgar's
  authored key for the early game (weapon-classes.md, Measurement #8) and
  handing it to a second source dilutes the one element OT6 has actually
  authored encounters around.
- *Cure* — Kirin's. Ifrit heals by taking, not by giving; that is the whole
  difference between the two stones.

### 4.2 The stat: +5 vigor

`Ot6EsperStatTbl` byte: `OT6_SM_VIGOR | 5`.

- **Nobody else grants vigor.** The four shipped rows are Ramuh +3 stamina,
  Siren +2 speed, Stray +3 mag.pwr, Kirin +3 mag.pwr
  (`ot6_progression.asm:392-409`). Vigor is the unclaimed selector and the one
  that reads as "Ifrit".
- **Size.** Character base vigor at these levels sits at 31–47 (`char_prop.asm`:
  Terra 31, Locke 37, Cyan 40, Edgar 39, Sabin 47, Celes 34) and, with vanilla's
  per-level esper bonuses deleted (`genju_prop.asm:65-71`), those numbers barely
  move all game. +5 is ~11–16% — one clear step above the field-stone tier.
  Vanilla doubles vigor into the battle stat `$3b2c`
  (`ot6_progression.asm:269-271`), so the effective bump is +10.
- **Proposed magnitude ladder, so the tiers read:** *field stones* (Zozo,
  picked up off the floor) = 2–3; *boss stones* (Ifrit, Shiva) = 4–5. This is
  the first release where a player can feel that a fought-for stone is better
  than a found one. M6 owns the final numbers.
- **It is the right bonus for this dungeon.** §2.3: every Facility boss is
  class-breakable and several have no usable element row at all. Vigor is chip
  throughput on the axis the dungeon actually rewards.

### 4.3 The divine: Inferno

Vanilla record `$37` kept as-is: fire, all enemies, power 51, **26 MP**,
unblockable (+0x04 = `$20`, hit rate 0).

- **Once per battle, per character**, by vanilla's own latch — `tsb $3f2e` in
  `FixPlayerAttack` (`battle_main.asm:12747`), read by the Magic menu's enable
  pass (`battle_main.asm:14436-14439`). Nothing new is needed and nothing is
  changed.
- **Boost multiplies it.** `Ot6BoostDmg` exempts only fight, capture, bushido
  and steal (`ot6_kits.asm:1206-1224`); command `$19` is not exempt, so a 3-BP
  Inferno is ×8 on every enemy for its flat 26 MP. That is the Octopath divine
  register exactly — an apex moment you get once — and it is the reason Ifrit
  can afford a two-spell list.
- **It is the wrong tool for the rest of the Facility, on purpose.** The Right
  Crane absorbs fire; Number 128 and 024 do not care. Softening that would
  contradict the absorb lesson the dungeon exists to teach (`bosses-wob.md`
  §13), and OT6's house rule is that vanilla's rudeness survives. Ifrit's
  Facility value is his vigor and his Drain; his fire is what he is worth in
  Beat C onward.

### 4.4 Divine cadence: the summon does **not** replace the character's divine

magicite.md left this open ("both exist, but both share the once-per-battle
register… playtest for redundancy in M6"). **Call: keep the two latches
separate.** The summon rides vanilla's `$3f2e`; kit divines ride OT6's
`OT6_DIVINE_USED` at `$3ecb` (`ot6_memory.inc:42-44`, used by `Ot6Oblivion` /
`Ot6Assassinate`, `ot6_kits.asm:264`, `:346`).

Reason: they are different resources. The summon lives on a transferable stone
and costs MP; the divine is a permanent property of the character. Fusing them
would mean **handing Cyan a magicite disables Oblivion**, which punishes the
sub-job system for being used — the opposite of what a sub-job should do. Two
apex actions in one battle is a real power spike, so M6 measures it; if it is
too much, the lever is the summon's MP cost, not the latch.

---

## 5. Shiva — **the Rime**

> *Menu line:* **SHIVA** — *The still cold. Bearer draws the fight's own magic
> out of it, and turns spellfire aside.*

| channel | value |
|---|---|
| Grants | **Ice**, **Osmose**, **Shell** |
| Stat (while equipped) | **+4 magic power** |
| Summon (divine) | **Diamond Dust** — re-authored: ice, all enemies, reduced power, **inflicts Slow** |
| Weapon permit | **none** (§7) |

### 5.1 The three spells

| spell | id | MP | boost behaviour | why |
|---|---|---|---|---|
| Ice | `$01` | **5** | **folds** to Ice 2 / Ice 3 | the element she carries out of the dungeon; the chip axis against Ifrit and everything ice-weak after |
| Osmose | `$29` | **1** (see §6) | multiplies (MP damage) | the party's only MP income; the answer to v0.5's live MP economy |
| Shell | `$25` | **15** | **inert** — see below | the answer to the Facility's telegraph contract |

**Shell is the Facility-specific pick and it is deliberate.** Read the dungeon's
telegraphs: Ifrit → Fire 2, Shiva → Ice 2 (`bosses-wob.md` §13), Number 024 →
the wall's matching tier-2 spell (§14), the Cranes → Fire 3 / Giga Volt /
Magnitude8 (§16). Three of the four remaining boss fights answer to magic
mitigation, and nobody in the party has any. Vanilla Shell is single-target
(`magic_prop_en.dat` spell `$25`, +0x00 = `$01`; the multi-target rows in that
table carry `$6x`) and costs 15 MP — expensive, which is exactly why Osmose sits
beside it. *Safe* was considered and rejected: only Number 128's Gale Cut is a
physical threat, and Golem owns Safe in magicite.md's roster.

**Known wart: boosting Shell does nothing.** It is not in `Ot6FoldTbl` and it
deals no damage, so `Ot6BoostDmg` has nothing to multiply. DESIGN.md's BP
economy promises "Buffs/debuffs: duration per BP" but no such mechanism is
built. Flagged in §12; it is a general gap, not a Shiva bug, and Shiva is
simply the first kit to walk into it.

**Deliberately not granted:**
- *Ice 2* — dead pre-folded tier, deleted (same reason as Ifrit's Fire 2).
- *Rasp* — Ramuh already grants it (`genju_prop.asm:82-83`). Splitting the MP
  war (Ramuh destroys MP, Shiva steals it) keeps two stones distinct instead of
  one strictly better.
- *Cure* — the current vanilla row's 5th slot. Kirin's job. Shiva prevents
  damage; Kirin repairs it.
- *Slow* — folds to Slow 2 (all enemies) for 5 MP, which is superb value and
  very much Shiva. It goes on the **divine** instead (§5.3), so the list and the
  summon do not duplicate each other, and so Siren keeps a reason to exist.

### 5.2 The stat: +4 magic power

`Ot6EsperStatTbl` byte: `OT6_SM_MAGPWR | 4`.

Base mag.pwr sits at 25–39 (`char_prop.asm`: Celes 36, Terra 39, Strago 34,
Locke 28, Sabin 28), so +4 is ~10–16%. It is one step above Kirin's and Stray's
+3 (`ot6_progression.asm:400`, `:409`) — the boss-stone tier from §4.2 — and it
is the honest selector: her list is three spells, two of which scale off
mag.pwr.

**This is the one place the machinery forced a compromise.** What the design
wants is a *two-sided* mod — Ifrit +vigor / −mag.pwr, Shiva +mag.pwr / −vigor —
so that the two stones read as opposite specialisations rather than as "a big
number for fighters" and "a big number for mages". `Ot6EsperStatTbl` cannot
express it: one selector, one unsigned 4-bit magnitude
(`ot6_progression.asm:314-320`). See §12.

### 5.3 The divine: Diamond Dust, re-authored

Vanilla `$38` is a straight mirror of Ifrit's `$37` — same targeting, same
flags, power 52 vs 51, 27 MP vs 26. A mirror divine is the exact failure this
document is trying to avoid.

**Re-author it as the tempo divine:** ice, all enemies, **power 52 → 34**, and
add **Slow** to the record's status bytes.

| field | offset in record `$38` | from | to |
|---|---|---|---|
| spell power | +0x06 | 52 | **34** |
| status byte 3 | +0x0C | `$00` | **`$04`** (`STATUS3::SLOW`, `const.inc:1517`) |

Everything else — targeting `$6e`, element `$02`, unblockable `$20`, 27 MP —
unchanged.

- **Why Slow.** It is element-independent, so it is worth something against the
  machines that shrug off ice, and it directly buys the party more actions
  inside every telegraph fuse — the same job as Shell, on the other side of the
  equation. Decoded from `monster_prop.dat` +0x16 (STATUS3 immunities): Number
  128 `$10`, both Cranes `$10`, both blades `$00` → **Slow lands**; Number 024
  `$14` → **Slow is blocked**. That spread is good design luck: it works
  everywhere except the boss whose whole contract is "classes are the handhold"
  (`bosses-wob.md` §14).
- **Boost canon.** Diamond Dust is a **damage verb**, so boost multiplies its
  damage and *does not* touch the rider — the same no-double-dip line that
  keeps folded spells out of `Ot6BoostDmg`. Because the record is already
  unblockable (+0x04 = `$20`, hit 0), there is no chance axis for boost to
  guarantee, so the canon rule stays legible.
- **UNVERIFIED and load-bearing:** whether an unblockable (+0x04 `$20`,
  hit-rate 0) damage spell also applies its status bytes without a roll, and
  whether per-monster STATUS3 immunity is still consulted on that path. Read the
  status-application path off `CalcAttackEffect` / `ApplyDmg`
  (`battle_main.asm:2964-3050` is the damage half) before building. If the
  answer is "unblockable skips the status", the fallback is Siren's shape
  (`magic_prop_en.dat` `$39`: +0x04 = `$00`, hit 136, status byte set), which
  demonstrably works — at the cost of making the rider blockable.
- **Lower power is the point.** Inferno stays the damage divine; Diamond Dust
  becomes the control divine. Boosted to ×8 it is still a real nuke; it just is
  not *the* nuke, and the pair finally reads as two different apex moments.

---

## 6. Osmose, and the biggest balance risk in this design

**Osmose costs 1 MP** (`magic_prop_en.dat` spell `$29`, +0x05 = `$01`), power
26, hit 150, MP-targeting (+0x03 bit `$80`), drain-flagged (+0x04 bit `$02`).
Facility boss MP pools run **447–810** (§2.4). Party max MP at this point is
roughly 40–60 (mp-economy.md).

FF6's magic damage scales on power, level and mag.pwr; at Facility levels a
single unboosted Osmose computes for several hundred, which is many times the
caster's entire pool. **One 1-MP cast is a full refill, against any enemy with
MP, every fight.** And v0.5 flipped `OT6_MP_COSTS` on, making *every* verb but
Fight cost MP (mp-economy.md; owner ruling 2026-07-22) — so a character who
never runs dry is worth vastly more now than when the drain-verb ruling was
written.

Compounding it: MP damage rides the same `$11b0` value the boost multiplier
edits, so `Ot6BoostDmg` scales it too (`ot6_kits.asm:1240-1252`; MP application
at `ApplyDmgMP`, `battle_main.asm:3021-3050`). *(**UNVERIFIED:** whether the
drain half credits the caster with the **computed** amount or with the amount
actually removed from a smaller pool. Read `_c213a7`'s net-damage path before
tuning. It changes the size of the problem, not its existence.)*

Existing canon already anticipated the shape and blessed it — mp-economy.md:
"MP-drain verbs stay… reaching one is a deliberate perk: this character can
manage their own resources. Osmose (Shiva) and Rasp (Ramuh) sit in the esper
pool." That ruling is from 2026-07-17, **before** costs went live and before the
"only Fight is free" absolute. The ground moved under it.

**The call: keep Osmose on Shiva — it is her identity and it is the one thing
the party genuinely lacks — and reprice it.**

> **Proposal: Osmose `$29` +0x05: 1 → 8 MP.**

This is an explicit, argued exception to mp-economy.md's "Magic keeps its
vanilla MP costs (house rule)." The justification is that vanilla priced Osmose
at 1 MP in a world where four characters spent MP at all; under OT6 every verb
does, and a 1-MP full refill is not a spell, it is an off switch for a currency
the release just turned on. 8 MP keeps it strongly net-positive (still a
refill), keeps it castable on an empty-ish pool, and stops it from being free.
It is one byte, and it applies globally (ZoneSeek inherits it, correctly).

**Rejected alternatives**, recorded so the decision does not get relitigated:
- *Drop Osmose from Shiva.* Loses the whole "she takes the fight's fuel" identity
  and leaves the MP economy with no answer at the exact release it went live.
- *Gate boost off MP-targeting spells* (a `+0x03` bit-`$80` test inside
  `Ot6BoostDmg`, beside the existing command gates). Worth doing **as well** if
  measurement wants it — it is the same shape as the steal exemption — but it
  does not fix the unboosted case, which is already the whole problem.
- *Cap the drain at the caster's missing MP.* New battle-code, and it makes the
  spell's behaviour unreadable.

**This is the single biggest balance risk in the design** and the one to
measure first: `bal_party.lua` with an Osmose-cycling policy against a Facility
fixture, watching mp-economy.md's proposed M6 bands (`mp_spent`,
`mp_restored`, mp-zero incidence, "a refill arrives before ~70% depletion").

---

## 7. Weapon permits: deliberately none

magicite.md's roster line assigns Ifrit "slashing (claws)" and Shiva
"bludgeoning (rods)". **Neither ships.** Four reasons, in order of weight:

1. **The channel does not exist.** No equip-side code reads a permit; the only
   mention in the source is a forward-looking comment (`ot6_class.asm:17`).
   Building an equip-menu permit system to serve two stones is the wrong place
   to spend v0.6, and weapon-classes.md itself calls permits "a knob to gesture
   with, not a system to balance around."
2. **The headline use case is already covered without one.** magicite.md's
   argument for Ifrit's claw permit is "Sabin + Ifrit = the fire fist" — but
   weapon-classes.md already rules that "equipping claws switches his *Fight* to
   slashing ✦". Sabin can wear claws today. The permit buys nothing.
3. **There is no class hole to fill here.** Every Facility boss is
   slash|pierce-breakable (§2.3) and the fixed party covers both.
4. **Scarcity is the design.** magicite.md caps WoB permits at three so that
   multi-class characters read as builds. Spending two of the three on the pair
   that needs them least is a bad trade.

**Recommendation:** the first permit ships with **Golem** (piercing — the siege
engine read) or **Stray** (slashing/claws — the alley-cat read), in a release
that is already doing equip-menu work, against a stretch with an actual class
gap. Recorded here so the deferral is a decision, not an omission.

---

## 8. Player-facing copy

### 8.1 The gap

The esper detail screen is **untouched by OT6** and is now actively misleading
(`skills.asm:2570-2645`):

- It draws each granted spell's **learn rate as a percent**, read from
  `GenjuProp`'s even bytes — which M5 zeroed on purpose
  (`genju_prop.asm:56-64`). Every esper shows five rows of nothing-per-cent, for
  a system that no longer teaches anything.
- It draws a **"at level up:"** line from the bonus byte, and **blanks it** when
  the byte is `$ff` (`skills.asm:2627`, the `@5a67` path) — which M5 made
  universally true (`genju_prop.asm:66-71`). So the while-equipped stat mod,
  the single most important thing a player needs to know about a stone, is
  invisible.

A player equipping Ifrit today sees a fire spell, a drain spell, two `0%`
columns, and a blank line where the reason to equip him should be.

### 8.2 What to change

Two edits, both C3 menu-bank work of the same shape as the Bushido submenu
(kits.md, #8 Layer A) — i.e. real work, priced honestly:

1. **Replace the learn-% column with the spell's MP cost.** The number a player
   needs is what the spell costs to cast, and MP is now live for every verb.
   `Ot6CostFor`/`Ot6LoadoutCost` already exist as menu-callable pricing shims
   (`ot6_kits.asm:1167-1176`), so the menu and the charge cannot disagree.
2. **Replace the "at level up:" line with a "while equipped:" line**, drawn from
   `Ot6EsperStatTbl` rather than the `$ff` bonus byte. Vanilla's
   `GenjuBonusName` strings are fixed 9-character rows indexed 0–16
   (`genju_bonus_name_en.json`) and top out at "+2", so they cannot be reused —
   this needs its own short string table in bank `$F0`.

Proposed lines, at the 9-character width the existing column uses:

| esper | line |
|---|---|
| Ifrit | `Vigor  +5` |
| Shiva | `MagPwr +4` |

**Zero-code fallback if the menu work slips:** the acquisition dialogue is the
only other surface, and the two stones arrive in a scripted scene. Say it in the
text — *"Take my fire, and my strength."* / *"Take my cold, and my sight."* —
and file the menu work as a v0.7 item. This is a fallback, not the plan; a
hidden stat bonus is the same hidden-tax problem that kept `OT6_MP_COSTS`
dormant for a whole release (mp-economy.md, "Why dormant").

### 8.3 Names

Keep `GenjuName` "Ifrit" / "Shiva" and the vanilla summon names (`Inferno`,
`Diamond Dust`, `genju_attack_name_en.json`). The sub-job nicknames — *the
Furnace*, *the Rime* — are documentation vocabulary, not shipped strings.
Vanilla's names are the ones players already know, and DESIGN.md's difficulty
transform says to preserve the enemy/esper fantasy unless a deliberate redesign
says otherwise.

---

## 9. Balance

### 9.1 Against the Factory party

The test is issue #16's: *a meaningful choice, not a single answer.* Six stones,
four slots.

| stone | wants to be worn by | competes with | the choice |
|---|---|---|---|
| Ramuh | any caster | — | keeps its slot: bolt is the Right Crane's only reachable element key |
| Kirin | the designated healer | Ifrit (partly) | keeps its slot, but Ifrit's Drain now makes a Kirin-less party viable in trash |
| **Ifrit** | Sabin / Cyan / Edgar / Locke | **Siren** | Siren's incidental Fire vs Ifrit's deliberate Fire + Drain + a body bonus. Ifrit should win the fire slot; Siren survives as the control stone (Sleep/Mute/Slow) |
| **Shiva** | Celes / Locke / Setzer | **Stray** | Stray's Muddle/Imp/Float trickster kit vs Shiva's Osmose/Shell sustain-and-mitigate. Shiva should win in a boss dungeon; Stray should win in a trash-heavy sweep |
| Siren | a caster | Ifrit | control |
| Stray | a caster | Shiva | disruption |

The failure mode to watch is **Ifrit + Kirin + Shiva + Ramuh becoming the
answer to everything**, with Siren and Stray retired. If measurement shows that,
the lever is Ifrit's list (two spells is already thin; the vigor bump is the
knob) rather than nerfing the two Zozo stones the v0.4 pass already tuned.

### 9.2 Against the boss keys

| fight | element key | class key | what Ifrit adds | what Shiva adds |
|---|---|---|---|---|
| Ifrit & Shiva `$109`/`$108` | ice → Ifrit, fire → Shiva | pierce / slash | *(not yet owned)* | *(not yet owned)* |
| Number 024 `$10a` | rotating, re-hidden | slash\|pierce | **vigor on the class axis**; Drain (element-independent) | **Shell** vs the wall's tier-2 payoff; Osmose vs a 777 pool. *Slow is immune here* |
| Number 128 `$10b` | authored bolt/water (see below) | pierce | vigor; Drain | **Diamond Dust's Slow**; Shell. *Ice is absorbed — do not cast it* |
| Cranes `$10d`/`$10e` | water (both), bolt (right only) | pierce | vigor; Drain. *Inferno is absorbed by the right Crane* | **Slow on two independent fuses**; Shell vs Fire 3 / Giga Volt |

Both stones contribute to all three post-acquisition fights **without their
element**, which is the §3 thesis holding up.

**An authoring dependency, not a design one:** `bosses-wob.md` §15 lists Number
128 as "bolt, water + piercing", but `monster_prop.dat` `$10b` +0x19 reads
`$00` — it has **no vanilla element weakness**, and `Ot6ElemAddTbl` stops at
v0.4's search corridor (`wob-route.md` §4). That bolt row has to be *authored*
during Beat B or Ramuh's "sub-job debut" moment (`bosses-wob.md` §15) does not
exist. Out of scope for issue #16; raised because the Ifrit/Shiva balance story
assumes the rest of the beat's element authoring happens.

### 9.3 Against the encounter set — and the authoring ask

§2.5's decode: one fire-weak species (Flan), zero ice-weak species, six
bolt-weak, one bolt-absorber, two with no element row at all, and **no
`Ot6ElemAddTbl` coverage for any of them**.

Two things follow, and they pull in opposite directions.

**(a) The kits are already built for this, and that is the good news.** Neither
stone's Facility value is elemental — Ifrit's is +5 vigor on the class axis the
break floor gives every one of these bodies, plus non-elemental Drain; Shiva's
is Osmose, Shell, and Diamond Dust's Slow. A player who equips both and never
casts Fire or Ice still gets full value out of them for the whole dungeon. That
is §3's thesis being load-bearing rather than decorative.

**(b) But "your new stone chips nothing" is still a bad feeling, and the fix is
an authoring pass, not a kit change.** Recommendation for the Beat B M6 pass,
following Measurement #8's discipline (`balance-metrics.md:811` — author where a
species *needs* a reachable axis, keep the keys roughly even):

- Give **fire** a real footprint. The Facility is full of oiled machinery and
  organics; Flan is the only fire-weak body and it appears in one group. Two or
  three `Ot6ElemAddTbl` rows (Gobbler `$088` and Rhinox `$075` are the obvious
  candidates — they currently have **no** element weakness at all, exactly the
  Cirpius/Rhodox hole Measurement #8 closed with poison) would make Ifrit's fire
  a key without displacing bolt.
- Give **ice** a footprint too, or accept that Shiva is a support stone in this
  dungeon and say so in her acquisition copy. ProtoArmor `$165` is the natural
  ice add — armour, coolant, the machine that overheats — and it is currently
  bolt-only, so adding ice widens rather than replaces.
- **Do not** blanket-add bolt. Six of ten species already carry it and Ramuh is
  already close to a skeleton key here; Rhinox's bolt *absorb* is the one thing
  keeping that honest and should stay.

This is out of scope for issue #16 (which is the kits), but the two issues
should ship in the same release or Ifrit and Shiva will read as dead loot.

**What still needs measuring:**

- Does Fire-at-4-MP-folding-to-Firaga trivialise Facility trash once it *has*
  targets? Bodies here run 250–1202 HP at level 18–19, so a 4-MP Fire 3 (power
  121) into a fire-weak, shielded body is ×2 weak × the shielded/broken factor —
  the 8:4:2:1 ladder in DESIGN.md. Measure before authoring more fire, not after.
- Does Osmose-cycling make MP attrition a non-event? (§6 — the headline
  measurement.) Note that trash MP pools, unlike the 447–810 boss pools, were
  not read; if trash pools are small the exploit is boss-only, which changes the
  urgency but not the call.
- Do the boss-tier stat magnitudes (+5 / +4) move `char_dmg_taken` and
  `player_actions_broken` enough to be felt, without moving break-lands-at%
  past the band? Run `bal_party.lua`'s `boost3` policy with and without each
  stone equipped and diff.

### 9.4 MP arithmetic, one worked line

A Celes wearing Shiva at ~50 max MP: Shell (15) on the front-liner, Ice at 1 BP
(5) as a probe, Osmose (**8** after the reprice) to refill — net −12 MP per
three actions against any enemy with a pool, versus −20 without Osmose. That is
the intended shape: **noticeably sustaining, not free.** At vanilla's 1 MP it is
−19 for three actions *and* a full refill, i.e. permanently net-positive, which
is §6's problem stated as a number.

---

## 10. The data, literally

Everything this design asks for, as edits. No new battle code is required for
anything except the menu copy (§8.2) and — if measurement wants it — the
optional `Ot6BoostDmg` MP-targeting gate (§6).

**`ff6/src/menu/genju_prop.asm`** — replace rows 1 and 2:

```
; 1: ifrit -- the Furnace.  BASE-TIER Fire (folds to Fire2/Fire3 via Ot6FoldTbl)
;   plus Drain, which is in no fold family and correctly takes Ot6BoostDmg's
;   multiplier instead.  The vanilla FIRE_2 grant is DROPPED for the Kirin
;   reason: a pre-folded tier is a dead, un-foldable row beside the base spell.
make_genju_prop {FIRE, 0}, {DRAIN, 0}, {}, {}, {}

; 2: shiva -- the Rime.  Base-tier Ice (folds) + Osmose (MP income) + Shell
;   (the Facility's telegraphs are tier-2/3 magic).  ICE_2 dropped as above;
;   RASP left to Ramuh; CURE left to Kirin.
make_genju_prop {ICE, 0}, {OSMOSE, 0}, {SHELL, 0}, {}, {}
```

**`ff6/src/battle/ot6_progression.asm`**, `Ot6EsperStatTbl` rows 1 and 2:

```
        .byte   OT6_SM_VIGOR  | 5       ;  1 ifrit    +5 vigor  (the only vigor
                                        ;    stone; boss-tier magnitude)
        .byte   OT6_SM_MAGPWR | 4       ;  2 shiva    +4 mag.pwr (boss-tier, one
                                        ;    step over Kirin/Stray's +3)
```

**`ff6/src/battle/magic_prop_en.dat`** — three bytes:

| record | offset | from | to | why |
|---|---|---|---|---|
| `$29` Osmose | +0x05 (MP) | `01` | **`08`** | §6 |
| `$38` Shiva summon | +0x06 (power) | `34` (52) | **`22`** (34) | §5.3 |
| `$38` Shiva summon | +0x0C (status 3) | `00` | **`04`** | §5.3, `STATUS3::SLOW` |

**Unchanged, explicitly:** Ifrit's summon record `$37`; every learn-rate byte
(stays 0); every `GENJU_BONUS` byte (stays `$ff`); `Ot6FoldTbl`; `Ot6ShieldTbl`
rows `$108`/`$109`; `Ot6AbilityCostTbl` (magic prices on the vanilla ruler).

---

## 11. Tests (issue #16's acceptance criteria)

Model on `battle_subjob.lua` (grant + deletions) and `battle_esperstats.lua`
(the stat half), which already carry the per-esper kit confirmations for the
four Zozo stones. Add Ifrit and Shiva as new scenarios in the same file rather
than new files — they are the same assertions with different rows.

| # | assertion | shape |
|---|---|---|
| 1 | equip Ifrit → Fire and Drain appear in the in-battle Magic list; **Fire 2 does not** | the `checkEsper(..., grants, absents)` shape `battle_esperstats.lua` already has (see its Kirin row, which already asserts "NOT Cure2") |
| 2 | equip Shiva → Ice, Osmose, Shell appear; Ice 2, Rasp, Cure do not | same |
| 3 | unequip → both lists revert; the BASE negative control | `battle_esperstats.lua`'s existing BASE scenario |
| 4 | Ifrit worn → vigor +5 and **only** vigor; Shiva worn → mag.pwr +4 and only mag.pwr | same file's stat comparison |
| 5 | granted Fire at 2 BP queues attack id `$09` and charges **4** MP, not 51 | extend `battle_fold.lua` / `battle_mpcost.lua`; this is the load-bearing interaction of the whole design |
| 6 | granted Ice at 2 BP queues `$0a` and charges **5** MP | same |
| 7 | Osmose charges **8** MP and restores the caster; refused at < 8 MP | `battle_mpcost.lua`'s charge+refusal pattern |
| 8 | Inferno usable once per battle per character; the esper row greys after | drive `$3f2e`; positive control that the row was *offered* first (CONTRIBUTING: a quiet test is not a passing test) |
| 9 | Diamond Dust applies Slow to a non-immune target and **not** to Number 024 | the §5.3 UNVERIFIED item is what this test exists to settle; it must fail loudly if the status silently never applies |
| 10 | boosted Inferno takes the ×2/×4/×8 multiplier; boosted Fire does **not** (it folded) | `Ot6BoostDmg`'s tier-family scan is the thing under test |

Frontier gating: these ride the Beat B fixtures (`@suite frontier=<name>`), so
they report "skipped" until the Vector/MRF chain mints — the house pattern.

---

## 12. What the shipped machinery **cannot** express

The important section. Every item here is a design intent this document wanted
and had to give up, drop, or route around.

1. **A two-sided stat mod.** `Ot6EsperStatTbl` is one selector, one *unsigned*
   4-bit magnitude (`ot6_progression.asm:314-320`, `:335-380`). There is no way
   to say "+5 vigor, −3 mag.pwr". The pair's identities would be sharper as
   opposed specialisations than as two positive numbers, and that is the single
   biggest expressiveness gap. Fixing it is small — widen the table to two bytes
   and make the magnitude signed, with a floor clamp beside the existing `$ff`
   cap — but it is a change to shipped machinery and to `battle_esperstats.lua`.
2. **More than one stat per stone.** Same table, same limit. "+vigor and
   +stamina" is not sayable.
3. **HP% / MP% mods.** Structurally deferred: the selector has no encoding for
   them (`ot6_progression.asm:299-303`). *Max MP up* is one of mp-economy.md's
   named MP-relief candidates and cannot be authored on either stone.
4. **Named passives.** *Kindling* ("fire spells chip +1") and *Frostbite* ("ice
   chip +1") from magicite.md's roster have no ROM behind them — there is no
   passive pool, no slots, no learning meter (ROADMAP M4, ⬜). Both stones are
   designed without them, which is why so much weight lands on the spell lists.
5. **Weapon permits.** No equip-side consumer exists (`ot6_class.asm:17`). §7
   turns this into a deliberate design call rather than a blocker, but it is a
   real missing channel.
6. **Boost on a buff.** DESIGN.md promises "Buffs/debuffs: duration per BP".
   Nothing implements it: `Ot6QueueFold` only folds the 8 tier families and
   `Ot6BoostDmg` only multiplies damage. **Boosting Shiva's Shell does literally
   nothing** and the UI will happily let a player spend 3 BP on it. This is the
   most player-visible gap in the list.
7. **A boost/fold family for anything outside the 8 rows.** `Ot6FoldTbl` is
   scanned with a hard `cpx #$0018` bound in three places
   (`ot6_boost.asm:255,:317`, `ot6_kits.asm:1233`), so adding a ninth family
   means touching all three. Not needed by this design; noted because the next
   esper's might.
8. **Per-esper summon gating beyond vanilla's.** The once-per-battle latch is
   vanilla's `$3f2e` and is per-character, party-wide-uniform. There is no way
   to say "this summon is twice per battle" or "this summon requires a Broken
   target" the way `Ot6Oblivion` can for a kit divine.
9. **Esper menu copy.** §8.1 — the detail screen shows misleading learn-% and
   hides the stat mod entirely. This is menu-bank (C3) work that has not been
   started, and it is the difference between "Ifrit makes you hit harder" being
   a mechanic and being a secret.
10. **Re-pricing magic without breaking a house rule.** Magic prices through
    vanilla `GetMPCost` off the spell record; `Ot6AbilityCostTbl` keys only
    blitz/bushido/tool id ranges (`ot6_boost.asm:352-400`). Repricing Osmose is
    a one-byte `.dat` edit, so it is *possible* — but it is a global change to a
    vanilla spell, and mp-economy.md's "magic keeps vanilla costs" rule has to
    be explicitly amended rather than quietly bent.

---

## 13. Open questions for the driver

1. **Osmose's price.** Is 8 MP the call, or does the house rule ("magic keeps
   vanilla MP costs") win and the risk get carried into playtest instead?
   Recommendation: reprice — the rule predates the release that made MP matter.
2. **Diamond Dust's power cut.** 52 → 34 is chosen so the two divines stop being
   mirrors. Too far? The alternative is keeping power and dropping the Slow
   rider, which puts us back where we started.
3. **Ifrit's third slot.** Two spells and a big body bonus, or add Bserk? This
   document argues two; it is the most reversible decision here.
4. **Two divine latches or one** (§4.4). Recommendation: two, because fusing
   them punishes wearing a magicite. Flagged for M6 measurement.
5. **Siren's leftover Fire** (`genju_prop.asm:95-96`). Drop it when Siren gets
   her pass, so Ifrit is the deliberate fire key? magicite.md's roster table
   already omits it, so this is arguably just finishing the v0.4 data pass.
6. **The `bosses-wob.md` §16 correction** — "Ifrit's fire" as a Crane key is
   contradicted by the same section's own decode. Who owns that edit?
7. **The Beat B element-authoring pass** (§9.3). Ifrit and Shiva chip almost
   nothing in the Facility as its data stands — one fire-weak species, zero
   ice-weak. Does the `Ot6ElemAddTbl` pass ship in v0.6 alongside these kits, or
   do the stones ship as deliberate support/stat rewards with copy that says so?
   Recommendation: same release, or the reward reads as dead loot.
8. **MRF rooms `$109`/`$10B`/`$10C`** have random battles enabled but battle
   group `$00`, which resolves to the level-5 Leafer / Dark Wind formations. If
   those rooms are walkable with the check live, that is a vanilla oddity worth
   its own issue — noted here only because it turned up in the §2.5 decode.
