# Magicite as sub-jobs

Scope: the espers; the World of Balance roster, then the World of Ruin's
twelve (last section). Locked ✦. Pillar (DESIGN.md ✦):
equipping a magicite grants its kit *while equipped*. Spells are
never taught permanently, level-up stat bonuses are deleted, one
copy of each exists, and summon = once per battle as the sub-job's
divine. One proposed later exception below is that **passives may be
learned**; that system is not implemented, and the while-equipped
spell/stat model is canon.

## What one magicite carries

Five slots, all data-table work:

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

The **Spells** column ships for every row (#305): each stone grants exactly
its listed spells, except the tube room's six, which grant the lists in
`magicite-tube-six.md` §11, and Golem, whose "Protect-alike" names no FF6
spell, so it grants Safe alone. `tools/check_spell_grants.py` checks this on
the built ROM. The other columns of every row but Ifrit's and Shiva's are
still proposals.

The World of Ruin stones grant the lists in the last section's table
(#327), checked the same way.

- The **kit-forming question** per character is which esper completes
  them (Celes+Carbunkl = the rune fortress; Locke+Stray = the
  ghost thief; Edgar+Golem = the siege engine; Sabin+Ifrit = the
  fire fist). The one-copy rule ✦ makes those choices exclusive, so
  the party has to divide the espers between characters.
- Espers granting *permits* stay rare (3 in WoB) so that a
  multi-weapon character reads as a deliberate build.
- Summon-as-divine tier ✦: the summon does not replace the
  character's own divine for the battle. Both exist, and both are
  once-per-battle abilities used at the same point in a fight.

## Learning summary

Spells, permits, summons: while-equipped, never learned ✦.
Passives, including the stat bump: learned by battles-carried
(above). That is the one form of esper permanence, and it replaces
vanilla's stat-bonus grind with collecting passives. Character
passives (kits.md) and esper passives share the same slots.

## World of Ruin Espers

Owner-approved 2026-09-29 (#327) and built. The table below is what
`GenjuProp` grants: `tools/check_spell_grants.py` (#305) reads every row of
this file whose first cell is exactly an Esper's name and holds that
Esper's `GenjuProp` row to the Spells cell, in the order written. Every spell
name is spelled as `magic_name_en.json` spells it.

These are the twelve stones the World of Balance plans leave out, and all
twelve are World of Ruin rewards. Each is planned the way
`magicite-ifrit-shiva.md` and `magicite-tube-six.md` plan theirs: one job
per stone, one to three **base-tier** spells (nothing in `Ot6FoldTbl`'s
second or third column: Fire 2/3, Ice 2/3, Bolt 2/3, Bio, Cure 2/3, Life 2/3,
Slow 2, Haste2), a while-worn stat package in `Ot6EsperStatTbl`'s four signed
nibbles, and the vanilla summon kept as the divine, unchanged. There is no
passive or permit channel, so none is planned.

**What ships.** The Spells column. The stat column is still a proposal:
`Ot6EsperStatTbl`'s rows for these twelve are zero (no while-worn change).

**Every base spell has a source.** The route lands in the World of Ruin with
twelve stones (Ramuh, Ifrit, Shiva, Siren, Shoat, Maduin, Bismark, Stray,
Kirin, Carbunkl, Phantom, Unicorn; `route-wor-sabin.md`'s party dump); Golem,
ZoneSeek and Sraphim are optional WoB pickups. Between those fifteen and
Terra's and Celes's natural magic (kits.md), the base spells with no source
were Poison, Flare, Quartr, X-Zone, Meteor, Ultima, Quake, W Wind, Stop,
Bserk, Float, Warp, Quick, Dispel and Antdot (Merton and Scan come only from
natural magic). These twelve stones grant all fifteen. The owner's direction
was to place the four the first draft dropped (W Wind, Bserk, Warp, Antdot)
on the stones that carried one spell, stretching a little to fit. Life 3,
which vanilla Phoenix granted, is now Life's third tier (below), so no stone
grants it.

**Why a few copies are deliberate.** "WoR deepens via magicite" (kits.md)
means new verbs, but the World of Ruin also splits the party: the Phoenix
Cave takes two parties (`party_menu 2` in `EnterPhoenixCave`) and Kefka's
Tower three (`party_menu 3` in `EnterKefkasTower_proc`). There is one copy of
each stone, so the WoB medic and caster jobs can serve only one of those
parties each. Starlet and Tritoch are therefore a second copy of a core job,
each with a verb no WoB stone has (owner, 2026-09-29: keep both).

**Stat tiers** are the tube six's (`magicite-tube-six.md` §3): FIELD is +6
over two stats with no downside, STORY +8 with a −2, BOSS +10 with a −3.
Nibbles cap at ±7, so a late stone cannot out-stat Maduin; the World of Ruin
stones differ by shape instead. Crusader is the one exception: +3 in all
four stats, the capstone (owner, 2026-09-29: fine for now).

| Esper | Source | Spells (base) | Stat vig/spd/stm/mag | Job | Notes |
|---|---|---|---|---|---|
| Palidor | Solitary Island beach, once the Falcon flies | Float, Slow | +2 / +4 / 0 / 0 (FIELD) | **the Tailwind**: lift the party, drag the enemy | first WoR stone; Float has no other source |
| Fenrir | Mobliz, when Terra rejoins (Phunbaba) | Stop, X-Zone | 0 / +6 / −3 / +4 (BOSS) | **the Banisher**: take one enemy out of time, or a group out of the fight | no WoB plan grants Stop |
| Starlet | Jidoor, Owzer's mansion (Relm joins) | Cure, Regen, Remedy | 0 / +4 / −3 / +6 (BOSS) | **the second medic**: a heal-and-cleanse stone for a second party | deliberate copy of Kirin + Unicorn's Remedy |
| Alexandr | Doma Castle, the end of Cyan's dream | Dispel, Safe, Shell | +4 / −3 / +6 / 0 (BOSS) | **the Bastion**: strip the enemy's buffs, wall the party | Dispel has no other source |
| Terrato | Umaro's cave, the carving's eye | Quake, Quartr | 0 / −3 / +4 / +6 (BOSS) | **the Landslide**: whole-field attrition | Quake hits the party too, so wear it beside Palidor |
| Tritoch | Narshe cliffs, after its fight | Ice, Bolt, Poison | 0 / +3 / −3 / +7 (BOSS) | **the second caster**: three fold families, Poison in place of Fire | Poison has no other source |
| Odin | the Ancient Castle | Meteor, Bserk | +4 / +4 / −2 / 0 (STORY) | **the Warlord**: a fighter's stone with one field-wide spell, and a berserker's rage for an enemy caster | becomes Raiden |
| Raiden | the Ancient Castle's queen statue (replaces Odin) | Meteor, Bserk, Quick | +6 / +4 / −3 / 0 (BOSS) | **the Warlord, ascended**: Odin's list plus the extra turn | Quick has no other source |
| Bahamut | Doom Gaze, in the sky | Flare, W Wind | +3 / 0 / −3 / +7 (BOSS) | **the Dragon King**: the untyped single-target nuke, and the wingbeat | Flare has no other source |
| Phoenix | the Phoenix Cave (Locke) | Life, Antdot | −2 / +2 / +6 / 0 (STORY) | **the Rebirth**: revive, or boost into the revival before the blow | Life boosts to Life 2 and Life 3 |
| Ragnarok | Narshe weapon shop, chosen over the sword | Ultima, Warp | +5 / 0 / −3 / +5 (BOSS) | **the Last Word**: end the fight, or leave it | kits.md already routes Ultima here |
| Crusader | all eight dragons | Merton, Meteor | +3 / +3 / +3 / +3 (capstone) | **the Capstone**: the two biggest field spells | Merton's only stone; the one four-stat package |

### Where each stone comes from

All twelve grants are `give_genju` in `ff6/src/event/event_main.asm`; the
lines and the dialog beside them are in
`build/attempts/wt/wor-esper-plan/grants.log`. Palidor is the only one whose
place is not obvious from its dialog: it is an NPC on map 398, the Solitary
Island fishing beach (`npc_prop.asm:17661`, `make_npc {13, 6}, $039b`), shown
by `switch $039B=1` in the Falcon's first-flight scene (`event_main.asm:11276`,
after "Follow that bird!") and hidden again when taken (`:12849`). So it is the
first stone the World of Ruin offers once the Falcon flies; on the route the
party then is Celes, Sabin, Edgar and Setzer. Raiden is `take_genju ODIN` followed by
`give_genju RAIDEN` (`:81362`, `:81364`): the player trades Odin in rather
than holding both. Ragnarok's shop door has its own gate (`if_switch $01A1=0`
→ "Locked!"), and the switch was not traced. Terrato's event is followed by
`battle 117` before the grant; the formation was not decoded.

### Why each list

- **Palidor, the Tailwind.** Vanilla's list is tempo: Haste, Slow, Haste2,
  Slow 2, Float. Haste2 and Slow 2 are tiers. Haste already has three sources
  (Bismark, ZoneSeek, Celes at L32) and is dropped; Slow has one (Bismark),
  so Palidor keeps it as the second copy. Float (17 MP, can target the whole
  party) is the stone's own verb: floating bodies are out of reach of earth,
  which is what makes Terrato's Quake castable. The early World of Ruin
  party is three fighters and Celes, so the stat is a FIELD package on
  vigor and speed, a pairing no WoB stone has. Divine: Sonic Dive (`$3F`, the
  party jumps).
- **Fenrir, the Banisher.** Vanilla's Warp, X-Zone and Stop hold no tiers.
  Stop (10 MP, single) and X-Zone (53 MP, a group, death-class, hit 85)
  differ from Shoat's Break/Doom by target (a group, not one body) and by a
  non-lethal option. Terra rejoins here with Break in her own list, so Fenrir
  brings deletion that reaches a whole group. Warp moves to Ragnarok, the
  one-spell stone. Divine: Moon Song (`$4E`, Image on the party).
- **Starlet, the second medic.** Vanilla's list is Cure, Cure 2, Cure 3,
  Regen, Remedy; the two tiers go, and the rest stays. It duplicates Kirin
  (Cure, Regen) and Unicorn's Remedy on purpose: a split party needs a medic
  in each group. Relm joins in the same scene with Sketch as her kit
  (kits.md), so Starlet is what makes her a healer. Divine: the party heal
  (`$4F`).
- **Alexandr, the Bastion.** Vanilla's five are Pearl, Shell, Safe, Dispel,
  Remedy. Pearl and Remedy are Unicorn's job and are dropped. Dispel (25 MP)
  is new. Safe and Shell are each already on two stones, but no stone grants
  both, so this is the one stone that walls both kinds of damage, plus the
  only way to strip an enemy's own buffs. The stone ends Cyan's quest, and
  the stat (vigor and stamina) is built for a front-liner like him. Divine: Justice
  (`$44`, holy, all enemies).
- **Terrato, the Landslide.** Vanilla's Quake, Quartr and W Wind hold no
  tiers. Quake (50 MP, earth, `targ $04`) hits every body on the field, the
  caster's side included, unless it floats; Quartr (48 MP, all enemies, a
  fraction of current HP) is the enemy-only version of the same attrition. W
  Wind (75 MP, a fraction of every body's HP, both sides) is the both-sides
  copy of Quartr, so it moves to Bahamut rather than sit beside it. Divine:
  Earth Aura (`$3A`, earth, all enemies).
- **Tritoch, the second caster.** Vanilla's list is Fire 3, Ice 3, Bolt 3, all
  tiers. The stone keeps Ice and Bolt as the second copy of the caster job and
  replaces Fire with Poison. Fire is the best-covered element (Ifrit, Maduin,
  Terra, Sabin's Fire Dance), while Poison, the fourth fold family (3 MP, Bio
  at 1 BP), is on no other stone. Its divine Tri-Dazer (`$40`, fire|ice|bolt)
  keeps all three of vanilla's elements.
- **Odin and Raiden, the Warlord.** Vanilla's lists are Meteor and Quick. The
  two are one stone: Raiden replaces Odin, so Raiden keeps Odin's list and
  adds Quick, and the upgrade shows as a third spell, a larger stat package
  and True Edge's hit 140 over Atom Edge's 110 (`$42`, `$41`). Their stat
  package is for fighters (vigor and speed). Bserk (16 MP, single) is the
  stretch that fits a warlord: Odin's berserkers. Cast on an enemy, it turns
  a spellcaster into a brawler that can only Fight; cast on an ally, it takes
  that ally out of the player's hands (Phantom's recorded reason for dropping
  it), so it is an enemy verb in practice. Quick (99 MP) is the game's dearest
  spell and the only extra-turn verb.
- **Bahamut, the Dragon King.** Vanilla's Flare holds no tier. Flare (45 MP,
  single, untyped) is never absorbed, so it is the answer for a body that
  absorbs or nulls every element the other stones carry. W Wind is the
  dragon's wingbeat: it cuts every body on the field, the party included, to
  a fraction of its HP, so it opens a fight against a group before Flare
  finishes one body. Mega Flare (`$43`) is the all-enemies version of Flare,
  the same single-to-all shape as Shoat's Break and Demon Eye.
- **Phoenix, the Rebirth.** Vanilla's list is Life, Life 2, Life 3, Cure 3,
  Fire 3. The owner's call (2026-09-29): Phoenix grants Life, which boosts to
  Life 2 and then Life 3, so `Ot6FoldTbl`'s life row is Life, Life 2, Life 3
  and Life 2 and Life 3 are both tiers that no stone grants. Cure 3 and Fire 3
  go (Cure is Kirin's and Starlet's; Fire is Ifrit's and Maduin's and in
  Terra's list). Antdot (3 MP, cures Poison) is the stretch: phoenix tears
  cure venom, and Tritoch's Poison is new in this world. The Phoenix Cave is
  the two-party dungeon, and Phoenix is the second party's revival. Divine:
  Rebirth (`$50`, revives the party).
- **Ragnarok, the Last Word.** Vanilla's Ultima holds no tier, and kits.md's
  Terra section already says "Everyone else gets Ultima by equipping
  Ragnarok". Warp (20 MP) is its second word: in battle it takes the party
  out of a fight it can run from, and in the field it leaves a dungeon.
  Ragnarok ends the fight one way or the other. The stone competes with the
  Ragnarok sword that the same choice would give, so it carries a BOSS
  package split between vigor and magic.
- **Crusader, the Capstone.** Vanilla's Merton and Meteor hold no tiers.
  Merton (85 MP, fire|wind, every body on the field) is otherwise Terra's
  alone at L33; Meteor is a copy of Odin's, accepted on the stone that closes
  the eight-dragon hunt. Its stat, +3 in all four stats, is outside the
  three tiers (+12, no downside) and is the only four-stat package in the
  game.

### Life 3 is Life's third tier

Boosting Life by one point casts Life 2 and by two or three points Life 3
(`Ot6FoldTbl`, `ot6_boost.asm`), with the name and the price in the Magic
list following the boost like every other family. A folded cast pays its
tier's own MagicProp price, and vanilla priced Life 3 at 50, under Life 2's
60, so the second point would have bought a cheaper cast than the first.
OT6 prices Life 3 at 60 (`battle_main.asm`, MagicProp override 6), the least
price at which the fold's two pricing rules hold: a boost never makes a
family cheaper, and a folded tier costs at least twice its base
(`battle_foldcost`). `battle_lifefold` measures the name, the price, the cast
and the effect at every boost (`build/attempts/wt/wor-espers/`).

Vanilla's Life 3 is the pre-emptive revival: it marks a living body to rise
once when it falls, and it cannot touch a KO'd body. Life and Life 2 only hit
a KO'd body. As first built, a two-point Life on a fallen ally therefore cast
Life 3, spent the pips and 60 MP, and left the ally down (LOCKE KO'd by his
own party, then a two-point Life on him: `lab_lifedead_try1.log`, "hp0
st1$80"). The owner's call (2026-09-29): **Life 3 revives too.** When a
character casts it through Magic or X-Magic (or Mimics such a cast), on a
KO'd ally it revives at full HP, as Life 2 does, and grants its Life 3
status; on a living ally it grants the status as before. Every other Life 3
is vanilla's (below).

| Boost | Casts | MP | On a KO'd ally | On a living ally |
|---|---|---|---|---|
| 0 | Life | 30 | revives | nothing |
| 1 | Life 2 | 60 | revives at full HP | nothing |
| 2 or 3 | Life 3 | 60 | revives at full HP, and marks it to revive | marks it to revive |

How (`ot6_boost.asm`): two hooks in `CalcAttackEffect`, both gated on the
executing action itself (`Ot6Life3Cast`: the attacker is a character, the
queued command is Magic `$02` or X-Magic `$17`, the attack is Life 3).
`Ot6Life3Targeting`, just before `ChooseTarget`, lets that Life 3 keep a KO'd
target, as Life and Life 2 do, without the record's resurrection flag, which
`CheckHit` reads as "misses the living". `Ot6Life3Revive`, in the per-target
loop, gives a KO'd character target Life 2's effect (wound cleared, healed by
16/16 of max HP) on top of the record's Life 3 status. `battle_lifefold`
measures both targets at every boost: LOCKE KO'd, then a two- or three-point
Life leaves him at 1215/1215 with the status, and a Fenix Down right after a
Life 3 still revives as a Fenix Down (`build/attempts/wt/wor-espers/`).

**Everyone else keeps vanilla Life 3.** The monsters that cast it (Madam,
Magic Master, L.80 and L.90 Magic; Rhinox's script names it but its 35 MP
never pays), Gau's Rhinox rage, Control and Sketch. A first cut gave every
Life 3 the revival, and a review lab (every monster casting Life 3) showed
monsters then picking their own dead and raising them
(`build/attempts/review-wor-espers/lab_rv_monlife3_A.log`: 11 landings on
KO'd bodies). That would retune those fights, and a raged Gau could raise a
fallen ally in the World of Balance, where kits.md keeps revival to Terra,
Fenix Downs and Sraphim. With the gate the same lab matches the vanilla
control counter for counter (74 landings, 0 on a KO'd body, 8 reraises;
`lab_monlife3_G.log` against `lab_rv_monlife3_B.log`). A rage turn is queued
as command `$10` (`RandRageAction`) and keeps it in `$3a7c` while it runs,
so the gate never matches it.

### Boost on these lists

Poison, Ice, Bolt, Cure, Life and Slow fold. Flare, Meteor, Merton, Ultima,
Quake and the damaging divines (Earth Aura, Tri-Dazer, Mega Flare, Justice,
Purifier) take `Ot6BoostDmg`'s ×2/×4/×8 at the escalating price
(mp-economy.md). Float, Stop, X-Zone, Quick, Dispel, Safe, Shell, Regen,
Remedy, Bserk, Warp and Antdot deal no damage and fold nowhere, so they are
outside both boost axes: the gap `magicite-tube-six.md` §12.4 records for
Shoat and Phantom. Whether Quartr's and W Wind's fraction damage takes the
multiplier was not checked.

### The Magicite item, boosted (#368)

The Magicite item calls a random esper (`AttackerEffect_49`: `RandGenju`, 25
espers, never Odin or Raiden), and its boost is `Ot6BoostDmg`'s multiplier.
Half the pool had nothing for it to multiply: twelve espers of power 0
(Siren, Shoat, Stray, Palidor, Ragnarok, Kirin, ZoneSeek, Carbunkl, Phantom,
Golem, Unicorn, Fenrir) and Phoenix's revival, 0.520 of a draw
(`build/attempts/wt/procboost-magicite/summary.txt`). A boosted Magicite
that drew one spent its pips and bought nothing. And Crusader's Purifier
strikes both sides (targeting `$04`, flags `$40`, vanilla's record byte for
byte; vanilla's Magicite→Crusader also hits the party,
`build/attempts/wt/one-graph/review-procboost-magicite/codepath.txt`), so a
boosted one multiplied onto the caster's own party: ×8 is 9999 on every
seat.

**Decision:** the boost still buys the multiplier, and a boosted Magicite
draws again past any esper the multiplier cannot serve on the enemy:
power 0, a revival, or damage that can reach the party (both sides, or the
caster's side without "can't target characters"). A heal (Starlet,
Sraphim) is kept: the multiplier is the heal. `Ot6MagiciteKeep`
(`ot6_magicite.asm`) reads each draw's `MagicProp` record, so the rule
follows the espers' data rather than a list; every draw is vanilla's own
`RandGenju`. Unboosted, the Magicite is vanilla's gamble, Crusader
included. On today's records the boosted pool is Ramuh, Ifrit, Shiva,
Terrato, Maduin, Bismark, Tritoch, Bahamut, Alexandr, Sraphim and Starlet.
`battle_procboost`'s magicite case decodes the same rule from the ROM and
checks every boosted draw: each one it kept pays, each one it passed over
does not, and some try drew again.

### Open questions for the owner

1. **Stat packages.** The stat column above is not built; the twelve rows of
   `Ot6EsperStatTbl` are zero.
2. **Verbs that boost cannot touch.** This table carries twelve verbs outside
   both boost axes. Whether BP should buy duration or certainty on them is
   DESIGN.md's open canon, not this table's to settle.
