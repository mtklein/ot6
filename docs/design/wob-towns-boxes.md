# World of Balance: the side trips off the line

Issues #281 (the Imperial Base: its guards and its treasure room), #284
(Kohlingen, SHADOW's hire and Jidoor's auction) and #285 (the monster boxes),
from the World of Balance coverage audit (`build/attempts/wob-coverage/`).
Each trip is a branch leg off the savestate chain at the point a player can
first reach it; nothing boots what a branch leaves, so the line from power-on
(the middle path) does not move for them. Evidence is under
`build/attempts/wt/v043-wob-towns/`.

| leg | boots | what it plays |
|---|---|---|
| `wob_base_guards` | `blackjack` | the base's guard fights, formations 416 and 417 |
| `wob_base_treasure` | `banquet-done-v1` | the treasure room's thirteen chests |
| `wob_kohlingen` | `figaro_submerged` | Kohlingen's chests and store, SHADOW at the inn |
| `wob_auction` | `narshe-mission-v1` | Jidoor's auction until Golem and ZoneSeek are bought |
| `wob_camp_telstar` | `camp_intro` | the Imperial Camp's Telstar box |
| `wob_fc_gigantos` | `fc_landing` | the Floating Continent's Gigantos box |

## 1. The Imperial Base's guards (#281)

The base's ten soldiers stand until the Narshe meeting sets `$0076`
(event_main.asm:94179-94189 hides `$045E`-`$0467`). Entering the base runs
`_cb25b9`, which turns their collision on, so a soldier who walks into the
party starts a fight as surely as one the party talks to. The magitek rider
(NPC_1 at (15,9)) starts battle 40, formation 417 (Mega Armor `$102` and
ProtoArmor `$165`); every other soldier battle 39, formation 416 (Commando
x4). Win or lose, the party is "Chucked out" to the world at (164,194), and a
loss is a game over (`_ca5ea9`).

The southern continent is first reached on the Blackjack after the Opera, so
the leg boots `blackjack`. The Blackjack does not fly from there: A on its tile
walks aboard, but the wheel's `_caf532` returns while `$016F` is clear, and
it is clear in both the `blackjack` and `n128_won` states. The leg walks east
to the base on foot, as `wob_base_treasure` does from Vector.

**Break rows.** Commando (2, pierce) and ProtoArmor (2, bludg) were already
authored for the Magitek Factory. Mega Armor was on the generated floor (4,
pierce). Its row is **3, pierce|bludg**: the bigger suit beside the
ProtoArmor, with joints a pike or a dagger finds (EDGAR's Mithril Pike,
LOCKE's daggers) and a shell SABIN's blitzes dent. Vanilla bolt|water stays.
`battle_breakwobbase.lua` checks the three rows and both formations against
the shipped ROM.

## 2. The Imperial Base's treasure room (#281)

The Emperor's reward ("the right to take any weapons you desire from the
Imperial base", dlg $0751) comes at a banquet score of 67 or more and hides
the treasure room's lock (`$045D`, `_cb2566`). The canon banquet scores 70
(gen_banquet_done), so the room is open from `banquet-done-v1`: TERRA and
LOCKE, alone, on the world outside Vector. The base is on foot from there
and the guards are gone, so the room costs only the walk.

Map 378 is two pockets: the door from the base lands at (33,43), and the
vault with the chests is behind the inner door (39,40) -> (52,33), out by
(51,32) -> (38,39). The thirteen chests hold 41,000 GP (8,000, 13,000 and
20,000), the Flame Sabre, Back Guard, Cure Ring, Wall Ring, RunningShoes,
Cherub Down, two Elixirs, an X-Potion and an Ether.

**The main line.** A player who scored the reward walks to the base: it is
on the way off Vector's plain, it costs no fight, and 41,000 GP is the
biggest purse in the World of Balance. The case for the canon play taking it
is strong. It stays a branch for now because the reward reaches far: the
gil and the relics change every shop and dressing decision from Albrook to
the Floating Continent, and every tracked save after `banquet-done-v1` would
move. That is a decision for the line's owner, made with a replay budget in
hand.

## 3. Kohlingen and Jidoor's auction (#284)

**Kohlingen** sits beside the castle's west landing; the line walks past it
on the way north to the Hero Ring. The branch boots `figaro_submerged`,
leaves the castle the way gen_zozo2_arrival does, and walks in.

- The two chests, the Green Beret (195) and the Elixir (197), share their
  treasure bits (65, 69) with the World of Ruin's Kohlingen, which holds the
  same prizes, so opening them here only moves them earlier.
- The general store's three counters (shops 17, 18, 19): weapons Air Lancet
  950, Flail 2000, Full Moon 2500, Shuriken 30, Fire/Water/Bolt Edge 500 each,
  Inviz Edge 200; armor Mithril Shld 1200, Magus Hat 600, Bandana 800, Head
  Band 1600, Iron Helmet 1000, Silk Robe 600, Iron Armor 700; items Potion
  300, Tincture 1500, Revivify 300, Antidote 50, Green Cherry 150, Fenix Down
  500, Sleeping Bag 500, Tent 1200. The Flail (CELES among its wearers) and
  the Full Moon (LOCKE's) are the "blunt" weapons the audit named: both bludg,
  both free of the row penalty, a bludg key for a party whose only one is
  SABIN's blitzes.
- SHADOW sits at the inn (191 NPC_1, `$0651`, shown until the Opera
  starts). See section 3.1.

### 3.1 SHADOW's hire

**He refuses.** The party arrives with 5,794 GP, so the 3,000 GP price is in
reach, but the talk never names it: "We meet again..." (dlg $03E3) is
followed by "Leave me alone..." (dlg $03E5), in every run (labs `kohl6`,
`kohl7`; sweeps `kohlingen/s0`, `s4`). The talk (`_cc6f84`, `$000B` set since
the first meeting) runs `_cac5c1`'s party check before the price, and the
check (`set_case PARTY_CHARS`, EventCmd_de: object party bytes at `$0867`
against the active party `$1A6D`, into `$1EB4`) reads SHADOW in the party:
`$1EB4` is `$72` as the talk opens (LOCKE, EDGAR, SABIN, CELES: objects 1,
4, 5, 6) and `$78` after the check (objects 3-6: SHADOW's bit set, LOCKE's
clear), where the objects' party bytes read SHADOW out of the party just
before the talk (object 3's byte `$00`, his record's `$1850+3` `$00`). So a
player cannot hire him here on this route; why the check reads object 3 is
open (it may be vanilla's own behaviour with SHADOW gone at the falls, or a
leftover of the scenario's party juggling). The leg asserts that no gil is
spent when he refuses, and would take the hire if the price were offered.

### 3.2 The auction

The clerk opens the auction only once `$006B` is set (the Blackjack's rejoin
after the factory escape, event_main.asm:97000); before that he says "Today's
auction is over." `$006B` reads 0 in the `blackjack` and `n128_won` states
and 1 from `narshe-mission-v1` on, so the World of Balance auction runs from
the factory escape to the end of the world. Each sitting draws one lot
(`_cb4ecc`): the Golem lot (20,000 GP, `_cb5197`) only while `$016D` is clear
and the ZoneSeek lot (10,000 GP, `_cb5312`) only while `$016C` is clear, each
behind coin flips, so **both magicite are offered in the World of Balance**
(magicite.md:74-75), Golem one sitting in eight and ZoneSeek one in sixteen
while Golem is unbought. `$01F0`, the sitting held, clears with the next map
load, so a player sits again by stepping out to the street and back in.

The leg (`narshe-mission-v1`, 72,709 GP) bought Golem at the fifth sitting
and ZoneSeek at the thirteenth, 30,000 GP between them; the other eleven lots
were Cherub Down and the lot first asked with dlg $0A5B, passed (sweeps
`auction/s0`, `s4`: the same thirteen lots in the same order both times; the
draw is the field's own RNG, which an in-battle seed shift does not move).

**The main line.** Golem's Bulwark and ZoneSeek's Ward are party-wide
passives a player who knows the auction buys with the Narshe purse. It stays
a branch: a sitting costs a walk in and out and the draw is a coin, and the
line's party already spends its gil at Jidoor's shops on this leg.

## 4. The monster boxes (#285)

| box | species | row | leg |
|---|---|---|---|
| Narshe school 107 (54,28) | Lobo `$019` | 3 pierce (authored) | none (below) |
| Imperial Camp 117 (17,18) | Telstar `$044` | 4 bludg (authored) | `wob_camp_telstar` |
| Phantom Train 153 (22,24) | Specter `$156` | **3 slash\|special** (new) | none (below) |
| Floating Continent 394 (48,15) | Gigantos `$0AE` | **5 slash\|bludg** (new) | `wob_fc_gigantos` |

- **Gigantos** (L25, 6000 HP, Throat Jab x5, weak poison) was on the floor
  row 5 bludg, which the landing party (TERRA, LOCKE and EDGAR's blades,
  SHADOW's point) cannot touch: on the old row the box was lost (lab
  `giga6`). Its row keeps the boss-grade five and keys slash and bludg, a
  giant's tendons and bones. The box is reached by the floor switch at
  (44,11) (`_cad62f`), which the line's crossing never steps on; the switch
  and the bridge at (40,12) lay tiles a menu's map reload takes away, so the
  leg opens no menu between them and the box.
- **Specter** (L19, 1500 HP, weak fire|holy) is a spirit, so its row is 3
  slash|special: CYAN's blade, and special for the guidelines' spirit rule
  (#347). No leg plays it: the rooms car (153) hangs off the front strip the
  train leg walks, and no state stands between `forest_done` and
  `train_done`; adding one would move the line's frames (an `H.saveState`
  takes two). `battle_breakwobtrain.lua` checks the row; the fight waits for
  a capture inside the train.
- **Lobo** (L5) is on an authored row and no leg plays it: from
  `narshe-mission-v1` the Beginner's House door (map 20 (33,54)) was not on
  foot from Narshe's south gate (lab `school1`), and a party past L20 meets
  an L5 wolf.
- The camp box's two neighbours: the MithrilGlove (19,18) opens; the Barrier
  Ring (15,8) is not on foot from the box's yard (lab `camp1`).

## 5. Results

Each fight leg ran once per in-battle seed shift (0, 4, 8, ... ; distinct
draws counted by battle key, `$be` at the open plus the formation), on the
replayed line's states (the ROM with these rows), under
`build/attempts/wt/v043-wob-towns/sweeps/`.

| fight | runs | distinct keys | won | lost |
|---|---|---|---|---|
| 417 Mega Armor + ProtoArmor | 6 | 6 (be88 beDC beAC be78 be8C be2C) | 6 | 0 |
| 416 Commando x4 | 6 | 5 (be90 be30 be80 beF0 beD4) | 5 | 0 |
| 61 Telstar | 4 | 4 (beA4 be04 be84 beF0) | 4 | 0 |
| 170 Gigantos | 6 | 5 (be90 be64 beB4 be40 beE4) | 4 | 1 (be90) |

- Every guards run passed on its first attempt; both formations fell within
  2,231-4,394 ticks.
- Gigantos: the one lost key (`gigantos/s0` attempt 1) wiped over two rounds,
  each member losing 800-860 HP a round to its counters, LOCKE dying with 3
  BP banked; the reload drew be64 and won. Four keys in five is a box a
  player beats, and a lab candidate: the driver opens with SHADOW's Fight and
  EDGAR's AutoCrossbow (pierce, not a Gigantos key), and every action draws a
  counter, so fewer, boosted slash Fights are the lever to measure.
- Telstar is won by SABIN and SHADOW at L12-14 with the camp's bag (one to
  seven Potions); each run ended above half HP.
- The treasure room (`treasure/s0`, `s4`) and Kohlingen fought only the
  world's own random battles on the walk, all won.
