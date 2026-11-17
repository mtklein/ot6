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
the same page while he carries Sketch. The row is greyed out while the Fake
Mustache is worn, since Relm then has Control in battle and no list.
Locke's row in the same list now reads TresHnt, the name his battle command
shows, and is greyed out while he wears the Thief Glove, since he then has
Capture and no list. The list is back to its original width, so the name of
an equipped Esper beside it is no longer drawn over its border.

Both pages now explain each move. The window at the top of the screen
says what the move under the cursor does, and for a move not learned yet,
where or at what level it is learned.

Bahamut's top Esper rank is now Limit Break: everything that character
deals, from attacks and spells to throws, summons and counters, can do up to
42,069 damage instead of stopping at 9999. Healing still stops at 9999, and
everyone else's damage still stops at 9999. Damage numbers now show five
digits when they need them. Bahamut's old top rank, the Hero Ring's boost to
Fight and magic damage, moves to Ragnarok's top rank, which no longer raises
Vigor by half. It still counts as an Earring.

## Saves

Saves from v0.28 and later load in this release. A save from before v0.44
starts with no esper progress.
