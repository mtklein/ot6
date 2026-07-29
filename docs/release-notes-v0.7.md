# OT6 v0.7 — the playtest release

OT6 is a ROM hack of Final Fantasy VI (released in North America as
Final Fantasy III). It is distributed as a BPS patch containing only the
differences from the original game.

This release folds in everything the v0.6 playthrough turned up, plus
Gau's kit. The playable frontier is unchanged from v0.6 — this one is
about the game *feeling* right where you already are.

## How to play

Apply `ot6-v0.7.bps` to a Final Fantasy III (USA) 1.0 ROM with SHA-1
`4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7` using a BPS patcher such as
Flips or beat. The patcher will reject any other ROM.

Play from the beginning through the Raid on Vector, the same supported
stop point as v0.6: the first stable world-map moment after Terra
rejoins.

## What's changed since v0.6

**You can see your MP now.** Every costed submenu — Blitz, Tools,
Bushido, Dance — shows the character's current MP beside the prices, and
the field menu no longer hides MP for characters who know no spells.
Vanilla FF6 had no battle MP display at all, and its field menu only
showed MP once your party owned an esper; the economy made MP everyone's
resource while the interface still treated it as a caster detail.

**The HUD keeps time with the fight.** Boost pips now disappear at the
moment the boosted ability resolves, not at the next menu restage — they
were vanishing up to 564 frames early. A revealed weakness now appears
on the frame the matching damage lands, and appears under *every* enemy
of that species at once; reveals used to fire ~370 frames early, at
damage calculation, and never propagated to siblings at all.

**Dance costs MP** — 8, paid once when the dance begins, with the rest of
the trance free. A dance you can't afford is refused cleanly instead of
starting the whole-battle state for nothing.

**Bushido costs at least one Boost Point.** The free tech is gone and the
loadout window is 1x/2x/3x. Cyan's sword-art is spending banked time now;
the free swing is what Fight is for. Your loadout carries over — the
three techs the old window put at boosts 1/2/3 are exactly the three the
new AUTO picks.

**The SwdTech page is readable.** It was rendering as garbled tile soup —
its labels had been assembling under the ending-credits font with no
string terminator, so each one sprayed up to 256 tiles across the page.
That shipped in v0.5 and v0.6. Its layout was also wrong underneath the
garble: rows drawn at half height, and three of four learned-pool rows
outside the window entirely.

**Menus stop showing other lists' contents.** Backing out of a boosted
Magic list within a few frames used to leave a shared drawing cycle
stranded, so the next window you opened — Tools, Item, anyone's Magic —
drew its rows over the old list's tiles. Present since v0.1.

**Setzer's Slot answers to boost.** 0 BP is vanilla to the byte; 1 BP
stops the machine cheating against you; 2 BP tilts it in your favor;
3 BP gives you the triple of whichever reel you stop first. Certainty
replaces the damage multiplier, the same way Steal works.

**True Knight banks a Boost Point** when it takes a hit for a weakened
ally — once per round, and the pip lands as the blow does. *(Thanks to
[@TimRahaim](https://github.com/TimRahaim) for the idea.)*

**Gau becomes a hunter with a loadout.** Keep hunting the Veldt for
every rage you can find — that part is unchanged — but battle offers a
chosen **eight**, configured under Skills → Rage, instead of a wall of
two hundred. Rage costs 8 MP at the start of the trance, Leap costs 2,
and boost buys certainty: at 3 BP the special comes out every turn
instead of on a coin flip.

**Six magicite become real sub-jobs.** Maduin, Shoat, Phantom, Carbunkl,
Bismark and Unicorn each get a designed identity — Maduin the pure mage
(three elements and the strongest stat bonus in the game so far),
Unicorn the paladin (Pearl and Remedy), Bismark tempo, Carbunkl the
mirror, Phantom the ghost, Shoat the executioner. Three of them were
shipping actively broken: Maduin's spells were dead pre-folded tiers,
Bismark granted revival against our own design rule, and Shoat granted a
spell four of five cave species absorb.

## Also in here, less visibly

The Sealed Gate route is mapped and minted as far as the airship crash,
with save-point battery anchors at each boundary — groundwork for v0.8.
The world-walking test harness was spending 139 frames per tile where 16
would do. And a stack of harness gaps closed: pages that no test had ever
rendered, tests that passed against fixtures minted for different bytes.

## What we'd like to know

- Does Bushido's one-pip floor make Cyan feel like a Boost character, or
  just poorer? (The tuning lever if it's the latter is BP regeneration,
  not the floor.)
- Gau's eight: is configuring the loadout interesting, or a chore you'd
  rather AUTO handled? Do the eight feel like enough?
- With MP visible everywhere: does the economy read as decisions, or as
  rationing?
- Do the pip and weakness timings actually feel connected now?
- Anything that got *worse* than v0.6 — that's the one thing this release
  must not have done.
