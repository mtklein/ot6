# OT6 v0.25 — Setzer's Kit

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch, a file that
records the differences between the original ROM and the modified ROM.

## How to play

You need a Final Fantasy III (USA) 1.0 ROM (sha1
4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7). Anything else will be rejected.

The easy way: unzip `ot6-v0.25.zip` and put `Final Fantasy III (USA).bps` in
the same folder as your ROM, keeping both names exactly as they are, then
open the ROM. Most emulators — Mesen, bsnes, Snes9x and others — notice a
patch sitting beside a ROM of the same name and apply it as they load. Your
ROM file is not modified.

If your emulator does not do that, apply the patch yourself with any BPS
patcher (Flips, beat) and open the result instead.

On Android, see "OT6 on Android" below: the release's `ot6-v0.25.apk`
patches your ROM for you.

## What's changed

**Setzer has his whole kit.** His Slot command now opens a short list.
Slot is the first entry and spins the reels as before. Coin Toss throws
Gil at every monster, Setzer's level × 30 of it, for twice that in damage
shared among them; the coins count as his special weapon type, so they
chip a shield off every monster weak to cards and dice, and each Boost
Point throws them once more, chipping and paying again. Hired Help pays a sellsword
Setzer's level × 50 Gil for a blow at one monster, dealt with whichever
weapon type that monster is weak to (slashing, piercing or bludgeoning),
so Setzer can break what his own weapon can't; each Boost Point hires one
more blow, paid for and chipping like the first. You see each hire: Setzer
steps aside and a merchant walks in to strike, and each Boost Point brings
someone new, an Imperial soldier, then General Leo, then a fourth: Shadow
himself if he's free to hire, his dog Interceptor if Shadow is fighting in your
party (with nothing left to hit, the dog doesn't appear), or a ghost from the
Phantom Train if Shadow was never recruited or was left behind on the Floating
Continent. Both cost Gil instead of
MP. Once he rejoins in the World of Ruin he also has **Jackpot**: for 99
MP, once a battle, three dice come up matching for a hit that can be
anything from a dud to the maximum, and each Boost Point rolls the dice
once more for another hit. Jackpot chips no shields, but a Broken target
takes it doubled. The rows grey out when you can't pay or Jackpot is
spent. Wearing the Coin Toss relic still swaps Slot for plain GP Rain,
which now chips like Coin Toss and throws once more for each Boost Point.
A throw or a blow that finds no monster left standing costs nothing,
and Jackpot stops rolling once no monster is left. The Narshe
school's skills advisor has two new pages about it.

**Extra hits move on to another monster when theirs falls.** When a
boosted Fight kills its target with swings still to come, the rest now
go to another monster instead of beating the fallen one. The same goes
for Pummel's second blow and for Setzer's extra hires and Jackpot rolls,
so the hits you paid for land on a monster while one is standing.
Without boost, a Genji Glove's second swing still follows the first, as
in the original game.

**The game shows which OT6 it is.** The splash at power-on shows "OT6 v"
and the version number under the FINAL FANTASY III logo, and the Config
screen shows it on the bottom line of its window, on both of its pages, so
you can tell which build a device is running without leaving the game.
Emulators and flash carts that show a game's internal title now show
"OT6" and the version too.

## Saves

Nothing about what a save holds changed in this release: saves from v0.24
load and play in v0.25. The file name the Android app writes, `OT6.sfc`,
never changes, so an emulator keeps finding the same save file.

## A warning about Sketch

Relm's Sketch still carries Final Fantasy VI 1.0's most famous bug,
deliberately left in place. When a Sketch misses, the game can rarely corrupt
your inventory or save. **Save before experimenting with Sketch.** The world
map saves anywhere.
