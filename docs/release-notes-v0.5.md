# OT6 v0.5

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch containing only the
differences from the original game.

## How to play

Apply `ot6-v0.5.bps` to a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7` using a BPS patcher such as
Flips or beat. The patcher will reject any other ROM.

Play from the beginning through the complete Opera sequence. The supported
v0.5 stop point is reached after Ultros is defeated, Setzer joins, and the
Blackjack is acquired. Vector and the rest of the World of Balance are
planned for v0.6.

## What's changed since v0.4.1

- The playable frontier now includes Jidoor and the complete Opera sequence.
- Ability MP costs are live. Blitz, Tools, Bushido, and Steal participate in
  the resource economy; their menus show costs and unavailable choices are
  greyed and refused consistently.
- Cyan's Bushido command is a direct submenu with technique names and MP
  costs. Its four BP slots can be configured per save under
  **Skills → SwdTech**, with an Auto option for players who prefer the
  default progression.
- Every enemy without a hand-authored break row now receives a generated
  physical-class weakness, closing the long tail of otherwise-unbreakable
  encounters.
- Fixed-party break coverage and the Narshe school explanation were revised
  so the party always has a plausible seam to exploit without implying that
  every enemy has one uniquely correct answer.
- The route-fixture and automated-test tooling received substantial
  reliability and speed improvements.

## What we'd like to know

- Do MP costs create useful decisions over a dungeon without producing an
  Ether grind? Are cost labels, grey states, and refusal feedback clear?
- Is Cyan's four-slot Bushido setup discoverable and understandable? Does the
  Auto option provide a good default, including on a save upgraded from
  v0.4/v0.4.1?
- Does the Opera route complete cleanly, especially the aria, flower dance,
  rafter chase, Ultros fight, and transition to the Blackjack?
- Does Ultros survive long enough for the break loop to matter, and is his
  six-shield slash/pierce row fair for the party you brought?
- Did you see any menu, font, cursor, HUD, save/load, or cutscene regression?

See `docs/playtest-v0.5.md` for the focused playtest checklist.
