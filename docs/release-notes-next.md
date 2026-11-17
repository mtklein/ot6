# Next release

Add each player-visible change as one short paragraph. Describe the change
and its effect. Cite evidence in the commit message.

## What's changed

A boosted spell now casts the tier its list showed. At the target choice, L
and R spread a spell like Fire or Cure over a group, and they also moved the
boost: picking Fire 3 with two points and spreading it with L cast Fire 2 for
one point while the list still said Fire 3, and spreading with R raised it
without showing the new name or price. Now a spell or skill picked from its
list keeps the boost the list showed; L and R there only spread it. In a list,
R also no longer adds a point the character's MP cannot pay for, so a row is
never left greyed by a boost; before, the point was taken and the row could
not be cast until it was taken back.

Locke's Bestow is greyed and refused when no ally can take a point, as when
he fights alone, boosted or not; before, it was usable whenever he held a
point and spent his turn and its MP on nothing. Relm's Portrait and Gesture
are greyed the same way when no ally can take them.

Relm's skills now have a page in the field menu, like Locke's. Skills >
Painter lists her eight rows in the order her battle list uses, with their
MP prices, and marks the ones she has not learned yet as locked. Gogo sees
the same page while he carries Sketch. On both pages the window at the top
says what the move under the cursor does, or where or at what level it is
learned. Locke's row in the Skills list now reads TresHnt, the name his
battle command shows. His row is greyed out while he wears the Thief Glove,
and Relm's while she wears the Fake Mustache, since they then have Capture
and Control in battle and no list. The list is back to its original width,
so the name of an equipped Esper beside it is no longer drawn over its
border.

Bahamut's top Esper rank is now Limit Break: everything that character
deals, from attacks and spells to throws, summons and counters, can do up to
42,069 damage instead of stopping at 9999. Healing and everyone else's
damage still stop at 9999. Damage numbers now show five digits when they
need them. Ragnarok's top rank no longer raises Vigor by half; it now gives
the boost to Fight and magic damage that Bahamut's top rank gave, and it
still counts as an Earring.

An Imp has joined Setzer's Hired Help: the third hire now walks in as an
Imp with a halberd.

## Saves

Saves from v0.28 and later load in this release. A save from before v0.44
starts with no esper progress.
