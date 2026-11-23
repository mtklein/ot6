# Gogo: each command opens its owner's whole kit (#547)

> **Owner's ruling (2026-11-15):** "he should be able to get full kits as
> much as possible. some characters spread their kits across abilities, but
> he should get as much as reasonable for each choice." And: "and similar
> for everyone. we basically want to let him have access to everything cool
> about each character."  The broader brainstorm in #547 (every style at
> once, Shadow play, Curtain Call) stays parked until the owner has played
> him in the World of Ruin.

Status: **built** (v0.50, `ot6_gogo.asm` and the leaves it names).  This
document is the survey the ruling asked for: for every command Gogo can
pick, what of its owner's kit he had before (main at 8a8868d2), what he has
now, and the engine limits that keep a piece out.  `kits.md` "Gogo" is the
summary.

## 1. How Gogo's commands work

Gogo keeps Mimic in his first row and fills the other three in the field
Status menu from every command the recruited cast's records hold
(`DrawStatusGogoWindow`, `ff6/src/menu/status.asm:129`: each record of
`$1EDC`'s characters, duplicates removed, then filtered by
`BattleCmdProp`'s GOGO flag, `status.asm:197`).  The pick is written into
his record (`$1616`-`$1619`), so in battle he carries it like any other
character's command.

Most of OT6's kit machinery is keyed on the **command**: a list opens
because the command was picked, whoever picked it.  Those pieces already
answered for Gogo.  The pieces keyed on the **owner's actor id** did not;
each of those now also answers for actor `$0C` (`OT6_CHAR_GOGO`,
`ot6_gogo.asm`).  Since v0.49 Gogo can be revealed as General Leo (#552,
`leo-reveal.md`); the slot keeps actor `$0C`, so every test here holds in
both states.

## 2. The survey

"Before" cites main at 8a8868d2; "now" cites this branch.

| Command | Owner | Before | Now |
|---|---|---|---|
| Magic | the party (vanilla: Gogo's list is every spell the seated party can cast) | the union, built in `InitSpellList` (`battle_main.asm:14686`) and kept whole for him (`AddToSpellList_00`, `:14884`); Terra's Ultima fold was hers alone (`Ot6FoldSteps`, `ot6_boost.asm:2157`: char id 0) | the union as before, plus **Ultima**: his Fire at 3 BP folds into Ultima once Terra has rejoined (switch `$00BF`), priced as Ultima (`Ot6FoldSteps`, `ot6_boost.asm:2157-2161`) |
| Morph | Terra | not pickable (`BattleCmdProp[$03]` has no GOGO flag, `battle_cmd_prop.asm:44`) | not pickable: an engine limit (section 3) |
| Runic | Celes | plain Runic; RunicBlade was Celes's (`Ot6BladeRaise`, `ot6_runicblade.asm:45`) | **RunicBlade**: his Runic at 3 BP sends each absorbed spell back at its caster, once switch `$0068` is set (`ot6_runicblade.asm:45-48`).  Since #563 the command opens **Celes's list** for him (`Ot6RuneListOpen`, `ot6_rune.asm`, no actor test): Runic, a blade row for each element *he* can cast (his Magic list is the seated party's), and Break Blade once the party has learned it (switch `$0266` or `$00A4`); his Runic's absorbs arm his blade (`Ot6RuneAbsorb`'s Gogo compare) |
| Steal (TresHnt) | Locke | **already his**: Locke's list opens for anyone holding Steal (`_c1_thief_open`, `btlgfx_main.asm:18269`; `Ot6ThiefListOpen`, `ot6_thief.asm:228`, no actor test), with the rows Locke's story has taught | unchanged |
| Tools | Edgar | the bag's tools; Overclock was Edgar's (`Ot6Overclocks`, `ot6_overclock.asm:48`) | **Overclock**: his Tool at 3 BP fires twice for the two firings' price (`ot6_overclock.asm:48-51`) |
| Blitz | Sabin | **already his**: Sabin's list from `$1D28` (`Ot6BlitzListOpen`, `ot6_cmdmenu.asm:35`) with Bum Rush at 3 BP (`Ot6BlitzTake`, `ot6_divine.asm:401`, keyed on the attacker's boost) | unchanged |
| SwdTech | Cyan | **already his**: Cyan's window and loadout (`Ot6BushidoListOpen`, `ot6_cmdmenu.asm:707`; `Ot6BushidoPick`, `ot6_bushido.asm:93`, off the shared `$2020`/`$1CF7`) with Cleave on its 3 BP row (`Ot6Oblivion`, `ot6_divine.asm:76`, keyed on the attack id) | unchanged |
| Throw | Shadow | the bag's throwables; the smoke and the exit's reach (`Ot6TrickReach`, `ot6_shadow.asm:46`: any thrower) and the hobble and pin (`ot6_pin.asm:62`: command `$08`) were already his; Assassinate was Shadow's (`Ot6AssassinateGate`, `ot6_divine.asm:306-308`) | **Assassinate** on his Throw: a 3-BP Throw's hit that breaks a non-boss, or lands on a Broken one, kills it (`ot6_divine.asm:306-312`: actor `$0C` with command `$08` in `$b5`).  Only his Throw: Shadow's divine rides any of Shadow's actions, but Gogo's other commands are other characters' kits |
| Slot | Setzer | the bare reels: Setzer's table opened for Setzer alone (`Ot6SetzerListOpen`, `ot6_setzer.asm:90-93`) | **Setzer's table**: Slot, Coin Toss, Hired Help and Jackpot (once switch `$00CA`), priced from Gogo's level and bought with his own points (`ot6_setzer.asm:91-95`).  The hires walk in where he stood: `Ot6HireSwap` (`ot6_setzer.asm:1350`) swaps whatever graphics the slot holds and puts them back, Gogo's or the revealed Leo's |
| Lore | Strago | **already his**: Strago's loadout and Aqua Rake, one mask for every caster (`Ot6LoreMask`, `ot6_lore.asm:200`, read by `InitSpellList`, `battle_main.asm:14646`).  Analyze (Scan) and Bserk ride Strago's Magic row, so Gogo had them only through Magic with Strago seated (`Ot6UnionEspers`, `ot6_progression.asm:326`, skipped Gogo); Study was Strago's (`Ot6StudyOne`, `ot6_analyze.asm:141`; `Ot6MagicPrice`, `ot6_boost.asm:2584`) | **Scan and Bserk** join his Magic list whenever he carries Lore, Bserk once Strago has learned it (`Ot6UnionEspers`, `ot6_progression.asm:325-339`); **Study**: his Scan at 3 BP, carrying Lore, learns every lore the present species could cast, 99 MP (`Ot6StudyCaster`, `ot6_gogo.asm`; `ot6_analyze.asm:141`, `ot6_boost.asm:2585`) |
| Painter (Sketch) | Relm | **already his** since v0.47: Relm's whole list (`Ot6PaintListOpen`, `ot6_paint.asm:230`), with the rows she has learned, and Skills > Painter shows it | unchanged; the command is named Painter now (owner, 2026-11-21), and Sketch is its first row |
| Dance | Mog | **already his**: Mog's dances (`$1D4C`) and the stumble ladder, his own tier (`OT6_DANCETIER`, stride 2; `Ot6DanceTerrain`, `ot6_dance.asm:36`).  Mog has no divine (#478) | unchanged |
| Rage | Gau | **already his**: Gau's loadout, one list for every rager (`Ot6RageList`, `ot6_rage.asm:152`, `$257E`), and the coin and special ladder at his own tier (`Ot6RageTierStore`, `ot6_rage.asm:564`).  Gau has no divine (owner, 2026-11-15) | unchanged; Leap is an engine limit (section 3) |
| Control | (the Fake Mustache's Painter) | vanilla Control | unchanged |

Two of these commands also need the right weapon in hand, by vanilla's
rule for everyone: SwdTech greys unless the weapon carries the SwdTech bit
and Runic unless it carries the Runic bit (`UpdateCmdList`,
`battle_main.asm:14094`, reads the weapon's `$3BA4`; `UpdateCmd_02`, `:14189`,
and `UpdateCmd_01`, `:14198`).  Of the weapons Gogo can hold, the
SwordBreaker and the Graedus open SwdTech, and his daggers, the
SwordBreaker, the Graedus, the Imp Halberd and the Magus Rod open Runic
(ItemProp's equip and weapon-flag bytes).  The SwordBreaker is sold at
Maranda in the World of Ruin and won at the Colosseum.

The other commands Gogo can pick (Fight, Item, Capture, Jump, X-Magic, GP
Rain, Summon, Possess, and the revealed Leo's Shock) belong to no one's kit.

## 3. Engine limits

- **Morph and Trance stay Terra's.**  Morph is Terra's own command, not a
  piece of Magic, and making it pickable would break three things the
  engine holds for one morpher: the battle graphics turn any morphed
  character into Terra's esper form (`status_pat_tfr`,
  `btlgfx_main.asm:6734-6743`, `CHAR_GFX::ESPER_TERRA`); the morph clock is
  one character's (`$3EE2`, `ot6_trance.asm:77`), so a second morpher would
  take over Terra's gauge; and the boost a Morph was bought with is one
  byte (`OT6_MORPHBOOST`, `ot6_trance.asm:59`).
- **Leap stays Gau's.**  Leap's end of battle removes Gau's slot and his
  availability bit by name (`BattleEnd_02`, `battle_main.asm:12503`:
  `$300B`, the Gau slot, and `$1EDF` bit 3), and he comes back through the
  Veldt's own events for him; a Gogo's Leap would remove Gau, or nobody.
  `BattleCmdProp[$11]` has no GOGO flag (`battle_cmd_prop.asm:89`).  What
  Leap is for, learning rages, already reaches Gogo through Gau's loadout.
- **Scan, Bserk and Study need his Magic row.**  They are Magic-row spells
  (Strago's too: the Fanatics' Tower keeps them), and the Lore window holds
  only the 24 lore records, one per lore id (`InitSpellList`'s walk,
  `battle_main.asm:14646-14662`), so a Gogo carrying Lore without Magic has
  Strago's lores and not his Scan.  With Magic and Lore he has all of it.

## 4. Mimic

Mimic copies the action, not the price (guidelines), and a copy reads
Gogo's own pending boost where the copied action reads one.  The divines
keyed on the actor now answer for him, so a copy at three of his points
buys what his own command would: a Mimic of Edgar's Tool overclocks, of
Celes's Runic is a RunicBlade (and of her blade row arms Gogo's own
weapon with that element, of her Break Blade starts his own: both are
self-targeted, so the copy lands on the copier, #563), of Shadow's Throw assassinates, of Terra's
Fire is Ultima, and (when he carries Lore) of Strago's Scan studies, each
free as every copy is.  Under three of his points each is its plain self.

## 5. Tests

`battle_gogokits` (wor-colosseum-v1, the Falcon's cabin seats GOGO, TERRA,
RELM and SHADOW, so no seated member lends Scan, and GOGO holds the
SwordBreaker the Colosseum won): four rounds, each its three commands set
in his Status menu and played through the real battle menu -- Magic, Slot
and Tools (no Scan without Lore, Setzer's table, Ultima, Jackpot,
Overclock, and a Tool stopping at the Assassinate gate's command test);
Magic, Lore and Runic (Scan and Bserk, the lore loadout, Study, RunicBlade
and its bounce); Throw, Steal and Blitz (Locke's rows, Sabin's list and Bum
Rush, Assassinate's Death mark at 3 BP and none at 2); SwdTech, Rage and
Dance (Cyan's window and Cleave, Gau's loadout, Mog's dances); then a fifth
from `gen_wor_leo`'s state after the reveal (Setzer's table, Overclock and
Assassinate for the revealed slot).  Two declared stagings: Strago already
knows every lore the plain's casters cast, so those are unlearned for the
battle Gogo studies in (the victory teaches them back); and no party there
breaks a body on cue, so every standing non-boss is Broken as Gogo's 2- or
3-BP throw begins.  `battle_relmwor` covers his Painter list.  Each Gogo
arm has a byte-patch mutant (its `cmp #$0C`, Study's `lda #$0C`, the study's
own full-boost test, Jackpot's second roll), each red in the suite:
`build/attempts/wt/v050-gogo-kits/mutants/r3/`.
