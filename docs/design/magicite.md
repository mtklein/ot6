# Magicite as sub-jobs

Scope: World of Balance espers. Locked ✦. Pillar (DESIGN.md ✦):
equipping a magicite grants its kit *while equipped*. Spells are
never taught permanently, level-up stat bonuses are deleted, one
copy of each exists, and summon = once per battle as the sub-job's
divine. One proposed later exception below is that **passives may be
learned**; that system is not implemented, and the while-equipped
spell/stat model is canon.

## What one magicite carries

Five slots, all data-table work (menu plumbing lands M5):

1. **Spells** — 2–3 *base-tier* spells (boost folds the tiers, so a
   Ramuh bearer with 2 BP already casts Bolt 3). They are available
   only while the magicite is equipped.
2. **Stat passive** — a fixed, constant stat bump (+magic, +speed…)
   that behaves like the passive below: active while
   equipped, and learnable ✦. This is the only stat growth a
   magicite grants. Vanilla's per-level bonuses stay deleted, and
   there is no while-equipped-only stat mod either. It follows
   Octopath's Support-Skill shape: a large bump that does not
   compound. Octopath sizes these at about +50 on a 999-scale stat;
   translate to FF6's stat ranges at tuning, so the roster
   magnitudes below are placeholders.
3. **Passive** — active while equipped, and **teachable ✦**: carry
   the esper long enough and its passives are learned. They join
   the character's permanent passive pool and can be slotted even
   with a different esper equipped. This is Octopath's job+subjob
   passive mix-and-match expressed through espers, so a character's
   passive pool records which espers they have carried.
   - **Learning meter**: a fixed count of *battles fought while
     equipped*, which makes it a deed like dances and lores rather
     than a level. Minor espers ~15 battles, major ones ~25. The
     count is stored **per esper, party-wide ✦-leaning**, not per
     character: one copy of each esper exists, so which character
     carried it barely matters, and party-wide storage keeps the
     save format simple.
   - Passive slots per character stay capped (up to 4, DESIGN.md),
     so learning more passives widens the player's choice without
     raising total power. Stat passives compete for those same
     slots, which is what stops the bonuses compounding.
4. **Weapon permit** — at most one extra weapon class in the equip
   menu (see weapon-classes.md; battle code never checks it). Kept
   spare ✦: it is a development knob rather than a pillar.
5. **Summon** — the divine, once per battle ✦.

Sub-job check: a magicite should read as a *job* rather than a bag
of spells. Its spells, passives, and permit should fit one theme,
and the passives are the part of that job the character keeps.

## The WoB roster

**Ifrit and Shiva** are built; `docs/design/magicite-ifrit-shiva.md` is the
authority for both, alongside the data in `ff6/src/menu/genju_prop.asm` and
`Ot6EsperStatTbl` (`ff6/src/battle/ot6_progression.asm`). Every other row
describes the *proposed* system, not the shipped one.

| Esper | Source | Spells (base) | Stat passive | Passive | Permit | Notes |
|---|---|---|---|---|---|---|
| Ramuh | Zozo | Bolt, Rasp | +1 magic | *Conductor*: bolt spells chip +1 | piercing | the storm-lancer job |
| Kirin | Zozo | Cure, Regen | +1 stamina | *Mender*: heals never miss the row | — | the medic job |
| Stray | Zozo | Muddle, Imp | +1 speed | *Alley Cat*: +5 evade | slashing (claws) | the trickster job |
| Siren | Zozo | Mute, Sleep | +1 speed | *Lullaby*: sleepers take +50% chip | — | the controller job |
| Ifrit | Magitek factory | Fire, Drain | magicite-ifrit-shiva.md §4.2 | none, deliberately | none, deliberately | **"the Furnace": weight** |
| Shiva | Magitek factory | Ice, Osmose, **Shell** | magicite-ifrit-shiva.md §5.2 | none, deliberately | none, deliberately | **"the Rime": economy** |
| Unicorn | tube room | Remedy, Safe | +1 stamina | *Purity*: status durations halved | — | the paladin-adjacent |
| Maduin | tube room | Fire, Ice, Bolt | +2 magic | *Trinity*: first spell each battle +1 tier | — | Terra's inheritance: the pure mage job |
| Shoat | tube room | Break, Doom | +1 magic | *Gorgon Eye*: Break may (25%) chip 2 | — | the executioner |
| Phantom | tube room | Vanish, Sleep | +1 speed | *Ghostwalk*: first hit taken each battle misses | — | the assassin's second |
| Carbunkl | tube room | Rflect, Shell | +1 stamina | *Facet*: Runic feeds +1 more BP | — | Celes's natural pairing |
| Bismark | tube room | Slow, (Water lore-alike) | +1 vigor | *Tidal*: water chip +1 | — | see open Q2 |
| Golem | Jidoor auction | Safe, Protect-alike | +2 stamina | *Bulwark*: party takes −10% physical | piercing | the wall job |
| ZoneSeek | Jidoor auction | Shell, Haste | +1 magic | *Ward*: magic taken −10% (party) | — | the abjurer |
| Sraphim | Tzen (buy) | Cure, Life | +1 stamina | *Grace*: KO'd allies keep their BP | — | the white-mage job |

The tube room grants Unicorn, Maduin, Shoat, Phantom, Carbunkl and Bismark
together, in one scene; see `magicite-tube-six.md`.

- The **kit-forming question** per character is which esper completes
  them (Celes+Carbunkl = the rune fortress; Locke+Stray = the
  ghost thief; Edgar+Golem = the siege engine; Sabin+Ifrit = the
  fire fist). The one-copy rule ✦ makes those choices exclusive, so
  the party has to divide the espers between characters.
- Espers granting *permits* stay rare (3 in WoB) so that a
  multi-weapon character reads as a deliberate build.
- Summon-as-divine cadence ✦: the summon does not replace the
  character's own divine for the battle. Both exist, and both are
  once-per-battle abilities used at the same point in a fight.
  Playtest for redundancy in M6.

## Learning summary

Spells, permits, summons: while-equipped, never learned ✦.
Passives, including the stat bump: learned by battles-carried
(above). That is the one form of esper permanence, and it replaces
vanilla's stat-bonus grind with collecting passives. Character
passives (kits.md) and esper passives share the same slots; the M6
pass checks for degenerate pairs (Facet + Rune Eater = 3 BP per
Runic, probably fine because Runic still eats the turn).

## Open questions for the driver

1. Battle-count tuning: is ~15/~25 right, and should the count show
   on the esper screen as a meter (recommended: yes, so the player
   can see the progress)?
2. Water has no base spell in vanilla's list (it's lore/esper
   territory). Bismark either grants the only Water spell in the
   game or a Slow/Haste utility pair instead. Which?
3. Maduin's *Trinity* (first cast +1 tier free): too strong a
   folding interaction, or the right flavor for "Terra's blood"?
4. The stat ruling gives every esper *two* passives on one
   learning meter, which was tuned for a single payoff. Should they
   land together at the threshold, or staggered, with the stat bump
   early (~10 battles) and the named passive at the full count?
