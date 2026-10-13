# World of Ruin: Narshe (Mog, Umaro's Cave, Tritoch, the Ice Dragon)

The plan for milestone v0.29, #266: from the save beside the Falcon outside
Jidoor (`wor-cyan-v1`, where the v0.28 route ends) to MOG and UMARO joined,
Terrato and Tritoch owned, the Ice Dragon beaten, and a save beside the
Falcon outside Narshe. Sections 0-10 are the plan as written before play;
section 11 is what the route built and measured.

Line numbers are into `ff6/src/event/event_main.asm` unless a file is named.
Evidence is under `build/attempts/wt/v029-plan/`, read from `build/ot6.sfc`
built at cc088b02 (`rom_commit.txt`) by `tools/route_data.py` and the
scripts beside the logs, and from the tracked `wor-cyan-v1` SRAM on
wt/v028-cyan-route at a57087a5 (`wor-cyan-v1_a57087a5.sram`). Estimates are
marked.

---

## 0. Findings

1. **Ragnarok needs LOCKE; it moves to v0.32.** The old man who offers it
   (`_cc0b1e`, :78299; `give_genju RAGNAROK` :78329) stands in the weapon
   shop's back room, map 24 (43,50) (`npc_prop.asm:1529`, `NPCProp::_24`),
   not map 36 as magicite.md had it. Map 24's only door in the World of
   Ruin is map 32 (32,30), and a lock object stands on the tile below it
   (map 32 NPC_3 (32,31), `npc_prop.asm:1806`). Its event `_cc0aae` (:78252)
   is `set_case PARTY_CHARS` then `if_switch $01A1=0, _cc0a9a` ("Locked!",
   :78241); `set_case PARTY_CHARS` writes the active party's characters to
   switches `$01A0-$01AF` (`EventCmd_de`, `field/event.asm:4313-4327`), so
   `$01A1` is LOCKE (character 1) in the party. Only then does `_cc0a22`
   (:78159, LOCKE picking the lock) run and the lock hide. The locks are
   shown from a new game (`InitNPCSwitches`, `field/obj.asm:176`, reads
   `init_npc_switch.dat`: `$06C0`-`$06C7` all 1, `narshe_lock_switches.txt`)
   and nothing but these events clears them; `wor-cyan-v1` holds all eight
   set and LOCKE unavailable (`switch $06C1 = 1`, `switch $02F1 = 0  LOCKE
   available`, `wor-cyan-v1_dump.txt`).
2. **The same locks shut every Narshe service.** Six lock objects stand in
   front of six doors of map 32 (`npc_prop.asm:1798-1838`): the inn (41,36),
   the weapon shop (32,30; Ragnarok, shop 68), the relic shop (29,25; shop
   70), the item shop (41,22; shop 71, the town's only stocked counter in
   the World of Ruin), and two doors of the elder's house: (52,37) to the
   treasure room (Hyper Wrist, Sneak Ring, Wall Ring, ThiefKnife, Earrings,
   5,000 GP) and (32,16) to the Cursed Shld's old man (`_cc0b70`, :78347;
   `map30_paths.txt`: only the (80,35) landing reaches (87,46), only the
   (79,17) landing reaches (79,9)). Open without LOCKE: the armor shop
   (shop 69, which stocks nothing), two elder's-house rooms with an Elixir
   each, the mines, the moogle cave, Mog, the cliffs, Tritoch, the Ice
   Dragon and Umaro's cave. v0.29 therefore buys nothing in Narshe.
3. **There is no Lone Wolf choice in the World of Ruin.** The Lone Wolf
   chase and the Mog-or-Gold-Hairpin choice are World of Balance events:
   `_ccd3ce` (:110050) returns at once once `$00A4` (the World of Ruin) is
   set (:110051), and the choice is on a 240-frame timer (`_ccd52d`,
   :110283). The route never ran it (`$0239 = 0`, `$023F = 0`), so `$029F`
   (set when MOG joins there, :110594) is clear, and Mog's World of Ruin
   meeting (`_cc396c`, :85056; map 44 (121,46), `npc_prop.asm:1972`) takes
   its first-meeting branch `_cc3a4c` (:85212): his naming menu (`name_menu
   MOG`, :85284), then the join. The WoR "pickpocket" at Narshe's gate
   (`_cc36f2`, :84739, triggers (37-39,50)) is one dialog.
4. **Tritoch is not optional on this route.** The opening to Umaro's cave
   (`_cc37e7`, :84872, map 35 (9,12)) returns unless Tritoch is freed
   (`if_switch $029E=0, EventReturn`, :84873), and the only way to that
   tile crosses Tritoch's trigger (9,14) (`_cc3719`, :84770). No other
   entrance loads maps 281-283 (`load_map 281` at :84916 and the cave's own
   floor drops, :110910-111003). Umaro and Terrato are behind it.
5. **The Ice Dragon is a fight a player takes.** It stands on map 34 beside
   the cliffs' save point (25,5), on the way to Tritoch, touched to fight
   (`collision_on` by map 34's init `_cc36dc`, :84726; battle 132 at
   :84730, a game over when lost, `_ca5ea9`). The static walk reaches the
   save point and the way on without its tile (`map34_dragon.txt`: `(25,
   6) avoiding (22,20): 48 steps`), so it is a choice; level-curve.md keeps
   the dragons at their milestones, and it is the arc's other fire-weak ice
   body, so the plan takes it from the save point, before Tritoch.
6. **UMARO joins only with MOG in the active party.** Umaro's event
   (`_ccd793`, :110721) is `set_case PARTY_CHARS` then `if_switch
   $01AA=0, _ccd88e` ("Ooh…", :110891): `$01AA` is MOG (character 10). He
   then waits on the Falcon ("me wait for you in big airship", `$007E`). MOG
   has to be seated before the cliffs.
7. **Mog's divine is out of reach here.** `wor-cyan-v1` knows one dance:
   `$1D4C = $40`, Dusk Requiem (bit 6; Water Rondo is bit 5,
   `ot6_waterrondo.asm:34`; `wor-cyan-v1_roster.txt`). kits.md keeps Water
   Rondo WoB-missable, learned on the Lete River, and this route's MOG
   never learned it. See section 10.
8. **Narshe's arc is ice.** Every boss absorbs ice and is weak to fire
   (Umaro, Tritoch, the Ice Dragon, `species.txt`), the three party fire
   sources are TERRA's natural Fire and the Ifrit and Maduin stones
   (`wor-cyan-v1_spells.txt`), and Tritoch's defence is 254, so its damage is
   magic. None of the arc's 17 species has an authored row today; their
   MonsterProp records are vanilla's byte for byte (`vanilla_cmp.txt`).

## 1. The start state (`wor-cyan-v1`)

From the tracked SRAM (`wor-cyan-v1_dump.txt`, `wor-cyan-v1_roster.txt`):

- Party: `TERRA L39 HP 2424/2424`, `CYAN L38 HP 2911/2911`, `SABIN L40 HP
  2552/2552`, `CELES L40 HP 2538/2538`. Aboard: `EDGAR L34`, `SETZER L33`.
  Not yet available: `MOG L11`, `UMARO L18`, `LOCKE L28`, `GAU L33`.
- Stones worn: TERRA Fenrir, CYAN Palidor, SABIN Ifrit, CELES Maduin, EDGAR
  Ramuh, SETZER Unicorn; owned, unworn: Siren, Shoat, Shiva, Bismark,
  Stray, Kirin, Carbunkl, Phantom, Sraphim.
- Bag: `Potion x95, Fenix Down x30, ... Revivify x25, ... Elixir x4, Tent
  x2, ... Tincture x13, ... Ether x6`; `Ice Shld x1, Thunder Shld x1`;
  `gil 772108`.
- The v0.28 route ends on world 1 (36,156), beside Jidoor's item counter
  (shop 78) (route-wor-cyan.md section 7).

## 2. The order

1. **Jidoor, before take-off.** The item counter (shop 78) for the arc's
   spend (section 7). The cabin (map 12): seat three, CYAN, TERRA and CELES,
   and leave the fourth seat for MOG; SABIN waits aboard (section 5.4).
2. **Narshe.** Land beside world (115,33); the gate is map 32 (38,61)
   (`world_entrances1.txt`). The pickpocket's dialog at (38,50).
3. **To the moogle cave.** Its two doors on map 32, (10,36) and (26,8),
   are not in the town gate's pocket (`components.txt`). Two ways reach
   them. Through the elder's house: the open door (49,12) lands in map 30
   (55,34); that room's (67,26) leads out (`_cc3926`, :85032) to map 32
   (53,8), whose pocket holds (26,8), the door to map 38 (78,58). Or
   through the mines: map 32 (15,57), A held facing up (`_cc388f`,
   :84980; `UpdateCtrlFlags`, `field/event.asm:5438`, writes the facing
   direction to bits 0-3 and A to bit 4 of `$1EB6`, switches
   `$01B0`-`$01B4`), opens (15,56) (`$01F0`); map 36 (7,33), out at (21,9)
   to map 32 (23,44), whose pocket holds (10,36), the door to map 38
   (87,31). The static model joins both pockets to map 38's one 485-tile
   pocket, which holds the door to map 44. The first needs no facing-up
   press; the emulator settles which the walk takes.
4. **Mog.** Map 38: the Pod Bracelet (65,28) and Elixir (52,33); the door
   (49,21) to map 44; the Ribbon (98,53), the Moogle Charm (121,45), and
   MOG at (121,46): naming, join into the empty seat (`char_party MOG, 1`
   when `$01A3` is clear, :85310-85312). The Ribbon goes on at once
   (guidelines.md); the Moogle Charm stays in the bag (it stops random
   battles, and the route fights them).
5. **Back out and up.** The same way back to the town's main street, the
   north exit (35-39,1) to map 33 (61 steps from the gate, `paths.txt`). Map 33 to map 34 is a chain through the mines
   (`components.txt`, `components_mines.txt`): 33's lower pocket, its long
   exit (30-32,20) to 36 (108,59); 36's (18,51) to 33 (36,25); 33's
   (24,10) to 36 (108,12); 36's (117,12) to 33 (32,10); 33's long exit
   (34-38,1) to map 34 (19,39).
6. **The cliffs' save point** (map 34 (25,5)): the arc's mid checkpoint,
   `wor-narshe-cliffs-v1` (section 8), the retry point for the next three
   fights.
7. **The Ice Dragon** (map 34 NPC_2 at (22,20)), from the save point; back
   to the save point after.
8. **Tritoch.** Map 34's long exit (18-22,1) to map 35; (9,14) plays the
   thaw and battle 119 (:84785); Tritoch is given (:84853, `$029E`). A
   player saves again on the way back past (25,5); the route can too.
9. **Umaro's cave.** Map 35 (9,12): "Hop into it?" Yes (`choice _cc37fe`,
   :84878) drops the party to map 281 (14,55). The landing pocket
   reaches only map 282's doors and the floor drops (10,54)/(11,53)
   (`_ccd8b2`, `_ccd8d4`, :110910) and 282's (14,30)/(33,26) (`_ccd8f6`,
   `_ccd918`), which land in 281's main pocket (`components.txt`); the
   X-Ether in 282 (14,25), the Gauntlet in 281 (41,58). Map 281 (40,12), A
   held facing up (`_ccd967`, :110986): the floor gives way to the lair,
   map 283 (58,21). (31,9) is the same kind of drop back into 281 (59,38).
10. **Terrato and Umaro.** The carving (283 NPC_1 (57,15)): "Remove the
    Magicite?" Yes (`_ccd709`); Terrato is given after battle 117, Umaro
    (:110705, :110718), a game over when lost. Talk to Umaro (now shown,
    `$065B`): his naming menu (:110811), "me wait for you in big airship".
11. **Out.** The lair's (57,7) (`_cc3839`, :84922) carries the party to map
    33 (35,17) and down; through 36 and 33 to the town and the Falcon.
12. **The regroup and the save.** The cabin: UMARO and MOG in, with two of
    the others (section 5.4); relics; Terrato and Tritoch onto wearers; the
    save beside the Falcon outside Narshe, `wor-narshe-v1`.

Not on the way: the Pugs' chest (282 (13,34), event group 152: three
Pugs, L99, 14,001 HP each, evade 150, counter Pearl, XP 0; `pools.txt`).
A chest that is only a fight with nothing in it; the plan leaves it shut.
The two open elder's-house Elixirs (map 30 (105,14) from map 32's (18,22);
(55,30) from (49,12) or (53,9); `chests_reach.txt`) are a few steps off the
town's main street and the route takes them.

## 3. Maps, switches and battles

| map | what | switches and events | battles |
|---|---|---|---|
| 32 Narshe (WoR) | town; random battles on | init `_cc36bd` (:84711, `$02A0`); pickpocket `_cc36f2` (`$029B`); mines door `_cc388f` (`$01F0`); the locks `_cc0a9e`-`_cc0aee` (:78245-78285, `$06C0`-`$06C5`); house exits `_cc38be`-`_cc394d` (:85000-85049) load map 32 | group 189 |
| 36 mines | the chain to the cliffs; the way to the moogle cave | -- | group 190 |
| 38, 37 moogle cave | Pod Bracelet, Elixir | -- | group 191 |
| 44 Mog's room | Ribbon, Moogle Charm, MOG | `_cc396c` (`$029F` test :85060; `$02FA`, `$068D`) | none (random battles off) |
| 33 cliffs | -- | init `_cc36bd` | group 189 |
| 34 cliffs | save point (25,5); the Ice Dragon (22,20) | init `_cc36dc` (`collision_on`); `_cc36df` | group 191; event 132 |
| 35 cliffs | Tritoch, the opening | init `_cc37ac`; `_cc3719` (`$029E`); `_cc37e7` | group 191; event 119 |
| 281, 282 Umaro's cave | Gauntlet, X-Ether, Pugs' chest | `_ccd8a7` (:110905, `$0279`, `$01B5`); drops `_ccd8b2`-`_ccd967` | groups 166, 167; event 152 (the chest) |
| 283 the lair | Terrato, UMARO | init `_ccd896`; `_ccd6eb`/`_ccd709` (`$027A`, `$065B`); `_ccd793` (`$02FD`, `$007E`); exit `_cc3839` | group 168; event 117 |

Event groups (`pools.txt`): 117 is formation 444 (Umaro `$110`), 119 is 487
(Tritoch `$144`), 132 is 366 (Ice Dragon `$149`), 152 is 235 (Pugs `$0FF`
x3). World group 51 is the plain at Narshe's gate (`pool world 1 115 34`:
Geckorex, Reach Frog, Mantodea, Sprinter, Spek Tor), all authored on
wt/v028-cyan-route.

## 4. Species and proposed break rows

Vanilla stats (`species.txt`; identical to vanilla, `vanilla_cmp.txt`).
Shields follow ot6_hud.asm's tiers: trash 1-3, tanks and minibosses 4, bosses
by HP and fight length (the Storm Drgn's 14 at 42,000 HP, Phunbaba's 4-12).
Only one of these species appears anywhere else (Nastidon, random group 86,
`sharing.txt`). The party here holds slash (TERRA, CELES, CYAN, SABIN's claw),
pierce (MOG's spear) and fire; bludgeon arrives with UMARO at the end.
**Counts and keys are a proposal**; the route agent's play sets them.
(Built as proposed but for the Wizard, the Pugs and the Test Rider's
lesson: section 11.3.)

| species | where | L / HP | vanilla elements; notes | shields | classes | why |
|---|---|---|---|---|---|---|
| Red Wolf `$0F8` | 32-35, 37, 38 | 32 / 1,510 | none; Rush | 2 | slash, pierce | a wolf, as the WoB Lobo |
| Nastidon `$0CE` | 32, 33 | 32 / 1,877 | weak fire; starts Safe | 2 | slash, bludg | a hide; fire is the party's other key |
| Test Rider `$09C` | 32, 33 | 32 / 3,100 | weak poison; Gold Lance (x3), counters | 3 | pierce | the lance-rider: MOG's spear unseats it (the recruit's key) |
| Wizard `$0C4` | 34, 35, 37, 38 | 32 / 1,677 | weak bolt, poison; six Runic-able spells, def 50 | 2 | pierce, special | a caster; CELES's Runic eats its whole list |
| Psychot `$0DA` | 34, 35, 37, 38 | 32 / 900 | weak ice, **absorbs fire**; Float | 1 | pierce, special | the one body here fire heals |
| Mag Roader `$0E7` | 36 | 32 / 1,777 | none; Ice, Ice 2 | 2 | pierce, bludg | a wheel: puncture or crush |
| Mag Roader `$0F3` | 36 | 32 / 1,380 | none; Fire, Fire 2, counter Fire Ball | 2 | pierce, bludg | the same body |
| Poppers `$0C9` | 281 | 33 / 1,000 | weak fire; starts Safe; Stone (Muddle) | 1 | slash, pierce | in fours |
| Kiwok `$0CD` | 281 | 33 / 2,000 | weak ice; Pick (Imp) | 2 | slash, pierce | a bird |
| Ceritops `$0C6` | 281-283 | 33 / 2,000 | weak fire, absorbs bolt; starts Safe; Pal Maker (Imp) | 3 | pierce, bludg | horned and plated: the cave's tank |
| Anemone `$0B4` | 282, 283 | 33 / 2,000 | weak fire; absorbs bolt and water (its bolt weakness never applies); Giga Volt | 2 | slash | a plant; the Thunder Shld or Runic for Giga Volt |
| Tomb Thumb `$09E` | 282, 283 | 33 / 2,000 | weak bolt, water; Imp Song | 2 | pierce, special | a cursed body (guidelines.md: ¤ for cursed bodies) |
| Pug `$054` | 281 (16/256) | 27 / 8,000 | weak fire, bolt; absorbs water; evade 50; Step Mine only | 4 | slash, special | a rare miniboss-grade body |
| Umaro `$110` | event 117 | 33 / 17,200 | weak fire, poison; absorbs ice | 6 | slash, pierce | the boss under the party; break it before his Green Cherry |
| Tritoch `$144` | event 119 | 62 / 30,000 | weak fire; absorbs ice; nulls bolt, poison, wind, holy, earth, water; **def 254**; Float | 10 | slash, pierce | blades and the spear chip what they barely hurt (DESIGN.md: any damaging hit on a weakness chips; measure that a 1-damage hit does); fire burns it |
| Ice Dragon `$149` | event 132 | 74 / 24,400 | weak fire; absorbs ice | 10 | pierce, bludg | MOG's spear is the class key; fire is everyone's |

Not designed: Pugs `$0FF` (the chest the plan leaves shut).

Tritoch `$144`'s row today is `0, $00` under "scripted set-pieces"
(`ot6_hud.asm:2263`), beside the World of Balance records `$114` and `$115`
that the table's comment says cannot be told apart (`ot6_hud.asm:1635`).
`$144` is a different record: formations 487 and 488, event groups 119 and
120, and only `battle 119` (:84785) calls any of them (`sharing.txt`; no
`battle 120` in the source). Its row can be a real one without touching the
World of Balance's.

## 5. The bosses

The party arrives at L38-40 (section 1); level-curve.md projected 39 with a
target of 40 for this arc. MOG's branch sets him with `char_prop MOG,
MOG` (:85213), and UMARO's with `char_prop UMARO, UMARO` (:110724): `EventCmd_40` sets the level from
`CalcAverageLevel` plus `CharProp`'s level modifier (`field/event.asm:
1080-1088`). The available six average (39+38+34+40+40+33)/6 ≈ 37
(**estimate**; the modifier is not read here). A random on the arc's
pools pays 1,947-2,071 XP before the x2 (formations 273-275, `pools.txt`),
about 1,000 a member of four after it, against 12,792 for L40 (level-curve
.md): about a dozen randoms a level (**estimate**).

### 5.1 The Ice Dragon (event 132; `AIScript::_329`, `ai_script.asm:6922`)

Battle, N. Cross (ice, Frozen; Runic-able), Absolute 0 (ice, power 110),
Surge (ice, 55), in a three-step rotation; counter Battle to every hit, and
Surge on its death. Immune to Zombie, Magitek, Imp, Petrify, Death, Near
Fatal, Sleep, Stop.

- **Kit.** Fire, boosted toward Fire 2 and 3, from TERRA (natural), the
  Maduin wearer and the Ifrit wearer: the weakness doubles it and chips a
  shield each cast. CELES on Runic for N. Cross. MOG's spear is the class
  key; the blades are not. The bag's Ice Shld (absorbs ice) and Thunder
  Shld (halves ice) go on two members (`items.txt`). The Ribbon's list does
  not include Frozen (`items.txt`).
- **Expectation (estimate).** Its HP is 58% of the Storm Dragon's, which
  this party won 30 of 30 at L38-40 (route-wor-cyan.md 5.3, 8.2). Its whole
  list is one element the party can resist and one weakness three members
  hold. A lab if it costs more than the Storm Dragon did (Potions 0-24, Fenix
  Downs 0-4 a fight).

### 5.2 Tritoch (event 119; `AIScript::_324`, `ai_script.asm:6794`)

Rasp, Ice 3 (Runic-able) and Cold Dust (ice, Frozen) in rotation. Counters:
fire draws Rasp (MP); SwdTech, Tools, Blitz, Lore, Sketch and Rage draw Cold
Dust on the attacker. Fight draws nothing.

- **Kit.** Defence 254 leaves Fight about 1/256 of its damage (vanilla's
  defence step), and its magic
  defence is 70. So: fire for damage (Rasp drains the caster's MP:
  Tinctures and the save point's Tent before it); Fight to break it (the
  proposed slash/pierce row), which also stops its turns while it is Broken
  and doubles the fire; CELES's Runic for Ice 3; no SwdTech or Blitz, which
  only draw Cold Dust. MOG's dance stumbles off its terrain and Snowman Jazz
  is ice (`dance_prop.asm`: Snowball, Surge, Snare, Ice Rabbit), so MOG
  Fights.
- **Expectation (estimate).** 30,000 HP of magic damage at mdef 70 from
  three fire sources, with Ice 3 the only hard hit. Measure.

### 5.3 Umaro (event 117; `AIScript::_272`, `ai_script.asm:4914`)

Battle, Blizzard and his Special, Tackle (damage x3); under `if_num_chars
2` and a 40-tick timer, Snowball (Sap), Surge, Lode Stone (:4937-4941).
Below 10,240 HP he uses a Green Cherry on himself once: Protect, Shell,
Haste, Regen (:4917-4932). The party's Magic counts up a monster variable
(`if_cmd MAGIC`, `add_monster_var 1`, :4968-4969); past three he Jumps
(`if_battle_var_greater 36, 3`, `cmd JUMP`, :4933-4934). Counters: fire
draws Tackle or Blizzard; any hit can draw Tackle.

- **Kit.** L33 against L38-40. Break him before 10,240 HP, while his Green
  Cherry is unspent; Fight (blades and the spear), and fire on the break.
  The lair is a cave, MOG's terrain for Dusk Requiem (Elf Fire among its
  steps, `dance_prop.asm`).
- **Expectation (estimate):** under the party, as Phunbaba's first visits.

### 5.4 The party

**Into Narshe:** CYAN, TERRA, CELES, and MOG when he joins; SABIN, EDGAR and
SETZER aboard. CYAN (L38) and MOG (~37) are the lowest and earn the arc's
XP; CELES's Runic answers N. Cross, Ice 3 and the Wizards; TERRA brings
natural Fire and Morph. Ifrit moves from SABIN to CYAN or MOG so three
members cast fire. **Out of Narshe:** UMARO and MOG with two others, for
UMARO's arrival (section 6.3).

## 6. Espers and arrivals

### 6.1 Espers

| Esper | where | how | magicite.md list |
|---|---|---|---|
| Tritoch | map 35 | after battle 119 (:84853) | Ice, Bolt, Poison |
| Terrato | map 283, the carving's eye | Yes at `_ccd709`, then battle 117, then `give_genju TERRATO` (:110718) | Quake, Quartr |
| Ragnarok | map 24 (43,50) | behind LOCKE's lock (section 0.1): **v0.32** | Ultima, Warp |

Terrato's Quake misses floating bodies; Tritoch and the Psychots start with
Float (`species.txt`).

### 6.2 Mog on arrival

- **His key:** the spear is the only pierce in the party, and the proposed
  rows make pierce the Test Rider's only key and the Ice Dragon's class key
  (section 4).
- **Gear:** the Ribbon from his own room; a Partisan (pow 150, pierce) from
  Jidoor's weapon counter (shop 76, 13,000 GP) bought before take-off; the
  bag's Mithril Pike (70) otherwise (`items.txt`, `shops.txt`).
- **His divine:** not known on this route (finding 7).

### 6.3 Umaro on arrival

Bludgeon on Fight and Charge, ice on Storm (kits.md "Umaro"). His Rage Ring
is in the Cave in the Veldt (map 353 (18,20)) and his Blizzard Orb in the
Ancient Castle (map 406 (53,23)) (`chest_find.txt`): neither on v0.29, so he
Fights and Charges, and Storms only on a dump of three points. Every boss
here absorbs ice, so he joins after the fights where his divine would heal
them. His showcase is the regroup and the Narshe plain beside the Falcon
(world group 51), where the cyan arc's Reach Frog (bludg) and Mantodea
(slash, bludg) rows give him keys.

## 7. Shops, supplies and items

- **Narshe sells nothing** without LOCKE (finding 2). Shops 68-70 stock only
  a `$00 Dirk` row; shop 71 sells Potion, Tincture, Fenix Down, Revivify,
  Remedy, Echo Screen, Sleeping Bag, Tent, behind the lock (`shops.txt`).
  No inn either.
- **The arc's counters:** Jidoor (shop 78), where it starts, and Kohlingen
  (67), the nearest other, a flight away.
- **The band** at L40 (level-curve.md): Potion ~60, Tincture 10, Revivify 3,
  Fenix Down 20. Held: 95, 13, 25, 30. The Storm Dragon cost 0-24 Potions a
  fight (route-wor-cyan.md 8.2); three bosses here could cost twice that
  (**estimate**), so Jidoor's counter stocks the arc's spend with
  `H.careStockPotions` before take-off, and Tents (2 held, 1,200 each) for
  the cliffs' save point, the only place to rest.
- **Chests on the way:** Pod Bracelet (Shell, Safe) and Elixir (map 38),
  Ribbon and Moogle Charm (map 44), Gauntlet (281), X-Ether (282), two
  Elixirs (map 30). None of these treasure bits is in
  `tools/chests_opened.txt`.
- **For the ice:** one Ice Shld and one Thunder Shld in the bag; the Flame
  Shld (nulls ice) is on map 144 (Cyan's dream, `chest_find.txt`); no Snow
  Muffler in any chest.

## 8. Checkpoints

- `wor-narshe-cliffs-v1`: map 34's save point (25,5), MOG in the party, the
  Ice Dragon and Tritoch not fought (`$029E` clear). The retry point for the
  Ice Dragon, Tritoch and Umaro (Umaro's cave has no save point;
  `maps_umaro.txt`).
- `wor-narshe-v1`: beside the Falcon outside Narshe; `$029E`, `$027A`,
  `$007E` set; Terrato and Tritoch owned; MOG and UMARO available.

## 9. Harness risks

- **A-facing-up triggers.** The mines door (32 (15,57)) and the lair's drop
  (281 (40,12)) answer A pressed facing up (section 2, step 3); a walk
  that only steps on them does nothing. The wheel in route-wor-terra.md is
  the same kind.
- **Floor drops.** 281 (10,54), (11,53) and 282 (14,30), (33,26) drop the
  party on contact; 281 (31,9) is a facing-up drop. The walk has to take the
  ones it means to and step around the rest; the planner does not know them.
- **The chain through the mines.** Map 33 to map 34 is five door hops
  through map 36 (section 2.5); the moogle cave is reached through map 36
  too, or through the elder's house. The static model reaches these in
  parts; the emulator settles it.
- **Naming menus.** MOG's (:85284) and UMARO's (:110811) open the naming
  menu; `gen_moogle.lua` commits LOCKE's the same way.
- **Choices.** "Hop into it?" (:84878), "Remove the Magicite?" (:110625).
- **The Ice Dragon on contact.** It is a touch-to-fight NPC beside the save
  point: a walk that brushes (22,20) starts battle 132. The static shortest
  walk to the save point steps on it (`map34_dragon.txt`: `46 steps; via
  (22,20): True`); the route walks around it (48 steps) and fights it on
  purpose.
- **Lock objects are NPCs.** `route_data.py field-path` does not model NPCs
  and finds paths through the locked doors (`paths.txt`: 35 steps to the
  weapon shop's (32,31)).
- **The planner's search.** `route_data.py field-path` does not bound
  coordinates, so a target it cannot reach never returns (it ran past 5
  minutes and 10 GB before it was stopped, `field_path_unbounded.txt`);
  `paths.py` and `components.py` here bound them.
- **Scripted scenes:** the thaw before Tritoch (:84770-84784), the carving
  and Umaro's entrance (:110627-110704), the exit's slide (:84922). Each
  ends in a battle or player control.

## 10. Open questions (vision-level)

1. **Mog's Water Rondo.** It is WoB-missable by design (kits.md), and the
   route's MOG never learned it, so the arc where he joins has
   no divine for him. Keep it missable, or give the World of Ruin a way to
   learn it?
2. **Ragnarok.** LOCKE's lock decides when the stone arrives; the plan moves
   it to v0.32 (Locke). The stone-or-sword choice stays a player's choice
   there.

## 11. Played (v0.29)

The route plays the arc in two legs. Evidence is under
`build/attempts/wt/v029-narshe-route/`; the lab scripts beside the logs
(`make_kvariant.py`, `make_dragonlab.py`, `analyze_leg.py`,
`analyze_tritoch.py`, `mypath.py`).

### 11.1 The legs

- `gen_wor_narshe` (`wor-cyan-v1` -> `wor-narshe-cliffs-v1`): Jidoor's
  weapon counter (a Partisan, 13,000 GP) and item counter; Ifrit from SABIN
  to CYAN; the cabin seats CYAN, TERRA and CELES; Narshe, the elder's house,
  the moogle cave, MOG (named, joins into the empty seat); out through the
  elder's house, the town's north exit, the mines chain, the cliffs' west
  side to the save point.
- `gen_wor_tritoch` (`wor-narshe-cliffs-v1` -> `wor-narshe-v1`): armed for
  the ice and dressed once, the Ice Dragon, Tritoch, "Hop into it?", the
  X-Ether, the drop (14,30), the Gauntlet, the lair's floor (A held facing
  up), the carving (Terrato, Umaro), UMARO named and waiting aboard; out by
  the lair's slide, the mines and the town; the cabin seats UMARO, MOG,
  TERRA and CELES; Terrato on MOG, Tritoch on CELES (Maduin back in the
  bag); the Falcon lands at world (115,38) and the arc saves there.

### 11.2 What the walk learned

- **Doors in walls.** The elder's house door (32 (49,12)) is a wall tile
  entered by holding Up from (49,13); the route's `door()` walks onto a
  door when the planner reaches it and presses into it from below when not.
- **MOG's room is entered from the back.** Map 38's (49,21) door could not
  be entered from (49,22) (`dev/d3/run.log`: `no-effect: up for 320
  frames`); the route goes 38 (49,11) -> 37 -> (14,7) -> 44 (121,60), and out
  the same way.
- **Three of the plan's chests were opened in the World of Balance**: the
  elder's Elixir (bit $002) and the moogle cave's Pod Bracelet and Elixir
  ($00B, $00C share bits with the mines chase's chests) (`dev/d3`:
  `already open`). The route opens the Ribbon, the Moogle Charm, the X-Ether
  and the Gauntlet (`tools/chests_opened.txt`).
- **The Ice Dragon wanders** (`set_npc_movement RANDOM`): its object stood
  at (20,16), (17,18) and (16,20) in three runs. The touch reads its live
  tile; the walk up keeps to the cliffs' west side.
- **The mines' inner doors** (36 (113,45) -> (58,11), (57,21) -> (25,58),
  and back) are taken as warps the route detects by the party's tile
  jumping; the planner's radius cap needs waypoints on the longer walks
  (`mypath.py`, the plan's step model, bounded).
- **Relics are dressed once.** Dressing them again before Umaro, with the
  Gauntlet in the bag, planned a swap between two members that the relic
  rule cannot make from the bag (`dev/t4`: `a member's new relics are all
  in the bag (no swap deadlock)`). The library has no unequip, so the swap
  is left for later (section 11.7).
- **A lift-off and a landing on one tile** stalled the pilot one tile off
  it (`varA/tritoch_k2_s12.log`: `timeout after 6000 frames`); the arc's
  save is three tiles south of where the Falcon waited.

### 11.3 Break rows (built)

As proposed in section 4, with three changes: the Wizard takes slash as
well (2, slash|pierce|special: the moogle cave's Wizards meet CYAN, TERRA
and CELES before MOG joins, and none of them holds pierce or ¤), the Pugs
get a row (4, slash|special, the Pug's), and the Test Rider keeps pierce
alone on purpose: before MOG joins, the town's riders cannot be broken,
only worn down, and his spear is what breaks them after. Tritoch's
World of Ruin record `$144` has its row; `$114`/`$115` stay shieldless.
`battle_breakwor_narshe` checks every row, every species the arc's groups
can draw against the hands that meet it (the Test Rider before MOG is the
one declared exception), and the lessons (MOG's spear the Test Rider's only
key and the Ice Dragon's class key; each of the four keys Tritoch and
Umaro; every boss absorbs ice and is weak to fire): `PASS` on this ROM,
`got 65 ($41)` mismatches on main's, and three row mutants each red by name
(`rows/`).

**Tritoch's defense 254**: a 1-damage Fight chips. Without fire the party
broke it three times on Fight and took 485 of its 30,000 HP in 12,000
frames (`dev/t2`); the bosses are fought with fire.

### 11.4 The bosses

The driver casts fire at all three (TERRA's natural Fire at its tier; CYAN
and CELES once Ifrit and Maduin teach it), CELES's Runic and CYAN's
SwdTech on, and TERRA opens with **Trance** (`opts.trance`, new: her Morph
at 3 BP, which lasts the battle; her casts stay at base tier until the
bank holds three).

| set | the Ice Dragon | Tritoch | Umaro |
|---|---|---|---|
| no Trance, 10 shields (`varA/`, `dragonA/dragon10`) | 11 won, 1 lost of 12 (11 keys); 11 deaths; 5,423-20,615 ticks; Fenix 0-4 | 11 of 11, no deaths | 11 of 11, no deaths |
| no Trance, 6 shields (`dragonA/dragon6`, a lab ROM) | 12 of 12 (11 keys); 3 deaths; 4,743-12,782 ticks | -- | -- |
| Trance, 10 shields (`varB/`, the route) | 12 of 12 (10 keys); no deaths; broken in 12; 6,510-9,879 ticks; Potions 0-4 | 12 of 12 (10 keys); no deaths; broken in 12; 6,145-7,947 | 12 of 12 (12 keys); no deaths; broken in 12; 4,123-5,125 |

The Ice Dragon was the arc's attrition fight and a loss in one draw of
twelve (`varA/tritoch_s24.log`, `dragonA/dragon10_s24.log`: `GAME OVER
fired`). Spending TERRA's divine settles it, so its ten shields stay: the
win comes from the player's choice (guidelines.md, "What makes a fight
good"). Who breaks (`varB/who_breaks.txt`, the last party action before
each break): the Ice Dragon CYAN's Fire/Fire 2 4, TERRA 4, CELES's Fire 2 3,
MOG's Fight 1; Tritoch MOG's Fight 6, TERRA 3, CELES 3; Umaro TERRA 7,
CELES 3, CYAN 1, MOG 1. MOG lands half of Tritoch's breaks in the arc he
joins for.

**Short of "What makes a fight good"**: Tritoch and Umaro never threatened
the party in 23 fights (no deaths, at most 2 Potions); they are passages,
not contests, at L40-43. The Ice Dragon is a contest only without Trance.

### 11.5 The variation sets

Each leg twelve times from its tracked boot: eight seed shifts (0-28 by 4)
and K = 2 and 5 random battles used up before the body (outside Jidoor;
below the cliffs' save point), each at shifts 0 and 12; retries off.

- **`gen_wor_narshe`** (`varA/`): 12 of 12 pass (the first K runs walked
  to an unwalkable tile, `varA/failed1/`, and were rerun); `TOTAL battles
  178 (143 distinct keys), deaths 0` (`varA/analysis_narshe.txt`). MOG
  joins at L42; the save point holds TERRA 40-41, CYAN 39-40, CELES 41-42,
  MOG 42-43, and 91-97 Potions in the shift runs.
- **`gen_wor_tritoch`** (`varB/`, the route's generator): 12 of 12 pass;
  `TOTAL battles 148 (133 distinct keys), deaths 0`
  (`varB/analysis_leg.txt`); the bosses as in 11.4. `wor-narshe-v1` holds
  TERRA 41, CELES 42, MOG 43, UMARO 38 and 47-88 Potions; under the band
  (about 63 at L42) in one draw, so the next arc stocks up before its
  fights (Narshe sells nothing without LOCKE).

### 11.6 Retry sites

None in `varB/` or the leg-1 runs (`attempts=1/1` throughout). Before
Trance the Ice Dragon was the game-over risk (one wipe in twelve).

### 11.7 What was left

- **Mog's Water Rondo (#428).** The Serpent Trench can be re-entered in
  the World of Balance (the jump gates only on $0041) and its battles teach
  Water Rondo (`UNDERWATER`), but MOG is in the World of Balance party only
  through the Lone Wolf choice, in the airship era, and the dive ends in
  Nikeah, cut off on foot from where the airship has to be parked to reach
  Crescent Mountain (`428/findings.txt`). Not built; back to the
  coordinator.
- **Dance.** The driver has no Dance verb; MOG Fights.
- **The relic swap** (11.2): the relic rule needs an unequip to make a swap
  between two members.
- **Ragnarok** is v0.32 (finding 1).
