# The tube-room six — magicite sub-job designs (v0.7)

The six espers the tube room grants at once — MADUIN, SHOAT, PHANTOM,
CARBUNKL, BISMARK, UNICORN (`give_genju` block,
`ff6/src/field/event_main.asm:95777-95782`) — designed **in place**: the
all-six-at-once acquisition stays, because redistribution would be an event
edit plus regenerating every savestate and would buy no player-visible pacing.
§11 is the data, literally.

v0.7 has no conventional boss (`wob-route.md` §1's beat table), so these
six stones **are** the stretch's player-facing content. The exit criterion is
M5's: six stones sharing one acquisition moment need six distinct reasons to
swap mid-dungeon — differentiation, not a power ranking.

**Canon boundary.** The shipped **while-equipped** model is the baseline:
equip grants the spell list live, the stat mod exists only while worn, nothing
is learned, the summon is the once-per-battle divine
(magicite-ifrit-shiva.md, "Canon boundary"). magicite.md's roster row for each
stone is treated as an **identity seed** — its PASSIVE column (*Trinity*,
*Gorgon Eye*, *Ghostwalk*, *Facet*, *Tidal*, *Purity*) is unbuildable (no
passive channel exists in the ROM) and is re-expressed here through what IS
buildable, or dropped outright into §13's ledger. The seed names survive as
each stone's documentation nickname.

**Evidence rule (CONTRIBUTING.md).** Every mechanical claim cites the file and
line it was read from, or is labelled **UNVERIFIED**. Numbers taken out of
`.dat` files name the record and byte offset.

---

## Summary table

A stone's stat package is two bytes in vanilla's own equipment layout — four
*signed* nibbles, −7..+7 each, over vigor/speed/stamina/mag.pwr
(`docs/design/esper-stat-baseline.md`). Each stone below moves two or three stats
and five of the six carry a **downside**; `ot6_progression.asm`'s table carries
the per-esper reasoning.

| esper (idx) | nickname | grants | stat vig/spd/stm/mag | divine (vanilla record, all kept) | the swap reason |
|---|---|---|---|---|---|
| Maduin (6) | **the Trinity** | Fire, Ice, Bolt | **−3 / 0 / +3 / +7** | **Chaos Wing** `$3c`: non-elem 55, all enemies, 44 MP | one caster, three fold families — the right element on demand |
| Shoat (5) | **the Gorgon Eye** | Break, Doom | **−2 / +6 / +2 / 0** | **Demon Eye** `$3b`: petrify all, hit 96, 45 MP | delete one body per turn, where deletion is legal |
| Phantom (20) | **the Ghostwalk** | Vanish, Demi | **0 / +6 / −2 / +2** | **Fader** `$4a`: Clear on the party, 38 MP | the party stops being hit by physicals |
| Carbunkl (19) | **the Facet** | Rflect, Safe | **0 / −2 / +6 / +2** | **Ruby Power** `$49`: Rflect on the party, 36 MP | the fight's spellfire turns around |
| Bismark (7) | **the Tide** | Haste, Slow | **+5 / −2 / +3 / 0** | **Sea Song** `$3d`: WATER 58, all enemies, 50 MP | tempo both ways — and the game's only water verb |
| Unicorn (23) | **the Purity** | **Pearl** (§9), Remedy | **0 / 0 / +5 / +2** | **Heal Horn** `$4d`: Remedy on the party, 30 MP | the undead stretch's master key, and the cleanse |

Six stones, six *shapes*: Maduin is a caster who cannot punch, Shoat a striker's
speed without the strike, Phantom fast and bodiless, Carbunkl a wall that does
not move, Bismark mass that is slow, and Unicorn the only one that asks for
nothing back. That last is deliberate — the Pearl grant is where his power is
(§9), so his stat package is the smallest and the only one with no downside.

**Headline finding: no summon re-author is needed.** Unlike Inferno/Diamond
Dust — a mirrored pair that had to be split apart — vanilla already authored
these six divines as six different verbs: a petrify wipe, a non-elemental
nuke, a water nuke, party-reflect, party-vanish, party-cleanse (records
`$3b/$3c/$3d/$49/$4a/$4d`, decoded §4-§9; names Demon Eye / Chaos Wing / Sea
Song / Ruby Power / Fader / Heal Horn, `genju_attack_name_en.json`). The
MagicProp splice gains **zero new overrides** this pass.

---

## 1. The constraint budget

magicite-ifrit-shiva.md §1 is the authority on what the machinery can express:
≤5 spell ids per stone (`ot6_progression.asm:142-181` `Ot6EsperSpellKnown`,
`:203-252` `Ot6UnionEspers`), a while-worn stat package of four *signed*
nibbles, −7..+7 each, over Vigor/Speed/Stamina/Mag.Pwr in vanilla's own
`ItemProp+16/+17` layout (`ot6_progression.asm`, `Ot6EsperStatMod`), the
once-per-battle summon on vanilla's `$3f2e` latch (`battle_main.asm:12852` sets
it, `:14550` greys the menu row), boost folding for 8 families only
(`Ot6FoldTbl`, `ot6_boost.asm:340-348`), and the ×2/×4/×8 multiplier on
non-folding damage (`Ot6BoostDmg`, `ot6_kits.asm:1190-1256`; summons are not
exempt, `:1206-1224`). No passives, no permits, no learn rates.

Two things the design leans on:

1. **The esper detail page renders the kit accurately.** There is no learn-%
   column (blanked caption `skills.asm:2528-2544`, forced blank per-row
   `:2606-2608`), and the bonus line is a **"While worn...&lt;Stat&gt;+N"**
   block drawn straight from `Ot6EsperStatTbl` (`skills.asm:2624-2673`). So an
   authored stat row is automatically player-visible, and a `$0000` row draws a
   blank line.
2. **MP is universal** — every character brings their save's pool into battle.
   A stone on Locke or Sabin has a real pool behind it; granted-spell MP prices
   below are judged against this stretch's pools of roughly 40-60.

The vanilla rows these replace are placeholders, and three of them are broken
the same way Ifrit's and Shiva's were:

- **Vanilla Maduin grants three dead pre-folded tiers** — `FIRE_2, ICE_2,
  BOLT_2`, 20-22 MP each for what the base spells deliver at 4-6 MP under one
  boost. All three go (the Kirin reason).
- **Vanilla Bismark grants Life**, which violates kits.md's written rule that
  revival "lives on Terra, Fenix Downs, and Sraphim, and nowhere else"
  (kits.md, Terra section) — revival on a stone anyone can wear. Dropped.
- **Vanilla Shoat grants Bio** — the pre-folded **cap** of the poison family
  (`Ot6FoldTbl` row 3, `ot6_boost.asm:344`): 26 MP for what a 3-MP Poison folds
  into at 1 BP. It is also poison into a stretch where four of five cave
  species **absorb** poison (§2.2) — a 26-MP self-heal button for the enemy.
  Dropped.

---

## 2. Where the player is standing

### 2.1 The stretch's three parties

The stretch's route puts three different parties in front of these stones:

- **The cave: TERRA / LOCKE / EDGAR / SABIN** (owner ruling; Terra is a hard
  requirement at the base). Terra is the stretch's only innate
  mage — at these levels ~15-16 she knows Fire, Cure, Drain (kits.md, Terra's
  table; Life is L18). Locke, Edgar, Sabin cast **only** through their stones.
- **The banquet: TERRA + LOCKE** (`event_main.asm:99079-99086`).
- **The stop line: TERRA / LOCKE / SHADOW** at world (232,150). Shadow joins
  in the stretch's final frames — his kit is a sketch (kits.md, Sketches), so a
  stone is most of what he can be handed.

**Twelve stones, four slots.** By the cave the player owns Ramuh, Kirin,
Siren, Stray, Ifrit, Shiva plus these six. The incumbents' jobs (bolt+Rasp /
heal / sleep-mute control / trickster / vigor+Drain / economy+Shell) are the
competition every design below must name a win against.

### 2.2 The cave is an undead stretch that punishes the obvious buttons

Species table from `break-coverage-sealed-gate.md` §3, extended this pass with the
status-immunity bytes (`monster_prop.dat` +0x14/+0x15/+0x16 = blocked
STATUS1/2/3; element masks +0x17 absorb / +0x19 weak; STATUS1 `DEAD=$80`,
`PETRIFY=$40`, `INVISIBLE=$10`, STATUS3 `SLOW=$04`, `STOP=$10` —
`ff6/include/const.inc:1488-1525`):

| species | id | HP | MP | weak | absorb | death | petrify | slow | stop |
|---|---|---|---|---|---|---|---|---|---|
| Apparite | `$06e` | 781 | 60 | ice, **pearl** | fire, poison | **open** | blocked | blocked | blocked |
| Lich | `$0e5` | 590 | 90 | **pearl** | fire, poison | **open** | blocked | blocked | blocked |
| Ing | `$048` | 1100 | 50 | **pearl**, water | fire, poison | **open** | blocked | **lands** | **lands** |
| Zombone | `$082` | 1991 | 160 | fire, **pearl** | poison | **open** | blocked | **lands** | **lands** |
| Coelecite | `$0b3` | 480 | 15 | ice | fire | **open** | **open** | **lands** | **lands** |

Plus the stretch's one real ambush, the trap-switch **Ninja** `$003` (HP 1650,
weak bolt+pearl, absorbs poison; death open, petrify/slow/stop blocked), and
the banquet slate: **Mega Armor** `$102` / **Commando** `$0c7` (both weak
bolt+water, death open, slow/stop land) and the elite **Sp Forces** `$0c2`
(weak poison; death, petrify, slow, stop ALL blocked — the one body in the
stretch that answers only to damage).

Four findings that shape the designs:

1. **Pearl/holy is the master key** — 4 of 5 cave species are pearl-weak —
   and it is nearly unfielded. The one current source is Sabin's AuraBolt
   (record `$5e` element `$20`; classless by design, "aurabolt is a holy
   chip, not a punch", `ot6_class.asm:172`), a 5-MP blitz on one character.
   §9 makes Unicorn the deliberate second source, marked as the cross-doc
   coupling with the parallel cave-survey pass.
2. **Fire is a trap** (absorbed by 4 of 5) and Terra is forced into the party
   — the stretch inverts her signature exactly the way Zozo inverted poison.
   Ice is the natural secondary (Apparite, Coelecite); water reaches Ing.
3. **Death is open on every cave species** by the immunity byte — the undead
   cave is, on its face, Doom country. **UNVERIFIED and load-bearing for
   Shoat (§5):** whether the undead special-property flag (+0x12 bit `$80`,
   set on Apparite/Lich/Ing/Zombone) alters death-type resolution in C2
   before the immunity byte is consulted. The C2 death path was not read this
   pass; a probe test settles it (§12 row 9).
4. **Enemy MP pools are thin** (15-160) — Osmose income in this stretch is
   scraps, so Shiva does not automatically own a slot the way she did in the
   Facility. That is good for the new six.

### 2.3 The rest of the stretch's fights

The gate battles 121/122 and the deck battle 123 decode to dummy formations
and are scripted theater (`break-coverage-sealed-gate.md` §1.3) — no stone is
designed against them.
The banquet's optional fights and the 2-minute challenge are real: bolt+water
keys (Ramuh, Maduin, Sea Song) and a poison key nobody fields with Edgar
absent (Sp Forces resist all six stones' control — they are a damage check,
which is Maduin's or a boosted divine's job).

---

## 3. The design call

> **Six stones, six verbs: cast, execute, hide, turn, time, purify.**

The tube room hands over six stones in one scene, so the differentiation must
be legible on the equip screen and provable in the next corridor. Each stone
gets exactly one battlefield job, no stone's job overlaps an incumbent's, and
each is built from its magicite.md identity seed with the unbuildable passive
re-expressed through the three real channels (list, stat, divine):

| seed (unbuildable passive) | re-expression |
|---|---|
| Maduin *Trinity* — "first spell each battle +1 tier" | the only stone granting **all three** foldable attack elements; the biggest mag.pwr in the game |
| Shoat *Gorgon Eye* — "Break may chip 2" | the two deletion verbs (Break/Doom) plus the petrify-all divine |
| Phantom *Ghostwalk* — "first hit taken each battle misses" | **Fader literally is Ghostwalk for the whole party** — the divine carries the passive's soul unchanged |
| Carbunkl *Facet* — "Runic feeds +1 more BP" | undeliverable (Celes is absent for the whole stretch, §13); the stone keeps the gem's real verb: reflection, single and party-wide |
| Bismark *Tidal* — "water chip +1" | no water spell exists to grant (§13); **Sea Song is the game's only water verb**, and the kit becomes the tide itself: Haste/Slow |
| Unicorn *Purity* — "status durations halved" | cure-after-the-fact instead of shorten: Remedy in the kit, party-Remedy as the divine — plus the horn's light (Pearl, §9) |

Stat ladder: the tiers are FIELD (upside +6 across 2 stats, no downside), STORY
(+8 across 3, downside −2) and BOSS (+10 across 3, downside −3), cut against a
measurement of vanilla's own equipment ladder
(`docs/design/esper-stat-baseline.md` §4). The tube six are story-granted, not
fought for, so they sit on **STORY** — with one deliberate exception:
**Maduin on BOSS**. v0.7 has no boss, Maduin is Terra's inheritance and the
stretch's crown, and his stone being the strongest stat in the game so far *is*
the reward the stretch pays.

---

## 4. Maduin — **the Trinity**

> *Menu line:* **MADUIN** — *Terra's father. The whole storm in one stone.*

| channel | value |
|---|---|
| Grants | **Fire**, **Ice**, **Bolt** |
| Stat (while worn) | **vig −3 / stm +3 / mag +7** |
| Divine | **Chaos Wing** `$3c` — non-elemental, all enemies, power 55, 44 MP, unblockable (+0x04 `$20`, hit 0). Vanilla, unchanged. |

**The kit is three fold families on one stone.** Fire `$00` (4 MP), Ice `$01`
(5 MP), Bolt `$02` (6 MP) — every one folds to its tier-3 at 2 BP for base
price (`Ot6FoldTbl` rows 0-2, `ot6_boost.asm:341-343`). The Ifrit/Shiva pass
established that one base-tier elemental grant is worth ~10× its price to a
boosting caster; Maduin carries three of them. That is the entire design:
he grants no utility, no economy, no defense — he is the pure mage job, and
his empty fourth and fifth slots are the same statement Ifrit's were.

**Against the incumbents.** Ifrit, Shiva and Ramuh each carry one of these
elements *plus a job* (Drain / Osmose+Shell / Rasp). Maduin's offer is
breadth: the wearer is never elementally wrong for more than one turn. In the
cave that means ice for Apparite and Coelecite while fire stays holstered —
the stone that grants fire teaching you not to cast it is the stretch's absorb
lesson restated. At the banquet fights it means bolt into Mega Armor and
Commando without carrying Ramuh out of the cave.

**Stat.** +7 mag.pwr, one step over Shiva's +6 — the strongest stat stone in
the game, per §3's crown argument, and both the encoding's ceiling and
vanilla's own per-stat ceiling. Base mag.pwr 25-39 (`char_prop.asm`). All three
of his grants scale off it; the −3 vigor is Terra's father as a caster who
cannot punch.

**Divine.** Chaos Wing kept exactly: non-elemental, so it is never absorbed —
the apex button that works in the fire-hostile cave and against Sp Forces,
and the damage-check answer the stretch otherwise lacks. `Ot6BoostDmg` multiplies
it (summons are not exempt, `ot6_kits.asm:1206-1224`), so a 3-BP Chaos Wing is
the stretch's biggest number. Its 44 MP is most of a pool at these levels —
one cast, funded deliberately.

**Trinity, the passive, is dropped** (§13.1) — no passive channel. The
first-cast-free-tier idea was flagged "too strong a folding interaction?" in
magicite.md's own open questions; the fold engine already gives the tiering,
so what is lost is flavor, not function.

---

## 5. Shoat — **the Gorgon Eye**

> *Menu line:* **SHOAT** — *The stone that stares back. One look, one corpse.*

| channel | value |
|---|---|
| Grants | **Break**, **Doom** |
| Stat (while worn) | **vig −2 / spd +6 / stm +2** |
| Divine | **Demon Eye** `$3b` — petrify, all enemies, hit 96, blockable death-class (+0x04 `$10`), 45 MP. Vanilla, unchanged. |

**The executioner's two verbs.** Break `$0c` (25 MP, hit 120, sets PETRIFY)
and Doom `$0d` (35 MP, hit 95, sets DEAD) — both power 0, both hit-rolled,
both death-class (+0x04 `$10`). This is the stone for deleting one dangerous
body instead of whittling it: the anti-shield-math stone. Where the break
loop says "chip, break, nuke", Shoat says "skip all three, if the roll and
the immunity byte allow" — and the immunity byte is exactly what makes him a
*swap* choice rather than an answer: §2.2's table is his usage manual.
Bio is dropped (§1); two spells is the Ramuh/Ifrit precedent, and the third
slot is deliberately the divine.

**In this stretch.** Petrify is blocked by 4 of 5 cave species, the Ninja, Mega
Armor and Commando — but **death is open on every one of them except Sp
Forces**. If the undead-flag question (§2.2 finding 3) resolves "death-type
lands", Shoat is the cave's quiet monster: 35 MP deletes a 1991-HP Zombone
that would otherwise be the longest trash fight in the stretch. If it resolves
"undead shrug off death", his cave value collapses to Coelecite (petrifiable)
and the Ninja, and his real life starts in v0.8. **The design accepts either
outcome** — the executioner being situational is the identity — but the copy
and the balance read differ, so the probe (§12 row 9) is the first test the
build pass should run.

**Boost does nothing for Break or Doom, and that is a canon gap, not a Shoat
bug** (§13.4). They deal no damage (`Ot6BoostDmg` multiplies `$11b0`, which
stays 0) and fold nowhere. DESIGN.md's canon says chance verbs answer to
BP-buys-certainty — Steal's shipped shape — but no such mechanism exists for
hit-rolled magic. Shoat is the first stone whose whole kit sits outside both
boost axes; the UI will let a player spend 3 BP on Doom for nothing.

**Stat.** +6 speed, −2 vigor, +2 stamina. His spells scale off nothing (fixed
hit rates vs target m.block), so the natural bonus is tempo: the executioner
acts before the telegraph lands. The vigor downside is the fiction — the Gorgon
Eye is a stare, not a strike.

**Divine.** Demon Eye kept: petrify-all at hit 96 — the trash-wipe apex where
petrify is legal, a whiff everywhere §2.2 says so. 45 MP prices it as the
fight-ender it is. Kit-vs-divine duplication is the single→all scaling
(Break → Demon Eye), the same shape as Phantom's Vanish → Fader; accepted
in both places because the all-target version is the once-per-battle apex of
the same idea, not a second copy of it.

---

## 6. Phantom — **the Ghostwalk**

> *Menu line:* **PHANTOM** — *What the tubes could not hold. Be nowhere.*

| channel | value |
|---|---|
| Grants | **Vanish**, **Demi** |
| Stat (while worn) | **spd +6 / stm −2 / mag +2** |
| Divine | **Fader** `$4a` — Clear (INVISIBLE) on the whole party, 38 MP. Vanilla, unchanged. |

**The divine IS the unbuildable passive.** magicite.md's *Ghostwalk* — "first
hit taken each battle misses" — has no passive channel, but Fader is that
promise made party-wide and once per battle: everyone untargetable by
physicals until the spellfire finds them. No re-author needed; vanilla
already built the re-expression.

**The kit.** Vanish `$26` (18 MP, sets INVISIBLE, single target) is the
assassin's tool in both directions: on an ally, one guaranteed physical dodge;
on an enemy — targeting `$01` retargets in vanilla — the setup for the oldest
trick in the game (below). Demi `$10` (33 MP, gravity: fraction flag +0x04
`$80`) is the ghost's other half — halve the fat body you cannot yet kill.
Against Zombone's 1991 HP it is the stretch's best single action if the
death-class miss check (+0x04 `$10` rides Demi too) passes the same
undead-flag question as Doom — one probe answers both (§12 row 9). Bserk is
dropped from the vanilla row for the recorded Ifrit reason: it removes player
control (`genju_prop.asm:97-98`).

**The Vanish+Doom question, put on the table rather than dodged.** Phantom
grants Vanish; Shoat grants Doom; vanilla's Clear status famously forces
magic to bypass its hit roll, which in vanilla lets death-class spells ignore
protection. DESIGN.md's house rule is "vanilla's bugs stay" — the Sketch bug
is canon — and this combo costs two esper slots, two characters' turns, and
53 MP, which is a real price. **Recommendation: preserve it, as house-rule
charm.** But (a) the exploit's exact code path is **unread** — whether OT6's
CheckHit changes touched it is UNVERIFIED — and (b) unlike the Sketch bug it
can trivialize authored bosses in later stretches, so it is the owner's call.
Flagged in §14.2 with the options.

**Stat.** +6 speed, −2 stamina, +2 mag.pwr — the roster seed's selector at the
STORY tier, and the ghost is thinner for being faster.
The ghost moves first; on Locke it stacks with the thief read, and it is the
obvious hand-off to Shadow at the stop line: **Phantom is Shadow's stone**
(kits.md sketches him as the assassin; his kit debt is v0.8's, and this stone
is the bridge that makes him playable the frame he joins).

**Swap reason.** Wear Phantom when the enemy's threat is physical (Fader
blanks it) or when one body is too fat to race (Demi). In the cave the undead
have MP and presumably spells — Fader is deliberately *not* a cave skeleton
key (magic ignores Clear), which keeps Carbunkl's job separate next door.

---

## 7. Carbunkl — **the Facet**

> *Menu line:* **CARBUNKL** — *The little gem. What is cast at you is yours.*

| channel | value |
|---|---|
| Grants | **Rflect**, **Safe** |
| Stat (while worn) | **spd −2 / stm +6 / mag +2** |
| Divine | **Ruby Power** `$49` — Reflect on the whole party, 36 MP. Vanilla, unchanged. |

**The mirror stone.** Rflect `$24` (22 MP, single) and Safe `$1c` (12 MP,
single) — the two walls nobody else grants: Shiva owns Shell (magic damage
*through* the wall), Carbunkl owns Reflect (magic *turned around*) and Safe
(the physical wall, unclaimed since Celes and Golem are both absent from the
stretch). The vanilla row's grab bag (Haste/Shell/Warp beside them,
`genju_prop.asm:172`) is trimmed to the two spells that are the job: Haste
moves to Bismark where it is the identity rather than a fifth wheel, Shell
stays Shiva's, Warp is field furniture.

**Facet, the seed passive, is undeliverable this stretch and dropped rather
than faked** (§13.3): "Runic feeds +1 more BP" needs Celes, who is an NPC from
the banquet to past the stop line. When she returns, the pairing is
a *player discovery* (Carbunkl + Runic is already good without a passive), not
a mechanic this pass can author.

**Swap reason.** The cave undead carry real MP (Lich 90, Zombone 160) and the
stretch's set pieces telegraph magic; Ruby Power before a telegraph turns the
enemy's biggest turn into yours. The real cost is vanilla's own: a
reflected party bounces *friendly* magic too — Kirin's Cure thrown at a
Ruby-Powered ally lands on the enemy. That tension (Carbunkl wearer vs Kirin
wearer negotiating turns) is the party puzzle working as designed, and the
copy should not hide it. **UNVERIFIED:** the cave species' AI scripts were
not read; whether they actually cast reflectable spells decides how much of
Carbunkl's cave value is real. The survey pass or a probe at the fight's entry
point settles it; his Safe half and the divine carry him either way.

**Stat.** +6 stamina, −2 speed, +2 mag.pwr — the roster seed's selector at the
STORY tier. The gem endures, and it does not move.

---

## 8. Bismark — **the Tide**

> *Menu line:* **BISMARK** — *The sea remembers its own pace. So will you.*

| channel | value |
|---|---|
| Grants | **Haste**, **Slow** |
| Stat (while worn) | **vig +5 / spd −2 / stm +3** |
| Divine | **Sea Song** `$3d` — WATER (element `$80`), all enemies, power 58, 50 MP, unblockable. Vanilla, unchanged. |

**The kit is tempo in both directions, and both halves fold.** Haste `$1f`
(10 MP) folds to Haste2 — party-wide — at 1 BP (`Ot6FoldTbl` row 7,
`ot6_boost.asm:348`); Slow `$19` (5 MP) folds to Slow 2 — all enemies — at
1 BP (row 6, `:347`). One wearer, 15 MP and 2 BP, swings the whole
battlefield's action economy both ways. Party-wide haste for 10 MP (vanilla
Haste2 costs 38) is this stone's version of the 10×-value fold engine, and
it is the single number §10 most wants measured.

**Water lives in the divine, structurally.** magicite.md's open question 2 —
does Bismark grant the game's only Water spell? — answers itself against the
machinery: there is **no water-element record in the player-magic range** to
grant (scanned `magic_prop_en.dat` records `$00-$35`, +0x01 bit `$80`: none),
and the grant channel cannot create new spells (§13.5). Sea Song **is** the
only water verb the party can ever field this era, which makes Bismark's
divine unique in kind, not just in size: Ing in the cave, Mega Armor and
Commando at the banquet are all water-weak, and boost multiplies it. Tidal,
the chip passive, is dropped into the ledger; the water identity survives at
apex cadence.

**Life is removed** from the vanilla row, restoring kits.md's revival rule
(§1). Fire/Ice/Bolt are removed as Maduin's job.

**The Slow collision, named.** Siren also grants Slow
(`genju_prop.asm:119`), and Shiva's Diamond Dust carries a Slow rider. The
differentiation is real — Bismark folds Slow to all-enemies at 1 BP and
pairs it with Haste; Siren's is one of three single-target control pokes —
but three sources is one too many. Recommendation for Siren's eventual pass
(she is still on vanilla-leftover rows, including the Fire the Ifrit doc
already flagged): drop her Slow, consolidate her as the sleep/mute
controller. Follow-up, §14.4 — not this document's edit to make.

**Stat.** +5 vigor, +3 stamina, −2 speed: the leviathan is mass that is slow.
On the cave party it gives Edgar/Sabin/Locke a second body stone, so Ifrit is
not the only vigor answer. In the cave, where slow is blocked by Apparite/Lich
and the undead absorb the obvious elements, vigor-on-the-class-axis is his
floor value — the same argument that carried Ifrit through the Facility.

**Swap reason.** Wear Bismark when the fight is about turns: haste the party
into a telegraph window, slow what survives, and hold Sea Song for the
water-weak. He is the tempo mage the roster has never had.

---

## 9. Unicorn — **the Purity** — and the holy coupling

> *Menu line:* **UNICORN** — *The horn answers what should not be walking.*

| channel | value |
|---|---|
| Grants | **Pearl**, **Remedy** |
| Stat (while worn) | **stm +5 / mag +2** |
| Divine | **Heal Horn** `$4d` — Remedy's full status-clear set on the whole party (status bytes `45/e8/14`, identical to record `$33`; cleanse flag +0x04 `$04`), 30 MP. Vanilla, unchanged. |

**The paladin: smite and cleanse.** Remedy `$33` (15 MP, single-target full
cleanse) re-expresses *Purity* — cure-after-the-fact instead of
duration-halving — and Heal Horn scales it party-wide as the divine. Pearl
`$0e` (40 MP, holy, power 108) is the horn's light: the stretch's master key
(§2.2 — pearl-weak on 4 of 5 cave species and the Ninja) on the stone whose
whole fantasy is "the undead do not get to keep walking". Cure 2 (dead
pre-folded tier — Kirin reason), Dispel, Safe (→ Carbunkl), Shell (Shiva's)
all drop from the vanilla five-row.

**Pearl here is identity, not the cave's reachability.** The stretch's pearl
key is Sabin's AuraBolt — a 5 MP holy chip, load-bearing since Vargas
(`ot6_class.asm:172`, record `$5e` elem `$20`) — plus the authored class rows
in `break-coverage-sealed-gate.md`; pearl keys 90.6 % of cave draws with zero
absorbers, and none of that runs through this stone. What Unicorn adds is the
paladin's smite and the big-hit option. Its costs are real and accepted: power
108 one-shots this stretch's trash on-weakness (worked number in §10.3), it
takes `Ot6BoostDmg`'s ×2/×4/×8 as a non-folding damage spell, and it undercuts
Terra's L30 Pearl learn (kits.md) by a while-worn copy fifteen levels early.
The vanilla 40 MP — a whole pool at these levels — is the limiter, roughly one
cast a fight, and it is not repriced: the vanilla price is doing exactly the
work we want. Double-paying a key one party member already carries in a
five-slot Blitz list is depth, not redundancy.

**Why Unicorn and not Carbunkl carries holy:** the horn is the
holy image; the gem's identity (reflection) is already whole without it, and
loading Pearl onto Carbunkl would make one stone the wall *and* the smite
while Unicorn stays a two-utility also-ran — the opposite of six distinct
reasons to swap.

**Stat.** +5 stamina, +2 mag.pwr — the protector's selector, and the only
package of the six with no downside. His kit is where his power is, so the stat
should not also be the biggest.

**Swap reason.** The cave: Pearl into anything, Remedy/Heal Horn
against the zombie/poison riders undead stretches carry (**UNVERIFIED which
statuses the cave AI actually inflicts** — same unread-AI caveat as
Carbunkl's; the cleanse kit is the bet, and a survey of the cave AI confirms
the threat).
The banquet and voyage: the two- and three-person parties have no Kirin slot
to spare, and Unicorn is the healer-adjacent stone that also swings.

---

## 10. Balance

### 10.1 The slot fight, segment by segment

The M5 exit criterion: six stones granted together, each with a reason to be
worn at some point in the stretch.

| segment | party | the four slots' strongest claims | the six's entry points |
|---|---|---|---|
| cave (382-386) | Terra, Locke, Edgar, Sabin | Kirin (undead chip damage is constant), Maduin (ice + the crown stat), Unicorn (the key), one of Bismark/Carbunkl/Shoat by threat | Maduin and Unicorn near-locks; Bismark for tempo+Sea Song (Ing), Shoat if Doom lands (probe), Carbunkl if the undead cast (probe), Phantom vs the Ninja ambush and Zombone (Demi) |
| banquet fights | Terra + Locke | two slots only: Maduin (bolt into Mega Armor/Commando; Chaos Wing for Sp Forces) + Bismark (Sea Song covers both water-weak bodies; Haste inside the 2-minute timer) | Shoat: death is open on Mega Armor/Commando — one-cast solutions to the +5 score fights |
| voyage / stop line | Terra, Locke, Shadow | free choice, no fights until v0.8 — the segment exists to hand **Phantom to Shadow** | the loadout at the v0.8 entry point is the player's first three-stone build statement |

The failure mode to watch is **Maduin + Unicorn becoming the only answer** in
the cave (crown stat + master key). The levers, in order: Maduin's magnitude,
never his list; Pearl's presence, never its price.

### 10.2 What each incumbent keeps

Ramuh keeps bolt+Rasp (and is skippable within the stretch — Maduin covers
bolt, which is fine: Ramuh's era was Zozo/Vector). Kirin keeps the only
sustained heal. Shiva keeps Shell + the only MP income (thin here, §2.2.4 —
admittedly thin). Ifrit keeps Drain and shares vigor with Bismark. Siren and
Stray keep their control kits with the Slow collision flagged (§14.4). No new
stone strictly contains an old one.

### 10.3 Numbers to measure first, once the stretch's savestates are generated

1. **Party Haste2 at 1 BP / 10 MP** (Bismark). Run `bal_party.lua`'s policies
   with and without; if it dominates every fight, the lever is the fold
   table's haste row (make Haste2 2-BP by repeating the base tier), not the
   grant.
2. **Pearl one-shots** (Unicorn). Worked line: at L16, mag.pwr ~30, power
   108 computes ≈ 2000 unboosted, ×2 on weakness — over every cave HP pool
   before boost. The 40-MP price means ~1 cast/fight; measure whether that
   cadence reads as "the key" or "the delete button", and whether ×8 boosted
   Pearl into a broken pearl-weak body hits the 9999 cap (it should — that is
   the apex working).
3. **Doom/Demi vs the undead flag** — the §12 row 9 probe, before any cave
   balance conclusion includes Shoat or Phantom.
4. **Six-stone swap incidence** — the M5 criterion itself: instrument which
   stones the test policies equip per segment; any stone with zero wear-time in
   every policy failed differentiation and gets redesigned, not buffed.

---

## 11. The data, literally

No new battle code. No MagicProp overrides. Two files.

**`ff6/src/menu/genju_prop.asm`** — rows 5, 6, 7, 19, 20, 23:

```
; 5: shoat -- "the Gorgon Eye" (v0.7, magicite-tube-six.md §5).  The
;   executioner: Break + Doom, the two deletion verbs.  BIO is DROPPED twice
;   over: it is the pre-folded CAP of the poison family (Ot6FoldTbl row 3 --
;   a 26 MP dead tier beside a 3 MP fold) and poison is Edgar's authored key.
;   Both spells are power-0 hit-rolled death-class: outside BOTH boost axes
;   (no damage to multiply, no fold row, and no chance-verb certainty
;   mechanism exists for magic) -- ledger item, not a bug here.
make_genju_prop {BREAK, 0}, {DOOM, 0}, {}, {}, {}

; 6: maduin -- "the Trinity" (v0.7, magicite-tube-six.md §4).  Terra's
;   inheritance: the pure mage job.  ALL THREE grants are base tiers of fold
;   families (Ot6FoldTbl rows 0-2); the vanilla FIRE_2/ICE_2/BOLT_2 row was
;   three dead pre-folded tiers at once -- the Kirin reason, three times.
make_genju_prop {FIRE, 0}, {ICE, 0}, {BOLT, 0}, {}, {}

; 7: bismark -- "the Tide" (v0.7, magicite-tube-six.md §8).  The tempo mage:
;   Haste and Slow BOTH fold party-/field-wide at 1 BP (Ot6FoldTbl rows 6-7).
;   Water lives in his summon (Sea Song, the game's only water verb) because
;   no water-element player spell exists to grant.  LIFE is DROPPED: revival
;   lives on Terra, Fenix Downs and Sraphim only (kits.md) -- the vanilla row
;   violated that rule.  FIRE/ICE/BOLT dropped: Maduin's job.
make_genju_prop {HASTE, 0}, {SLOW, 0}, {}, {}, {}

; 19: carbunkl -- "the Facet" (v0.7, magicite-tube-six.md §7).  The mirror:
;   Rflect (nobody else grants it) + Safe (the physical wall -- Celes and
;   Golem are both absent).  HASTE moved to Bismark (identity, not fifth
;   wheel); SHELL stays Shiva's; WARP is field furniture, dropped.
make_genju_prop {RFLECT, 0}, {SAFE, 0}, {}, {}, {}

; 20: phantom -- "the Ghostwalk" (v0.7, magicite-tube-six.md §6).  The
;   assassin's second: Vanish (both directions -- the dodge, and the old
;   trick) + Demi (halve what you cannot yet kill).  BSERK dropped: removes
;   player control (the recorded Ifrit reason).  The divine, Fader, IS the
;   unbuildable Ghostwalk passive made party-wide.
make_genju_prop {VANISH, 0}, {DEMI, 0}, {}, {}, {}

; 23: unicorn -- "the Purity" (v0.7, magicite-tube-six.md §9).  The paladin:
;   smite + cleanse.  PEARL is the paladin identity and the big-hit option;
;   the cave's pearl reachability stands on Sabin's AuraBolt plus the authored
;   class rows (break-coverage-sealed-gate.md), never on this stone.
;   CURE_2 dropped (dead pre-folded tier); SAFE -> Carbunkl; SHELL stays
;   Shiva's.
make_genju_prop {PEARL, 0}, {REMEDY, 0}, {}, {}, {}
```

**`ff6/src/battle/ot6_progression.asm`**, `Ot6EsperStatTbl` — six rows in
vanilla's four-signed-nibble equipment layout, vigor/speed/stamina/mag.pwr:

```
        esper_stat   -2,  +6,  +2,   0   ;  5 shoat
        esper_stat   -3,   0,  +3,  +7   ;  6 maduin
        esper_stat   +5,  -2,  +3,   0   ;  7 bismark
        esper_stat    0,  -2,  +6,  +2   ; 19 carbunkl
        esper_stat    0,  +6,  -2,  +2   ; 20 phantom
        esper_stat    0,   0,  +5,  +2   ; 23 unicorn
```

Bismark is the second vigor stone, so Ifrit no longer owns that stat alone.

**Unchanged, explicitly:** all six summon records `$3b/$3c/$3d/$49/$4a/$4d`
(the MagicProp splice gains nothing); every learn-rate byte (stays 0); every
`GENJU_BONUS` byte (stays `$ff`); `Ot6FoldTbl`; the `$3f2e` summon latch and
the `$3ecb` kit-divine latch stay separate (the Ifrit §4.4 ruling carries —
fusing them would punish wearing a stone).

**Menu copy: zero work required.** The detail page renders granted spell
names and the while-worn stat mod directly from these two tables
(`skills.asm`); authoring the bytes above is the whole player-facing job.

---

## 12. Tests

Same files and shapes as the v0.6 pass: grants/absents in
`battle_esperstats.lua` scenarios, behavior in `battle_magicite.lua`. All
rows that depend on this stretch ride v0.7 fixtures (`@suite savestate=<name>`)
and report "skipped" until the chain is generated.

| # | assertion | notes |
|---|---|---|
| 1 | Shoat worn → Break, Doom in the Magic list; **Bio absent** | the `checkEsper(grants, absents)` shape |
| 2 | Maduin worn → Fire, Ice, Bolt; **Fire 2, Ice 2, Bolt 2 absent** | the three dead tiers are the row's whole point |
| 3 | Bismark worn → Haste, Slow; **Life, Fire, Ice, Bolt absent** | the Life absence is the kits.md revival rule, asserted |
| 4 | Carbunkl worn → Rflect, Safe; Warp/Haste/Shell absent. Phantom worn → Vanish, Demi; Bserk absent. Unicorn worn → Pearl, Remedy | |
| 5 | each stone worn → its stat package exactly, and no other stat moved | `battle_esperstats.lua`'s comparison — a table of all four expected deltas, so a downside that failed to apply fails here |
| 6 | Haste at 1 BP queues `$27` and charges **10** MP; Slow at 1 BP queues `$28` and charges **5** | the fold rows under test; the §10.3-1 risk's mechanical half |
| 7 | each summon fires once per battle per character and greys after (`$3f2e`); positive control that the row was offered | six stones, one latch test each — the Demon Eye row doubles as the petrify-immunity control (blocked on Apparite, lands on Coelecite) |
| 8 | Chaos Wing and Sea Song take the boost multiplier; Fader/Ruby Power/Heal Horn/Demon Eye unchanged by boost | the damage-verb vs no-damage boundary of `Ot6BoostDmg` |
| 9 | **THE PROBE: Doom (and Demi) vs an undead-flagged cave body.** Fire Doom at a Zombone; assert loudly whichever way it lands, then pin the answer | settles §2.2 finding 3 for Shoat and Phantom both; must fail loudly, not skip quietly |
| 10 | Vanish cast on an enemy, then Doom: does the death land through the Clear status? | pins the §14.2 ruling either way — if the owner preserves the trick, this is its conformance test; if not, its regression test |

---

## 13. What the shipped machinery cannot express

The full ledger. Of the Ifrit/Shiva §12 list, HP/MP-percentage mods still
cannot be expressed; two-sided and multi-stat mods now can (§1). New or
newly-instantiated items:

1. **Maduin's *Trinity*** ("first spell each battle +1 tier") — no passive
   channel, and no per-battle-first-cast hook exists anywhere. Dropped;
   the fold engine carries the tiering fantasy.
2. **Shoat's *Gorgon Eye*** ("Break may chip 2") — no passive channel, and
   Break could not chip regardless: chip requires a damaging hit (DESIGN.md,
   Break system) and Break deals none. Dropped.
3. **Carbunkl's *Facet*** ("Runic feeds +1 more BP") — no passive channel,
   and its beneficiary is absent for the whole stretch. Dropped; revisit as a
   passive-pool candidate if M4's channel ever lands.
4. **BP-buys-certainty for hit-rolled magic.** DESIGN.md's chance-verb canon
   is implemented only for Steal (command-specific). Break, Doom, Vanish —
   Shoat's and Phantom's whole lists — sit outside both boost axes: the UI
   accepts a 3-BP spend that does nothing. This is the §12.6 Shell wart's
   bigger sibling and the most player-visible gap this pass creates. A
   general "boost tilts magic hit rolls" mechanism is real battle-code work;
   flagged, not designed here.
5. **A water spell in a kit** (Bismark's *Tidal*). Structural: no
   water-element record exists in the player-magic range (`magic_prop_en.dat`
   `$00-$35` scanned, +0x01 bit `$80` — none), and the grant channel cannot
   create records. Water is expressible only at divine cadence (Sea Song) —
   until/unless a vanilla record is deliberately re-authored to water, which
   would be a global spell change of the Osmose-exception class.
6. **Unicorn's *Purity*** ("status durations halved") — no passive channel,
   no duration model to halve. Re-expressed as cure-after-the-fact.
7. **Per-battle-count or condition-gated summons** — unchanged from §12.8 of
   the exemplar; noted because Demon Eye at "twice per battle" was considered
   and is unsayable.

---

## 14. Open questions and follow-ups

2. **The Vanish+Doom ruling (§6).** Preserve as house-rule charm (recommended,
   with test row 10 pinning it) or break it deliberately. Either way the
   exploit's code path needs one read — it is UNVERIFIED that OT6's hit-path
   changes left it intact.
3. **The Doom/Demi-vs-undead probe (§12 row 9)** decides Shoat's and half of
   Phantom's cave story before any balance copy ships. If death-type misses
   undead, Shoat's acquisition copy should say what he is for (the Ninja, the
   banquet, v0.8) so he does not read as dead loot in his own stretch.
4. **Siren's Slow (and her leftover Fire).** Three Slow sources exist (§8).
   Siren's overdue pass should drop both leftovers and consolidate her as the
   sleep/mute controller — she and Stray are the last two vanilla-row stones in
   the game.
5. **Maduin at +7 mag.pwr** — the deliberate crown (§3). If measurement shows
   Maduin locked into a slot for the whole stretch, drop to +6 before touching
   his list.
7. **Shadow's kit debt (v0.8)** — Phantom is designed as his bridge stone
   (§6), which softens but does not settle kits.md's Shadow sketch.
