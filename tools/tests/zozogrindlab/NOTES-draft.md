# The Zozo grind -- the Iron Fist that casts Stone (#195)

Authored 2026-09-16 from `tools/tests/zozogrindlab.py` (the lab), the
v0.17 tree's `build/states/zozo_arrival.log` (2026-09-16 14:15, copied to
`build/lab/zozo-grind/baseline-coordinating-tree.log`) and a 6-seed
baseline sweep of `zozo_arrival` in this tree.  Every number below is
quoted from a retained log under `build/lab/zozo-grind/` (the lab keeps
every attempt; `python3 tools/tests/zozogrindlab.py aggregate` prints
them all).

## What happened in the qualification

`zozo_arrival` (gen_zozo2_arrival) in the v0.17 tree passed on its first
attempt (`PASS (frame 198707) attempts=1/3`) and spent six deaths and five
Fenix Downs doing it, all in randoms (`audit_fenix.py`: "RANDOM  Fenix in
randoms -- underleveled or lab these encounters").  Four of the six are the
same attack from the same seat:

    [worldNavTo] [death] f+1025 entity 3 char 5 from 407/407 by slot 2 cmd $0C atk $9F (ONE ACTION from >= 80%) bp=0 party_bp=0,2,2,0
    [worldNavTo] [death] f+2596 entity 2 char 4 from 156/354 by slot 2 cmd $0C atk $9F bp=3 party_bp=1,3,3,1 -- died holding 3 BP
    [worldNavTo] [death] f+1315 entity 2 char 4 from 235/354 by slot 2 cmd $0C atk $9F bp=0 party_bp=0,2,0,2
    [worldNavTo] [death] f+1570 entity 1 char 6 from 295/443 by slot 2 cmd $0C atk $9F bp=0 party_bp=0,0,0,0
    [worldNavTo] [death] f+2050 entity 0 char 1 from 42/447 by nobody (no monster action attributed) bp=0 party_bp=0,2,0,0
    [worldNavTo] [death] f+3644 entity 3 char 5 from 37/511 by nobody (no monster action attributed) bp=2 party_bp=1,4,2,2

and every one of the six fights read the same stage at f+1:

    monhp=s0:412/sh3,s2:333/sh2 monsters=2

## The row, decoded

World battle group 10 (the x=34 column and 158 of the crossing's 177
tiles; `rand_battle_group.dat[10*8..]`, decoded by
`build/lab/zozo-grind/decode.py`):

| roll | formation | bodies |
|---|---|---|
| 31.25% | $064 | slot 0 Vulture ($02A), slot 2 **Iron Fist** ($06C) |
| 31.25% | $065 | Mind Candy ($08C) x4 |
| 37.5% | $060 | Iron Fist x2 (slots 0, 1), Mind Candy x2 (slots 2, 3) |

| | value | source |
|---|---|---|
| Vulture $02A | L15, HP 412, speed 30, atk 13, def 100, mdef 155, mpow 10; 3 shields | `monster_prop.dat` +$0540 |
| **Iron Fist $06C** | **L15**, HP 333, speed 35, atk 13, def 75, mdef 145, mpow 10; absorbs poison ($08); 2 shields, PIERCE\|BLUDG | `monster_prop.dat` +$0D80, `Ot6ShieldTbl` |
| Mind Candy $08C | L15, HP 290, speed 30, atk 14, def 105, mdef 165, mpow 10 | `monster_prop.dat` +$1180 |
| Iron Fist AI | `if_num_monsters 1: attack BATTLE, STONE, STONE` / else `BATTLE, BATTLE, NOTHING` -- `wait` -- `BATTLE, BATTLE, SPECIAL` | `ai_script.asm:855-865` |
| Vulture AI | `if_num_monsters 1: attack SPECIAL, SHIMSHAM, SHIMSHAM` / else Battle/Shimsham/Battle | `ai_script.asm:841-851` |
| Mind Candy AI | Battle/Battle/Nothing -- wait -- Battle/Battle/Special; no solo branch | `ai_script.asm:869-874` |
| **Stone $9F** | `cmd $0C` (the lore command), power 40, hit 75, targeting $63, no element, **status2 $20 = Muddle**, special effect $22 | `magic_prop_en.dat` $9F: `63 00 00 26 00 16 28 02 4b 22 00 20 00 00`; `const.inc:756` |
| effect $22 | `lda $3b18,x / cmp $3b18,y / bne / lda #$0d / adc $bc / sta $bc`: when the caster's level byte equals the target's, add 13 + carry = **14** to the damage multiplier | `battle_main.asm` `TargetEffect_22` (@3922) |
| the multiplier | `ApplyDmgMult`: `+A *= (1 + ($bc / 2))`, so 14 is **x8** | `battle_main.asm` @370b |
| Shimsham $E7 | power 8, targeting $43 | `magic_prop_en.dat` $E7 |

So `slot 2 cmd $0C atk $9F` is the Iron Fist of formation $064 casting
Stone, and it casts Stone only when it is **the last body on the stage**:
the Vulture in slot 0 carries three shields to the Iron Fist's two, the
fight driver's target order takes slot 0 first, and the Iron Fist is left
alone with a two-in-three Stone line.  Stone is a ~one-third-HP hit with
Muddle on it for anyone, and an **x8 one-shot for a L15 member** -- the
Iron Fist is L15, and the grind walks every member through L15.

FILL: measured Stone rolls (raw word at `_writedamage`) non-parity and
parity, by target level, from the lab's [hit] lines.

FILL: the level curve over the grind (the baseline roster lines) and who
is at L15 when.

## The deaths, read against the driver's plan lines

FILL

## The lab

FILL

## Finding and recommendation

FILL

## What landed

FILL

## Out of scope, noticed on the way

FILL
