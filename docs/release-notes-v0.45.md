# OT6 v0.45

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.45.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

## Changes

The Narshe school's magicite ghost now explains how Espers work: an equipped
Esper lends its spells and its summon but never teaches them, and members
still standing at a victory earn Magic Points with it and rank up at 10, 30,
75, 200 and 500, keeping each rank's bonus for good.

On an Esper's page under Skills, move the cursor right onto the ranks to see
what each one does in the window at the top. A rank you haven't reached whose
effect the character already has from another rank says "Already held".
Shoat's top rank is now named "NoDeath/Doom", since it blocks Condemned as
well as instant death.

On Strago's Lore list, the R Button no longer adds Boost Points to a Lore
that a boost can't improve: Condemned, Roulette, Big Guard and the other
Lores with no damage or healing number, and Revenge, Blow Fish, Pearl Wind,
Step Mine and Exploder, whose number is set by something else. Boosting
those used to spend the points for nothing. The same goes for Sabin's Mantra
on the Blitz list: it heals with Sabin's HP shared among the party whatever
the boost, so it no longer takes one, and a boost raised before picking it
is kept rather than spent.

When Gau and Gogo both use Rage in the same battle, each now keeps the odds
his own Boost Points bought. Before, whoever started raging last set the odds
for both.

The last World of Balance monsters with generic shields now have designed
ones. On the Lete River raft, each weapon breaks two of the three monsters,
and Terra's Fire breaks all of them. The three ghosts in the sparkle trap in
Narshe's caves each give way to a different weapon, and all three to Fire.
The Phantom Train's Over-Mind breaks like the train's other ghosts. In the
Battle for Narshe, Bounty Man and Fidor break to the same weapons as the
troopers they march with, and the Sp Forces in the banquet's optional
sparring bout have shields of their own. Siegfried has a single shield, which
any weapon blow breaks. Terra's Magitek flashback and the scenes that play
inside a battle no longer show a shield gauge.

A new game no longer gives Gau an empty Rage list and Strago an empty Lore
list on emulators and consoles whose memory does not start out blank. Their
loadouts now start on AUTO, as they always did elsewhere. A game already
started that way is corrected the first time you save it in this release.
The one exception: if Gau already knows the Io rage, his Rage loadout may
still need setting back to AUTO on its page in the Skills menu.

## Saves

Saves from v0.28 and later load in this release. A save from before v0.44
starts with no esper progress.

The included saves were replayed on this version, so party levels and gear
differ slightly from v0.44's.

The zip has a `saves` folder: saves at points through the story, from
Narshe to the World of Ruin. Each save is in slot 3. `saves/README.txt` says
how to use one.
