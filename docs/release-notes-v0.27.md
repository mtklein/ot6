# OT6 v0.27

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch and an
Android patcher.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.27.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

On Android, install `ot6-v0.27.apk` and select the folder containing the ROM.

## Changes

**Break takes shields.** Break no longer petrifies. It removes one shield
from its target, whatever the target's weaknesses, plus one more for each
Boost Point spent (four at 3 points). It does no damage and costs 25 MP at
any boost. Terra learns it at level 24, Shoat grants it, and the Break
Blade sometimes casts it (one shield). A monster's Break still petrifies,
and so does Break through Control, Sketch or a Rage.

**Strongest skills need all 3 Boost Points.** Terra's Trance, Celes's
RunicBlade, Edgar's Overclock, Cyan's Cleave, Setzer's Jackpot and
Shadow's assassination each need a full 3-point boost, and can be used
again in the same battle. Cyan's Cleave is the 3-point SwdTech and no longer needs a Broken
target; against a boss it is a heavy cut instead of instant death. A
confused Cyan no longer picks Cleave. Shadow's hit kills a monster (not
a boss) it breaks, or one already broken, only on a 3-point action.
Setzer's Jackpot needs 3 points, rolls the dice twice (fewer rolls than a
3-point Jackpot before), and costs 99 MP.

**Terra's Trance.** Morph needs 3 Boost Points. With fewer, the command
buzzes and nothing is spent.

**Ultima for Terra.** After Terra rejoins in the World of Ruin, Fire cast
with 3 Boost Points becomes Ultima, for 80 MP.

**Celes's RunicBlade.** After the Magitek factory, a Runic raised with 3
Boost Points also sends each spell it absorbs back at whoever cast it,
except spells cast as counterattacks.

**Edgar's Overclock.** After the Magitek factory, a Tool used with 3 Boost
Points fires twice and costs 99 MP.

**Edgar's tools.** Debilitator now shows the weakness it adds, on the
monster it hit only. Flash is sold by Figaro's tool merchant and in South
Figaro; Debilitator is sold in Vector's weapon shop after the banquet.

**Phunbaba's weak points changed.** In Mobliz, blunt and Special attacks hit his
weak points in every fight the party joins, and Terra's sword does too in
the last one. Terra's solo fight shows no shields.

**World of Ruin Espers change stats.** The twelve Espers found in the
World of Ruin now change their holder's stats while equipped, as the
World of Balance Espers already do; the Esper's page in the menu shows
the change. Palidor gives +2 Vigor and +4 Speed. Fenrir gives +6 Speed
and +4 Mag.Pwr, and -3 Stamina.

## Saves

This release uses the v0.26 save layout. OT6 Patcher keeps the output name
`OT6.sfc`, so the emulator can keep using its save file.

## Sketch warning

The original FF6 1.0 Sketch bug remains. A missed Sketch can corrupt inventory
or save data. Save before using Sketch.
