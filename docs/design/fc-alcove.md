# The Floating Continent alcove — SHADOW crosses it naked, in the front row (#221)

Authored 2026-09-17 from `tools/tests/fcalcovelab.py` (the lab; its
docstring carries the policies), the v0.18 qualification's
`build/states/fc_alcove.log`, and a 12-seed spread of `gen_fc_alcove` over
three policies (plus a 6-seed fourth). Every number below is quoted from a
retained log under `build/lab/fc-alcove/` — the lab keeps every attempt,
failures included. `python3 tools/tests/fcalcovelab.py aggregate control
back dressback --seeds 0,5,10,15,20,25,30,35,40,45,50,55` prints them all;
`build/lab/fc-alcove/aggregate.txt` is that output and
`build/lab/fc-alcove/aggregate-dress.txt` the fourth policy's.

## What happened in the qualification

`fc_alcove` (gen_fc_alcove) passed first try, `PASS (frame 48714)
attempts=1/3`, and spent four deaths and four Fenix Downs doing it
(`python3 tools/audit_boost.py build/states/fc_alcove.log -v`):

```
segment                            fight     f+ ent      from bp party_bp  by
fc_alcove                              3   2747   1  519/1305  3  1,3,2,0  slot 0 cmd $00 atk $EF <- banked
fc_alcove                              4   1695   3   971/971  0  2,3,2,0  slot 1 cmd $00 atk $EF ONE ACTION
fc_alcove                              6   2902   3  242/1050  2  1,1,1,2  slot 0 cmd $00 atk $EE
fc_alcove                              7   1985   3  568/1050  0  2,3,2,0  slot 0 cmd $0C atk $94
```

**Correction to the issue's framing.** #221 says two of the four were
logged as "died holding >= 3 BP". `audit_boost` says **one**:
`4 party death(s), 1 holding >= 3 BP, 0 wipe(s)`. The other three fell at
2, 0 and 0 pips. That one is treated on its own under "The banked pips",
below.

`atk $EE` and `atk $EF` decode out of `ff6/src/text/attack_name_en.json`
at index `id - $51` as **Battle** (the plain physical) and **Special** (the
monster's own special attack, named per species in
`monster_special_name_en.json`); `atk $94` is **L.5 Doom**.

## Who was killing whom

The lab re-runs the generator with three read-only CPU exec observers
(`ExecCmd@battle_code` / `_writedamage` / `SaveForMimic`, the shape
`lab_map269_random.lua` uses) and one stage line per battle, so every death
carries the formation it happened in, the species and slot of the killer,
the attack's own name, and the raw damage word before `ApplyDmg` clamps it
to HP. Control seed 0 reproduces the qualification frame for frame — same
verdict, same four deaths — which is what says the observers change
nothing (`build/lab/fc-alcove/control/seed00.log`):

```
[kill] f16060 fight3 form=WireyDrgn+WireyDrgn+WireyDrgn entity 1 char 1 from 519/1305 by WireyDrgn(s0) Special:Wing raw=532 bp=3 ...
[kill] f23977 fight4 form=Behemoth+Behemoth entity 3 char 3 from 971/971 by Behemoth(s1) Special:TakeDown raw=1140 bp=0 ...
[kill] f34863 fight6 form=Brainpan+Misfit+Apokryphos+Brainpan entity 3 char 3 from 242/1050 by Brainpan(s0) Battle raw=291 bp=2 ...
[kill] f43561 fight7 form=Apokryphos+Apokryphos+Apokryphos entity 3 char 3 from 568/1050 by Apokryphos(s0) L5Doom raw=16383 bp=0 ...
```

Three of the four are char 3 — **SHADOW**. Over the whole 12-seed control
spread it is **15 of 24**.

## The party going in

The lab logs the field party the frame the descent starts
(`[fcalcovelab] [party descent start]`, control seed 0):

```
c0=L25  995/1039 hp 193/228 mp back  gear=0E,5C,6E,89 relics=FF,B1
c1=L28 1289/1305 hp  79/256 mp front gear=0F,05,73,8A relics=D1,B1
c3=L24  971/971  hp 206/206 mp front gear=FF,FF,FF,FF relics=FF,FF
c4=L25 1048/1048 hp 198/218 mp back  gear=0B,5B,76,8F relics=FF,B1
```

TERRA (c0) Blizzard / Mithril Shld / Bandana / Mithril Vest, back row.
LOCKE (c1) ThunderBlade / Assassin on a Genji Glove / Head Band / Ninja
Gear, front row. EDGAR (c4) RegalCutlass / Heavy Shld / Gold Helmet / Gold
Armor, back row. And **SHADOW (c3): `gear=FF,FF,FF,FF relics=FF,FF` — no
weapon, no shield, no helmet, no armor, no relics — in the FRONT row**, for
the whole crossing.

(He is **L24**, not the L25 the issue quotes. `norm_lvl SHADOW`
(`event_main.asm:32618`) runs `CalcAverageLevel`
(`ff6/src/field/event.asm:890`), which averages every *available*
character, not the three on the continent, and only ever raises. He levels
to L25 mid-crossing — the max-HP column goes 971 → 1050 — which is what
puts him on L5 Doom's multiple.)

Two shipped steps put him there, both in `gen_fc_alcove.lua`:

- `H.setRows({ [TERRA] = true, [EDGAR] = true, [LOCKE] = false })` runs
  **before** the Shadow talk, so the run never sets his row. The
  qualification says so itself — `[fc rows] already set: c0=back c1=front
  c4=back`, three names, and SHADOW joins 600 frames later.
- `kitSteps(SHADOW, "SHADOW", { ... })` runs at **step 4, the alcove** —
  after the crossing is over. Its own first log line is the proof:
  `[SHADOW FC kit slot 4] char=3 row=3 before=FF FF FF FF FF FF`.

This is the same omission the route doc already names for EDGAR
(`floating-continent-route.md` §3a, "Dressing the bench pick": "The first
cut fought all 13 battles with EDGAR naked and still won; the re-cut
dresses him after wave 1"). SHADOW arrives the same way — `char_party
SHADOW,1` with every slot empty — and nothing dresses him until the alcove.

## The pool, decoded

`python3 tools/tests/fcalcovelab/decode_group112.py` (offline, from
`battle_monsters.dat` / `monster_prop.dat` / the shipped text tables):

| roll | formation | bodies |
|---|---|---|
|  7.81% | 177 ($0B1) | Behemoth |
|  7.81% | 178 ($0B2) | Apokryphos, Misfit, Misfit |
|  7.81% | 179 ($0B3) | Apokryphos |
| 15.62% | 180 ($0B4) | Ninja |
|  7.81% | 181 ($0B5) | Wirey Drgn x3 |
|  7.81% | 182 ($0B6) | Apokryphos x3 |
| 15.62% | 183 ($0B7) | Brainpan, Misfit, Apokryphos, Brainpan |
|  7.81% | 184 ($0B8) | Brainpan x3 |
|  9.38% | 185 ($0B9) | Dragon |
|  9.38% | 186 ($0BA) | Behemoth, Misfit, Misfit |
|  1.56% | 187 ($0BB) | Behemoth x2 |
|  1.56% | 188 ($0BC) | Ninja, Wirey Drgn |

| species | L | HP | atk | def | weak | special | specdata |
|---|---|---|---|---|---|---|---|
| Ninja ($003) | 27 | 1650 | 22 | 135 | bolt\|holy | Inviz | $44 (no damage, status $04) |
| Apokryphos ($00C) | 26 | 1900 | 18 | 80 | bolt\|holy\|water | Silencer | $4B (no damage, status $0B) |
| **Behemoth ($020)** | 28 | 5800 | 25 | 100 | ice | **Take Down** | **$23 (physical x2)** |
| Brainpan ($04A) | 25 | 1300 | 24 | 120 | fire\|bolt\|holy | Smirk | $54 (no damage, status $14 = Stop) |
| Dragon ($083) | 29 | 7000 | 45 | 130 | bolt | **Tail** | **$27 (physical x4)** |
| Misfit ($0A4) | 26 | 1750 | 26 | 105 | fire\|holy | Enmity | $40 (no damage, status $00) |
| Wirey Drgn ($0D8) | 26 | 2802 | 35 | 150 | — | **Wing** | **$21 (physical x1)** |

`monster_prop +31` is the special-attack byte; `battle_main.asm`
@32ec-@334e unpacks it as bit 7 "cannot be dodged", bit 6 "deals no
damage", and bits 0-5 either a status bit (< $20) or `$bc += value - $20`,
after which `ApplyDmgMult` multiplies by `1 + $bc/2`.

The AI decides nothing that a kill order could steer. `ai_script.asm`
gives the **Behemoth** `attack BATTLE, SPECIAL, NOTHING` as its **ordinary**
turn, so Take Down is a one-in-three on every Behemoth turn from turn 1 —
not a counter, not a last-monster-standing branch. Wirey Drgn and Brainpan
are `attack BATTLE, BATTLE, SPECIAL` the same way. Only the Apokryphos's
`L5_DOOM / L4_FLARE / L3_MUDDLE` line is conditional (`if_num_monsters 1`
plus `if_hit`) — the #216 class, and one of the 24 deaths.

Everything else on that list goes down the physical path, which is the one
the back row halves: `battle_main.asm` @3392 skips the halving only when
`$b3` bit 5 is set, otherwise `bit $3aa1,x` (the target's row bit) and
`lsr $11b1 / ror $11b0`.

## The lab

`tools/tests/fcalcovelab.py`. Each policy is a derived copy of
`gen_fc_alcove.lua` — the generator verbatim, plus the observers, plus the
policy's own field steps at the landing — run once per seed under `run.sh`
with the lib's retries OFF (`OT6_RETRIES=1`, so every seed reports its
first try) and `OT6_SEED_SHIFT` idle frames at the boot point, which is
what a player who paused a beat before walking on would have done. Each run
cold-Continues the tracked `fc-landing-v1` battery exactly as the ninja
graph does. Every substitution asserts it matched exactly once, so a
generator edit that moves an anchor fails the derivation instead of
silently measuring something else. Nothing is published to `build/states`.

The declared spread is **seeds 0, 5, 10, ... 55** — twelve shifts across the
60-frame battle-seed period — the same twelve in control, back and
dressback; dress was measured on the first six before the row turned out to
be the lever. Every seed's first-battle RNG key is distinct within its
policy (the `first battle` column of `aggregate.txt`), so each policy is
twelve distinct samples.

The policies are **not** a paired A/B. Each one spends a different amount of
menu time at the landing (a rows drive, eleven equip rungs, or both) before
the first step onto the continent, so the encounters they draw diverge from
control's from the first fight. Twelve independent first tries per policy is
what these numbers are.

None of the policies reads hidden state. SHADOW's empty equipment screen
and his row are what the field menu shows the moment he joins, and the kit
is the same eleven rungs from the same bag the generator already walks at
the alcove.

- **control** — the generator as it ships.
- **dress** — SHADOW's kit at the landing instead of at the alcove.
- **back** — SHADOW to the back row at the landing.
- **dressback** — both.

### Results

```
policy       n  pass  deaths  fenix  wipes  fights   frames
control     12    12      24     20      1      88    45020
back        12    12      10     10      0      84    42862
dressback   12    12       7      7      0      84    39504
dress        6     6      17      9      2      48    49645
```

(`wipes` counts `[descent] attempt N LOST` — a lost crossing reloaded from
the landing save, the way a person reloads the 394 (7,12) save. `frames` is
the mean over passing runs, from the cold Continue. Every run passed: the
segment's own 3-attempt reload sweep absorbs a wipe.)

Per seed, deaths / Fenix Downs (the full table with frames and RNG keys is
`aggregate.txt`):

| seed | control | dress | back | dressback |
|---|---|---|---|---|
|  0 | 4 / 4 | 2 / 2 | 0 / 0 | 0 / 0 |
|  5 | **5 / 1, wipe** | — | 0 / 0 | 0 / 0 |
| 10 | 0 / 0 | 0 / 0 | 2 / 2 | 0 / 0 |
| 15 | 0 / 0 | — | 1 / 1 | 0 / 0 |
| 20 | 4 / 4 | **7 / 3, wipe** | 1 / 1 | 4 / 4 |
| 25 | 0 / 0 | — | 5 / 5 | 0 / 0 |
| 30 | 1 / 1 | 1 / 1 | 0 / 0 | 1 / 1 |
| 35 | 3 / 3 | — | 0 / 0 | 0 / 0 |
| 40 | 2 / 2 | **6 / 2, wipe** | 0 / 0 | 0 / 0 |
| 45 | 1 / 1 | — | 0 / 0 | 1 / 1 |
| 50 | 4 / 4 | 1 / 1 | 1 / 1 | 0 / 0 |
| 55 | 0 / 0 | — | 0 / 0 | 1 / 1 |

Clean crossings (no death at all): control **4 of 12**, back **7 of 12**,
dressback **8 of 12**.

### What killed them, by policy

Every `[kill]` line in the spread, grouped:

```
== control (24 kills)
   Behemoth Special:TakeDown     9   raw 586..1609
   WireyDrgn Special:Wing        4   raw 532..859
   Ninja $51 (Fire Skean)        4   raw 300..413
   Brainpan Battle               2   raw 268..291
   Behemoth Battle               2   raw 550..583
   Apokryphos L5Doom             1   raw 16383
   Ninja $53 (Bolt Edge)         1   raw 297
   Dragon Special:Tail           1   raw 3137
   by victim: char 3 (SHADOW) 15, char 1 (LOCKE) 5, char 4 (EDGAR) 3, char 0 (TERRA) 1
   in 8 different formations

== dressback (7 kills)
   Behemoth Special:TakeDown     6   raw 710..1312
   Ninja $51 (Fire Skean)        1   raw 311
   by victim: char 0 (TERRA) 3, char 3 (SHADOW) 2, char 1 (LOCKE) 2
   in 2 formations: Behemoth+Behemoth 6, Ninja+WireyDrgn 1
```

Control loses people to eight species in eight formations. dressback loses
them to **one attack in one formation**, and four of its seven are a single
fight (seed 20's `fight5`, a Behemoth pair).

### Why: the row, measured

The raw damage word each monster attack wrote **against SHADOW** across the
spread (`[hit]` lines, only the hits that landed on entity 3):

| attack | control (front, naked) | back (back, naked) | dressback (back, dressed) |
|---|---|---|---|
| Brainpan Battle | 265..301, med 279 (n=13) | 132..156, med 146 (n=17) | 105..119, med 114 (n=14) |
| Misfit Battle | 307..347, med 314 (n=5) | 152..172, med 164 (n=6) | 117..124, med 124 (n=4) |
| Apokryphos Battle | 261..288, med 282 (n=6) | 138..142, med 141 (n=4) | 102..107, med 103 (n=4) |
| Wirey Drgn Battle | 395..428, med 408 (n=12) | 191..207, med 204 (n=6) | 158..160, med 160 (n=4) |
| Wirey Drgn Wing | 783..859, med 792 (n=5) | 394..414, med 409 (n=4) | 303..305, med 305 (n=2) |
| **Behemoth Take Down** | 1065..1609, med 1130 (n=5) | 524..1788, med 565 (n=14) | 418..1312, med 441 (n=8) |
| Ninja Fire Skean | 393..423, med 393 (n=5) | 425..434, med 434 (n=2) | 345..381, med 371 (n=4) |

The back row halves the median of **every physical** — and the Ninja's Fire
Skean, which is not one, does not halve. The kit takes roughly another fifth
off on top. Against a 971/1050 max HP that is the difference between a
Wirey Drgn's Wing being a two-hit kill and a four-hit one, and it is why
Wing, Battle and Tail stop appearing on the kill list entirely.

What it does **not** fix is Take Down's tail. Halved, its median is 441-565,
but the roll still reaches **1788 in the back row** — over every member's
maximum on this route (TERRA 1039-1207, LOCKE 1305-1400, SHADOW 971-1050,
EDGAR 1048-1216). All six of dressback's Behemoth deaths are that tail:

```
[kill] f26239 fight5 form=Behemoth+Behemoth entity 3 char 3 from 1050/1050 by Behemoth(s1) Special:TakeDown raw=1246
[kill] f26956 fight5 form=Behemoth+Behemoth entity 0 char 0 from 787/1121 by Behemoth(s0) Special:TakeDown raw=1053
[kill] f27560 fight5 form=Behemoth+Behemoth entity 3 char 3 from 131/1050 by Behemoth(s1) Special:TakeDown raw=1312
[kill] f30712 fight5 form=Behemoth+Behemoth entity 1 char 1 from 280/1400 by Behemoth(s1) Special:TakeDown raw=769
[kill] f20542 fight5 form=Behemoth+Behemoth entity 0 char 0 from 878/1039 by Behemoth(s0) Special:TakeDown raw=1044
[kill] f20743 fight4 form=Behemoth+Behemoth entity 1 char 1 from 429/1305 by Behemoth(s0) Special:TakeDown raw=710
```

### Why dressing alone is not it

`dress` (kit, still front row) measured **worse** than control on its six
seeds: 17 deaths, 2 lost crossings. Its kill list is the control list with
armour on — Brainpan/Misfit Battle hits of 157-340 instead of 265-347 — and
that is not enough at a front-row member's exposure. Seed 40's attempt 1
wiped in its very first fight, formation 183:

```
[kill] f8898  fight1 form=Brainpan+Misfit+Apokryphos+Brainpan entity 3 char 3 from 100/971 by Brainpan(s0) Battle raw=328
[kill] f12516 fight1 ... entity 1 char 1 from 75/1305 by Brainpan(s3) Battle raw=286
[kill] f13457 fight1 ... entity 0 char 0 from 72/1039 by Misfit(s1) Battle raw=306
[kill] f13643 fight1 ... entity 2 char 4 from 124/1048 by Brainpan(s0) Battle raw=157
[kill] f13803 fight1 ... entity 3 char 3 from 121/971 by Brainpan(s3) Battle raw=340
[descent] attempt 1 LOST at f14012 (wiped on the walk to (40,6), r4) -- reloading the landing snapshot
```

Six seeds is a small sample and its two extra wipes are within the draw's
noise; the point the table supports is only that the **row** is the lever
and the kit is not, which is exactly what the damage table above predicts.
The kit still belongs in the answer — a party member with no armour, no
weapon and no relic is not something a person walks a continent with, and
dressback is the best row in the table on every count.

## The banked pips

The one qualification death that held 3 BP is fight 3, LOCKE at 519/1305.
The driver did **not** leave the boost on the table — it had already decided
to spend it, 47 ticks earlier:

```
[navTo] actor=1 SPEND (care): 519/1305 is inside one round of death (811) holding 3 BP, and no heal saves it (item $E9 +250 = 769) -- Fight at 3 BP (8 chip(s) on slot 0) rather than die holding boost (#175)
[navTo] actor=1 char=1 plan=fight
[navTo] [death] f+2747 entity 1 char 1 from 519/1305 by slot 0 cmd $00 atk $EF bp=3 -- died holding 3 BP
```

The plan was made at f+2700 and the Wirey Drgn's Wing landed at f+2747,
before LOCKE's turn resolved. This is the zozo lab's "shape 1" (#194): the
rule fires, the window does not come round. Spending the pips one window
earlier is not shown to help either — the boosted Fight's job would have
been to kill slot 0 outright (2687 HP, one shield up) in the turn it had,
which the same actor's measured swings in that fight (131 and 290 a hit) do
not reach.

Over the whole 12-seed control spread the same rule fires more than twenty
times, at up to 5 BP, and **3 of the 24 deaths** were holding >= 3 BP
(`python3 tools/audit_boost.py build/lab/fc-alcove/control/seed*.log -v`).
The decisive measurement is that the identical spend rule loses 24 members
with SHADOW in the front row and 7 with him in the back. **Boost is not the
lever here.**

What *was* available in that window was a Potion. The roll that killed
LOCKE was 532; he was at 519 with a Potion (+250, measured in that fight)
in the bag, so 769 would have survived the hit that actually landed. The
driver declined it because it compares the heal against the worst-case
**round** (811, two enemy actions) rather than against the next single hit.
That is a defensible conservative rule and changing it is a driver question,
not this lab's — noted below.

## Two things this lab found on the way

**1. Brainpan's Smirk is Stop, and the driver stands still under it.**
Smirk's `specdata $54` is "no damage, status $14" — status bit 20, Stop.
The fight driver answers a denied actor's open window by standing its stall
counters down and pressing nothing (`lib/ot6.lua`, the #187 block: "The
engine is about to take the window away ... or never meant to open one, so
nothing here is a stall"). Measured, that does not hold for Stop:
`python3 tools/tests/fcalcovelab/stop_stalls.py
build/lab/fc-alcove/control/seed*.log` (kept as
`build/lab/fc-alcove/stop-stalls-control.txt`) reports **19 Stop landings
across the 12 control seeds, 11 of which left the party with no plan at all
for 600+ ticks**. The worst:

```
== control/seed00.log
  fight6 Brainpan+Misfit+Apokryphos+Brainpan  Stop on char 1 at f+823  -> next plan 2700 (gap 1877 ticks); partyhp 812,1065,742,1050 -> 723,825,601,503; deaths inside: char 3 from 242/1050 at f+2902
== control/seed35.log
  fight1 Brainpan+Brainpan+Brainpan           Stop on char 3 at f+421  -> next plan 3000 (gap 2579 ticks); partyhp 995,1101,1048,971 -> 909,536,904,693
```

In seed 0 the battle sat at `menu=01 state=05 actor=2` for 2,276 ticks with
EDGAR under Stop, no member planned or acted, the monsters' HP never moved,
and SHADOW fell 1050 → 0 inside it. That is one of the qualification's four
deaths. It is a driver question, not a balance one, and it is left for its
own issue.

**2. The Tonic bag empties.** The qualification lands with `tonic=45` and
leaves the alcove with `tonic=4 potion=50 fenix=22` (`[care at the alcove] done`), far under the
owner's ~level x5 band. That is the already-known #213 finding — the
continent has no counter behind it and a Tonic is +50 against L26 maxima
near 1000 — and not something this segment can fix.

## Recommendation

**Dress SHADOW and put him in the back row at the landing, where he joins,
instead of at the alcove after the crossing is over.** Measured over the
same 12 seeds:

| | deaths | Fenix Downs | lost crossings | clean crossings | mean frames |
|---|---|---|---|---|---|
| before (`control`) | 24 | 20 | 1 | 4 / 12 | 45,020 |
| after (`dressback`) | **7** | **7** | **0** | **8 / 12** | **39,504** |

That is the whole of the issue's signal: `audit_fenix`'s "any Fenix in a
random" flag fires on eight of twelve control crossings and four of twelve
after, and the three ordinary-attack deaths the issue names — `atk $EF`
twice and `atk $EE` once, all on SHADOW — are exactly the class that
disappears.

The change is two steps in `gen_fc_alcove.lua`, both of which the file
already contains, moved: `H.setRows` to include `[SHADOW] = true` after the
talk at (10,16) rather than before it, and the existing
`kitSteps(SHADOW, "SHADOW", { ... })` block applied at the landing as well
as at the alcove. `build/lab/fc-alcove/dressback.lua` is that exact diff
against the shipped generator, and the lab's `derive()` asserts each anchor
matched once.

**This lab does not land that change.** Editing `gen_fc_alcove.lua` moves
its `generator_sig` and stales the tracked `fc-alcove-v1` checkpoint and
everything downstream of it, and the route regeneration for this cycle is
owned by another branch. The measured recommendation is the deliverable;
the re-cut is that branch's step.

**What is left after it is the #216 answer, honestly.** Six of dressback's
seven deaths are the Behemoth's Take Down in formation 187 (Behemoth x2,
1.56% of rolls; Behemoth is in three formations, ~18.8% in total). It is a
vanilla x2 physical on an ordinary AI turn — no counter to avoid, no last-
monster-standing branch to steer, and no kill order to pick in a formation
that is two of the same species. The back row halves it and the tail still
reaches 1788, above every member's maximum at L24-28. Covering that tail by
levels would need SHADOW's max HP up about 70%, which is a different game;
covering it by retuning the Behemoth is not on the table. So: a rare
non-wipe death to a vanilla mechanic, raised with a Fenix Down and walked
off — the class the owner accepted in #216, now actually rare (7 deaths in
12 crossings, 0 wipes) instead of the 24-in-12 the front-row naked SHADOW
was producing.

**Not the cause, measured:** levels (SHADOW's L24 is the roster average and
only L5 Doom keys on it, one death in 24), kill order (the killers' AI has
no branch a kill order reaches), and banked boost (the spend rule fires and
the same rule loses 7 instead of 24 once the row changes). The one
in-combat healing lever worth a follow-up is the round-cost test that
refused a Potion which would have survived the hit that landed.
