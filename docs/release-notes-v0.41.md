# OT6 v0.41

OT6 is a Final Fantasy VI ROM hack. This release contains a BPS patch.

## How to play

Use a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7`.

Unzip `ot6-v0.41.zip`. Put `Final Fantasy III (USA).bps` beside the ROM and
open the ROM. Mesen, bsnes, Snes9x, and other compatible emulators apply the
patch without changing the ROM. Otherwise, apply the patch with a BPS patcher
such as Flips or beat.

## Changes

- Into Owzer's house in the World of Ruin, the party is now four: Sabin joins Terra, Celes and Cyan, and Relm
  waits on the Falcon after she joins until the cabin seats her before the Fanatics' Tower. The basement's
  SoulDancers and Chadarnook went from occasional losses to rare ones, and Chadarnook ends faster. The Ribbon Mog
  leaves behind goes on Cyan for the house.
- At the end of the Phoenix Cave, the Ribbons come off the members the scene leaves behind, so the cave's Ribbon
  is worn in the next arc instead of riding the Falcon on Strago.
- Strago's Pearl Wind now heals each member as much as Strago's maximum HP, not his current HP, so it is just as
  strong when he is hurt. The same goes for Gau's Rage and Gogo's Mimic of it; monsters that cast Pearl Wind still
  heal by their current HP, as before. Since Pearl Wind ignores Reflect, it makes a good party heal for a group
  wearing Wall Rings, such as the one that faces the Poltergeist in Kefka's Tower. Strago can learn it from the
  Sprinters in the wood just west of the plain north-west of Jidoor.
- Sabin's Bum Rush now needs three boost points: with fewer it is greyed out in the Blitz list. With three it lands
  four blows, each as strong as a fully boosted attack, and each blow that lands removes one of the enemy's shields,
  whatever the enemy is weak to. A confused or charmed Sabin, and the Colosseum, never pick it. When Gogo mimics
  it with fewer than three boost points it comes out as a Pummel instead.
- Cyan's Cleave now kills every enemy it can kill outright, not just the first one it strikes, and each one it
  cannot, such as a boss, loses four shields and takes its full cut. Gogo's Mimic of Cleave does the same.
- A battle no longer freezes when a monster's spell bounces off a party member's Reflect after every monster has
  fallen, as when the last L.30 Magic in the Fanatics' Tower dies to Poison with its counterattack still coming. The
  spell now bounces off and lands nowhere, and the battle ends in victory. The original game freezes the same way.
- The included saves for Kefka's Tower were played again. The group of Terra, Relm, Edgar and Setzer now gains its
  levels near where it lands in the tower, rather than in the long hall below the Goddess, where the Scullions'
  Condemned kept costing it members. The party enters the tower with 35 Fenix Downs instead of 40.

## Saves

This release uses the v0.29 save layout.

The zip has a `saves` folder: saves at points through the story, from
Narshe to the World of Ruin. Each save is in slot 3. `saves/README.txt` says
how to use one.
