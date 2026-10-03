# OT6 v0.24 — The Falcon

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch, a file that
records the differences between the original ROM and the modified ROM.

## How to play

You need a Final Fantasy III (USA) 1.0 ROM (sha1
4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7). Anything else will be rejected.

The easy way: unzip `ot6-v0.24.zip` and put `Final Fantasy III (USA).bps` in
the same folder as your ROM, keeping both names exactly as they are, then
open the ROM. Most emulators — Mesen, bsnes, Snes9x and others — notice a
patch sitting beside a ROM of the same name and apply it as they load. Your
ROM file is not modified.

If your emulator does not do that, apply the patch yourself with any BPS
patcher (Flips, beat) and open the result instead.

On Android, see "OT6 on Android" below: the release's `ot6-v0.24.apk`
patches your ROM for you.

## What's changed

**The World of Ruin from Figaro Castle to the Falcon has designed break
weaknesses.** The monsters around Kohlingen and in Darill's Tomb used to
carry generic weaknesses and five shields, so a break could take most of
a fight to land. Now most have two to four shields and a weakness the
party holds: Edgar's crossbow chips Deep Eyes and Exorays, Sabin's
Pummel and Suplex suit the Osteosaur's bones, and the Bogy, a ghost with
no weakness of its own, answers to Setzer's cards. Setzer's cards, Trump and dice also key
the tomb's undead and its demon (the Orog, the Osteosaur, the PowerDemon)
and Dullahan himself; the tomb's plants still want blades, points and
fire. Dullahan has ten shields, open to spears, darts, the crossbow,
Sabin's Pummel and Suplex, fire and Setzer's cards, and Setzer is the one
who breaks him most often. In the tomb's monster chest the shell has no
shields and takes full damage from the start, and felling either the
shell or the head ends the fight.

**A boosted action that never happens keeps its boost points.** When a
character is knocked out or put to sleep after choosing a boosted action
but before it goes off, the action is lost, as in the original game, and
the points stay in the bank: a Slot spin that never turns costs Setzer
nothing.

**OT6 on Android, kept up to date for you.** Each release now carries
`ot6-v0.24.apk`, OT6 Patcher: a small app for Android handhelds. Open it
once and choose the folder that holds your own Final Fantasy III (USA) 1.0
ROM; it finds the ROM there and writes `OT6.sfc` beside it, leaving your
ROM untouched, so the original game and OT6 sit side by side. Subscribe to
this project in Obtainium (filter `ot6-.*\.apk`) and each new release
arrives as an app update carrying the new patch: the app writes the new
`OT6.sfc` as the update installs, and opening it shows what it last wrote
(or why it couldn't). The file name never changes, so your emulator keeps
using the same save file; see Saves below. The app has no notifications and asks for no permissions.

## Saves

Nothing about what a save holds changed in this release: saves from v0.23
load and play in v0.24. The file name the Android app writes, `OT6.sfc`,
never changes, so an emulator keeps finding the same save file.

## A warning about Sketch

Relm's Sketch still carries Final Fantasy VI 1.0's most famous bug,
deliberately left in place. When a Sketch misses, the game can rarely corrupt
your inventory or save. **Save before experimenting with Sketch.** The world
map saves anywhere.
