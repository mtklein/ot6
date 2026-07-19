# OT6 v0.2

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch, a file that
records the differences between the original ROM and the modified ROM.

## How to play

Apply ot6-v0.2.bps to a Final Fantasy III (USA) 1.0 ROM (sha1
4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7) using any BPS patcher (Flips,
beat). The patcher will reject any other ROM.

Play through Vargas at the top of Mt. Kolts, then stop. That is roughly
an hour and fifteen minutes.

Past the stop point the new systems run but are not balanced yet.

## What's changed

- **The playable stretch now runs to Vargas.** v0.1 stopped at the
  Moogle defense in the Narshe mines; the escape, the world map, Figaro
  Castle, South Figaro and Mt. Kolts are now tuned territory.
- **The Narshe school teaches OT6.** Eight advisors in the Beginner's
  House cover shields and Breaking, Boost Points and why greed loses,
  spell folding, and the icons on the battle HUD. The monster in the
  chest is a practice fight now.
- **Vargas fights under the new rules.** Five shields, weak to
  bludgeoning, and — through Sabin's AuraBolt — holy. His bear escorts
  gate the fight: Edgar's Bio Blaster cannot reach him until they fall.
  He still dies to the scripted Pummel, as he should; Breaking him buys
  you the calm to land it.
- **Edgar's Tools are worth buying.** The Figaro shop sells the Bio
  Blaster, and poison is a real key for the first time.
- **Fixed: opening the Tools window in battle could hard-lock the
  game** on any tool without a weapon class — including the Bio Blaster
  itself.
- **Fixed: a scratch buffer sat inside live vanilla RAM** and corrupted
  the battle HUD whenever a command list was drawn.
- Cyan's Bushido is rebuilt on Boost Points — the charge gauge is gone,
  and BP picks the tech. He is not recruitable this early, so you will
  not see it yet; it ships for the next stretch.

## What we'd like to know

- Do Breaks ever matter to you? We think enemies still die at almost
  exactly the moment their shields empty, so the Broken window — the
  payoff the whole system is built around — may never actually happen
  in an ordinary fight.
- Does the difficulty curve land? Early encounters can be mashed
  through; Mt. Kolts is meant to require Boosting and weaknesses. If
  you had to stop and grind, we want to hear where.
- Anything cosmetic that looks wrong. Known already: the Boost pips
  sometimes render as numbers, and a weakness icon reveals as the
  action starts rather than when the damage lands.
