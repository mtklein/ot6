# The tube-room six — magicite sub-job designs (v0.7) — design dive v1 (2026-07-28)

Scope: issue #31's headline. The six espers the v0.6 tube room grants at once —
MADUIN, SHOAT, PHANTOM, CARBUNKL, BISMARK, UNICORN (`give_genju` block,
`ff6/src/field/event_main.asm:95777-95782` per sealed-gate-recon.md's decode) —
redesigned **in place**: the all-six-at-once acquisition stays (dispatcher
ruling, magicite.md's 2026-07-28 note; redistribution would be an event edit
plus a full re-mint buying no player-visible pacing). This is a **design
pass**: no assembly, no data edits. Everything the build pass needs is listed
literally in §11.

v0.7 has no conventional boss (sealed-gate-recon.md §0 headline 1), so these
six stones **are** the band's player-facing content. The exit criterion is
M5's: six stones sharing one acquisition moment need six distinct reasons to
swap mid-dungeon — differentiation, not a power ranking.

**Canon boundary.** The shipped **while-equipped** model is the baseline:
equip grants the spell list live, the stat mod exists only while worn, nothing
is learned, the summon is the once-per-battle divine
(magicite-ifrit-shiva.md, "Canon boundary"). magicite.md's roster row for each
stone is treated as an **identity seed** — its PASSIVE column (*Trinity*,
*Gorgon Eye*, *Ghostwalk*, *Facet*, *Tidal*, *Purity*) is unbuildable (no
passive channel exists in the ROM) and is re-expressed here through what IS
buildable, or honestly dropped into §13's ledger. The seed names survive as
each stone's documentation nickname.

**Evidence rule (CONTRIBUTING.md).** Every mechanical claim cites the file and
line it was read from, or is labelled **UNVERIFIED**. Numbers taken out of
`.dat` files name the record and byte offset. Line numbers are from the
`wt/v07-espers` worktree on 2026-07-28.

---

## Summary table

| esper (idx) | nickname | grants | stat byte | divine (vanilla record, all kept) | the swap reason |
|---|---|---|---|---|---|
| Maduin (6) | **the Trinity** | Fire, Ice, Bolt | `OT6_SM_MAGPWR\|5` | **Chaos Wing** `$3c`: non-elem 55, all enemies, 44 MP | one caster, three fold families — the right element on demand |
| Shoat (5) | **the Gorgon Eye** | Break, Doom | `OT6_SM_SPEED\|3` | **Demon Eye** `$3b`: petrify all, hit 96, 45 MP | delete one body per turn, where deletion is legal |
| Phantom (20) | **the Ghostwalk** | Vanish, Demi | `OT6_SM_SPEED\|4` | **Fader** `$4a`: Clear on the party, 38 MP | the party stops being hit by physicals |
| Carbunkl (19) | **the Facet** | Rflect, Safe | `OT6_SM_STAM\|4` | **Ruby Power** `$49`: Rflect on the party, 36 MP | the fight's spellfire turns around |
| Bismark (7) | **the Tide** | Haste, Slow | `OT6_SM_VIGOR\|4` | **Sea Song** `$3d`: WATER 58, all enemies, 50 MP | tempo both ways — and the game's only water verb |
| Unicorn (23) | **the Purity** | **Pearl** (§9, cross-doc), Remedy | `OT6_SM_STAM\|3` | **Heal Horn** `$4d`: Remedy on the party, 30 MP | the undead band's master key, and the cleanse |

**Headline finding: no summon re-author is needed.** Unlike Inferno/Diamond
Dust — a mirrored pair that had to be split apart — vanilla already authored
these six divines as six different verbs: a petrify wipe, a non-elemental
nuke, a water nuke, party-reflect, party-vanish, party-cleanse (records
`$3b/$3c/$3d/$49/$4a/$4d`, decoded §4-§9; names Demon Eye / Chaos Wing / Sea
Song / Ruby Power / Fader / Heal Horn, `genju_attack_name_en.json`). The
MagicProp splice gains **zero new overrides** this pass.

---

## 1. The constraint budget — deltas since the Ifrit/Shiva pass

magicite-ifrit-shiva.md §1 is the authority on what the machinery can express:
≤5 spell ids per stone (`ot6_progression.asm:142-181` `Ot6EsperSpellKnown`,
`:203-252` `Ot6UnionEspers`), exactly one unsigned stat mod
`[selector:4][magnitude:4]` from Vigor/Speed/Stamina/Mag.Pwr
(`ot6_progression.asm:314-384`), the once-per-battle summon on vanilla's
`$3f2e` latch (`battle_main.asm:12852` sets it, `:14550` greys the menu row),
boost folding for 8 families only (`Ot6FoldTbl`, `ot6_boost.asm:340-348`), and
the ×2/×4/×8 multiplier on non-folding damage (`Ot6BoostDmg`,
`ot6_kits.asm:1190-1256`; summons are not exempt, `:1206-1224`). No passives,
no permits, no two-sided or multi-stat mods, no learn rates.

Two things changed since that section was written:

1. **The esper detail page now renders the kit honestly.** The learn-% column
   is gone (blanked caption `skills.asm:2528-2544`, forced blank per-row
   `:2606-2608`) and the old bonus line is now a **"While worn...&lt;Stat&gt;+N"**
   line drawn straight from `Ot6EsperStatTbl` (`skills.asm:2624-2673`). The
   most player-visible gap of the v0.6 pass is closed: **authoring a stat byte
   below is automatically player-visible**, and a `$00` row draws a blank
   line — which is exactly what all six stones show today.
2. **MP is universal** — every character brings their save's pool into battle
   (commit `97f6d6e`, #32). A stone on Locke or Sabin has a real pool behind
   it; granted-spell MP prices below are judged against band pools of roughly
   40-60.

The six current rows are placeholders and several are actively broken, the
same way Ifrit's and Shiva's were:

- **Maduin grants three dead pre-folded tiers** — `FIRE_2, ICE_2, BOLT_2`
  (`genju_prop.asm:128`), 20-22 MP each for what the base spells deliver at
  4-6 MP under one boost. All three must go (the Kirin reason,
  `genju_prop.asm:160-165`).
- **Bismark grants Life** (`genju_prop.asm:131`), which violates kits.md's
  written rule that revival "lives on Terra, Fenix Downs, and Sraphim, and
  nowhere else" (kits.md, Terra section). The shipped state has revival live
  on a stone anyone can wear; this redesign removes it.
- **Shoat grants Bio** (`genju_prop.asm:125`) — the pre-folded **cap** of the
  poison family (`Ot6FoldTbl` row 3, `ot6_boost.asm:344`): 26 MP for what a
  3-MP Poison folds into at 1 BP. It is also poison into a band where four of
  five cave species **absorb** poison (§2.2) — a 26-MP self-heal button for
  the enemy. Dropped.
- All six stat rows are `$00` (`ot6_progression.asm:429-448`), so all six
  detail pages show a blank while-worn line.

---

## 2. Where the player is standing

### 2.1 The band's three parties

From sealed-gate-recon.md (§1, §4):

- **The cave: TERRA / LOCKE / EDGAR / SABIN** (dispatcher ruling; Terra is a
  hard gate at the base, recon headline 3). Terra is the band's only innate
  mage — at band levels ~15-16 she knows Fire, Cure, Drain (kits.md, Terra's
  table; Life is L18). Locke, Edgar, Sabin cast **only** through their stones.
- **The banquet: TERRA + LOCKE** (`event_main.asm:99079-99086` per recon).
- **The stop line: TERRA / LOCKE / SHADOW** at world (232,150). Shadow joins
  in the band's final frames — his kit is a sketch (kits.md, Sketches), so a
  stone is most of what he can be handed.

**Twelve stones, four slots.** By the cave the player owns Ramuh, Kirin,
Siren, Stray, Ifrit, Shiva plus these six. The incumbents' jobs (bolt+Rasp /
heal / sleep-mute control / trickster / vigor+Drain / economy+Shell) are the
competition every design below must name a win against.

### 2.2 The cave is an undead band that punishes the obvious buttons

Species table from sealed-gate-recon.md §3.2, extended this pass with the
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

Plus the band's one real ambush, the trap-switch **Ninja** `$003` (HP 1650,
weak bolt+pearl, absorbs poison; death open, petrify/slow/stop blocked), and
the banquet slate: **Mega Armor** `$102` / **Commando** `$0c7` (both weak
bolt+water, death open, slow/stop land) and the elite **Sp Forces** `$0c2`
(weak poison; death, petrify, slow, stop ALL blocked — the one body in the
band that answers only to damage).

Four findings that shape the designs:

1. **Pearl/holy is the master key** — 4 of 5 cave species are pearl-weak —
   and it is nearly unfielded. The one current source is Sabin's AuraBolt
   (record `$5e` element `$20`; classless by design, "aurabolt is a holy
   chip, not a punch", `ot6_class.asm:172`), a 5-MP blitz on one character.
   §9 makes Unicorn the deliberate second source, marked as the cross-doc
   coupling with the parallel cave-survey pass.
2. **Fire is a trap** (absorbed by 4 of 5) and Terra is forced into the party
   — the band inverts her signature exactly the way Zozo inverted poison.
   Ice is the honest secondary (Apparite, Coelecite); water reaches Ing.
3. **Death is open on every cave species** by the immunity byte — the undead
   cave is, on its face, Doom country. **UNVERIFIED and load-bearing for
   Shoat (§5):** whether the undead special-property flag (+0x12 bit `$80`,
   set on Apparite/Lich/Ing/Zombone) alters death-type resolution in C2
   before the immunity byte is consulted. The C2 death path was not read this
   pass; a probe test settles it (§12 row 9).
4. **Enemy MP pools are thin** (15-160) — Osmose income in this band is
   scraps, so Shiva does not automatically own a slot the way she did in the
   Facility. That is good for the new six.

### 2.3 The rest of the band's fights

The gate battles 121/122 and the deck battle 123 decode to dummy formations
and are scripted theater (recon §3.1) — no stone is designed against them.
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
| Carbunkl *Facet* — "Runic feeds +1 more BP" | undeliverable (Celes is absent all band, §13); the stone keeps the gem's real verb: reflection, single and party-wide |
| Bismark *Tidal* — "water chip +1" | no water spell exists to grant (§13); **Sea Song is the game's only water verb**, and the kit becomes the tide itself: Haste/Slow |
| Unicorn *Purity* — "status durations halved" | cure-after-the-fact instead of shorten: Remedy in the kit, party-Remedy as the divine — plus the horn's light (Pearl, §9) |

Stat ladder: the shipped tiers are FIELD 2-3 / BOSS 4-5
(`ot6_progression.asm:386-393`). The tube six are story-granted, not fought
for, so they sit at **3-4** — with one deliberate exception: **Maduin at 5**.
v0.7 has no boss, Maduin is Terra's inheritance and the band's crown, and his
stone being the strongest stat in the game so far *is* the reward the band
pays. M6 owns the final numbers.

---

## 4. Maduin — **the Trinity**

> *Menu line:* **MADUIN** — *Terra's father. The whole storm in one stone.*

| channel | value |
|---|---|
| Grants | **Fire**, **Ice**, **Bolt** |
| Stat (while worn) | **+5 mag.pwr** (`OT6_SM_MAGPWR\|5` = `$45`) |
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
the stone that grants fire teaching you not to cast it is the band's absorb
lesson restated. At the banquet fights it means bolt into Mega Armor and
Commando without carrying Ramuh out of the cave.

**Stat.** +5 mag.pwr, one step over Shiva's +4 — the strongest stat stone in
the game, per §3's crown argument. Base mag.pwr 25-39 (`char_prop.asm`), so
~13-20%. The honest selector: all three spells scale off it.

**Divine.** Chaos Wing kept exactly: non-elemental, so it is never absorbed —
the apex button that works in the fire-hostile cave and against Sp Forces,
and the damage-check answer the band otherwise lacks. `Ot6BoostDmg` multiplies
it (summons are not exempt, `ot6_kits.asm:1206-1224`), so a 3-BP Chaos Wing is
the band's biggest number. Its 44 MP is most of a band-level pool — one cast,
funded deliberately.

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
| Stat (while worn) | **+3 speed** (`OT6_SM_SPEED\|3` = `$23`) |
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

**In this band.** Petrify is blocked by 4 of 5 cave species, the Ninja, Mega
Armor and Commando — but **death is open on every one of them except Sp
Forces**. If the undead-flag question (§2.2 finding 3) resolves "death-type
lands", Shoat is the cave's quiet monster: 35 MP deletes a 1991-HP Zombone
that would otherwise be the longest trash fight in the band. If it resolves
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

**Stat.** +3 speed. His spells scale off nothing (fixed hit rates vs target
m.block), so the honest bonus is tempo: the executioner acts before the
telegraph lands. Kept a step under Phantom's +4 so the two speed stones read
as a ladder.

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
| Stat (while worn) | **+4 speed** (`OT6_SM_SPEED\|4` = `$24`) |
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
Against Zombone's 1991 HP it is the band's best single action if the
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
charm.** But (a) the exploit's exact code path was **not read this pass** —
whether OT6's CheckHit changes touched it is UNVERIFIED — and (b) unlike the
Sketch bug it can trivialize authored bosses in later bands, so it is a
dispatcher decision, not a subagent's. Flagged in §14.2 with the options.

**Stat.** +4 speed — the roster seed's selector at the story-tier magnitude.
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
| Stat (while worn) | **+4 stamina** (`OT6_SM_STAM\|4` = `$34`) |
| Divine | **Ruby Power** `$49` — Reflect on the whole party, 36 MP. Vanilla, unchanged. |

**The mirror stone.** Rflect `$24` (22 MP, single) and Safe `$1c` (12 MP,
single) — the two walls nobody else grants: Shiva owns Shell (magic damage
*through* the wall), Carbunkl owns Reflect (magic *turned around*) and Safe
(the physical wall, unclaimed since Celes and Golem are both absent from the
band). The vanilla row's grab bag (Haste/Shell/Warp beside them,
`genju_prop.asm:172`) is trimmed to the two spells that are the job: Haste
moves to Bismark where it is the identity rather than a fifth wheel, Shell
stays Shiva's, Warp is field furniture.

**Facet, the seed passive, is undeliverable this band and dropped honestly**
(§13.3): "Runic feeds +1 more BP" needs Celes, who is an NPC from the banquet
to past the stop line (recon §4). When she returns, the pairing is a *player
discovery* (Carbunkl + Runic is already good without a passive), not a
mechanic this pass can author.

**Swap reason.** The cave undead carry real MP (Lich 90, Zombone 160) and the
band's set pieces telegraph magic; Ruby Power before a telegraph turns the
enemy's biggest turn into yours. The honest cost is vanilla's own: a
reflected party bounces *friendly* magic too — Kirin's Cure thrown at a
Ruby-Powered ally lands on the enemy. That tension (Carbunkl wearer vs Kirin
wearer negotiating turns) is the party puzzle working as designed, and the
copy should not hide it. **UNVERIFIED:** the cave species' AI scripts were
not read; whether they actually cast reflectable spells decides how much of
Carbunkl's cave value is real. The survey pass or a doorstep probe settles
it; his Safe half and the divine keep him honest either way.

**Stat.** +4 stamina — the roster seed's selector, story-tier magnitude, one
step over Ramuh's +3. The gem endures.

---

## 8. Bismark — **the Tide**

> *Menu line:* **BISMARK** — *The sea remembers its own pace. So will you.*

| channel | value |
|---|---|
| Grants | **Haste**, **Slow** |
| Stat (while worn) | **+4 vigor** (`OT6_SM_VIGOR\|4` = `$14`) |
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
and the grant channel cannot mint new spells (§13.5). Sea Song **is** the
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

**Stat.** +4 vigor. The leviathan is mass; on the cave party it gives
Edgar/Sabin/Locke a second body stone so Ifrit stops being the only vigor
answer — deliberately breaking Ifrit's "ONLY vigor stone" comment
(`ot6_progression.asm:396-398`), which §11 amends. In the cave, where slow
is blocked by Apparite/Lich and the undead absorb the obvious elements,
vigor-on-the-class-axis is his floor value — the same argument that carried
Ifrit through the Facility.

**Swap reason.** Wear Bismark when the fight is about turns: haste the party
into a telegraph window, slow what survives, and hold Sea Song for the
water-weak. He is the tempo mage the roster has never had.

---

## 9. Unicorn — **the Purity** — and the holy coupling, laid out for decision

> *Menu line:* **UNICORN** — *The horn answers what should not be walking.*

| channel | value |
|---|---|
| Grants | **Pearl** *(branch A — the recommendation; see the decision box)*, **Remedy** |
| Stat (while worn) | **+3 stamina** (`OT6_SM_STAM\|3` = `$33`) |
| Divine | **Heal Horn** `$4d` — Remedy's full status-clear set on the whole party (status bytes `45/e8/14`, identical to record `$33`; cleanse flag +0x04 `$04`), 30 MP. Vanilla, unchanged. |

**The paladin: smite and cleanse.** Remedy `$33` (15 MP, single-target full
cleanse) re-expresses *Purity* — cure-after-the-fact instead of
duration-halving — and Heal Horn scales it party-wide as the divine. Pearl
`$0e` (40 MP, holy, power 108) is the horn's light: the band's master key
(§2.2 — pearl-weak on 4 of 5 cave species and the Ninja) on the stone whose
whole fantasy is "the undead do not get to keep walking". Cure 2 (dead
pre-folded tier — Kirin reason), Dispel, Safe (→ Carbunkl), Shell (Shiva's)
all drop from the vanilla five-row.

> **CROSS-DOC DECISION (dispatcher + the parallel cave-survey pass).** The
> survey's open question — pearl/holy is the undead band's natural key and
> almost no kit fields it — has two answers that must not both ship blind:
>
> - **Branch A (recommended): Unicorn grants Pearl.** The band gets a real
>   pearl key on a swap-in stone; Sabin's AuraBolt (holy, 5 MP,
>   `ot6_class.asm:172`, record `$5e` elem `$20`) stays the chip-tempo
>   source; the cave reads as designed. Costs: Pearl at power 108 one-shots
>   band trash on-weakness (worked number in §10.3), takes `Ot6BoostDmg`
>   ×2/×4/×8 as a non-folding damage spell, and undercuts Terra's L30 Pearl
>   learn (kits.md) by a while-worn copy fifteen levels early. Its 40 MP —
>   a whole band-level pool — is the honest limiter: roughly one cast per
>   fight, no reprice recommended (the Osmose exception is precedent that
>   repricing is *possible*; here the vanilla price is doing exactly the
>   work we want).
> - **Branch B: Unicorn stays support-only** (`{REMEDY, DISPEL}`) and the
>   survey pass authors secondary axes instead (ice/water rows, or
>   class-row authoring on the cave bodies). The cave key then comes from
>   encounter data, not a kit; Unicorn is the weakest of the six (two
>   utility spells against Kirin's four) and the copy must sell the cleanse
>   as the job.
>
> These are substitutes: **if the survey authors a reachable pearl-adjacent
> answer into the encounter data, branch A double-pays the key; if it does
> not and branch B ships, the band has no pearl damage at all.** One owner
> must pick. Everything else in this document is independent of the choice;
> §11 lists both rows.
>
> **DECIDED (dispatcher, 2026-07-28): branch A, with the premise
> corrected.** The parallel survey (`break-band-sealed-gate.md`)
> disproved "no kit fields pearl" — Sabin's AuraBolt is a shipped 5 MP
> pearl chip, load-bearing since Vargas, and pearl keys 90.6% of cave
> draws with zero absorbers. So the substitutes framing dissolves: the
> band's REACHABILITY stands on AuraBolt plus the survey's authored
> class rows and never on Unicorn, while Unicorn still grants Pearl as
> the paladin identity and the big-hit option (40 MP keeps it a
> decision, not the default swing). Double-paying a key one party
> member already carries in a five-slot Blitz list is depth, not
> redundancy.

**Why Unicorn and not Carbunkl carries the holy branch:** the horn is the
holy image; the gem's identity (reflection) is already whole without it, and
loading Pearl onto Carbunkl would make one stone the wall *and* the smite
while Unicorn stays a two-utility also-ran — the opposite of six distinct
reasons to swap.

**Stat.** +3 stamina — the protector's selector at the lower story rung
(branch A's kit is strong enough; the stat should not also be the biggest).

**Swap reason.** The cave: Pearl into anything (branch A), Remedy/Heal Horn
against the zombie/poison riders undead bands carry (**UNVERIFIED which
statuses the cave AI actually inflicts** — same unread-AI caveat as
Carbunkl's; the cleanse kit is the bet, the survey pass confirms the threat).
The banquet and voyage: the two- and three-person parties have no Kirin slot
to spare, and Unicorn is the healer-adjacent stone that also swings.

---

## 10. Balance

### 10.1 The slot fight, leg by leg

The M5 exit criterion: six stones granted together, each with a reason to be
worn at some point in the band.

| leg | party | the four slots' strongest claims | the six's entry points |
|---|---|---|---|
| cave (382-386) | Terra, Locke, Edgar, Sabin | Kirin (undead chip damage is constant), Maduin (ice + the crown stat), Unicorn-A (the key), one of Bismark/Carbunkl/Shoat by threat | Maduin and Unicorn near-locks; Bismark for tempo+Sea Song (Ing), Shoat if Doom lands (probe), Carbunkl if the undead cast (probe), Phantom vs the Ninja ambush and Zombone (Demi) |
| banquet fights | Terra + Locke | two slots only: Maduin (bolt into Mega Armor/Commando; Chaos Wing for Sp Forces) + Bismark (Sea Song covers both water-weak bodies; Haste inside the 2-minute timer) | Shoat: death is open on Mega Armor/Commando — one-cast solutions to the +5 score fights |
| voyage / stop line | Terra, Locke, Shadow | free choice, no fights until v0.8 — the leg exists to hand **Phantom to Shadow** | the v0.8 doorstep loadout is the player's first three-stone build statement |

The failure mode to watch is **Maduin + Unicorn-A becoming the only answer**
in the cave (crown stat + master key). The levers, in order: Maduin's
magnitude (5→4), never his list; Pearl's presence (branch B), never its
price.

### 10.2 What each incumbent keeps

Ramuh keeps bolt+Rasp (and is skippable in-band — Maduin covers bolt, which
is fine: Ramuh's era was Zozo/Vector). Kirin keeps the only sustained heal.
Shiva keeps Shell + the only MP income (thin here, §2.2.4 — honest). Ifrit
keeps Drain and shares vigor with Bismark. Siren and Stray keep their control
kits with the Slow collision flagged (§14.4). No new stone strictly contains
an old one.

### 10.3 Numbers to measure first (M6, when the band's fixtures mint)

1. **Party Haste2 at 1 BP / 10 MP** (Bismark). Run `bal_party.lua`'s policies
   with and without; if it dominates every fight, the lever is the fold
   table's haste row (make Haste2 2-BP by repeating the base tier), not the
   grant.
2. **Pearl one-shots** (Unicorn-A). Worked line: at L16, mag.pwr ~30, power
   108 computes ≈ 2000 unboosted, ×2 on weakness — over every cave HP pool
   before boost. The 40-MP price means ~1 cast/fight; measure whether that
   cadence reads as "the key" or "the delete button", and whether ×8 boosted
   Pearl into a broken pearl-weak body hits the 9999 cap (it should — that is
   the apex working).
3. **Doom/Demi vs the undead flag** — the §12 row 9 probe, before any cave
   balance conclusion includes Shoat or Phantom.
4. **Six-stone swap incidence** — the M5 criterion itself: instrument which
   stones the test policies equip per leg; any stone with zero wear-time in
   every policy failed differentiation and gets redesigned, not buffed.

---

## 11. The data, literally

No new battle code. No MagicProp overrides. Two files, plus one comment
amendment.

**`ff6/src/menu/genju_prop.asm`** — replace rows 5, 6, 7, 19, 20, 23:

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
;   smite + cleanse.  PEARL is BRANCH A of the cross-doc holy decision (§9
;   decision box) -- if the cave-survey pass authors the pearl answer into
;   encounter data instead, this row is {REMEDY, 0}, {DISPEL, 0} (branch B).
;   CURE_2 dropped (dead pre-folded tier); SAFE -> Carbunkl; SHELL stays
;   Shiva's.
make_genju_prop {PEARL, 0}, {REMEDY, 0}, {}, {}, {}
```

**`ff6/src/battle/ot6_progression.asm`**, `Ot6EsperStatTbl` — six rows leave
`OT6_SM_NONE`:

```
        .byte   OT6_SM_SPEED  | 3       ;  5 shoat    +3 speed (the executioner
                                        ;    acts first; his spells scale off
                                        ;    nothing, so tempo is the honest pick)
        .byte   OT6_SM_MAGPWR | 5       ;  6 maduin   +5 mag.pwr -- the crown.
                                        ;    v0.7 has no boss; Terra's
                                        ;    inheritance being the strongest
                                        ;    stat stone IS the band's reward
                                        ;    (magicite-tube-six.md §3)
        .byte   OT6_SM_VIGOR  | 4       ;  7 bismark  +4 vigor (the leviathan;
                                        ;    second vigor stone -- see the Ifrit
                                        ;    comment amendment)
        .byte   OT6_SM_STAM   | 4       ; 19 carbunkl +4 stamina (the gem endures)
        .byte   OT6_SM_SPEED  | 4       ; 20 phantom  +4 speed (the ghost moves
                                        ;    first; Shadow's stone at the stop line)
        .byte   OT6_SM_STAM   | 3       ; 23 unicorn  +3 stamina (the protector;
                                        ;    kept low -- branch A's kit is the power)
```

**Comment amendment, same file:** Ifrit's row comment (`:396-398`) says "+5
vigor -- the ONLY vigor stone (nobody else claims the selector)". Bismark now
claims it; reword to "the first vigor stone (Bismark joins at v0.7)".

**Unchanged, explicitly:** all six summon records `$3b/$3c/$3d/$49/$4a/$4d`
(the MagicProp splice gains nothing); every learn-rate byte (stays 0); every
`GENJU_BONUS` byte (stays `$ff`); `Ot6FoldTbl`; the `$3f2e` summon latch and
the `$3ecb` kit-divine latch stay separate (the Ifrit §4.4 ruling carries —
fusing them would punish wearing a stone).

**Menu copy: zero work required.** The detail page renders granted spell
names and the "While worn...&lt;Stat&gt;+N" line directly from these two tables
(`skills.asm:2528-2544`, `:2624-2673`); authoring the bytes above is the
whole player-facing job.

---

## 12. Tests

Same files and shapes as the v0.6 pass: grants/absents in
`battle_esperstats.lua` scenarios, behavior in `battle_magicite.lua`. All
band-dependent rows ride v0.7 fixtures (`@suite frontier=<name>`) and report
"skipped" until the chain mints.

| # | assertion | notes |
|---|---|---|
| 1 | Shoat worn → Break, Doom in the Magic list; **Bio absent** | the `checkEsper(grants, absents)` shape |
| 2 | Maduin worn → Fire, Ice, Bolt; **Fire 2, Ice 2, Bolt 2 absent** | the three dead tiers are the row's whole point |
| 3 | Bismark worn → Haste, Slow; **Life, Fire, Ice, Bolt absent** | the Life absence is the kits.md revival rule, asserted |
| 4 | Carbunkl worn → Rflect, Safe; Warp/Haste/Shell absent. Phantom worn → Vanish, Demi; Bserk absent. Unicorn worn → per shipped branch | |
| 5 | each stone worn → its one stat at its magnitude, and only that stat | `battle_esperstats.lua`'s existing comparison |
| 6 | Haste at 1 BP queues `$27` and charges **10** MP; Slow at 1 BP queues `$28` and charges **5** | the fold rows under test; the §10.3-1 risk's mechanical half |
| 7 | each summon fires once per battle per character and greys after (`$3f2e`); positive control that the row was offered | six stones, one latch test each — the Demon Eye row doubles as the petrify-immunity control (blocked on Apparite, lands on Coelecite) |
| 8 | Chaos Wing and Sea Song take the boost multiplier; Fader/Ruby Power/Heal Horn/Demon Eye unchanged by boost | the damage-verb vs no-damage boundary of `Ot6BoostDmg` |
| 9 | **THE PROBE: Doom (and Demi) vs an undead-flagged cave body.** Fire Doom at a Zombone; assert loudly whichever way it lands, then pin the answer | settles §2.2 finding 3 for Shoat and Phantom both; must fail loudly, not skip quietly |
| 10 | Vanish cast on an enemy, then Doom: does the death land through the Clear status? | pins the §14.2 ruling either way — if the dispatcher preserves the trick, this is its conformance test; if not, its regression test |

---

## 13. What the shipped machinery cannot express

The honest ledger. Items 1-3 of the Ifrit/Shiva §12 list (two-sided mods,
multi-stat, HP/MP%) all still apply; new or newly-instantiated items:

1. **Maduin's *Trinity*** ("first spell each battle +1 tier") — no passive
   channel, and no per-battle-first-cast hook exists anywhere. Dropped;
   the fold engine carries the tiering fantasy.
2. **Shoat's *Gorgon Eye*** ("Break may chip 2") — no passive channel, and
   Break could not chip regardless: chip requires a damaging hit (DESIGN.md,
   Break system) and Break deals none. Dropped.
3. **Carbunkl's *Facet*** ("Runic feeds +1 more BP") — no passive channel,
   and its beneficiary is absent all band. Dropped; revisit as a passive-pool
   candidate if M4's channel ever lands.
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
   mint records. Water is expressible only at divine cadence (Sea Song) —
   until/unless a vanilla record is deliberately re-authored to water, which
   would be a global spell change of the Osmose-exception class.
6. **Unicorn's *Purity*** ("status durations halved") — no passive channel,
   no duration model to halve. Re-expressed as cure-after-the-fact.
7. **Per-battle-count or condition-gated summons** — unchanged from §12.8 of
   the exemplar; noted because Demon Eye at "twice per battle" was considered
   and is unsayable.

---

## 14. Open questions / follow-ups for the dispatcher

1. **The Unicorn holy coupling (§9 decision box)** — branch A (Pearl on
   Unicorn) vs branch B (survey authors the answer into encounter data).
   Substitutes, not complements; needs one owner across this doc and the
   cave-survey pass. Recommendation: branch A.
2. **The Vanish+Doom ruling (§6).** Preserve as house-rule charm (recommended,
   with test row 10 pinning it) or break it deliberately. Either way the
   exploit's code path needs one read — it is UNVERIFIED that OT6's hit-path
   changes left it intact.
3. **The Doom/Demi-vs-undead probe (§12 row 9)** decides Shoat's and half of
   Phantom's cave story before any balance copy ships. If death-type misses
   undead, Shoat's acquisition copy should say what he is for (the Ninja, the
   banquet, v0.8) so he does not read as dead loot in his own band.
4. **Siren's Slow (and her leftover Fire).** Three Slow sources exist once
   Bismark ships (§8). Recommend Siren's overdue pass drop both leftovers and
   consolidate her as the sleep/mute controller — she and Stray are now the
   last two vanilla-row stones in the game.
5. **Maduin at +5 mag.pwr** — the deliberate crown (§3). If M6 measurement
   shows Maduin locked into a slot all band, drop to 4 before touching his
   list.
6. **The stat-ladder doc** (`ot6_progression.asm:386-393` comment) should gain
   the story-tier rung (3-4, crown exception) when the build pass lands the
   bytes, so the three-rung ladder is written where the data lives.
7. **Shadow's kit debt (v0.8)** — Phantom is designed as his bridge stone
   (§6), which softens but does not settle kits.md's Shadow sketch; the
   recon already flags his kit as this milestone's exit criterion or v0.8's
   entry debt.
