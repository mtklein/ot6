# OT6 v0.22 — Into the Ruin

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch, a file that
records the differences between the original ROM and the modified ROM.

## How to play

You need a Final Fantasy III (USA) 1.0 ROM (sha1
4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7). Anything else will be rejected.

The easy way: unzip `ot6-v0.22.zip` and put `Final Fantasy III (USA).bps` in
the same folder as your ROM, keeping both names exactly as they are, then
open the ROM. Most emulators — Mesen, bsnes, Snes9x and others — notice a
patch sitting beside a ROM of the same name and apply it as they load. Your
ROM file is not modified.

If your emulator does not do that, apply the patch yourself with any BPS
patcher (Flips, beat) and open the result instead.

## What's changed

**The World of Ruin from the Solitary Island to Tzen has designed break
weaknesses.** The monsters Celes meets there used to carry generic ones and
four or five shields, so a break often landed on a monster that was
already dying, and some fights gave her sword no way in. Now each one is
designed around what Celes carries. The island's tiny pests fall with one shield,
and the Black Drgn on the sand opens to a blade. The plains monsters carry
two or three shields and reward reading the element: half of them are weak
to ice, the Gilomantis to fire (its counter punishes a plain Fight), and a
plain sword hit can't remove the plated Chitonid's shields: break them with
lightning (a ThunderBlade, sold in Albrook and Tzen, or Maduin's Bolt) or, once he joins,
Sabin's punches. In Tzen's collapsing house every monster breaks to her sword,
including the Scorpions that used to leave her no answer.

**Gogo's Mimic never costs MP, boosted or not.** A boosted Mimic of a
two-spell X-Magic turn used to charge Gogo MP for the second spell. Now
every Mimic is free, and a boost on it buys what it would buy on the
copied action: a copied Fire, Ice, Bolt or other spell with stronger
versions casts the stronger one (Fire 2 for one boost, Fire 3 for two or
more), where before the boost was spent on a plain Fire.

**The Beginner's House in Narshe now explains OT6 in plain words.** Its
advisors used to speak in riddles. Now each one says what a new rule is,
what you will see on screen and which button to press: shields and
breaking, weaknesses, Boost Points and what a boost buys, stronger
spells, the skills that now cost MP, and Espers, whose spells last only
while they are equipped (the old advice about learning spells from Espers
didn't apply to OT6 and is gone).

## A warning about Sketch

Relm's Sketch still carries Final Fantasy VI 1.0's most famous bug,
deliberately left in place. When a Sketch misses, the game can rarely corrupt
your inventory or save. **Save before experimenting with Sketch.** The world
map saves anywhere.
