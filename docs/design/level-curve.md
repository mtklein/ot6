# The OT6 level curve — party levels by area

> This is the authoritative party-level reference, and it is *empirical*: the
> levels below are read directly off the routed **checkpoint savestate chain**
> (`build/states/*.mss`), not from a vanilla walkthrough — so they are the
> levels OT6's own route actually reaches, which is what tuning must answer to.
>
> Regenerate with `tools/savestate_party.py`'s `read_party` over the checkpoints
> (the snippet at the bottom). Requires `make savestates` to have built the
> chain.

## The curve (active party at each checkpoint)

| area / checkpoint | party (name L) | range |
|---|---|---|
| Narshe start (arvis_wake) | TERRA 4 | L4 |
| Figaro (figaro_intro) | TERRA 5 | L5 |
| Mt. Kolts (kolts_cave) | TERRA 8 · LOCKE 9 · EDGAR 10 | L8–10 |
| Vargas (vargas_won) | TERRA 10 · LOCKE 10 · EDGAR 11 · SABIN 12 | L10–12 |
| Returner Hideout | TERRA 10 · LOCKE 11 · EDGAR 11 · SABIN 12 | L10–12 |
| Lete River (banon aboard) | TERRA 10 · EDGAR 11 · SABIN 12 · BANON | L10–12 |
| Sabin scenario (camp/Doma) | CYAN 13 · SHADOW 11 · SABIN 13 | L11–13 |
| Sabin's leap done (sabin_done) | UMARO-slot 17 | ~L17 |
| Battle for Narshe (kefka_won) | LOCKE 12 · EDGAR 13 · SABIN 13 · CELES 12 | L12–13 |
| Zozo (zozo_done) | LOCKE 14 · EDGAR 15 · SABIN 15 · CELES 14 | L14–15 |
| Opera / Vector (ultros2_entry) | LOCKE 14 · EDGAR 15 · SABIN 15 | L14–15 |
| Blackjack (post-Vector) | LOCKE 14 · EDGAR 15 · SABIN 15 · CELES 14 | L14–15 |
| Crescent → Thamasa | TERRA 14 · LOCKE 15 · SHADOW 14 | L14–15 |
| Esper Mtn / Ultros③ | TERRA 15 · LOCKE 16 · STRAGO 17 | L15–17 |
| **FC entry (thamasa_done)** | **TERRA 15 · LOCKE 16 · STRAGO 17 · RELM 15** | **L15–17** |

## The Floating Continent gap

The routed party reaches the **Floating Continent at L15–17**. Rough vanilla
FF6 expectation for the same content is **~L25–30** (AtmaWeapon is a ~L30 fight
in vanilla). So OT6 arrives at the FC roughly **ten levels light**, and the gap
is widest here — the WoB's hardest stretch against its lowest-relative party.

The deficit is real, and there are two answers, not one — a player can lean on
tactics, **or grind to close part of the gap** with the Blackjack. See
"Pre-FC grinding" below. Two things carry the deficit even without grinding:

- **Break, not levels, is the damage.** OT6's fights are Octopath shield/break
  tactics; boss shield and weakness rows are authored *against the routed
  levels* (`check_boss_rows.py` is green through Nerapa, i.e. the FC bosses'
  data already matches the party they will actually meet). Raw level gates HP
  and survivability more than damage output.
- **Prep is the lever.** Row, boost banking, weakness coverage, and the field
  care between fights (the humane line) are what a player spends to clear a
  stretch they are under-levelled for — the same discipline the Thamasa arc
  already shipped (`ROADMAP.md`: "winnable at route level with a player's
  prep").

Practical consequences of the route as it stands:
- The IAF gauntlet is eight fights with **no save and a real Game Over on a
  loss** (the `_ca5ea9` handler). At L15–17 that is a survivability test, not a
  damage race — budget for HP attrition across the chain and lean on break to
  end fights fast.
- The FC's random pool (forms 177–188) includes **pincer-capable formations**
  (`audit_encounters.py 394`), so the walk between save points is itself a
  drain — care at the 394 (7,12) / 358 (8,10) save points matters.
- If tuning shows a fight is unwinnable at these levels even with perfect
  break/prep *and* a reasonable grind, that is a **balance signal** (retune the
  shield row).

## Pre-FC grinding (with the Blackjack)

Once the Blackjack is repaired (the stop line), the whole WoB world map is
reachable: fly to a region, land, and farm on foot. Ranked by XP, derived from
this ROM's data (`monster_prop.dat +12` = XP, `+16` = level; world encounters
via `world_battle_group.dat` → `rand_battle_group` → `battle_monsters.dat`):

| spot (WoB world encounter) | formation | XP | levels | note |
|---|---|---|---|---|
| **Chimera + Cephaler** | form 190 | **1572** | Chimera L22, Cephaler L21 | best WoB world XP; group 22/25 |
| Chimera solo | form 161 | 1144 | L22 | same zone |
| Ralph + Wyvern | form 144 | 1223 | L17–18 | group 14/15/21 |
| Ralph + Wyvern + ChickenLip | form 145 | 1119 | L17–18 | group 17/18 |
| ChickenLip ×5 | form 149 | 950 | L18 | group 15/17/18 |

Notes and cautions:
- **Chimera + Cephaler (~1572 XP) is the standout** and only ~L21–22, a few
  above the party — an efficient close-the-gap grind. It sits in world
  encounter group 22 (top-of-map zones, roughly X 64–128) and group 25
  (mid-map). Exact fly-to coordinates want a world-tile probe (the #131
  airship-driver can now fly and read the roll); until then, fly the eastern/
  central WoB landmasses and land where Chimera/Cephaler roll.
- **Intangir is NOT an XP grind here** — `monster_prop` gives it **0 XP**
  (species `$0a3`). The Triangle Island trick is a magic/gil story, not levels.
- The huge-XP formations (Tyranosaur 8800, Doom Drgn 8500, Brachosaur 14396)
  are all **WoR-gated** (L44–77) and unreachable pre-FC.
- **The Veldt pays no XP** (`$11E4` bit 1; HANDOFF), so Gau's stretch is not a
  grind — `WorldBattleGroup` marks veldt sectors with `$FF`
  (`field/battle.asm:138-142`).
- OT6 scales XP by the inverse of the encounter rate (`DESIGN.md:408`), so
  absolute numbers differ from vanilla but the *ranking* of spots holds (same
  monster data, uniform scale).

## Gear at the FC entry (thamasa_done)

The owner's warning was "behind in gear **and** levels"; the gear half, read
from the same checkpoint:

| char | weapon | armor | relic |
|---|---|---|---|
| TERRA | **ThunderBlade** (bolt) | Mithril Vest | — |
| LOCKE | **ThunderBlade** (bolt) | Kung Fu Suit | — |
| STRAGO | Fire Rod | Cotton Robe | — |
| RELM | Chocobo Brush | Silk Robe | Memento Ring |

Two things stand out:
- **Two ThunderBlades** — the party already carries bolt weapons, and the whole
  IAF (and AtmaWeapon) is bolt-weak (`floating-continent-route.md` §3). Front-row
  Terra/Locke swings, or their Thunder, are a natural break answer; a bolt-leaning
  three is available without new purchases.
- **Empty relic slots on three of four**, mid-tier (Mithril/cloth) armor. Relics
  are the clearest under-gear, and survivability relics are exactly what the IAF's
  care-stop-less attrition punishes the lack of. The Blackjack reopens WoB shops
  (Thamasa and others), so gear/relic shopping is part of FC prep alongside a
  grind.

## How to regenerate

```py
import sys; sys.path.insert(0, "tools")
import savestate_party as sp
for stem in ("arvis_wake", "kolts_cave", ..., "thamasa_done"):
    party, err = sp.read_party("build/states/%s.mss" % stem)
    active = [m for m in party if m["active"]]
    print(stem, [(m["name"], m["level"]) for m in active])
```

Each member dict carries `name`, `level`, `hp`/`maxhp`, `mp`/`maxmp`, `weapon`,
`gear`, and the `active`/`party` flags — so this same read backs a gear/HP
audit at any checkpoint, not just levels.
