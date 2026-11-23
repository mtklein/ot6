# The opening under six weapon classes (#566)

The weapon weaknesses of every species the game deals from the Narshe mines
through the Narshe defense, then Kohlingen and Zozo, authored by hand for the
six classes (Sword, Dagger, Spear, Katana, Blunt, Ranged). The owner restarts
from zero on this release and judges the opening first: "the beginning of the
game is especially important to get right because of how limited your options
are" (2026-11-23).

- The rows are `tools/six_classes/pins.py`'s `OPENING` block, 85 species, each
  with its reason. `python3 tools/six_classes/split.py` writes them into
  `Ot6ShieldTbl` (`ff6/src/battle/ot6_hud.asm`); the masks are never edited
  by hand. They were applied with `--keep origin/wt/v051-six-classes`, which
  leaves every other row as that branch had it: the split's balance step
  reads a running tally, so without it dozens of rows nobody looked at move
  too (59 at the last run).
- The tables below are `python3 tools/six_classes/opening.py --md`, and the
  numbers `python3 tools/six_classes/opening.py`
  (`build/attempts/wt/v051-six-classes/opening/shares.txt`). The species of
  each area are decoded from the data (the maps' and World sectors' pools,
  the event battles, the monster-in-a-box chests), not listed by hand.
- No fight here was played: no emulator was used. What each row teaches is a
  design claim until the lead's replay and the owner's play say otherwise.

## Whose hands

A row is authored for the hands a **new player** holds when the game deals the
body: the weapon each character joins with (`ff6/src/field/char_prop.asm`),
then what the first shops sell.

| member | joins with | class | changes when |
|---|---|---|---|
| TERRA | Mithril Knife; Fire, Cure | Dagger | South Figaro's shop sells the first swords (Mithril Blade, RegalCutlass): Sword from Mt. Kolts on |
| LOCKE | Dirk; Steal, Filch, Bestow | Dagger | Trickshot (Dagger whatever he holds) from the Lete on; a sword is his by choice |
| MOG and ten moogles | pikes, flails, a brush, blades, a claw, boomerangs | all six | the defense only |
| EDGAR | Mithril Blade; the AutoCrossbow | Sword; Ranged by tool | Bio Blaster (poison), NoiseBlaster, Flash at Figaro; the first Mithril Pike on sale is Narshe's, before the defense; the Drill (Spear) at Figaro after the dive |
| SABIN | MetalKnuckle; Pummel; AuraBolt (level 6) | Blunt, hand and Blitz | Suplex at 10, Fire Dance at 15; the first Mithril Claw (Katana in hand) is Mobliz's |
| BANON | Punisher | Blunt | never |
| CELES | nothing in hand; Ice, Runic | Blunt (bare fists) until the player equips her | a spare sword from the bag: Sword |
| CYAN | Ashura; SwdTech | Katana | never in the opening |
| SHADOW (a hire) | Imperial; Throw | Dagger in hand | Ranged once Shurikens are bought (the merchant at the house where he is hired); Fire Skeans on the Phantom Train |
| GAU | his fangs; Rage | Dagger | never |

Three things follow that the class list alone does not show.

- **The first hour holds one weapon class.** TERRA's knife and LOCKE's dirk
  are both daggers. On main they were both pierce, and the Leafer and the
  Areneid (slash|bludgeon) took neither.
- **EDGAR holds no spear before Narshe.** He joins with a sword. The
  automated route gives him MOG's pike, taken off MOG in the moogle defense;
  a new player does not. No row before the Narshe defense asks for a Spear
  except the moogles' own fight.
- **SABIN lost a class.** His MetalKnuckle slashed on main (all claws did) and
  his Blitzes bludgeoned, so alone he held two of four. Now both are Blunt,
  until a claw from Mobliz's shop makes his Fight Katana.

The automated route's hands differ, and `shares.txt` gives its numbers beside
the new player's: TERRA keeps the knife to Mt. Kolts, LOCKE takes EDGAR's
Mithril Blade, EDGAR wields MOG's pike from Figaro on (it keys nothing before
Narshe under these rows: 15 of the route's 27 cave-and-plains fights are keyed
in hand, where four classes keyed 27), LOCKE wears a Genji Glove pair of
knives from his scenario, and SABIN buys his claw at Narshe. Its gear step
should choose by key under six classes: EDGAR keeps the Mithril Blade until
Narshe, TERRA takes a sword at South Figaro.

## The rules the rows follow

1. With one or two members the party holds a weapon key for most bodies, in
   hand. The stretches with one weapon class are listed in the walk-through.
2. A new member's class matters in the next fights: LOCKE's dagger at the
   Marshal, EDGAR's AutoCrossbow at the M-TekArmors, SABIN's fists on the way
   down Mt. Kolts, CYAN's katana in his duel, GAU's fangs in the trench.
3. No fight needs a class only a hired SHADOW holds.
4. Elements are the mage's lever and are not changed here.
5. A species keeps the number of weapon weaknesses it has on main, each a
   class its old weakness's weapons went to (`classes.py` `CHILDREN`), unless
   the hands that meet it argue otherwise. The departures are listed below.
6. Fliers take a point or a missile: Dagger or Ranged on the Dark Wind, the
   Hornet, the Cirpius and the Vulture, Sword or Ranged on the Pterodon,
   Katana or Ranged on the Beakor. The AutoCrossbow teaches it at Figaro.
7. Elements and classes together fit the HUD's four cells (elements are
   drawn first). One body cannot: the FossilFang, with four vanilla elements.

## The areas

"Keys" counts the area's gauged species the party can chip. "On main" is the
four-class row. `+` marks an element OT6 adds (`Ot6ElemAddTbl`).

### 1. The mines in Magitek armor

**TERRA, VICKS, WEDGE in armor.** TERRA (in armor: Fire, Bolt and Ice Beam, Bio Blast, TekMissile); VICKS (in armor: the three beams); WEDGE (in armor: the three beams). Holds: - in hand, Ranged by kit; elements: fire, ice, bolt, poison. Keys 4 of 4 species (0 in hand, 2 by kit, 4 by element); under four classes 4 (0 in hand). Each member's own keys: TERRA 4, VICKS 3, WEDGE 3.

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$000` Guard | 5 | 40 | 2 | Ranged | poison | pierce |
| `$019` Lobo | 5 | 27 | 3 | Dagger, Spear | fire | pierce |
| `$01B` Vomammoth | 1 | 115 | 2 | Sword, Blunt | fire | slash, bludg |
| `$100` Whelk | 4 | 50000 | no gauge | | | |
| `$134` Head | 6 | 1600 | 4 | Ranged | +fire | pierce |
| `$114` Tritoch | 19 | 12000 | no gauge | | | |

Formations: Guard x2 (battle 1); Lobo (battle 0); Lobo x2 (battle 2); Lobo + Guard x2 (battle 3); Vomammoth x2 + Guard x2 (battle 4); Whelk + Head (battle 64); Tritoch (battle 77).

Teaches: The beams end every fight in a hit; the shield and '?' cells are seen, not yet needed. The Whelk's head is the first break: three Fire Beams and a TekMissile.

### 2. TERRA alone, the mine shaft out of Narshe

**TERRA alone.** TERRA (Mithril Knife (she wakes with it); Fire, Cure). Holds: Dagger in hand; elements: fire. Keys 3 of 3 species (3 in hand, 3 by kit, 2 by element); under four classes 3 (3 in hand).

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$046` Vaporite | 5 | 15 | 1 | Dagger, Blunt | fire, holy; absorbs bolt | pierce, bludg |
| `$013` Were-Rat | 4 | 24 | 2 | Sword, Dagger | fire; absorbs poison | slash, pierce |
| `$04D` Repo Man | 5 | 35 | 2 | Sword, Dagger | poison | slash, pierce |

Formations: Vaporite x2 (map 50); Were-Rat x2 (map 50); Repo Man + Vaporite (map 50).

Teaches: One member, one weapon class: her knife keys every body. Fire keys two of the three; on the Repo Man it shows nothing, so the '?' is the knife's.

### 3. The moogle defense

**LOCKE's squad.** LOCKE (Dirk; Steal, Filch, Bestow); KUPEK (Mithril Pike); KUPOP (Morning Star); KUMAMA (Mithril Claw). Holds: Dagger, Spear, Katana, Blunt in hand; elements: -. Keys 3 of 3 species (3 in hand, 3 by kit, 0 by element); under four classes 3 (3 in hand). Each member's own keys: LOCKE 2, KUPEK 2, KUPOP 1, KUMAMA 0.

**MOG's squad.** MOG (Mithril Pike); KUKU (Flail); KUTAN (Mithril Blade); KUPAN (Full Moon). Holds: Sword, Spear, Blunt, Ranged in hand; elements: -. Keys 3 of 3 species (3 in hand, 3 by kit, 0 by element); under four classes 3 (3 in hand). Each member's own keys: MOG 2, KUKU 1, KUTAN 1, KUPAN 0.

**KUSHU's squad.** KUSHU (Chocobo Brush); KURIN (Mithril Pike); KURU (Mithril Blade); KAMOG (Boomerang). Holds: Sword, Spear, Blunt, Ranged in hand; elements: -. Keys 3 of 3 species (3 in hand, 3 by kit, 0 by element); under four classes 3 (3 in hand). Each member's own keys: KUSHU 1, KURIN 2, KURU 1, KAMOG 0.

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$01B` Vomammoth | 1 | 115 | 2 | Sword, Blunt | fire | slash, bludg |
| `$019` Lobo | 5 | 27 | 3 | Dagger, Spear | fire | pierce |
| `$064` Marshal | 8 | 420 | 4 | Dagger, Spear | poison | pierce |

Formations: Vomammoth + Lobo (battle 5); Lobo x2 + Marshal (battle 6).

Teaches: All six weapon icons are on the field at once and nobody has a spell: the Lobo takes points (the pikes, LOCKE's dirk), the Vomammoth swords and blows, and each squad holds a key to both. The Marshal is the first boss broken by weapons alone.

### 4. TERRA and LOCKE: the plains and the Figaro desert (and the school's practice chest)

**TERRA and LOCKE.** TERRA (Mithril Knife (she wakes with it); Fire, Cure); LOCKE (Dirk; Steal, Filch, Bestow). Holds: Dagger in hand; elements: fire. Keys 5 of 5 species (5 in hand, 5 by kit, 3 by element); under four classes 4 (3 in hand). Each member's own keys: TERRA 5, LOCKE 5.

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$017` Leafer | 5 | 33 | 2 | Sword, Dagger | fire, water; absorbs ice | slash, bludg |
| `$028` Dark Wind | 5 | 34 | 2 | Dagger, Ranged | fire | slash, pierce |
| `$05C` Sand Ray | 6 | 67 | 2 | Dagger | ice, water, +poison | slash, pierce |
| `$05D` Areneid | 6 | 87 | 2 | Dagger | ice, water, +poison | slash, bludg |
| `$019` Lobo | 5 | 27 | 3 | Dagger, Spear | fire | pierce |

Formations: Leafer (world group 0); Leafer x2 + Dark Wind (world group 0); Leafer x2 + Dark Wind x2 (world group 2); Sand Ray x2 (world group 1); Areneid x3 (world group 1); Sand Ray + Areneid x2 (world group 1); Sand Ray + Areneid x3 (world group 1); Lobo (chest, battle 0).

Teaches: Two members, still one weapon class. The daggers key every body; Fire keys the plains' two and neither of the desert's, where the knives carry it. LOCKE's Steal is his other turn.

### 5. Figaro Castle: the M-TekArmors

**TERRA, LOCKE, EDGAR.** TERRA (Mithril Knife (she wakes with it); Fire, Cure); LOCKE (Dirk; Steal, Filch, Bestow); EDGAR (Mithril Blade and the AutoCrossbow (he joins with both)). Holds: Sword, Dagger in hand, Ranged by kit; elements: fire. Keys 1 of 1 species (1 in hand, 1 by kit, 0 by element); under four classes 1 (1 in hand). Each member's own keys: TERRA 1, LOCKE 1, EDGAR 1.

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$042` M-TekArmor | 8 | 210 | 3 | Dagger, Ranged | bolt, +poison | pierce, bludg |

Formations: M-TekArmor x2 (battle 65).

Teaches: EDGAR's first fight: his sword does nothing to the armor and his AutoCrossbow chips both at once. The knives chip too; the Bio Blaster, if bought on the way out, is a second key.

### 6. The cave to South Figaro (and the desert at its mouth)

**TERRA, LOCKE, EDGAR.** TERRA (Mithril Knife (she wakes with it); Fire, Cure); LOCKE (Dirk; Steal, Filch, Bestow); EDGAR (Mithril Blade; AutoCrossbow; the Bio Blaster from Figaro's tool merchant). Holds: Sword, Dagger in hand, Ranged by kit; elements: fire, poison. Keys 5 of 5 species (5 in hand, 5 by kit, 5 by element); under four classes 5 (5 in hand). Each member's own keys: TERRA 5, LOCKE 4, EDGAR 4.

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$02E` Hornet | 6 | 92 | 1 | Dagger, Ranged | fire | slash, pierce |
| `$063` Bleary | 7 | 119 | 2 | Dagger | fire | pierce |
| `$062` Crawly | 7 | 122 | 2 | Sword, Blunt | fire | slash, bludg |
| `$05C` Sand Ray | 6 | 67 | 2 | Dagger | ice, water, +poison | slash, pierce |
| `$05D` Areneid | 6 | 87 | 2 | Dagger | ice, water, +poison | slash, bludg |

Formations: Hornet x2 (map 72); Bleary x2 + Crawly (map 72); Crawly x3 (map 72); Hornet x2 + Bleary x3 (map 73); Hornet + Crawly x2 (map 73); Sand Ray x2 (world group 1); Areneid x3 (world group 1); Sand Ray + Areneid x2 (world group 1); Sand Ray + Areneid x3 (world group 1).

Teaches: The first place the cell picks the target: the eye takes the knives, the worm EDGAR's blade, the hornets anyone's point or the sweep. Fire burns all three.

### 7. The plains round South Figaro

**The three, before the shop.** TERRA (Mithril Knife (she wakes with it); Fire, Cure); LOCKE (Dirk; Steal, Filch, Bestow); EDGAR (Mithril Blade; AutoCrossbow; the Bio Blaster from Figaro's tool merchant). Holds: Sword, Dagger in hand, Ranged by kit; elements: fire, poison. Keys 3 of 3 species (2 in hand, 3 by kit, 3 by element); under four classes 3 (3 in hand). Each member's own keys: TERRA 2, LOCKE 2, EDGAR 3.

**The three, TERRA with a sword.** TERRA (a sword from South Figaro's shop; Fire, Cure). Holds: Sword, Dagger in hand, Ranged by kit; elements: fire, poison. Keys 3 of 3 species (2 in hand, 3 by kit, 3 by element); under four classes 3 (3 in hand). Each member's own keys: TERRA 1, LOCKE 2, EDGAR 3.

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$0A8` GreaseMonk | 8 | 132 | 2 | Dagger, Blunt | poison | pierce, bludg |
| `$012` Rhodox | 7 | 119 | 2 | Sword, Dagger | +poison | slash, pierce |
| `$015` Rhinotaur | 8 | 232 | 2 | Blunt, Ranged | +poison; absorbs bolt | pierce, bludg |

Formations: GreaseMonk x2 (world group 3); Rhodox x2 + GreaseMonk (world group 3); Rhinotaur (world group 3); Rhinotaur + Rhodox x2 (world group 4); Rhinotaur + GreaseMonk + Rhodox x2 (world group 4); Rhodox x4 (world group 4).

Teaches: No body here is weak to fire: the Bio Blaster is the element (all three), the Rhodox is everybody's, the GreaseMonk the dagger's, the Rhinotaur the crossbow's.

### 8. Mt. Kolts and Vargas

**TERRA, LOCKE, EDGAR.** TERRA (a sword from South Figaro's shop; Fire, Cure); LOCKE (Dirk; Steal, Filch, Bestow); EDGAR (Mithril Blade; AutoCrossbow; the Bio Blaster from Figaro's tool merchant). Holds: Sword, Dagger in hand, Ranged by kit; elements: fire, poison. Keys 7 of 7 species (5 in hand, 5 by kit, 6 by element); under four classes 7 (5 in hand). Each member's own keys: TERRA 5, LOCKE 3, EDGAR 6.

**With SABIN, from the summit down.** SABIN (MetalKnuckle; Pummel, AuraBolt (level 6)). Holds: Sword, Dagger, Blunt in hand, Ranged by kit; elements: fire, poison, holy. Keys 7 of 7 species (6 in hand, 6 by kit, 6 by element); under four classes 7 (5 in hand). Each member's own keys: TERRA 5, LOCKE 3, EDGAR 6, SABIN 3.

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$086` Cirpius | 10 | 134 | 2 | Dagger, Ranged | +poison | pierce |
| `$07A` Tusker | 10 | 270 | 2 | - | fire, +poison | - |
| `$032` Trilium | 9 | 147 | 2 | Sword, Dagger | fire; absorbs water | slash, pierce |
| `$00B` Brawler | 9 | 137 | 2 | Sword, Blunt | ice; absorbs poison | slash |
| `$046` Vaporite | 5 | 15 | 1 | Dagger, Blunt | fire, holy; absorbs bolt | pierce, bludg |
| `$103` Vargas | 12 | 11600 | 5 | Blunt | poison, +holy | bludg |
| `$14D` Ipooh | 11 | 360 | 2 | Sword | fire | slash |

Formations: Cirpius x3 (map 96); Tusker + Cirpius x3 (map 96); Trilium + Tusker + Cirpius x2 (map 98); Trilium x2 (map 98); Brawler x2 (map 100); Tusker x2 (map 100); Brawler + Trilium + Vaporite x2 (map 101); Vargas + Ipooh x2 (battle 66).

Teaches: TERRA's new sword and her Fire carry the mountain; the Tusker has no weapon weakness at all (Fire or the Bio Blaster); the fliers fall to the dagger or the sweep. Vargas cannot be broken until SABIN arrives: Pummel, his MetalKnuckle and AuraBolt.

### 8b. The Returners' side of Mt. Kolts, SABIN's first walk

**TERRA, LOCKE, EDGAR, SABIN.** TERRA (a sword from South Figaro's shop; Fire, Cure); LOCKE (Dirk; Steal, Filch, Bestow); EDGAR (Mithril Blade; AutoCrossbow; the Bio Blaster from Figaro's tool merchant); SABIN (MetalKnuckle; Pummel, AuraBolt (level 6)). Holds: Sword, Dagger, Blunt in hand, Ranged by kit; elements: fire, poison, holy. Keys 7 of 7 species (6 in hand, 6 by kit, 6 by element); under four classes 7 (6 in hand). Each member's own keys: TERRA 5, LOCKE 4, EDGAR 6, SABIN 4.

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$00B` Brawler | 9 | 137 | 2 | Sword, Blunt | ice; absorbs poison | slash |
| `$07A` Tusker | 10 | 270 | 2 | - | fire, +poison | - |
| `$032` Trilium | 9 | 147 | 2 | Sword, Dagger | fire; absorbs water | slash, pierce |
| `$046` Vaporite | 5 | 15 | 1 | Dagger, Blunt | fire, holy; absorbs bolt | pierce, bludg |
| `$0A8` GreaseMonk | 8 | 132 | 2 | Dagger, Blunt | poison | pierce, bludg |
| `$015` Rhinotaur | 8 | 232 | 2 | Blunt, Ranged | +poison; absorbs bolt | pierce, bludg |
| `$012` Rhodox | 7 | 119 | 2 | Sword, Dagger | +poison | slash, pierce |

Formations: Brawler x2 (map 100); Tusker x2 (map 100); Brawler + Trilium + Vaporite x2 (map 101); GreaseMonk x2 (world group 5); Rhinotaur + Rhodox x2 (world group 5); Rhodox x2 + GreaseMonk (world group 5).

Teaches: SABIN's Blunt matters the day he joins: the Vaporite, the GreaseMonk and the Rhinotaur take his fists.

### 9. The Lete River and Ultros

**TERRA, EDGAR, SABIN, BANON.** TERRA (a sword from South Figaro's shop; Fire, Cure); EDGAR (Mithril Blade; AutoCrossbow; the Bio Blaster from Figaro's tool merchant); SABIN (MetalKnuckle; Pummel, AuraBolt (level 6)); BANON (Punisher (a rod); Health). Holds: Sword, Blunt in hand, Ranged by kit; elements: fire, poison, holy. Keys 4 of 4 species (4 in hand, 4 by kit, 4 by element); under four classes 4 (4 in hand). Each member's own keys: TERRA 4, EDGAR 4, SABIN 2, BANON 2.

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$038` Nautiloid | 11 | 236 | 2 | Blunt, Ranged | fire, bolt; absorbs water | pierce, bludg |
| `$039` Exocite | 11 | 196 | 2 | Sword, Blunt | fire, bolt; absorbs water | slash, bludg |
| `$022` Pterodon | 12 | 380 | 2 | Sword, Ranged | fire | slash, pierce |
| `$12C` Ultros | 13 | 3000 | 5 | Sword, Ranged | fire, bolt; absorbs water | slash, pierce |

Formations: Nautiloid + Exocite (battle 7); Pterodon + Exocite x2 (battle 7); Pterodon x2 (battle 8); Nautiloid + Exocite + Pterodon (battle 8); Ultros (battle 103).

Teaches: Each hand keys two of the raft's three: TERRA's blade, EDGAR's bolts, the fists and BANON's rod. Ultros takes the swords, the AutoCrossbow and Fire; SABIN and BANON hit and heal.

### 10a. TERRA's scenario: the raft, Narshe's mines and the back way

**TERRA, EDGAR, BANON.** TERRA (a sword from South Figaro's shop; Fire, Cure); EDGAR (Mithril Blade; AutoCrossbow; the Bio Blaster from Figaro's tool merchant); BANON (Punisher (a rod); Health). Holds: Sword, Blunt in hand, Ranged by kit; elements: fire, poison. Keys 13 of 13 species (12 in hand, 13 by kit, 13 by element); under four classes 13 (12 in hand). Each member's own keys: TERRA 12, EDGAR 12, BANON 6.

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$013` Were-Rat | 4 | 24 | 2 | Sword, Dagger | fire; absorbs poison | slash, pierce |
| `$04D` Repo Man | 5 | 35 | 2 | Sword, Dagger | poison | slash, pierce |
| `$0EF` 1st Class | 11 | 180 | 2 | Blunt, Ranged | poison | pierce, bludg |
| `$0F4` Wild Rat | 12 | 160 | 2 | Sword, Dagger | fire; absorbs poison | slash, pierce |
| `$046` Vaporite | 5 | 15 | 1 | Dagger, Blunt | fire, holy; absorbs bolt | pierce, bludg |
| `$017` Leafer | 5 | 33 | 2 | Sword, Dagger | fire, water; absorbs ice | slash, bludg |
| `$028` Dark Wind | 5 | 34 | 2 | Dagger, Ranged | fire | slash, pierce |
| `$038` Nautiloid | 11 | 236 | 2 | Blunt, Ranged | fire, bolt; absorbs water | pierce, bludg |
| `$039` Exocite | 11 | 196 | 2 | Sword, Blunt | fire, bolt; absorbs water | slash, bludg |
| `$022` Pterodon | 12 | 380 | 2 | Sword, Ranged | fire | slash, pierce |
| `$060` Dark Side | 13 | 255 | 2 | Sword, Ranged | fire, holy; absorbs poison | slash, special |
| `$0B6` Spectre | 13 | 235 | 2 | Blunt, Ranged | fire, holy; absorbs poison | bludg, special |
| `$0CF` Rinn | 11 | 110 | 1 | Blunt, Ranged | fire, holy; absorbs poison | pierce, special |

Formations: Were-Rat x3 (map 41); Were-Rat + Repo Man (map 41); 1st Class + Wild Rat (map 48); 1st Class x3 (map 48); Wild Rat x3 + 1st Class x2 (map 48); Vaporite x2 (map 50); Were-Rat x2 (map 50); Repo Man + Vaporite (map 50); Leafer (world group 0); Leafer x2 + Dark Wind (world group 0); Leafer x2 + Dark Wind x2 (world group 2); Nautiloid + Exocite (battle 7); Pterodon + Exocite x2 (battle 7); Pterodon x2 (battle 8); Nautiloid + Exocite + Pterodon (battle 8); Dark Side x2 (battle 38); Dark Side + Spectre + Rinn x3 (battle 38).

Teaches: Three hands, three classes. The checkpoint's trap is the lesson in elements: all three bodies burn and all three drink the Bio Blaster's poison.

### 10b. LOCKE's scenario, alone in South Figaro

**LOCKE alone.** LOCKE (a dagger; Steal, Filch, Bestow, Trickshot (from the Lete on)). Holds: Dagger in hand; elements: -. Keys 3 of 3 species (3 in hand, 3 by kit, 0 by element); under four classes 3 (3 in hand).

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$13A` Merchant | 5 | 119 | 2 | Dagger | - | pierce |
| `$175` Officer | 7 | 102 | 2 | Dagger | poison | pierce |
| `$09F` HeavyArmor | 13 | 495 | 3 | Dagger | bolt, water, +poison | slash, pierce |

Formations: Merchant (battle 10); Officer (battle 9); HeavyArmor (battle 11).

Teaches: One member, one class, and every body takes it. Steal is the scenario's verb.

### 10b2. LOCKE and CELES: the basement, the cave, TunnelArmor

**LOCKE and CELES (a blade for her).** LOCKE (a dagger; Steal, Filch, Bestow, Trickshot (from the Lete on)); CELES (a spare Mithril Blade (she joins unarmed); Ice, Cure, Runic). Holds: Sword, Dagger in hand; elements: ice. Keys 10 of 10 species (10 in hand, 10 by kit, 3 by element); under four classes 10 (10 in hand). Each member's own keys: LOCKE 8, CELES 8.

**LOCKE and CELES (unarmed, as she joins).** CELES (bare hands, as she joins; Ice, Runic). Holds: Dagger, Blunt in hand; elements: ice. Keys 10 of 10 species (10 in hand, 10 by kit, 3 by element); under four classes 10 (10 in hand). Each member's own keys: LOCKE 8, CELES 6.

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$071` Vector Pup | 11 | 166 | 2 | Sword, Dagger | fire | slash, pierce |
| `$011` Commander | 10 | 102 | 2 | Sword, Dagger | poison | slash, pierce |
| `$036` Trilobiter | 12 | 150 | 2 | Dagger, Blunt | - | pierce, bludg |
| `$094` Primordite | 11 | 145 | 2 | Sword, Blunt | bolt | slash, bludg |
| `$0F5` Gold Bear | 13 | 275 | 3 | Sword, Blunt | - | slash, bludg |
| `$05C` Sand Ray | 6 | 67 | 2 | Dagger | ice, water, +poison | slash, pierce |
| `$05D` Areneid | 6 | 87 | 2 | Dagger | ice, water, +poison | slash, bludg |
| `$017` Leafer | 5 | 33 | 2 | Sword, Dagger | fire, water; absorbs ice | slash, bludg |
| `$028` Dark Wind | 5 | 34 | 2 | Dagger, Ranged | fire | slash, pierce |
| `$104` TunnelArmr | 16 | 1300 | 5 | Dagger | bolt, water, +ice | pierce |

Formations: Vector Pup x2 (map 87); Vector Pup x2 + Commander (map 87); Commander x3 (map 87); Trilobiter + Primordite x2 (map 69); Primordite x2 (map 69); Gold Bear + Primordite (map 69); Trilobiter x3 (map 69); Sand Ray x2 (world group 1); Areneid x3 (world group 1); Sand Ray + Areneid x2 (world group 1); Sand Ray + Areneid x3 (world group 1); Leafer (world group 0); Leafer x2 + Dark Wind (world group 0); Leafer x2 + Dark Wind x2 (world group 2); TunnelArmr (battle 67).

Teaches: The two hands split the cave: the soldiers and the hounds take both, the shell LOCKE's point (or her bare hands), the soft body and the bear her blade. TunnelArmor: his dagger and Trickshot, her Ice, and Runic for the quake.

### 10c. SABIN's scenario: east of the Lete

**SABIN alone.** SABIN (MetalKnuckle; Pummel, AuraBolt (level 6)). Holds: Blunt in hand; elements: holy. Keys 3 of 4 species (3 in hand, 3 by kit, 0 by element); under four classes 4 (3 in hand).

**SABIN and a hired SHADOW.** SHADOW (Imperial; Throw, with the Shurikens the house's merchant sells). Holds: Dagger, Blunt in hand, Ranged by kit; elements: holy. Keys 4 of 4 species (3 in hand, 4 by kit, 0 by element); under four classes 4 (4 in hand). Each member's own keys: SABIN 3, SHADOW 3.

**With CYAN, on the way to the forest.** CYAN (Ashura; SwdTech). Holds: Katana, Blunt in hand; elements: holy. Keys 4 of 4 species (4 in hand, 4 by kit, 0 by element); under four classes 4 (3 in hand). Each member's own keys: SABIN 3, CYAN 2.

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$076` Rhobite | 10 | 135 | 3 | Katana, Blunt | water | slash, bludg |
| `$029` Beakor | 11 | 290 | 3 | Katana, Ranged | fire | slash, pierce |
| `$02F` CrassHoppr | 11 | 243 | 3 | Dagger, Blunt | fire, wind | pierce, bludg |
| `$018` Stray Cat | 10 | 156 | 3 | Dagger, Blunt | +poison | slash, pierce |

Formations: Rhobite x3 (world group 6); Beakor + Rhobite x2 (world group 6); Beakor (world group 6); CrassHoppr x2 + Stray Cat x2 (world group 7); Rhobite x5 (world group 7); Beakor x2 + Stray Cat (world group 7); Beakor + Stray Cat + CrassHoppr x2 (world group 7); Stray Cat x3 (world group 8); CrassHoppr x3 (world group 8).

Teaches: One member, one class: fists key three of the four bodies. The Beakor is out of his reach, a flier for a thrown star or, later, CYAN's katana.

### 10c2. The Imperial camp and Doma

**SABIN alone.** SABIN (MetalKnuckle; Pummel, AuraBolt (level 6)). Holds: Blunt in hand; elements: holy. Keys 6 of 7 species (6 in hand, 6 by kit, 0 by element); under four classes 5 (4 in hand).

**SABIN and a hired SHADOW.** SHADOW (Imperial; Throw, with the Shurikens the house's merchant sells). Holds: Dagger, Blunt in hand, Ranged by kit; elements: holy. Keys 6 of 7 species (6 in hand, 6 by kit, 0 by element); under four classes 7 (6 in hand). Each member's own keys: SABIN 6, SHADOW 2.

**CYAN alone (his duel: the Soldiers, the Leader).** CYAN (Ashura; SwdTech). Holds: Katana in hand; elements: -. Keys 4 of 7 species (4 in hand, 4 by kit, 0 by element); under four classes 4 (4 in hand).

**SABIN and CYAN.** Holds: Katana, Blunt in hand; elements: holy. Keys 7 of 7 species (7 in hand, 7 by kit, 0 by element); under four classes 5 (4 in hand). Each member's own keys: SABIN 6, CYAN 4.

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$002` Templar | 11 | 205 | 3 | Dagger, Blunt | poison, +bolt | pierce |
| `$01A` Doberman | 12 | 465 | 2 | Dagger, Blunt | fire | pierce |
| `$001` Soldier | 11 | 100 | 2 | Katana, Blunt | poison | slash, pierce |
| `$14E` Leader | 12 | 456 | 3 | Katana | - | slash |
| `$14F` Grunt | 12 | 100 | 2 | Katana, Blunt | - | slash, bludg |
| `$176` Cadet | 13 | 380 | 3 | Katana, Blunt | poison | slash, bludg |
| `$044` Telstar | 14 | 1800 | 4 | Blunt | bolt, water | bludg |

Formations: Templar x2 (battle 12); Doberman x3 (battle 12); Doberman x2 (battle 42); Templar x2 + Soldier x2 (battle 44); Soldier x2 (battle 43); Leader (battle 46); Grunt x3 (battle 13); Grunt x4 (battle 13); Cadet + Grunt x2 (battle 14); Telstar (chest, battle 32).

Teaches: Everything in the camp takes a blow, so SABIN alone always holds the key; SHADOW's blade keys the Templars and the dogs, CYAN's katana the infantry. No body here needs the hire.

### 10c3. The Phantom Forest and the Phantom Train

**SABIN and CYAN.** SABIN (MetalKnuckle; Pummel, AuraBolt (level 6)); CYAN (Ashura; SwdTech). Holds: Katana, Blunt in hand; elements: holy. Keys 10 of 10 species (10 in hand, 10 by kit, 8 by element); under four classes 10 (9 in hand). Each member's own keys: SABIN 9, CYAN 9.

**With SHADOW.** SHADOW (Imperial; Throw, with the Shurikens the house's merchant sells). Holds: Dagger, Katana, Blunt in hand, Ranged by kit; elements: holy. Keys 10 of 10 species (10 in hand, 10 by kit, 8 by element); under four classes 10 (9 in hand). Each member's own keys: SABIN 9, CYAN 9, SHADOW 4.

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$05A` Ghost | 10 | 226 | 3 | Katana, Blunt | fire, holy; absorbs poison | slash, special |
| `$0A2` Poplium | 11 | 145 | 3 | Dagger, Katana | fire, holy; absorbs poison | slash, pierce |
| `$00E` Whisper | 12 | 230 | 2 | Katana, Blunt | fire, holy; absorbs poison | slash, special |
| `$008` Hazer | 12 | 120 | 2 | Katana, Blunt | holy | slash, special |
| `$04F` Bomb | 8 | 160 | 3 | Katana, Ranged | ice, water; absorbs fire | slash, bludg |
| `$0BA` StillGoing | 12 | 200 | 2 | Katana, Blunt | fire, holy; absorbs poison | slash, bludg |
| `$00F` Over-Mind | 13 | 390 | 2 | Katana, Ranged | fire, holy; absorbs poison | slash, special |
| `$131` Siegfried | 7 | 100 | 1 | Dagger, Katana, Blunt | - | slash, pierce, bludg |
| `$106` GhostTrain | 14 | 1900 | 4 | Blunt | fire, bolt, holy; absorbs poison | bludg |
| `$156` Specter | 19 | 1500 | 3 | Katana, Blunt | fire, holy; absorbs poison | slash, special |

Formations: Ghost (map 130); Ghost + Poplium x2 (map 130); Ghost x3 (map 134); Ghost x2 + Poplium x3 (map 134); Whisper x2 + Hazer (map 141); Whisper x4 (map 141); Bomb (map 141); Bomb x3 (map 141); Whisper (map 145); StillGoing x3 (map 145); Whisper + Hazer x3 (map 145); Over-Mind x2 (map 149); Over-Mind + StillGoing x2 (map 149); Bomb x2 + Hazer x2 (map 151); Whisper + StillGoing + Hazer x2 (map 151); Siegfried (battle 109); GhostTrain (battle 68); Specter (chest, battle 34).

Teaches: CYAN's katana keys every body but the train itself; AuraBolt's holy keys all but the Bomb. The GhostTrain takes only blows (and fire, bolt, holy): CYAN waits for the break his Cleave needs.

### 10c4. Baren Falls and the Serpent Trench

**SABIN and CYAN (the falls).** SABIN (MetalKnuckle; Pummel, AuraBolt (level 6)); CYAN (Ashura; SwdTech). Holds: Katana, Blunt in hand; elements: holy. Keys 4 of 5 species (4 in hand, 4 by kit, 0 by element); under four classes 5 (3 in hand). Each member's own keys: SABIN 3, CYAN 3.

**SABIN, CYAN, GAU (the trench), SABIN with Mobliz's claw.** SABIN (a Mithril Claw (Mobliz's or Narshe's shop); Pummel, Suplex, AuraBolt); GAU (his fangs; Rage). Holds: Dagger, Katana in hand, Blunt by kit; elements: holy. Keys 5 of 5 species (4 in hand, 5 by kit, 0 by element); under four classes 5 (5 in hand). Each member's own keys: SABIN 4, CYAN 3, GAU 1.

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$154` Piranha | 9 | 10 | 1 | Katana, Blunt | bolt | slash, bludg |
| `$05E` Actaneon | 12 | 230 | 2 | Blunt | fire, bolt; absorbs water | bludg |
| `$03A` Anguiform | 13 | 315 | 2 | Katana | bolt; absorbs water | slash |
| `$059` Aspik | 12 | 220 | 2 | Dagger | fire; absorbs water | bludg |
| `$155` Rizopas | 13 | 775 | 4 | Katana, Blunt | bolt; absorbs water | slash, bludg |

Formations: Piranha x2 (battle 18); Actaneon x3 (battle 19); Anguiform (battle 19); Anguiform + Actaneon + Aspik (battle 20); Anguiform x2 (battle 21); Actaneon x3 + Aspik x2 (battle 21).

Teaches: The falls take both hands. The trench is three aquatics, three keys, one a member: CYAN's katana, SABIN's Blitzes, GAU's fangs.

### 11. The Narshe defense and Kefka

**All seven.** TERRA (a sword from South Figaro's shop; Fire, Cure); LOCKE (a dagger; Steal, Filch, Bestow, Trickshot (from the Lete on)); EDGAR (the Mithril Pike Narshe's shop sells before the defense; AutoCrossbow; Bio Blaster); SABIN (a Mithril Claw (Mobliz's or Narshe's shop); Pummel, Suplex, AuraBolt); CYAN (Ashura; SwdTech); GAU (his fangs; Rage); CELES (a spare Mithril Blade (she joins unarmed); Ice, Cure, Runic). Holds: Sword, Dagger, Spear, Katana in hand, Blunt, Ranged by kit; elements: fire, ice, poison, holy. Keys 6 of 6 species (6 in hand, 6 by kit, 6 by element); under four classes 6 (6 in hand). Each member's own keys: TERRA 5, LOCKE 6, EDGAR 4, SABIN 4, CYAN 4, GAU 6, CELES 4.

**A squad as the scenarios ended: TERRA, EDGAR.** Holds: Sword, Spear in hand, Ranged by kit; elements: fire, poison. Keys 6 of 6 species (4 in hand, 4 by kit, 6 by element); under four classes 6 (6 in hand). Each member's own keys: TERRA 5, EDGAR 4.

**A squad as the scenarios ended: LOCKE, CELES.** Holds: Sword, Dagger in hand; elements: ice. Keys 6 of 6 species (6 in hand, 6 by kit, 0 by element); under four classes 6 (6 in hand). Each member's own keys: LOCKE 6, CELES 4.

**A squad as the scenarios ended: SABIN, CYAN, GAU.** Holds: Dagger, Katana in hand, Blunt by kit; elements: holy. Keys 6 of 6 species (6 in hand, 6 by kit, 0 by element); under four classes 6 (6 in hand). Each member's own keys: SABIN 4, CYAN 4, GAU 6.

**The automated route's party 1: TERRA, EDGAR, CELES.** Holds: Sword, Spear in hand, Ranged by kit; elements: fire, ice, poison. Keys 6 of 6 species (4 in hand, 4 by kit, 6 by element); under four classes 6 (6 in hand). Each member's own keys: TERRA 5, EDGAR 4, CELES 4.

**The automated route's party 2: LOCKE, GAU.** Holds: Dagger in hand; elements: -. Keys 6 of 6 species (6 in hand, 6 by kit, 0 by element); under four classes 6 (6 in hand). Each member's own keys: LOCKE 6, GAU 6.

**The automated route's party 3: CYAN, SABIN (bare fists).** SABIN. Holds: Katana, Blunt in hand; elements: holy. Keys 4 of 6 species (4 in hand, 4 by kit, 0 by element); under four classes 6 (6 in hand). Each member's own keys: CYAN 4, SABIN 0.

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$065` Trooper | 13 | 255 | 2 | Sword, Dagger, Katana | poison | slash, pierce |
| `$079` Bounty Man | 13 | 285 | 2 | Sword, Dagger, Katana | fire | slash, pierce |
| `$01C` Fidor | 13 | 355 | 2 | Sword, Dagger, Katana | fire | slash, pierce |
| `$09F` HeavyArmor | 13 | 495 | 3 | Dagger | bolt, water, +poison | slash, pierce |
| `$03F` Rider | 14 | 1300 | 3 | Dagger, Katana | fire, poison | slash, pierce |
| `$14A` Kefka | 18 | 3000 | 6 | Sword, Dagger | +fire, +poison | slash, pierce |

Formations: Trooper x4 (battle 22); Bounty Man + Trooper x2 (battle 22); Fidor + Trooper (battle 23); HeavyArmor + Trooper x2 (battle 23); Rider (battle 24); Kefka (battle 57).

Teaches: The player forms three squads from seven without seeing the enemy, so one row serves the raiders: swords, daggers and fangs, the katana. The Rider takes the dagger and the katana, Kefka the sword and the dagger, and both Fire and poison: his four cells are full, and the katana has none.

### 12. Kohlingen, the plains and Zozo, with Dadaluma

**All six.** LOCKE (a dagger; Steal, Filch, Bestow, Trickshot (from the Lete on)); EDGAR (Mithril Pike; AutoCrossbow, the Drill (Figaro, after the dive); Bio Blaster); SABIN (a Mithril Claw; Pummel, Suplex, AuraBolt, Fire Dance (level 15)); CYAN (Ashura; SwdTech); GAU (his fangs; Rage); CELES (a spare Mithril Blade (she joins unarmed); Ice, Cure, Runic). Holds: Sword, Dagger, Spear, Katana in hand, Blunt, Ranged by kit; elements: fire, ice, poison, holy. Keys 13 of 13 species (11 in hand, 13 by kit, 11 by element); under four classes 13 (13 in hand). Each member's own keys: LOCKE 5, EDGAR 12, SABIN 8, CYAN 3, GAU 5, CELES 6.

| species | L | HP | shields | weapon weaknesses | elements | on main (four classes) |
|---|---|---|---|---|---|---|
| `$0DF` Gabbldegak | 15 | 350 | 2 | Dagger, Ranged | poison | pierce |
| `$04E` Harvester | 16 | 428 | 2 | Sword, Spear | poison | slash, pierce |
| `$053` HadesGigas | 16 | 1200 | 2 | Blunt, Ranged | poison; absorbs earth | bludg |
| `$052` SlamDancer | 15 | 392 | 2 | Sword, Katana | poison | slash, pierce |
| `$078` Red Fang | 14 | 325 | 2 | Spear, Katana | +poison | slash, pierce |
| `$02A` Vulture | 15 | 412 | 2 | Dagger, Ranged | wind | pierce |
| `$06C` Iron Fist | 15 | 333 | 2 | Blunt, Ranged | -; absorbs poison | pierce, bludg |
| `$08C` Mind Candy | 15 | 290 | 2 | Sword, Ranged | fire, wind | slash, special |
| `$090` Over Grunk | 15 | 492 | 3 | Katana, Blunt | fire | slash, bludg |
| `$023` FossilFang | 20 | 1399 | 3 | Spear, Blunt | fire, ice, holy, water; absorbs poison | pierce, bludg |
| `$05C` Sand Ray | 6 | 67 | 2 | Dagger | ice, water, +poison | slash, pierce |
| `$05D` Areneid | 6 | 87 | 2 | Dagger | ice, water, +poison | slash, bludg |
| `$107` Dadaluma | 22 | 3270 | 6 | Dagger, Blunt | poison | pierce, bludg |

Formations: Gabbldegak x4 (map 221); Harvester + Gabbldegak x2 (map 221); HadesGigas (map 221); HadesGigas + Harvester (map 221); SlamDancer (map 225); Harvester (map 225); SlamDancer + Harvester x2 (map 225); SlamDancer + Gabbldegak x3 (map 225); Red Fang x2 (world group 9); Red Fang x2 + Vulture (world group 9); Vulture x2 (world group 9); Vulture + Iron Fist (world group 10); Mind Candy x4 (world group 10); Iron Fist x2 + Mind Candy x2 (world group 10); Over Grunk + Vulture + Iron Fist (world group 11); Over Grunk x2 + Mind Candy x3 (world group 11); FossilFang (world group 12); Sand Ray x2 (world group 12); Sand Ray + Areneid x2 (world group 12); Dadaluma (battle 69).

Teaches: The first free party. EDGAR's tools reach almost everything (the sweep, the new Drill, the Bio Blaster); each other member keys about a third by hand, so the pick is a real choice. Dadaluma takes the dagger, a blow or poison, and every pick of four holds one.

## The walk-through: what a new player gains, in order, and what rewards it

1. **Magitek armor: three beams, and TERRA's TekMissile (Ranged) and Bio
   Blast (poison).** Every body falls to one beam. Fire Beam turns the Lobo's
   and the Vomammoth's '?' into fire; TekMissile or Bio Blast turns the
   Guard's. VICKS and WEDGE hold nothing that chips a Guard, as on main (see
   the proposals). The Whelk's head (4 shields; fire, Ranged) is the first
   break: three Fire Beams and a TekMissile.
2. **TERRA wakes: a dagger, and Fire.** *One weapon class.* The Were-Rat and
   the Vaporite take both; the Repo Man takes the knife and not Fire.
3. **LOCKE: a second dagger, and Steal. The moogles: every class.** Each squad
   holds a pike and a flail or brush; two hold a sword. The Lobo takes points,
   the Vomammoth swords and blows, the Marshal points: LOCKE's dirk chips the
   boss, as it did on main.
4. **The school** (optional, at Narshe's gate): the weapon advisor names the
   six types. The chest beside the practice advisor holds one Lobo: the
   daggers and Fire all key it.
5. **The plains and the desert, TERRA and LOCKE.** *One weapon class, two
   members.* All four bodies take a dagger. Fire keys the Leafer and the Dark
   Wind and neither desert body (ice, water, and a poison nobody has yet).
6. **EDGAR: Sword in hand, Ranged by AutoCrossbow; Figaro sells the Bio
   Blaster (poison).** The M-TekArmors (Dagger, Ranged; bolt, +poison) shrug
   off his sword and take his crossbow's sweep, and the knives. The Bio
   Blaster then keys both desert bodies and all three on South Figaro's
   plains.
7. **The cave.** The Bleary takes the knives, the Crawly EDGAR's blade, the
   Hornet a dagger or the sweep, and Fire burns all three. LOCKE has no key
   on the Crawly and EDGAR none on the Bleary.
8. **South Figaro's shop: a sword for TERRA.** On the plains it keys the
   Rhodox only; LOCKE's dagger keys the Rhodox and the GreaseMonk; the
   Rhinotaur is EDGAR's (the crossbow, the Bio Blaster). On Mt. Kolts the
   sword keys the Trilium, the Brawler and the Ipoohs, and Fire the Tusker
   (no weapon weakness), the Trilium, the Vaporite and the Ipoohs.
9. **SABIN: Blunt, and holy.** Vargas (Blunt; poison, +holy) takes his
   Pummel, his MetalKnuckle and AuraBolt. On the way down the Brawler and
   the Vaporite take his fists, on the plains the GreaseMonk and the
   Rhinotaur, on the raft the Nautiloid and the Exocite.
10. **BANON: a rod (Blunt). The Lete.** TERRA's blade, EDGAR's bolts, and the
    two blunt hands each key two of the raft's three. Ultros (Sword, Ranged;
    fire, bolt) is TERRA's and EDGAR's to break; SABIN and BANON have no key
    on him or on the Pterodon.
11. **TERRA, EDGAR, BANON.** Swords key the rats and the Dark Side, the
    crossbow and the rod the guard in plate and the trap's Spectre and Rinn.
    Fire keys every body but the guard and the Repo Man; the Bio Blaster keys
    those two and heals the rats and the whole trap.
12. **LOCKE alone.** *One weapon class.* The Merchant, the Officer and the
    HeavyArmor all take a dagger, in hand or by Trickshot.
13. **CELES: Sword once equipped, and Ice.** She joins unarmed; her fists are
    Blunt and key the Trilobiter, the Primordite and the Gold Bear. With a
    blade she keys the soldiers, the hounds, the Primordite and the bear, and
    LOCKE the soldiers, the hounds and the shell. TunnelArmor (Dagger; bolt,
    water, +ice) takes LOCKE's dagger and Trickshot and her Ice. Mug is
    learned when the escape is done, after this fight.
14. **SABIN alone.** *One weapon class.* East of the Lete his fists key the
    Rhobite, the CrassHoppr and the Stray Cat, and not the Beakor. In the
    camp every body he can meet takes a blow.
15. **SHADOW, if hired: Dagger in hand, Ranged by Throw.** His blade keys the
    CrassHoppr, the Stray Cat, the Templars and the Dobermans; a Shuriken the
    Beakor.
16. **CYAN: Katana.** *One weapon class in his duel.* The Soldiers and the
    Leader take it. With SABIN the camp's infantry take both hands; on the
    train his katana keys every body but the GhostTrain, which takes only
    blows, fire, bolt and holy, so SABIN breaks it and CYAN's Cleave gets its
    Broken target.
17. **Mobliz's shop: a claw for SABIN (Katana in hand, Blunt by Blitz). GAU:
    his fangs (Dagger).** The trench's three take one member each: the
    Anguiform CYAN's katana, the Actaneon SABIN's Blitzes, the Aspik GAU's
    fangs.
18. **Narshe's shop, before the defense: the first Mithril Pike (Spear), a
    claw, a Kotetsu.** The raiders take a sword, a dagger or a katana, so
    every squad the player can form holds a key unless it is only EDGAR with
    a new pike and SABIN with a knuckle, and those two have the Bio Blaster
    and Pummel's damage. The Rider takes a dagger, a katana, Fire and poison;
    Kefka a sword, a dagger, Fire and poison. No body takes a Spear or a
    bolt: with a pike in hand, EDGAR's key at the defense is the Bio Blaster.
19. **Kohlingen and Zozo: any four of six; the Drill (Spear) at Figaro,
    SHADOW for hire, boomerangs and skeans in Kohlingen.** EDGAR's pike and
    Drill key the Red Fang, the Harvester and the FossilFang; his crossbow the
    Gabbldegak pack, the Vulture, the Mind Candy swarm, the Iron Fist and the
    HadesGigas; his Bio Blaster all of Zozo. Every pick of four keys at least
    11 of the 13 bodies; the pick without EDGAR and SABIN has no key on the
    HadesGigas or the Iron Fist.

### The stretches with one weapon class

| stretch | class | bodies that take it | elements held | bodies that take one |
|---|---|---|---|---|
| in armor | Ranged (TERRA's TekMissile only) | Guard, the Whelk's head | fire, ice, bolt (all three); poison (TERRA) | all four |
| TERRA alone | Dagger | all 3 | fire | Were-Rat, Vaporite |
| TERRA and LOCKE | Dagger | all 4, and the practice Lobo | fire | Leafer, Dark Wind, the Lobo |
| LOCKE alone | Dagger | all 3 | none | none |
| SABIN alone, east of the Lete | Blunt | 3 of 4 (not the Beakor) | holy | none |
| SABIN alone, the camp | Blunt | the Soldier, Templar, Doberman, Grunt, Cadet, Telstar | holy | none |
| CYAN's duel | Katana | the Soldier, the Leader | none | none |

## Where the rows depart from "same count, a child class"

22 of the 85 rows (`split.py`'s report lists them as OPENING DEPARTS).

**More weaknesses than on main (12).**

- Lobo, Marshal (pierce to Dagger, Spear): the old pierce was LOCKE's dirk
  and the moogles' pikes at once. One class would take the boss's key out of
  the thief's hand or the moogles'.
- Cirpius, Vulture, Gabbldegak (pierce to Dagger, Ranged): the old pierce was
  a dagger and the AutoCrossbow's bolts at once. Ranged alone has one real
  holder in the party that meets each; Dagger alone would end "the
  AutoCrossbow sweeps the pack".
- Templar, Doberman (pierce to Dagger, Blunt): the old pierce was only
  SHADOW's, an optional hire. SABIN can walk the camp alone.
- Brawler (slash to Sword, Blunt): SABIN's MetalKnuckle slashed on main and
  keyed it; the first two maps he walks deal it.
- HadesGigas (bludgeon to Blunt, Ranged): GAU's hand left bludgeon, so Blunt
  alone has one real holder among the six (the holder rule).
- Trooper, Fidor, Bounty Man (slash|pierce to Sword, Dagger, Katana): the
  player forms three squads from seven before seeing a raider. The old slash
  was five of the seven's hands and is two classes now; two weaknesses cannot
  serve sword, katana and dagger squads (the suites agent's finding).

**Fewer (3).** Sand Ray, Areneid, HeavyArmor (two to Dagger alone): each has
three elements, and the HUD draws four cells, elements first. A second class
would never be shown. The class kept is the one the party that first meets
the body holds (two daggers; LOCKE alone).

**A class that is no child of the old ones, or an old weakness with no child
in the row (7 more, and some of those above).**

- Leafer (slash|bludgeon to Sword, Dagger), Areneid (to Dagger): two daggers
  meet them first. On main that party had no weapon key on either.
- Dark Wind, Hornet (slash|pierce to Dagger, Ranged): the fliers' rule; both
  are pierce's children and slash has none.
- Stray Cat (slash|pierce to Dagger, Blunt), Soldier (to Katana, Blunt),
  Templar, Doberman, Brawler: Blunt for SABIN, whose hand was slash on main.
- Aspik (bludgeon to Dagger): GAU's bare hand was bludgeon and is his fangs
  now; the trench keeps one key a member.
- SlamDancer (slash|pierce to Sword, Katana): both slash's children. The
  body that one-shots takes the two blade classes; Dagger went to the pack
  beside it.

## Where the holder rule binds

From `split.py`'s report, the opening's rows only.

| row | where | why | acceptable, or what relieves it |
|---|---|---|---|
| Lobo (Dagger, Spear), Vomammoth (Sword, Blunt) | in armor | TERRA's armor holds only Ranged | Acceptable: all three members key both with Fire Beam, and the rows are the moogle defense's. |
| Beakor (Katana, Ranged) | east of the Lete, SABIN before CYAN | only a hired SHADOW's star | Acceptable as the one body there: 3 of 4 take SABIN's fists, and it is a random encounter. Blunt in place of Ranged relieves it. |
| Dark Wind (Dagger, Ranged) | the World of Ruin, CELES alone | she holds a sword | A 34-HP bird. Sword in place of Ranged relieves it and costs the fliers' rule. |
| Actaneon (Blunt) | the trench again, the Opera-era party | SABIN is the one real Blunt holder of seven | Fire and bolt are vanilla weaknesses and the party has espers by then. Ranged as a second weakness relieves it. |

Not flagged, but the same kind: the Bleary, the Sand Ray, the Areneid, the
Merchant, the Officer, the HeavyArmor and TunnelArmor take only a dagger.
The story puts LOCKE (and early TERRA, with her knife) in each party that
must fight them; at Narshe and Kohlingen LOCKE and GAU both hold one.

## The HUD's four cells

Every row here fits the four cells with its elements, except:

- **FossilFang** (fire, ice, holy, water vanilla; Spear, Blunt): its four
  elements fill the line and no class is ever drawn. The classes are kept:
  a pick with none of those elements (LOCKE, EDGAR, CYAN, GAU) still breaks
  it with EDGAR's Drill. The honest alternatives are no weapon weakness, or
  one element fewer.
- **Ultros 4** (`$168`, past the opening): it takes Ultros 1's row by
  `pins.FAMILY` and has three elements (the bolt add), so it shows Sword and
  never Ranged.

## Bosses 1-10, restated

| # | boss | shields | weak | the forced party's break |
|---|---|---|---|---|
| 1 | Whelk's head | 4 | +fire; Ranged | three Fire Beams and TERRA's TekMissile |
| 2 | Marshal (Lobos 3) | 4 | poison; Dagger, Spear (Lobos: fire; Dagger, Spear) | every squad's pikes, and LOCKE's dirk |
| 3 | Vargas (Ipoohs 2) | 5 | poison, +holy; Blunt (Ipoohs: fire; Sword) | not before SABIN: Pummel x2, AuraBolt, and now his MetalKnuckle's Fight; the Bio Blaster once the Ipoohs are down |
| 4 | Ultros 1 | 5 | fire, bolt; Sword, Ranged | TERRA's sword and Fire, EDGAR's sword and AutoCrossbow |
| 5 | TunnelArmor | 5 | bolt, water, +ice; Dagger | LOCKE's dagger and Trickshot, CELES's Ice, Runic for the quake |
| 6 | Kefka at the camp | no gauge | | |
| 7 | Telstar (Dobermans 2) | 4 | bolt, water; Blunt (Dobermans: fire; Dagger, Blunt) | SABIN's fists and Pummel |
| 8 | GhostTrain | 4 | fire, bolt, holy; Blunt | AuraBolt, Pummel, SABIN's knuckle, SHADOW's Fire Skean; not CYAN |
| 9 | Rizopas (Piranhas 1) | 4 | bolt; Katana, Blunt | CYAN's Ashura and SABIN's knuckle, as before |
| 10 | Kefka at Narshe | 6 | +fire, +poison; Sword, Dagger | TERRA's, CELES's and EDGAR's swords, LOCKE's dagger, GAU's fangs, TERRA's Fire, EDGAR's Bio Blaster |
| 11 | Dadaluma (Iron Fists 2) | 6 | poison; Dagger, Blunt (Iron Fists: Blunt, Ranged) | every pick of four holds LOCKE, GAU, SABIN or EDGAR |

Two of these change what `bosses-wob.md` measured:

- **Vargas and the GhostTrain take SABIN's Fight now.** His MetalKnuckle is
  Blunt. `bosses-wob.md` 3 (#329) rests on his Fight chipping nothing: "`$08`
  is not reachable Broken". It may be now, and wants measuring.
- **Kefka no longer takes a katana.** On main CYAN's blade and SABIN's
  claws chipped him (slash). A squad of CYAN and SABIN alone keys him only
  with Fire Dance (level 15); with GAU it has his fangs. Sword, Dagger and
  Katana together need a fifth cell. The Rider before him takes the katana
  and not the sword.

## Proposals (not made here)

Element adds, shield counts, shops and events are outside this change.

1. **Guard: add bolt** (or fire). In the game's first fight VICKS and WEDGE
   hold nothing that chips a Guard; a beam that turns a '?' is the lesson's
   first step.
2. **Lobo: 3 shields to 1.** It has 27 HP. The practice chest's Lobo dies to
   the second hit with a shield left, so the chest cannot show a break; at
   one shield the first keyed hit breaks it and the second lands doubled.
3. **South Figaro's weapon shop: the Mithril Pike in its empty eighth slot.**
   EDGAR's Spear would exist from the second town. The Rhinotaur ("the pike
   goes in") and a Mt. Kolts body could then take Spear.
4. **CELES: `opt_equip` when she joins.** She joins unarmed and the menu does
   not say so.
5. **Kefka at Narshe: drop the poison add** to free a cell for Katana, so
   that the row is every squad's again. EDGAR's key on him would then be his
   sword, if he kept it.
6. **"Weak against blunt" and "Weak against ranged"** read as cut short beside
   "Weak against swords". "Weak against blunt attacks" and "Weak against
   ranged attacks" fit the message window (27 letters; vanilla lines run to
   34) and are true of fists, Pummel and thrown things.

## Evidence

- `python3 tools/six_classes/opening.py`: each area's species, the party's
  holds, and the species keyed in hand, by kit and by element under four
  classes and six, for each party and each member, every pick of four at
  Zozo, and the automated route's own hands.
  `build/attempts/wt/v051-six-classes/opening/shares.txt`.
- Over the areas' first parties: the party keys 110 of 113 species some way
  under both; in hand 96 under four classes and 99 under six. A single
  member keys 77% under four and 70% under six, and by weapon or skill 70%
  and 57%: the party still holds a key, and who acts matters more.
- `python3 tools/six_classes/split.py --report-only`: every row, its reason, the
  departures and the holder rule's binds.
  `build/attempts/wt/v051-six-classes/opening/split-report.txt`.
- `python3 tools/six_classes/dlg_fit.py`: the school's pages wrapped as the
  field does it; none runs past four lines.
- `ninja build/ot6.sfc` assembles, and on the built ROM
  `tools/check_shield_rows.py`, `tools/check_break_reach.py`,
  `tools/audit_break_coverage.py --gate` and `tools/check_save_layout.py`
  pass. `tools/check_boss_rows.py` names 13 lines of bosses-wob.md that
  still state the rows this change replaces
  (`build/attempts/wt/v051-six-classes/opening/boss-rows-disagreements.txt`).
