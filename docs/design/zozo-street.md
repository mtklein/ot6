# The Zozo street — the SlamDancer that one-shots (#155)

Authored 2026-09-07 from `tools/tests/lab_zozo_street.lua` (the lab; its
header carries the decoded rows) and the v0.16 qualification log
`build/states/dadaluma_entry.log`.  Every number below is quoted from a
retained run log under `build/zozolab/` (the batch runner keeps every
attempt; `tools/tests/zozolab_aggregate.py` prints them all).

## What happened in the qualification

Map 225 (the crane-maze interiors), the stair-room landing (59,34), three
steps in:

    [followPath (52,30)] battle f+300 ... partyhp=353,349,0,407 roundcost=0,0,371,0 monhp=s0:392/sh2 monsters=1
    [care before the stair climb] plan: revive char 4 with $F0 (0/398 hp, status1 80)

EDGAR, L15, **back row** (`[zozo rows] c1=front c4=back c5=back c6=back`),
371/398 HP after the 0.9-threshold care stop, was dead before anyone in
the party had executed a command.  The monster read 392/392 with two
shields at full: **SlamDancer ($052)**, formation **$069 (SlamDancer x1)**,
one of map 225's four rolls (`tools/audit_encounters.py 225`: $069 31.25%,
$06b Harvester x1 31.25%, $06c Harvester x2 + SlamDancer 31.25%, $06a
SlamDancer + Gabbldegak x3 6.25%).

## The row, decoded

| | value | source |
|---|---|---|
| SlamDancer $052 | L15, HP 392, MP 120, speed 35, atk 13, def 115, mdef 145, **mpow 10** | `monster_prop.dat` +$0A40; byte-identical to the vanilla ROM record |
| weakness | poison ($08) only; no absorb/null | `monster_prop.dat` +25 |
| shields | **2, no class key** | `Ot6ShieldTbl`, `ot6_hud.asm:1671` (first match wins, `ot6_break.asm:74-83`) |
| AI | `if_one_monster_type` -> `attack FIRE_2, ICE_2, BOLT_2`; else two Battle lines | `ai_script.asm:925` |
| Fire 2 / Ice 2 / Bolt 2 | power 60 / 62 / 61, magic, targeting $61 | `magic_prop_en.dat` |

So the solo formation casts a tier-2 elemental **every turn** and never
swings.  The 371 was not a critical, not a row matter (magic ignores row),
not a special attack, and not a boosted enemy turn (monsters bank no BP,
`ot6_boost.asm:156`).  It was a single-target Fire 2 / Ice 2 / Bolt 2 with
the damage clamped to EDGAR's remaining HP — the log's number is his HP,
not the roll.

## The lab

Fixture `build/states/zozolab_pre.mss`: the stair-room landing (59,34),
captured by a copy of `gen_zozo4_dadaluma.lua` with a `saveState` after
`climbCare("after P11a")`, so the party arrives exactly as the route
delivers it (LOCKE L14 339/353, CELES L14 349/349, EDGAR L15 380/398,
SABIN L15 380/407, 65 Tonics, 13 Fenix Downs; `build/zozolab/bake.log`).

From that snapshot the next random is fixed: `CheckBattleSub`
(`field/battle.asm`) draws the encounter from `RNGTbl[$1fa1]` once per
step and the formation slot from `RNGTbl[$1fa2]` once per battle, both
counters saved in the snapshot, so the first step off the tile always
rolls **$069** — the formation under study.  Idling before the step varies
only the battle seed (`$021e*4` at `InitBattle`), in 4-frame quanta, so
the declared spread is **15 seeds (0..56 step 4), the whole 60-phase
cycle**.  `control`, `breakfirst` and `runic` share the exact pre-battle
state per seed (a paired A/B); the two row policies spend a menu drive
first and draw their own 15.

Policies (none reads hidden state; the poison key is the Bio Blaster the
route already carries, Runic is CELES's own command):

- **control** — `gen_zozo4_dadaluma`'s `encounters()` driver as it ships
  (tactical, boost, bank 3, items, healer CELES at 60%, Bio Blaster).
- **allback** — LOCKE joins the other three in the back row.
- **allfront** — everyone front (the contrast).
- **breakfirst** — bank 0: BP spent as it comes, so EDGAR's first Bio
  Blaster and everyone's first Fight go out boosted.
- **runic** — CELES answers every command menu with Runic (which opens a
  target window in this ROM, state $38); LOCKE is the item medic.

### Results, 15 SlamDancer-solo fights per policy

`python3 tools/tests/zozolab_aggregate.py` (deaths = members dead when the
fight ended; fenixB/fenixC = Fenix Downs spent in battle / at the care stop
after it; frames = mean battle length):

```
policy        n formations                   seeds deaths fenixB fenixC wipes  frames  maxhit
allback      15 SlamDancer:15                   15      2      2      2     0    1969     380
allfront     15 SlamDancer:15                   15      2      2      2     0    1946     380
breakfirst   15 SlamDancer:15                   15      6      2      6     0    1521     380
control      15 SlamDancer:15                   15      4      3      4     0    2173     380
runic        15 SlamDancer:15                   15      8      2      8     0    2214     380
```

Per cast (`build/zozolab/caststats.py` over the `[hit]` lines):

```
control    casts=16 single=5 all=11 nocast_runs=2 first_cast_f+=[414..1297] party_acts_before_first=[0,0,0,0,0,0,1,1,1,2,2,2,3]
breakfirst casts=10 single=8 all=2  nocast_runs=5 first_cast_f+=[414..986]
runic      casts=17 single=8 all=9  nocast_runs=2
allback    casts=8  single=3 all=5  nocast_runs=9   (allfront: identical damage ranges)
all-target damage per member: 207..263 (LOCKE 233..263, CELES 207..239, EDGAR 228..255, SABIN 223..246)
single-target: every one a kill at any HP the party can have here (380 EDGAR, 339 LOCKE, 349 CELES, 380 SABIN -- the clamp)
```

What the numbers say:

1. **Rows are irrelevant.** `allback` and `allfront` drew the same casts
   with the same damage; the spells are magic.  The route already has
   three of four in the back row; leave LOCKE in front for Dadaluma.
2. **The SlamDancer moves first.** Its first cast lands at battle
   f+386..660 in most seeds, before *any* party command has executed
   (`acts_before_first` is 0 in 6 of 13 control fights).  "Kill it before
   it acts" is a seed lottery: 2/15 for control, 5/15 for `breakfirst`.
3. **A single-target cast is a death, full stop.** All-target casts split
   to ~207..263 per member; the single-target roll is roughly twice that,
   above every member's maximum HP (353/349/398/407).  No gear in the bag
   changes that (the unused pieces are a RegalCutlass, hats, a Buckler,
   Jewel Rings), and healing cannot pre-empt it.
4. **Runic is not a shield here.** The command is queued at selection but
   executes behind the other queued actions (s16: selected ~f+200,
   executed f+1228; the Fire 2 landed at f+605), and the stance is gone
   by the next cast.  With CELES off the Cure line it did worse than
   control (8 deaths vs 4).  A driver that could Runic would still need
   to time it, which the queue does not allow.
5. **`breakfirst` is the fastest kill** (mean 1521 frames, 5 no-cast
   wins) but drew more single-target casts in this spread (8 of 10) and
   ended with more deaths (6).  Whether that is the policy or the seeds
   is not separable at n=15; it is not a fix.

## The whole street (arrival -> Dadaluma's door), once per policy

`python3 tools/tests/zozolab_street.py run` derives one variant of the
generator per policy (artifacts redirected to `build/zozolab/street/`, the
tree's `dadaluma_entry` untouched):

STREET_TABLE

## Finding and recommendation

This is a **balance finding**, not a gear, row or driver problem.  The
solo SlamDancer's tier-2 line is vanilla data (every stat byte matches the
vanilla ROM) meeting a party the level curve places at L14-15 (vanilla
reaches Zozo around L20: `level-curve.md`).  At mpow 10 / L15 the
single-target roll exceeds every member's max HP; the party would need
roughly **L17-18** (EDGAR 502 HP at L17, ~560 at L18 on the chain's own
curve) for the low roll to be survivable, i.e. the row is hot by about
three levels, or ~25-35% in damage.

Options, cheapest first (the owner's call; none is applied here):

- **Retune the solo branch**: `attack FIRE, ICE, BOLT` (tier 1, power
  21/22/20) in the `if_one_monster_type` block keeps the elemental read
  and lands ~150-180 single / ~80 all — a hit, not a KO — at these levels.
  The other three Zozo bodies (Harvester, HadesGigas, Gabbldegak) swing
  physicals and are not in this finding.
- **Or lower mpow** on $052 (10 -> 6 puts the single roll near 300) if
  the tier-2 names are wanted for the reveal.
- **Or accept it as the level gate** and route a grind before the climb
  (`gen_zozo2_arrival` already grinds to "Zozo's level tier"; three more
  levels there).  The care threshold does not help: the qualification's
  EDGAR was at 93% and a topped 398 dies to the same roll.

Until one of those lands, a Fenix Down per solo SlamDancer that draws a
single-target cast (about a third of its casts, `single=5 of 16` in
control) is the expected cost of this street, and `audit_fenix.py` will
keep flagging it.

## Out of scope, noticed on the way

- `Ot6ShieldTbl` carries the four Zozo species **twice**
  (`ot6_hud.asm:1671-1678` with no class, `:1849-1860` with
  SLASH|PIERCE / BLUDG / PIERCE).  `Ot6SeedShields` takes the first match,
  so the second block is dead; `tools/check_boss_rows.py`'s parser keeps
  the *last* row per species, so it reads the dead block.  Either delete
  the second block or, if class keys were intended, delete the first.
- Runic opens a target window in this ROM (`state $38` after the confirm),
  so `newFightDriver` will need a target step if it ever gains a Runic
  line (the lab's steer is in `lab_zozo_street.lua`).
- The generator's care threshold (0.9) leaves EDGAR at 380/398 on the
  fixture; irrelevant to this finding but worth knowing for any HP-margin
  argument.
