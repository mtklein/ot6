# Pre-FC World-of-Balance wrap-up — the plan (#132)

> **Owner goal (2026-08-22):** thoroughly cover the WoB *before* the Floating
> Continent. No rush to the FC. This is both the owner's own playthrough and a
> completeness pass over the whole game's areas and tuning — so it includes
> **tuning** the optional content (e.g. the optional espers), not just reaching
> it. Approach A: full headless coverage where feasible.
>
> Status legend: ☐ todo · ◐ in progress · ☑ done. Kept current as work lands.

## The party's starting point (thamasa_done, the stop line)

L15–17, ~10 under vanilla's FC expectation; two ThunderBlades (bolt — the IAF/FC
key), empty relic slots on 3/4. Full detail in `level-curve.md`. Blackjack
repaired; the whole WoB world map is reachable.

## Enabling tooling

- ☑ Airship-driver: board → discovery → deck → party-select → IAF (`probe_iaf.lua`, #131).
- ◐ **Airship autopilot** (`probe_grind.lua`): flies, closes to ~14 tiles;
  needs brake-on-approach + landing to dock at towns / land in a grind region.
  Position X=$33/$35, Y=$37/$39 (tile=fine>>12); heading $73; thrust A; rotate L/R.
- ☐ Chocobo rental + overworld nav (for the Serpent Trench leg).
- ☐ On-foot dungeon nav reused from the harness (navTo) for Narshe mines, the
  Serpent Trench, auction/shop menus.

## The wrap-up checklist

1. ☐ **Grind** to close the level gap (target ~L21–22). Best WoB spot:
   Chimera+Cephaler (~1572 XP), else Ralph/Wyvern. Verify the IAF becomes
   survivable post-grind (`probe_iaf_fight.lua`).
2. ☐ **Shop** — relics (the clear under-gear) and armor at WoB towns.
3. ☐ **Mog** — recruit in Narshe (WoB).
4. ☐ **Water Rondo / Water Harmony** — take Mog down the Serpent Trench:
   Nikeah → rent chocobo → east/south through Doma to Baren Falls → leap to the
   Veldt → leap into the Serpent Trench (water battles teach the dance) → back
   to Nikeah. Missable in the WoR.
5. ☐ **Optional espers — obtain:** Golem + Zoneseek (Jidoor Auction House),
   Sraphim (man in the woods near Tzen, 3000 GP in the WoB).
6. ☑ **Optional espers — tuned** (d5de87e): Golem/Zoneseek/Sraphim had sat
   untuned (esper_stat 0,0,0,0, dead pre-folded CURE_2 grants) unlike the
   story/field espers. Gave them the deliberate identity+kit+stat pass —
   Sraphim "the Seraph" (durable reviver 0,0,+4,+2), Golem "the Bulwark"
   (physical wall 0,-2,+5,0), Zoneseek "the Sap" (MP-warfare caster 0,0,+2,+3);
   dropped the dead CURE_2 tiers. esper tests green.
7. ☑ **Full WoB esper audit** — read owned-esper bitfield ($1A69) off the
   checkpoint chain. **Owned at FC entry (12):** Ramuh, Ifrit, Shiva, Siren,
   Shoat, Maduin, Bismark, Stray, Kirin, Carbunkl, Phantom, Unicorn (the routed
   WoB story set). **WoB-optional, not yet owned (3):** Golem, Zoneseek (Jidoor
   auction), Sraphim (Tzen 3000 GP) ← the obtain targets. **WoR-gated (12):**
   Terrato, Palidor, Tritoch, Odin, Raiden, Bahamut, Alexandr, Crusader,
   Ragnarok, Fenrir, Starlet, Phoenix.
8. ☐ **Sweep for other WoB optional content** reachable by airship pre-FC
   (colosseum? Zozo/other shops? Gau rages?) — note anything worth tuning.

## Then (out of scope for this goal, tracked in #132)

The FC arc itself — IAF → Floating Continent → AtmaWeapon → the humane escape →
WoR landing — once the party is prepped.
