# OT6 Roadmap

Every milestone ends with a buildable ROM, a distributable `.bps` patch, and
a save/savestate that demos the new behavior. Order is chosen so the two
signature systems (Break, BP) are playable against vanilla content early —
menus, data entry, and balance come after the fun is proven.

## The headline metric: the playable frontier

Progress is measured in playtest terms: **how far into the game we'd tell a
playtester to play before stopping.** A rung is reached when the fixture
pipeline reaches it, the balance bands measure green there, and every
recruited character's kit is honest there.

| rung | stop point | gated on |
|---|---|---|
| 1 | the Moogle defense (~1 hour: mines → Whelk → escape) | reached |
| 2 | Figaro → Vargas | reached |
| 3 | scenario split → Kefka at Narshe | reached |
| 4 | through Zozo — Dadaluma beaten, sub-jobs in hand | reached |
| 5 | end of the Opera sequence — Ultros ② beaten, Setzer joined, Blackjack acquired | reached |
| **6 (current)** | **end of WoB (Vector → Floating Continent)** | the frontier stands at **Terra's return**: Vector and the Magitek Research Facility through Number 128, the Cranes and the escape are playable. Remaining: the rest of the kits and espers; the wide weakness/telegraph pass (boss data already reaches Nerapa); route and tune from there through the Floating Continent |

Releases are named for their **theme**, not for a rung: the owner plays,
files findings, and a themed release folds them in within a day or two, so a
release need not move the frontier at all. **v0.9 is released; the push to
the end of the World of Balance is v0.10's job.**

**On versions:** 0.9 is followed by **0.10**, not 1.0 — these are ordinary
increments, not a countdown. 1.0 is a long way off: the end of the World of
Balance is roughly the game's halfway point, and the World of Ruin is
entirely unstarted. (1.0 is still the line where saves become
forward-compatible — see CONTRIBUTING — it is just nowhere near next.)

Rungs are useful stopping points, not a promise to ship every number
separately. Adjacent rungs may combine when implementation and playtesting
make that the better release.

**Design canon:** *on damage verbs boost multiplies; on chance verbs
boost guarantees.* Steal ships it (3 BP = a guaranteed steal of the rare);
Dance / Sketch / Slot / Rage inherit it when their characters arrive.

**Release discipline:** every distributable is built through `make patch`,
which refuses any ROM the test suite has not stamped green. The human bar
is the owner's ratchet rule: never release an inferior experience — a tag
must be at least as good as previous releases as far as the owner has
played; unplayed frontier ships on the machine gates with its gaps
documented, and the owner's playthrough trails behind.

## M4 — Skill lists on the native verbs — shipping piecemeal

Landing across releases rather than as one block. Still open:

- **Per-character 8-skill kits enforced** with scripted learn
  schedules (levels/items/deeds/story — design/kits.md): **likely no JP
  system**; JP returns only if playtesting wants a pacing knob.
- **Curated-kit machinery** for Gau/Strago (learn many, equip ~5 — the
  Ochette/Hikari model); menu-bank work remains in ca65.
- **Passives** unlock at 2/4/6/8 skills learned.

**Exit:** fresh save through Zozo with every character on their kit.

## M5 — Magicite as sub-jobs

- Esper equip grants its spell list live (usable while equipped, gone
  when unequipped); permanent learning and level-up esper bonuses
  removed; summon stays a once-per-battle divine.
- **Augment, not replace** (owner call): the born mages (Terra/Celes)
  keep their innate spells and the esper adds a second job; everyone
  else's magic *is* whatever magicite they hold — pure Octopath sub-job.
- **Stat mods are the simple while-equipped kind** (hold it, get the
  bump); the "earn-it-by-carrying" passive version is deferred.
- Boost spell-folding is source-agnostic, so a borrowed Fire folds to
  Firaga under boost — not for free: the fold reaches untaught tiers
  (kept, deliberately: it is what lets every spell list stay at 8) but
  pays that tier's real MP for them.
- Every esper receives its own complete redesign in the release where it
  becomes available. The while-equipped spell/stat model is canon;
  learned passives are not a hidden requirement.

**Exit:** swapping magicite mid-dungeon visibly swaps a character's kit.

## M6 — Tuning pass — per-stretch, alongside each release

Runs with each rung's balance pass rather than as one late block; the
lesson is that break/boost only *land* with authored weaknesses, and only
measured against real fixtures. Still open:

- **Sealed Gate / banquet**, **Thamasa**, and **IAF / Floating
  Continent**: extend the same measured authoring discipline to each newly
  supported route band. Boss shield/class data already reaches Nerapa, but
  authored rows alone do not make those frontiers release-ready.

**Exit:** the opening third of the game plays as a coherent Octopath-like.

## Stretch

- True round-based turn order with visible queue (replaces ATB).
- Shield pips / weakness icons as real battle-UI graphics.
- Passive-equip menu (choose 4), damage cap raise, Trance rework,
  Gau capture/stable UI.
