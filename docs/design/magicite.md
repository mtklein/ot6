# Magicite as sub-jobs — design dive v2 (2026-07-16)

Scope: World of Balance espers. Locked ✦. Pillar (DESIGN.md ✦):
equipping a magicite grants its kit *while equipped* — spells are
never taught permanently, level-up stat bonuses are deleted, one
copy of each exists, summon = once per battle as the sub-job's
divine. One deliberate exception below: **passives are learned**.

## What one magicite carries

Five slots, all data-table work (menu plumbing lands M5):

1. **Spells** — 2–3 *base-tier* spells (boost folds the tiers, so a
   Ramuh bearer with 2 BP already casts Bolt 3). While-equipped only,
   always.
2. **Stat mod** — flat while-equipped (+magic, +speed…), replacing
   vanilla's permanent level-up bonuses ✦.
3. **Passive** — active while equipped, and **teachable ✦**: carry
   the esper long enough and its passive is learned — it joins the
   character's permanent passive pool and can be slotted even with a
   different esper equipped. This is Octopath's job+subjob passive
   mix-and-match, gestured at through espers: your build is your
   history of who you've carried.
   - **Learning meter**: a fixed count of *battles fought while
     equipped* (a deed, like dances and lores — not levels). Trash
     espers ~15 battles, marquee ones ~25. Stored per character?
     **No — per esper, party-wide ✦-leaning**: one copy of each
     esper exists, so "who carried it" barely matters and party-wide
     keeps the save format trivial.
   - Passive slots per character stay capped (up to 4, DESIGN.md),
     so learning more passives deepens *choice*, not power.
4. **Weapon permit** — at most one extra weapon class in the equip
   menu (see weapon-classes.md; battle code never checks it). Kept
   deliberately spare ✦ — a development knob, not a pillar.
5. **Summon** — the divine, once per battle ✦.

Sub-job fantasy check: a magicite should read as a *job*, not a
spell bag — its spells, passive, and permit should rhyme, and the
passive is the part of the job you keep.

## The WoB roster

| Esper | Source | Spells (base) | Stat mod | Passive | Permit | Notes |
|---|---|---|---|---|---|---|
| Ramuh | Zozo | Bolt, Rasp | +1 magic | *Conductor*: bolt spells chip +1 | piercing | the storm-lancer job |
| Kirin | Zozo | Cure, Regen | +1 stamina | *Mender*: heals never miss the row | — | the medic job |
| Stray | Zozo | Muddle, Imp | +1 speed | *Alley Cat*: +5 evade | slashing (claws) | the trickster job |
| Siren | Zozo | Mute, Sleep | +1 speed | *Lullaby*: sleepers take +50% chip | — | the controller job |
| Ifrit | Magitek factory | Fire, Drain | +1 vigor | *Kindling*: fire spells chip +1 | slashing (claws) | the brawler-mage |
| Shiva | Magitek factory | Ice, Osmose | +1 magic | *Frostbite*: ice chip +1 | bludgeoning (rods) | the classic |
| Unicorn | Zozo (late) | Remedy, Safe | +1 stamina | *Purity*: status durations halved | — | the paladin-adjacent |
| Maduin | Sealed Gate | Fire, Ice, Bolt | +2 magic | *Trinity*: first spell each battle +1 tier | — | Terra's inheritance: the pure mage job |
| Shoat | Vector aftermath | Break, Doom | +1 magic | *Gorgon Eye*: Break may (25%) chip 2 | — | the executioner |
| Phantom | Magitek factory | Vanish, Sleep | +1 speed | *Ghostwalk*: first hit taken each battle misses | — | the assassin's second |
| Carbunkl | Sealed Gate | Rflect, Shell | +1 stamina | *Facet*: Runic feeds +1 more BP | — | Celes's natural pairing |
| Bismark | Thamasa | Slow, (Water lore-alike) | +1 vigor | *Tidal*: water chip +1 | — | see open Q2 |
| Golem | Jidoor auction | Safe, Protect-alike | +2 stamina | *Bulwark*: party takes −10% physical | piercing | the wall job |
| ZoneSeek | Jidoor auction | Shell, Haste | +1 magic | *Ward*: magic taken −10% (party) | — | the abjurer |
| Sraphim | Tzen (buy) | Cure, Life | +1 stamina | *Grace*: KO'd allies keep their BP | — | the white-mage job |

- The **kit-forming question** per character: which esper completes
  them? (Celes+Carbunkl = the rune fortress; Locke+Stray = the
  ghost thief; Edgar+Golem = the siege engine; Sabin+Ifrit = the
  fire fist.) The one-copy rule ✦ makes those choices exclusive —
  that's the party puzzle.
- Espers granting *permits* stay rare (3 in WoB) so multi-weapon
  characters feel like builds, not defaults.
- Summon-as-divine cadence ✦: the summon replaces the character's own
  divine for the battle? **No** — both exist, but both share the
  "once per battle, apex moment" register. Playtest for redundancy
  in M6.

## Learning summary

Spells, stats, permits, summons: while-equipped, never learned ✦.
Passives: learned by battles-carried (above) — the one form of
esper permanence, replacing vanilla's stat-bonus grind with build
collection. Character passives (kits.md) and esper passives share
the same slots; the M6 pass watches for degenerate pairs (Facet +
Rune Eater = 3 BP per Runic — probably fine, Runic still eats the
turn).

## Open questions for the driver

1. Battle-count tuning: is ~15/~25 right, and should the count show
   on the esper screen as a little meter (recommended: yes, meters
   are the fun part)?
2. Water has no base spell in vanilla's list (it's lore/esper
   territory). Bismark either grants the only Water spell in the
   game (special!) or a Slow/Haste utility pair instead. Which?
3. Maduin's *Trinity* (first cast +1 tier free) — too strong a
   folding interaction, or exactly the flavor of "Terra's blood"?
