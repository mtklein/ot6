# Gogo is General Leo

#552.  An optional scene in the World of Ruin: examining General Leo's grave
in Thamasa with Gogo in the active party reveals that Gogo is Leo.  A player
who never does it finishes the game with Gogo a mystery.  This is a surprise
for players: it stays out of the release notes, PLAYING.md, the booklet and
shipped save titles.

## The scene

Map 344 (Thamasa in the World of Ruin), the trigger before the grave's
stone (54,18), facing up and pressing A (`Ot6LeoGrave`, in bank $CC's tail
after the dialogue pointers: segment `ot6_event`).  Map 340, the World of
Balance's Thamasa, keeps vanilla's trigger.

- The reveal already played (switch `$00E0` set), or Gogo not in the active
  party: vanilla's line, "General Leo...".
- Otherwise `Ot6LeoScene`: the party steps out of its leader (vanilla's
  `_cac766`) and spreads below the grave one member at a time, then

```
GOGO: You know, this grave is
empty.
        (Gogo turns to the party; a chime and a white flash; Gogo is Leo)
LEO: I've been watching you.
        (the first of these in the party, in this order:)
CELES: General Leo...!
I saw Kefka strike you down!
TERRA: Leo...? You're alive!
LOCKE: General Leo?!
But... we buried you!
EDGAR: The Empire's finest
general, behind a mime's mask?
SABIN: Leo?! No wonder you
fight like a soldier!
CYAN: General Leo...
The one honorable man of the
Empire... thou livest!
SHADOW: ...I wondered when
you'd say so.
STRAGO: Leo?! Then whose
grave have I been tending?
RELM: No way! I cried at your
funeral, you know!
SETZER: Ha! A general dressed
up as a mime. What a bluff!
MOG: Kupo?! General Leo?!
GAU: Gau knew! You smell like
soldier!
UMARO: Uhhhh...?
LEO: Kefka's blade should have
ended me. I let the world bury
General Leo, and walked in your
footsteps instead.
        (Leo turns to the grave)
LEO: The world I swore to
protect lies in ruins. No more
hiding. My sword is yours.
```

  and the party steps back into its leader.  The speaker names are the
  record's names (`{gogo}` prints whatever the player named Gogo, then
  LEO).  The dialogue is `dlg1_en.json`'s last 17 entries, `$0C0C`-`$0C1C`
  (`OT6_LEO_DLG` in event_main.asm); every line fits the box's width
  (218 pixels at most, measured from the font's width table).  The sword
  on the grave is part of the map's background and stays where it is.

The transformation is the scene's own commands plus one new one:
`obj_gfx GOGO, LEO` (the field object and the record's graphics byte,
`$10`), `obj_pal GOGO, LEO` (palette 0, kept in `$1F70+12` at the next
menu or map change), `char_name GOGO, LEO` (the record's name, over any
name the player gave Gogo), and event command `$9F` (`ot6_leo_reveal`,
`Ot6LeoReveal`), which writes the stats and sets the switch.  The reveal is
one way: nothing clears the switch or undoes the record.

The slot keeps actor `$0C`.  `char_prop GOGO, LEO` is never used: Mimic, the
Status screen's command list, the final battle's order and every other rule
keyed on Gogo's actor keep working, and only presentation and the numbers
below change.

## The best of both

| What | How | Where |
|---|---|---|
| Vigor, speed, stamina, magic power | The higher of the record's and Leo's CharProp row, written once (Leo's 52/38/41/36 against Gogo's 25/30/20/26).  OT6 never grows these four, so the write is for good | `Ot6LeoReveal` |
| Max HP | Leo's base HP is 50, Gogo's 36, and every level adds the same to both, so max HP gains 14 (capped at 9999, the boost bits kept) and current HP the same | `Ot6LeoReveal` |
| Max MP | Gogo's base (12) is above Leo's (10): unchanged | `Ot6LeoReveal` |
| Battle power, defense, magic defense, evade, magic block | Read from Leo's row (60/63/41/22/21) whenever the switch is set, in the menu's stats and in battle | `Ot6LeoBattleRow` (UpdateEquip) |
| Run factor | Gogo's (normal); Leo's is low | unchanged |
| Equipment | Everything Gogo can wear plus Leo's whole set: equip-word bit 15, Leo's actor bit, the same bit the Merit Award opens.  Weapons 19 -> 85, armor 12 -> 22, helmets 12 -> 21, shields 11 -> 15 | Equip menu, Optimum and the shop's marks (`Ot6LeoEquipMask` in `chrequinf_get1`), the Item menu's "can be used by" (`Ot6LeoItemMask`), in-battle equip (`Ot6LeoActorMask`: bit 15 of `$3A20`) |
| Shock | The Status screen's command list ends in Shock once the switch is set | `status.asm` (`Ot6LeoShockList`) |
| Name, sprite, palette, portrait | The record's own bytes: everything that draws a party member from the record shows Leo | below |

Shock stays as vanilla has it (owner, 2026-11-16): free, non-elemental, every
enemy, and it takes no shield.  A boost buys the damage multiplier
(boost-rewards.md: "MagiTek beams with a number, Health, Shock"): x2/x4/x8.
Mimic copies it like any other action, free.  The displays tell the truth:
the command window shows Shock with no price (it has none), the shield and
weakness display does not move (it takes no shield and reveals no weakness),
and the boost pips are spent as on any multiplier action (`battle_leoshock`).

Vanilla's list holds at most 15 rows (the blank and the 14 commands a full
roster's records hold); Shock makes 16.  The 16th row's text is tilemap row
32, which in the status menu's 64x64 BG3 map is screen D's row 0, not the
next $800 bytes; `Ot6LeoRow16` puts it there, where the menu's HDMA shows
the cursor's 16th position.

## Everywhere he is drawn

Presentation follows the record's graphics byte (`$1601+12*$25`) and name
(`$1602`), so most places needed nothing: the field object (copied from the
record at a load), the world map's leader (`$11FB`/`$11FC`), the battle
sprite and palette (`$2EAE`, `CharPalTbl`), the menu portrait and its
palette, the party select, the Colosseum, the save and load screens, the
final battle's order menu, the ending's map scenes.  A search for every
place that picks a name, sprite, portrait or palette by actor instead of by
the record found these, each now branching on the switch:

- **The shop's "who can equip" sprites** pick by actor and load sheets 0-15
  into fixed VRAM slots: slot 12's frames come from Leo's sheet
  (`Ot6LeoShopGfx`) and its animation uses Leo's palette (`Ot6LeoShopAnim`,
  `Ot6ShopLeoAnim`).
- **The ending's cast card** reads its big name by character index: row 14,
  "Leo", built from the ending font's own letters (Locke's L, Terra's e,
  Gogo's o), for the revealed slot (`Ot6LeoCastName`).  The card's art stays
  Gogo's cloaked figure: there is no Leo art in the ending's graphics.
- **The ending's portrait vignette** loads portrait 12 by character: it
  loads Leo's ($10, the 17th pointer added to the field's table) once the
  switch is set (`Ot6LeoPortrait`).  The vignette plays only for a member
  never recruited (the script skips it after a recruited member's scene,
  behind switch `$0127`, which nothing sets), so a revealed Leo, recruited by
  definition, is shown by his map scene instead; the branch stands for
  consistency.

Gogo's own recruitment event writes his graphics, palette and name; it runs
before any reveal can, so it never undoes one.  Setzer's Hired Help can
summon a Leo figure into Setzer's slot (`Ot6HireGfxTbl`): with Leo in the
party the screen shows two Leos for that blow.

### Riding

Leo's map sheet is $1560 bytes against the main cast's $16A0: it has no
riding frames (poses $2E/$2F, tiles $1560-$169F), which would read the
first tiles of Banon's sheet.  Only the field's vehicle table picks them, for
a rider facing left or right on a chocobo or in Magitek armor; in the World
of Ruin that is the leader at the chocobo stables and in Cyan's dream (map
320).  The world map's chocobo, the airship, battles, menus, Kefka's Tower,
the ending and every event `action` stay within his sheet (no event uses
pose 46 or 47).  So `UpdateObjFrame` gives a rider with graphics $10 his
walking frames (`Ot6LeoRide`), and `Ot6LeoSaddle` drops the rider's lower
sprite when he faces sideways on a chocobo, so he sits in the saddle rather
than standing over the bird (`field_leoride`).

## Save compatibility

One new event switch, `$00E0` (byte `$1E9C`, bit 0), from the range
vanilla never references; nothing else new in the save.  The scan that
proved it free and the reads of every golden save and tracked checkpoint
(all 0) are in `build/attempts/wt/v049-leo/` (`switch_scan.txt`,
`switch_saves.txt`); save-layout.md's "Event switches" table holds its row
and the rule for taking a free switch, and `check_save_layout.py` checks it
against the build.  An older save with Gogo loads unrevealed and can play
the scene.  Everything the reveal changes lives in the record, the switch
and `$1F70`, all inside the vanilla save block, so it survives a save, a
Continue, party changes and the parties of Kefka's Tower (`save_leo`).

## Tests

- `gen_wor_leo`, a branch leg from `wor-gogo-v1` that nothing boots: the
  grave without Gogo (vanilla's line only, the record untouched), the reveal
  scene with him (the dialogue in order, the record, the switch), the grave
  again (vanilla's line), a save on the world map with Leo leading (his
  sprite and palette on the world map).  States `wor_leo_pre` (before) and
  `wor_leo` (after).
- `menu_leo`: before and after, the Status screen's battle-stat row and
  command list (Shock, once, drawn in the 16th row), the Equip menu's offer
  (a weapon of Leo's set, and one Gogo already could), the Item menu's
  "can be used by", the shop's sprite, Empty and Optimum.
- `battle_leoshock`: his battle sprite, palette, stat row and actor mask;
  Shock free, keyless, on every enemy, multiplied by its boost; Mimic of
  Shock.
- `save_leo`: Reset, Continue, and the reveal is all still there.
- `field_leoride`: the riding frames.
- `ending_leo` (an instrument spliced into `gen_wor_kefka`): the cast card
  and his scene with and without the reveal.

## Espers (the next step)

Letting him wear espers is a second step with a save-version bump (#552
piece F): the esper pages hold Magic Points for actors 0-11 only (624 bytes,
26 stones each), so actor 12 needs 52 more bytes in each slot's esper page
reserve, read only when `OT6_SAVEVER` is 2 or more.  What this step learned
for it: the menus that refuse him an esper key on the actor (`menu_common.asm`
`$0C`, `skills.asm`, `config.asm`, `battle_main.asm` 14677/14833/16098), so the
esper step branches there on the switch too; `Ot6EsperFold` already runs for
every slot in UpdateEquip, so his kept rungs would fold in through the same
path once the counters exist.
