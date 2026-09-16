# The map-269 random — the Trapper trio's L.4 Flare (#171)

Authored 2026-09-07 from `tools/tests/lab_map269_random.lua` (the lab; its
header carries the decoded rows) and the n024_entry regeneration log
`build/states/n024_entry.log`.  Every number below is quoted from a
retained run log under `build/m269lab/` (the batch runner keeps every
attempt; `tools/tests/m269lab_aggregate.py` prints them all).

## What happened in the regeneration

`gen_n024_entry` boots `magicite_ifrit_shiva` (map 264 (9,7), the Ifrit &
Shiva room) and walks 264 -> 269 -> 271 -> 273.  Nineteen steps onto map
269, at (48,38), the first random:

    [navTo] battle f+1 ... partyhp=502,0,447,443 roundcost=0,0,0,0 monhp=s2:555/sh2,s3:555/sh2,s4:555/sh2 monsters=3
    [navTo] actor=0 revive entity 1 with Fenix Down (to 63 HP of 511; ...)
    [navTo] slot 4's smallest hit this fight so far: 447, on entity 2 (447 -> 0)
    [navTo] slot 4's smallest hit this fight so far: 443, on entity 3 (443 -> 0)
    [care after battle (navTo)] opening the menu: c1 0/447 hp ... c6 0/443 hp ... | tonic=82 potion=0 fenix=12
    [care after battle (navTo)] done: c1 305/447 hp ... c6 305/443 hp ... | tonic=72 potion=0 fenix=10

Three things are in those lines, not one:

1. **The party walked in with SABIN dead** (`partyhp=502,0,447,443` at
   f+1).  Battle 70 (Ifrit & Shiva) killed him, the driver's no-raise rule
   held (`build/states/magicite_ifrit_shiva.log`: "no raise: Fenix Down
   would put entity 1 at 63 HP ... smallest hit this fight is 68"), the
   fight was won with him down, and `gen_ifrit_magicite` walked to the
   magicite pickups and **saved without a care stop** (`savestate_party`
   over `magicite_ifrit_shiva.mss`: SABIN hp 0/511, status1 $80).  The
   first Fenix Down of the leg (in battle, f+300) is battle 70's cost, not
   the random's.  CELES is also at **6/126 MP** from that fight.
2. **LOCKE (447/447) and CELES (443/443) died to one action** each, at the
   same moment (both "smallest hit" lines land together, f+1200..1500).
3. The fight then took **~4900 frames** (battle up ~f636, care opened
   ~f8269) for three 555-HP bodies, because the two members who hold the
   keys were the dead ones (below).

`python3 tools/audit_fenix.py build/states/n024_entry.log`:

    n024_entry                       3  RANDOM  Fenix in randoms -- underleveled or lab these encounters

## The fight, decoded

Map 269 rolls encounter group 105 (`tools/audit_encounters.py 269`):

    31.25% formation $077 PINCER POSSIBLE General($066)x2
    31.25% formation $078 PINCER POSSIBLE Pipsqueak($041)x2 General($066)x1
    31.25% formation $076 fleeable       Trapper($02d)x3
     6.25% formation $076 fleeable       Trapper($02d)x3

555 is Trapper's HP exactly (General 650, Pipsqueak 250);
`battle_monsters.dat` $076 is present-mask $1c, species $2d $2d $2d in
slots 2-4 -- the log's `s2,s3,s4`.  Trapper appears in **no other field
map's pool** (`audit_encounters.py` over maps 0..420: only 269).

| | value | source |
|---|---|---|
| Trapper $02d | L19, HP 555, MP 80, speed 35, atk 13, def 180, mdef 135, **mpow 10**, XP 235, GP 200 | `monster_prop.dat` +$05A0; all 32 bytes identical to the vanilla ROM record (`Final Fantasy III (USA).sfc` $0F05A0) |
| weakness | **bolt \| water** ($84); no absorb/null | `monster_prop.dat` +25 |
| shields | **2, class key OT6_BLUDG** | `Ot6ShieldTbl`, `ot6_hud.asm:1748` ("a fixed trap mechanism, smashed rather than stabbed"); no `Ot6ElemAddTbl` row |
| special "Program 18" | $57: bit $40 = **no damage** (`battle_main.asm:8447` clears the attack power), effect $17 = status bit 23 = **Reflect** on the target | `monster_prop.dat` +31 |
| AI | `attack SPECIAL, L5_DOOM, NOTHING` / wait / `attack SPECIAL, L4_FLARE, NOTHING` / wait / `attack SPECIAL, L3_MUDDLE, NOTHING` / end (loop) | `ai_script.asm:1262` "trapper" |
| L4 Flare $95 | power **66**, magic, flags +2 = $60 = **ignore defence \| no split**, +8 = **4** (the level divisor) | `magic_prop_en.dat`; byte-identical to vanilla, as are L5 Doom ($94, divisor 5) and L3 Muddle ($96, divisor 3) |

So a Trapper **never swings**.  A third of its turns do nothing, a third
are a damage-free Reflect, and a third are a level spell: turn 1 L5 Doom,
turn 2 **L4 Flare**, turn 3 L3 Muddle, then round again.  L4 Flare hits
*every* target whose level is a multiple of 4, each for the full unsplit
roll, defence and row ignored.  L5 Doom kills multiples of 5; L3 Muddle
confuses multiples of 3.

The routed party at the save (`audit_levels`, `savestate_party`):

| char | level | HP | MP | row | weapon | key |
|---|---|---|---|---|---|---|
| LOCKE | **16** | 447 | 103 | front | ThunderBlade (**bolt**) + Guardian (Genji Glove) | element key |
| EDGAR | 17 | 502 | 123 | back | RegalCutlass (slash) | none (AutoCrossbow is pierce) |
| SABIN | 17 | **0/511 dead** | 108 | back | MetalKnuckle (slash on Fight); **Pummel is OT6_BLUDG** | class key |
| CELES | **16** | 443 | **6** | back | MithrilBlade (slash); Ramuh (bolt, 25 MP) unaffordable | none at 6 MP |

Bag: 84 Tonics, 13 Fenix Downs, 2 Tinctures, 3 Elixirs.  XP: LOCKE 13097
(L17 at 14152, **1055 short**), CELES 13033 (**1119 short**).

**16 is a multiple of 4; 17 is a multiple of nothing the Trapper casts.**
The two L16s are exactly the two who died, to one L4 Flare; the two L17s
cannot be touched by any of its three spells.  "447 -> 0" is the roll
clamped to LOCKE's HP.  The engine's own damage word at `_writedamage`
(before `ApplyDmg` clamps), read by the lab:

    [hit] f2909 Trapper(s4) cmd=0C atk=L4Flare tgt=000F dmg=0,0,447,443 raw=16383,16383,802,778 kills=2   (control_s0)
    [hit] f3478 Trapper(s3) cmd=0C atk=L4Flare tgt=000F dmg=0,0,447,443 raw=16383,16383,792,765 kills=2   (breakfirst_s0)

(16383 = no damage word for that entity: EDGAR and SABIN, L17, are simply
not targets.)  The vanilla formula agrees: monster magic uses mag.pwr x1.5
(`battle_main.asm:6853,6933`), so 66*4 + 19*15*66/32 = 851, times the
224..255/256 spread = **744..851**, no defence term.  Against 447 / 443
max HP that is 1.7-1.9x a kill; on the chain's own HP curve it still
exceeds LOCKE at L20 (~680, the next multiple of 4), so "out-level it" only
works by *parity*, not by HP.

## The lab

Fixture `build/states/m269lab_pre.mss`: the map-269 landing (44,53),
baked by `tools/tests/probe_m269lab_bake.lua` = `gen_n024_entry`'s first
leg verbatim from `magicite_ifrit_shiva` -- no care, no menu, so the party
stands there exactly as the route delivers it (`build/m269lab/bake.log`:
`LOCKE L16 447/447 hp 103/118 mp front; EDGAR L17 502/502 hp 123/127 mp
back; SABIN L17 0/511 hp 108/124 mp back status1=80; CELES L16 443/443 hp
6/126 mp back | tonic=84 fenix=13 tincture=2`, `$1fa1=38 $1fa2=2A`).

From that snapshot the next random is fixed: `CheckBattleSub` draws the
encounter check from `RNGTbl[$1fa1]` once per step and the formation slot
from `RNGTbl[$1fa2]` once per battle, both counters live in the snapshot,
and neither an idle frame nor a menu moves them -- so every run rolls at
the same tile, (48,38), and always rolls **$076 Trapper x3** (80 of 80
runs: `python3 tools/tests/m269lab_aggregate.py`).  Idling before the
first step varies only the battle seed (`$021e*4`), in 4-frame quanta, so
the declared spread is **15 seeds (0..56 step 4), the whole 60-phase
cycle**; every policy drew 15 distinct `bseed` values.  `cared`,
`breakfirst` and `boostfight` share the exact pre-battle state per seed (a
paired A/B: same `bseed` column); `control` spends no menu and `allback`
spends a second one, so each of those draws its own 15.

Policies (`tools/tests/m269lab_batch.sh <policy> <seeds>`; none reads
hidden state -- the keys are the weapons the party wears, and the
level-multiple rule is what the screen says when "L.4 Flare" lands):

- **control** -- `gen_n024_entry`'s leg as it shipped: no care at the
  save (SABIN dead, CELES 6 MP), `navTo`'s tactical driver with its
  defaults (tactical, boost, items, healPercent 55, no bank, AutoCrossbow).
- **cared** -- one `fieldCare` (threshold 0.95) at the landing, SABIN
  raised and HP topped, then the control driver.
- **allback** -- cared + LOCKE joins the other three in the back row.
- **breakfirst** -- cared + bank 0 (LOCKE's first ThunderBlade Fight and
  SABIN's first Pummel go out boosted on turn 1) + one Trapper at a time.
- **boostfight** -- cared + bank 0 + `tactical=false`: everyone
  boost-Fights from turn 1, no AutoCrossbow, no Pummel (the "boost-Fight
  through randoms" default; SABIN's Fight is slash, so this holds only
  LOCKE's bolt key).

After the fight, `navTo`'s own between-battles care stop (`newCareDriver`,
threshold 0.65, Tonics only) runs, so a Fenix spent there counts the way
`audit_fenix` counts it.

### Results, 15 Trapper-trio fights per policy

`python3 tools/tests/m269lab_aggregate.py` (deaths = members dead when the
fight ended; fenixP/B/C = Fenix Downs at the landing care / in battle / at
the care stop after; frames = mean battle length; flares = L4 Flare casts;
maxraw = the largest damage word read at `_writedamage`):

```
policy        n formations     seeds deaths fenixP fenixB fenixC wipes frames flares maxhit maxraw
allback      15 Trapper+Trapper+Trapper:15    15      8     15      0      8     0   3378      4    447    832
boostfight   15 Trapper+Trapper+Trapper:15    15     12     15      5     12     0   8515     23    447    835
breakfirst   15 Trapper+Trapper+Trapper:15    15      8     15      0      8     0   3462      4    447    812
cared        15 Trapper+Trapper+Trapper:15    15      8     15      0      8     0   3355      4    447    845
control      15 Trapper+Trapper+Trapper:15    15     16      0     27     16     0   8050     22    447    848
```

The `deaths` column undercounts the kills: the control driver eventually
raises the pair late in its long fights.  Counting fights that contained an
`L4Flare!2` (both L16s killed by one cast):

| policy | double-kill fights | mean frames | Fenix per fight (B+C) | note |
|---|---|---|---|---|
| control | **9/15** | 8050 | 2.9 (SABIN's raise inside that) | as shipped |
| cared | **4/15** | 3355 | 0.53 | the kit fix |
| allback | 4/15 | 3378 | 0.53 | = cared: rows are irrelevant to a defence-ignoring spell |
| breakfirst | 4/15 | 3462 | 0.53 | = cared: the keys already land in round 1 |
| boostfight | **7/15** | 8515 | 1.13 | worse: no Pummel, no class key, 2.5x the frames |

Per attempt (`build/m269lab/<policy>_s<seed>.log`; `s`=seed, `b`=battle
seed, `f`=frames, `fenix`=landing/battle/care, `rolls`=raw L4 Flare words
per target, `hits`=every monster action in order; `Nothing` is the AI's
`attack ..., NOTHING` third, resolved through `ExecCmd` as command $12;
long lines elided with `...`):

```
== control
  s0  b80 f10020 deaths=0 fenix=0/3/0 flares=4 rolls=c1:802,c6:778 hits=Nothing,Nothing,Special,L4Flare!2,L4Flare,L4Flare,Nothing,Special,L3Muddle,Special,Special,Special,Special,L4Flare,Special,Nothing,Special,Nothing,Nothing,Spe
  s4  b90 f7583  deaths=2 fenix=0/2/2 flares=2 rolls=c1:802,c6:778 hits=Special,Nothing,L5Doom,Special,Nothing,L4Flare!2,L3Muddle,Nothing,L3Muddle,L5Doom,L5Doom,L5Doom,Nothing,Special,L4Flare,Nothing,Nothing,L3Muddle,Special
  s8  bA0 f8388  deaths=0 fenix=0/2/0 flares=0 rolls=- hits=L5Doom,Nothing,Special,Nothing,Special,Nothing,Special,Nothing,Nothing,L5Doom,L5Doom,Special,Special,Special,Special,Nothing,Nothing,Special
  s12 bB0 f8735  deaths=2 fenix=0/2/2 flares=2 rolls=c1:848,c6:778 hits=Special,Special,Special,Special,Special,L4Flare!2,Special,L3Muddle,L3Muddle,L5Doom,L5Doom,L5Doom,L4Flare,Special,Special,Nothing,Special,Nothing,Nothing,Nothi
  s16 bC0 f8035  deaths=2 fenix=0/2/2 flares=1 rolls=c1:798,c6:775 hits=Special,Nothing,Special,Special,Nothing,L4Flare!2,Nothing,Special,L3Muddle,Special,L5Doom,Nothing,Special,Special,Special,Nothing,L3Muddle,Special,Special
  s20 bD0 f8175  deaths=2 fenix=0/2/2 flares=3 rolls=c1:842,c6:798 hits=Special,Special,Special,L4Flare!2,Special,Special,L3Muddle,Nothing,L3Muddle,Nothing,Special,Special,L4Flare,L4Flare,Nothing,Nothing,Special,Special,Special,Sp
  s24 bE0 f8372  deaths=0 fenix=0/2/0 flares=1 rolls=- hits=Special,Special,L5Doom,Special,Special,Special,L3Muddle,Nothing,Nothing,Nothing,Nothing,L5Doom,Special,Special,L4Flare
  s28 bF0 f9360  deaths=0 fenix=0/1/0 flares=0 rolls=- hits=Nothing,Nothing,Nothing,Special,Special,Special,L3Muddle,Nothing,L3Muddle,Nothing,L5Doom,L5Doom,Special,Nothing,Nothing,L3Muddle,L3Muddle
  s32 b10 f7323  deaths=0 fenix=0/1/0 flares=0 rolls=- hits=Special,L5Doom,Special,Special,Special,Special,Nothing,Special,Special,L5Doom,Special,Nothing
  s36 b20 f6240  deaths=0 fenix=0/1/0 flares=0 rolls=- hits=Nothing,L5Doom,Nothing,Special,Nothing,Nothing,Special,Special,L3Muddle,Nothing,L5Doom,Nothing
  s40 b30 f7883  deaths=2 fenix=0/2/2 flares=2 rolls=c1:802,c6:822 hits=Special,Nothing,L5Doom,L4Flare!2,L4Flare,Special,Nothing,L3Muddle,Nothing,Nothing,Special,L5Doom,Nothing,Special,Nothing,Nothing,L3Muddle,L5Doom,Nothing,Nothi
  s44 b40 f9047  deaths=2 fenix=0/2/2 flares=1 rolls=c1:818,c6:828 hits=L5Doom,Nothing,L5Doom,Special,Special,L4Flare!2,Nothing,Nothing,Nothing,Nothing,Special,L5Doom,Nothing,Nothing,Nothing,L3Muddle,Special,L3Muddle,Special,Speci
  s48 b50 f6851  deaths=0 fenix=0/2/0 flares=0 rolls=- hits=L5Doom,Nothing,Special,Special,Nothing,Nothing,Special,Nothing,L3Muddle,Nothing,L5Doom,Nothing
  s52 b60 f7719  deaths=2 fenix=0/2/2 flares=3 rolls=c1:762,c6:848 hits=Special,Nothing,Special,L4Flare!2,Special,L4Flare,Special,Nothing,Special,L5Doom,Special,Nothing,Nothing,Nothing,L4Flare,Nothing,L3Muddle,L5Doom,Nothing
  s56 b70 f7019  deaths=2 fenix=0/1/2 flares=3 rolls=c1:798,c6:782 hits=Special,Nothing,Special,L4Flare!2,Nothing,L4Flare,L3Muddle,Special,L3Muddle,Special,Nothing,L4Flare
== cared
  s0  bA0 f3298  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Nothing,Nothing,Special,Nothing,Nothing
  s4  bB0 f3751  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=L5Doom,L5Doom,L5Doom,Special
  s8  bC0 f4202  deaths=2 fenix=1/0/2 flares=1 rolls=c1:745,c6:772 hits=Special,L5Doom,L5Doom,L4Flare!2
  s12 bD0 f2790  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,Special,Nothing,Nothing,Nothing
  s16 bE0 f3554  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=L5Doom,L5Doom,Nothing,Nothing,Special
  s20 bF0 f3414  deaths=2 fenix=1/0/2 flares=1 rolls=c1:768,c6:845 hits=Nothing,Nothing,Special,L4Flare!2,Nothing
  s24 b10 f2778  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,Nothing
  s28 b20 f3302  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,Special,Nothing,Nothing,Nothing
  s32 b30 f3642  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Nothing,L5Doom,Special,Nothing,Special
  s36 b40 f3654  deaths=2 fenix=1/0/2 flares=1 rolls=c1:845,c6:758 hits=Special,Nothing,Special,L4Flare!2,Nothing
  s40 b50 f3906  deaths=2 fenix=1/0/2 flares=1 rolls=c1:765,c6:842 hits=L5Doom,Nothing,Special,Nothing,L4Flare!2
  s44 b60 f3774  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=L5Doom,L5Doom,L5Doom,Nothing,Special,Nothing
  s48 b70 f2882  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=L5Doom,Nothing,Nothing,Nothing,Nothing
  s52 b80 f2694  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,Nothing
  s56 b90 f2682  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Nothing,Nothing,Special
== allback
  s0  b1C f3693  deaths=2 fenix=1/0/2 flares=1 rolls=c1:832,c6:758 hits=Nothing,L5Doom,Nothing,Nothing,L4Flare!2
  s4  b2C f3090  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Nothing,Special
  s8  b3C f3214  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,Nothing,L5Doom,Nothing,Nothing
  s12 b4C f3609  deaths=2 fenix=1/0/2 flares=1 rolls=c1:812,c6:768 hits=Nothing,Nothing,L4Flare!2
  s16 b5C f3022  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,Nothing
  s20 b6C f3026  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Nothing,Nothing,Nothing
  s24 b7C f4141  deaths=2 fenix=1/0/2 flares=1 rolls=c1:752,c6:752 hits=Nothing,Special,Nothing,L4Flare!2,Nothing,Nothing
  s28 b8C f4569  deaths=2 fenix=1/0/2 flares=1 rolls=c1:812,c6:808 hits=Nothing,Nothing,L4Flare!2,Special,Special
  s32 b9C f4286  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=L5Doom,Special,Special,Nothing,Special
  s36 bAC f2706  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,Nothing
  s40 bBC f3142  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Nothing,L5Doom,Nothing
  s44 bCC f3026  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,Nothing
  s48 bDC f3222  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,Special,Nothing,Nothing,Nothing
  s52 bEC f3010  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,Nothing,Special,Nothing,Nothing
  s56 b0C f2910  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Nothing,L5Doom
== breakfirst
  s0  bA0 f3498  deaths=2 fenix=1/0/2 flares=1 rolls=c1:792,c6:765 hits=Nothing,Nothing,Nothing,Nothing,L4Flare!2
  s4  bB0 f3582  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=L5Doom,L5Doom,L5Doom,Nothing
  s8  bC0 f3338  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,Nothing,Special,Nothing,Special
  s12 bD0 f3278  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,Special,Special,Nothing,Nothing
  s16 bE0 f3386  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=L5Doom,L5Doom,Nothing,Nothing,Nothing
  s20 bF0 f3542  deaths=2 fenix=1/0/2 flares=1 rolls=c1:812,c6:768 hits=Nothing,Nothing,Special,Nothing,L4Flare!2
  s24 b10 f2850  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,Nothing
  s28 b20 f3527  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,Special,Special,Nothing,Nothing,Special
  s32 b30 f3618  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Nothing,L5Doom,L5Doom,Nothing,Nothing,Nothing
  s36 b40 f3126  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,Nothing,Nothing,Nothing,Nothing
  s40 b50 f3610  deaths=2 fenix=1/0/2 flares=1 rolls=c1:805,c6:778 hits=Nothing,Special,Nothing,Nothing,L4Flare!2
  s44 b60 f4047  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=L5Doom,L5Doom,L5Doom,Nothing,Special
  s48 b70 f4154  deaths=2 fenix=1/0/2 flares=1 rolls=c1:808,c6:758 hits=L5Doom,Nothing,Nothing,L4Flare!2,Nothing,Special
  s52 b80 f3047  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Nothing,Nothing,Nothing
  s56 b90 f3330  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,Nothing,L5Doom,Nothing,Nothing
== boostfight
  s0  bA0 f4194  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Nothing,Nothing,Special,Nothing,Nothing,Nothing,Special,L5Doom
  s4  bB0 f14222 deaths=2 fenix=1/0/2 flares=5 rolls=c1:775,c6:815 hits=L5Doom,L5Doom,Special,L4Flare!2,L4Flare,Nothing,Special,Nothing,Nothing,Nothing,L4Flare,Special,Special,Special,L5Doom,Nothing,Special,Special,Special,Special
  s8  bC0 f5690  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,Nothing,Special,Nothing,Special,L3Muddle,L3Muddle,Nothing,Nothing
  s12 bD0 f6886  deaths=2 fenix=1/0/2 flares=1 rolls=c1:778,c6:765 hits=Special,Special,Nothing,Nothing,Special,Special,Nothing,Special,L4Flare!2,L3Muddle,L5Doom
  s16 bE0 f13354 deaths=2 fenix=1/0/2 flares=3 rolls=c1:818,c6:775 hits=L5Doom,L5Doom,Nothing,Nothing,Nothing,L4Flare!2,Special,Special,Special,L5Doom,Nothing,L4Flare,L3Muddle,Special,Nothing,L5Doom,Special,L4Flare,L3Muddle,Nothin
  s20 bF0 f5494  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Nothing,Nothing,Nothing,Special,Special,Nothing,Special,Special,L5Doom,Special,Nothing
  s24 b10 f3499  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,L5Doom,Nothing
  s28 b20 f5390  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=Special,Special,Nothing,Nothing,Special,Nothing,Special,L5Doom,Nothing,Nothing
  s32 b30 f13282 deaths=2 fenix=1/0/2 flares=4 rolls=c1:832,c6:832 hits=Nothing,L5Doom,Special,L4Flare!2,L4Flare,Nothing,Nothing,L5Doom,Special,Nothing,L4Flare,Nothing,Special,Special,Nothing,L4Flare,Special,Nothing,L5Doom,Special
  s36 b40 f13582 deaths=2 fenix=1/0/2 flares=3 rolls=c1:808,c6:765 hits=Special,Nothing,Special,L4Flare!2,Nothing,L3Muddle,L3Muddle,Nothing,Nothing,L4Flare,Nothing,Nothing,Special,Nothing,L5Doom,Special,Special,Special,L3Muddle,No
  s40 b50 f4746  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=L5Doom,Nothing,L5Doom,Nothing,Special,Special,L3Muddle
  s44 b60 f14670 deaths=0 fenix=1/3/0 flares=5 rolls=c1:752,c6:835 hits=L5Doom,Nothing,Nothing,L4Flare!2,Nothing,Nothing,L3Muddle,Special,Special,L4Flare,Nothing,Special,Special,Special,Nothing,Nothing,L4Flare,L3Muddle,Special,Spe
  s48 b70 f5458  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=L5Doom,Nothing,Nothing,Nothing,Special,Special,L3Muddle,Special,Nothing
  s52 b80 f5054  deaths=0 fenix=1/0/0 flares=0 rolls=- hits=L5Doom,Special,Nothing,Special,Special,Special
  s56 b90 f12210 deaths=2 fenix=1/2/2 flares=2 rolls=c1:745,c6:772,c1:808,c6:758 hits=Nothing,Nothing,Special,Nothing,L4Flare!2,L3Muddle,Nothing,Nothing,Nothing,Special,Nothing,Special,Special,Nothing,L4Flare!2,Nothing,Nothing,Not
```

What the numbers say:

1. **The raw L4 Flare roll is 745..848 (n=20 targets), 1.7-1.9x the L16s'
   maximum HP; it never missed, never hit an L17.**  Every `L4Flare` line
   with damage words reads `tgt=000F dmg=0,0,447,443` -- the whole party
   is targeted, only the level-multiple-of-4 members take the roll.  No
   L5 Doom or L3 Muddle ever landed on anyone (no L15/L18/L20 in the
   party), and `Special` (Program 18) never did damage.
2. **Rows and boost do not move it; the party's kill speed does.**  The
   Trappers' first actions land at f+430..650 and their second at
   f+2200..2400 (cared_s0: `[hit] f1487/f1507/f1697`, `f3279/f3296`
   after `battle up f1056`).  LOCKE's first Fight kills a Trapper outright
   through the bolt key (`[act] f2226 c1 Fight ... s4:555->0/sh2->0`) and
   SABIN's Pummel kills another through the bludgeon key (`[act] f3039 c5
   Pummel ... s2:555->0/sh2->0`); the third dies to the next two actions.
   So in a cared fight one or two Trappers reach their second turn, each
   with a 1/3 chance of L4 Flare; the measured double-kill rate is **4/15
   = 27%** for cared, allback and breakfirst alike, and every one of those
   Flares landed on a second turn.
3. **The as-shipped leg was three problems stacked.**  With SABIN dead
   (battle 70's cost, saved into the fixture) and LOCKE the first to die,
   both keys were gone: EDGAR's AutoCrossbow (pierce) and CELES's
   MithrilBlade plink half-damage into 2-shield 555-HP bodies for 6000-
   10000 frames, the Trappers get five to seven rounds, and 9/15 fights
   drew the double kill (22 Flares total vs 4).  The driver's no-raise
   rule ("a raise that cannot survive the next action", keyed on the 447
   "smallest hit") then kept the pair down for most of the fight, which
   kept the bolt key down too; 27 Fenix Downs were spent in battle across
   the 15 fights, 16 more at the care stops.
4. **`boostfight` is the wrong default here.**  Dropping Pummel for a
   boosted slash Fight drops the class key: mean 8515 frames, 7/15 double
   kills, 23 Flares, 5 in-battle Fenix.  The keyed tactical driver
   (`cared`, 3355 frames) beats the boost-Fight line by 2.5x on this
   formation; `breakfirst` (bank 0 on the keyed lines) buys nothing over
   bank 3 because the first keyed hits already kill.
5. **The whole leg is this one fight.**  `MODE=walk` (one run per policy,
   `build/m269lab/<policy>_walk_s0.log`) reached map 271 every time with
   exactly one random, the trio at (48,38); the step counter in the
   snapshot fixes the roll, so the General/Pipsqueak formations of this
   pool are not in this sample.  `cared_walk`: `battles=1 ... deaths=0
   fenix_total=0 battle_frames=3298 frames=5146`; `control_walk`:
   `fenix_total=3 battle_frames=10020 frames=11706`.  XP for a Trapper
   trio is **352 per surviving member** (`levels=c1=L16:13449` from
   13097), so LOCKE is three such fights from L17 and CELES four.

## Finding and recommendation

Two findings, one applied.

**Kit (applied).**  `gen_n024_entry` now runs `fieldCare` (threshold 0.95)
at the save before walking, the stop the owner's heal-outside-battles rule
already calls for and the route had skipped because battle 70 is a
scripted fight with no `navTo` care after it.  Regenerated
(`ninja build/states/n024_entry.mss.lua`):

    [ot6] [care at the Ifrit & Shiva save] done: c1 447/447 hp 103/118 mp  c4 502/502 hp 123/127 mp  c5 511/511 hp 108/124 mp  c6 443/443 hp 6/126 mp | tonic=75 potion=0 fenix=12
    [ot6] [navTo] battle f+1 ... partyhp=502,511,447,443 roundcost=0,0,0,0 monhp=s2:555/sh2,s3:555/sh2,s4:555/sh2 monsters=3
    [ot6] PASS (frame 10893)

    $ python3 tools/audit_fenix.py build/states/n024_entry.log
    Fenix audit: no threshold violations in the scanned logs (1 logs).

(was `n024_entry 3 RANDOM`; the generator finishes at frame 10893, was
14468.)  `battle_magicite`, `battle_subjob` and `field_subjob`, the suite
tests that boot `n024_entry`, pass on the regenerated fixture; its CELES
is still MP-dry, which they assert on.  The Fenix that raises SABIN moved
from the random's ledger to the save room, where it belongs to battle 70.
The upstream fix -- a care stop in `gen_ifrit_magicite` after battle 70,
so `magicite_ifrit_shiva` itself is not saved with a dead member -- is
the same one line and is left for the coordinator (it regenerates that
fixture and everything downstream of it).

**Balance / level: a parity trap, not a hot row.**  The remaining 27%
(two Fenix Downs per fight it lands in, ~0.5 per Trapper trio, 37.5% of
map-269 rolls) is vanilla data meeting a party at exactly L16/L17.  It is
not "hot vs the curve" the way Zozo's SlamDancer is: vanilla reaches this
room around L20, which is a multiple of 4 *and* 5, so vanilla's own
walkthrough party eats L4 Flare and L5 Doom here -- the Trapper is the
level-spell lesson by design, and its roll (744..851 by formula) out-damages
LOCKE's HP at any level below the mid-20s.  The levers, cheapest first
(the owner's call; none applied):

- **Nothing more.**  `audit_fenix` will flag this leg in roughly one
  regeneration in four; each flag is 2 Fenix from a bag of 12 and the
  party walks on whole.  The lab is the reason on file.
- **Level, by parity.**  L17 for LOCKE and CELES is immune to all three
  spells (L18 draws L3 Muddle, L20 both L4 Flare and L5 Doom).  1055 /
  1119 XP is three or four Trapper trios at 352 each -- the map rolls one
  per traversal, so that is a deliberate back-and-forth on 269, or the
  271 rooms (Rhinox x2 paid the n024 party 592 each).  A grind, not a
  free lever, and it moves the pair onto L18 (Muddle) next.
- **A driver rule (finding, not implemented -- `ot6.lua` untouched).**
  The no-raise rule takes the 447 as this enemy's per-turn floor and
  refuses the Fenix for the rest of the fight; for a level spell the
  raised pair face a 1/3 chance once per Trapper second turn, and LOCKE
  down is the bolt key down.  A rule that recognises a spell-kill (the
  hit came from a `cmd=0C` Lore / a magic attack with no split, or simply
  "the same action killed two members from full") and raises immediately
  would have turned the control fights from ~8000 frames into cared-shaped
  ones after the first Flare.  Separately, the "boost-Fight through
  randoms" default should read: **not when the formation carries a class
  key a member holds** -- Pummel here is worth 2.5x the frames of a
  boosted slash.
- **Retune, if the flag itself is unwanted.**  Swapping `L4_FLARE` for
  `L3_MUDDLE` (or `NOTHING`) in `AIScript::_45`'s second line keeps the
  level-spell reveal and removes the only damage the species can do; or
  lower L4 Flare's power (66 -> 30 lands the roll at 339..387, which the
  L16s survive only when topped above the 0.65 care threshold's 291; 24
  -> 270..309 is the number they survive from the care floor).  L4 Flare
  is also Strago's Lore, so a power change reaches the player's copy;
  the AI swap does not.

## 2026-09-16: the driver rules measured on this lab (wt/driver-boost)

Fixture rebaked on the v0.17 ROM (`7924d5a46173`); every number is from a
retained log under `build/m269lab/<driver>_<policy>_s<seed>.log`, 15 seeds
per cell, main's `ot6.lua` composed into the same lab template as the A
side.  Two things changed underneath the 2026-09-07 tables:

- **`control` is now the same fight as `cared`.**  main's regenerated
  `magicite_ifrit_shiva` already ships SABIN alive and topped
  (`[m269lab bake at the save] ... SABIN L17 511/511 hp`), so the "as
  shipped" leg no longer walks in with a dead member; `control`, `cared`,
  `caredkb` and `carednokey` are frame-identical on all 15 seeds
  (`mean frames=3290, 8 deaths, 8 care Fenix, 4 double-kill fights`, both
  drivers).  The 2026-09-07 `control` row (8050 frames, 27 Fenix) is the
  pre-#171-care fixture and stays above as history.
- **The #174 keyed line changes nothing here**: the tactical driver already
  led with Pummel / ThunderBlade (`actor=1 KEYED: Pummel lands 2 chip(s) on
  slot 2's 2 shield(s) -- 0 BP ... unboosted, the pip banks`), so `caredkb`
  and `carednokey` equal `cared` seed for seed.

**`boostfight`, the A/B that decided #174(a)** (fenix = in battle + at
the care stop; every run won, no wipes):

| driver | mean frames | Fenix B+C | double-kill fights | note |
|---|---|---|---|---|
| main (`1d1e9b12`) | 8126 | 10+2 | 6/15 | the gate as shipped |
| branch as pushed (exemption, `a7e12f45`) | 7942 | **27+0** | 6/15 | every later Flare re-killing the 55-HP raise was exempt too: `[death] f+4360 entity 3 char 6 from 55/443 by slot 2 cmd $0C atk $95` then `actor=3 revive entity 2` (s48); two actors raised the same corpse (`[act] f4322 c4 cmd=01 atk=$F0 tgt=0008`, `f4734 c1 ... tgt=0008`) |
| exemption once per attack + one Fenix per corpse + open-action read (`bddd90a1`) | 8127 | 14+6 | 6/15 | better, not main |
| **main's gate + one Fenix per corpse + open-action read (final)** | **7341** | 11+3 | 6/15 | 14 of 15 seeds equal main's Fenix; s12 drew a third Flare (`flares=3` vs main's 2) and main's own #168 top-up rule spent 2 more (`revive entity 2 ... 55 HP alone would not survive the 55 hit, but an ally tops up first`) |

The exemption was measured out: a 55-HP raise never survives the next
Flare either, so raising at all costs two Fenix per Flare and gains no
frames.  main's gate stands; what the branch keeps is the one-Fenix-per-
corpse rule (`raiseQueued`: `actor=1 no raise on entity 2: actor 0's Fenix
Down on them is confirmed (tick 7754) and has not landed`) and the raise
gate's provisional read of the monster action still in flight.

Final per seed, `boostfight` (`f`=frames, fenix=pre/battle/care):

```
seed  main                              final
s0    f13756 fenix 0/2/0 flares=1       f13427 0/2/0 flares=1
s4    f 5032 0/0/0                      f 4152 0/0/0
s8    f 4884 0/0/0                      f 4739 0/0/0
s12   f11256 0/2/0 flares=2             f 9559 0/3/1 flares=3
s16   f 4212 0/0/0                      f 3916 0/0/0
s20   f 5296 0/0/0                      f 4024 0/0/0
s24   f13883 0/0/2 flares=5             f13883 0/0/2 flares=5
s28   f 5672 0/0/0 flares=1             f 4232 0/0/0
s32   f 6364 0/0/0                      f 6220 0/0/0
s36   f14160 0/2/0 flares=4             f 8919 0/2/0 flares=1
s40   f 4100 0/0/0                      f 4100 0/0/0
s44   f 3264 0/0/0                      f 3264 0/0/0
s48   f13412 0/2/0 flares=1             f13412 0/2/0 flares=1
s52   f13103 0/2/0 flares=5             f12767 0/2/0 flares=4
s56   f 3508 0/0/0                      f 3508 0/0/0
```

`breakfirst` on the final driver: `mean frames=3444, Fenix 2+6, 4/15
double-kill fights` (2026-09-07: 3462, 4/15).  The boost audit over every
batch: no death held 3 or more pips (`Boost audit: 34 party death(s), 0
holding >= 3 BP, 0 wipe(s) across 45 logs`); the spend rule fired where a
member stood inside a Flare of death with a pip (`actor=3 SPEND (care):
55/443 is inside one round of death (443) holding 1 BP, and no heal saves
it (item $E8 +50 = 105) -- Fight at 1 BP`).

## Out of scope, noticed on the way

- `magicite_ifrit_shiva` is saved with **SABIN dead and CELES at 6 MP**
  (`gen_ifrit_magicite` has no care after battle 70; the driver's no-raise
  rule held through the win: "smallest hit this fight is 68").  Every
  consumer of that fixture inherits it; `gen_n024_entry` now heals, the
  fixture itself still carries it.
- The "Nothing" resolution: a monster's `attack ..., NOTHING` and a dead
  member's turn both reach `ExecCmd` as command $12 with a stale `$b6`,
  so any observer reading `$b6` there attributes a phantom action (the
  Zozo lab's observers, copied here, would too).  Labelled in
  `lab_map269_random.lua`; `tools/action_trace.py` should be checked for
  the same read.
- Trapper's Program 18 sets **Reflect** on a party member at no damage
  (`$57`); in a long fight CELES's Cure on a reflected ally bounces to the
  enemy.  Not seen to matter once the fight is keyed and short.
- `m269lab_batch.sh` was first launched with an unquoted zsh variable for
  the seed list, which produced one seed-0 run per policy under a
  mis-named log; those duplicates were deleted before the proper spread
  ran (all 80 retained logs are under `build/m269lab/`, plus the three
  pre-label-fix smoke runs under `build/m269lab/smoke/`).

