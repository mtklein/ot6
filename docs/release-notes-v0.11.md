# OT6 v0.11 — Magicite between fights

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch, a file that
records the differences between the original ROM and the modified ROM.

## How to play

You need a Final Fantasy III (USA) 1.0 ROM (sha1
4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7). Anything else will be rejected.

The easy way: unzip `ot6-v0.11.zip` and put `Final Fantasy III (USA).bps` in
the same folder as your ROM, keeping both names exactly as they are, then
open the ROM. Most emulators — Mesen, bsnes, Snes9x and others — notice a
patch sitting beside a ROM of the same name and apply it as they load. Your
ROM file is not modified.

If your emulator does not do that, apply the patch yourself with any BPS
patcher (Flips, beat) and open the result instead.

Play from the beginning through the end of the Magitek Research Facility and
Terra's return, then stop. This is a small release: it does not extend that
range, it improves things inside it.

Past the stop point the new systems may run but are not part of this
release's supported, balanced playtest range.

## What's changed

**Your equipped magicite now heals you between fights, not only in battle.**
The design has always been "equip a magicite, get its kit while you wear it."
That held in combat but not in the field menu: a character wearing a healing
esper could cast Cure in a fight and then had no Magic row at all when you
opened the menu to heal on the walk, so you drank a Tonic standing next to a
full MP pool. The field Magic list now shows an equipped esper's granted
spells too, and they are castable, so you can cure status and top off HP
between encounters with the magicite you are carrying. Unequipping removes the
granted spells again and never teaches them for good.

**A hang on a Zozo ladder is fixed.** The north bridge shaft in Zozo is a
vertical loop whose diagonal tiles change which floor you are on while a step
is still resolving. A random battle rolled at the wrong moment on that ladder
could stall with the fight never starting and control never coming back.
Encounters are now held off on that one stretch, so the ladder is safe to
climb.

**The opera's rafter chase can be broken.** The timed chase across the opera
rafters throws packs of sewer rats and vermin at Locke, Edgar and Sabin. Each
rat used to carry four shields — twenty chips to open a single pack, on a
clock that keeps ticking — so the break loop could not finish inside the
chase. Those rats now carry two shields, the same early-trash count Mt. Kolts
and Zozo use, so breaking is part of the chase instead of something the timer
eats.

## What we'd like to know

- Does healing with a carried esper between fights feel natural, and does it
  change which magicite you want to hold on a dungeon crawl?
- Did anything on the Zozo ladder or in the opera rafter chase feel off —
  a stall, or a pack that would not break in time?
