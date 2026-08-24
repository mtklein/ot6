# Pre-FC World-of-Balance wrap-up — the plan (#133)

> **Owner goal (2026-08-22):** thoroughly cover the WoB *before* the Floating
> Continent. No rush to the FC. This is both the owner's own playthrough and a
> completeness pass over the whole game's areas and tuning — so it includes
> **tuning** the optional content (e.g. the optional espers), not just reaching
> it. Approach A: full headless coverage where feasible.
>
> Status legend: ☐ todo · ◐ in progress · ☑ done. Kept current as work lands.

## ▶ STATUS (2026-08-24: the wrap-up is done as far as the game permits)

Everything below is complete except two items **blocked by #134** (the
Narshe cliff is unreachable, so WoB Mog — and Water Rondo, which needs
him — wait on an owner call).  The headline results:

- **Grind**: L15–17 → **L24/L24/L25** (two rounds, ~45 fights, zero
  wipes) over the rolling-chunk driver; gil funded the whole shopping
  and esper program along the way.
- **IAF verdict (item 1's verify): balance signal for #132.**  At L24
  with Ramuh-granted Bolt cast every round, Earrings ×2, RunningShoes
  haste, and the pre-FC gear ceiling, attrition still wins in wave 7 of
  8.  Full analysis in `floating-continent-route.md`.
- **Espers**: Golem + Zoneseek won at the Jidoor auction (lot RNG
  decoded; decline-unless-target bidding), Sraphim bought at Tzen
  (hidden roof path).  All three in — the WoB-optional set is complete.
- **Shopping**: Earrings ×2, Sniper Sight, RunningShoes; the armor
  ceiling finding is in the sweep notes.
- **Sweep**: done; findings under item 8.
- Chain fixtures: `wob_grind_run.mss` (L24 party at the pocket, the
  live head of the chain), plus per-leg banks named in the probes.

## ▶ old resume note (2026-08-23: landed at the grind spot)

**The party is landed at the decoded grind pocket** — `probe_land_grind.lua`
flies the Blackjack closed-loop from `iaf_deck` to world tile **(116,25)**,
lands, and saves `build/states/wob_grind.mss` (party on foot beside the
parked ship).  The grind spot question is answered from the ROM data, no map
knowledge needed: `world_battle_group.dat` sector (X 96–127, Y 0–31) grass
slot → group 22 = **Chimera+2×Cephaler (form 190, 1572 XP) at ~62.5%**, rest
3×Cephaler; **no pincer-capable formation**; Cephaler is weak bolt (the two
ThunderBlades).  The walkable+landable pocket is X 113–119 / Y 25–26 (tile
prop `$0044`), nearest entrance 8 tiles away across mountains.  Verified
live: the probe's paced encounter drew species `001F 0096 0096` and fled it.

**The grind is DONE (2026-08-23):** `probe_grind_run.lua` chunks (5 fights
per green run over the rolling `wob_grind_run.mss`, fieldCare between
fights, hard fights fled at 9k battle frames) took the active party
TERRA/LOCKE/STRAGO/RELM from L15–17 to **L21/L21/L22/L21** in 28 fights,
zero wipes.  Final state: `build/states/wob_grind_done.mss` (party on foot
at the pocket, healed, beside the parked Blackjack).  Balance read: form
190 is a fair fight-everything grind at these levels — the only walls were
driver artifacts (heal-treadmill on bad Aqua Rake streaks, both fixed in
the chunk driver), not tuning problems.

**Immediate next step:** re-board the parked Blackjack from
`wob_grind_done.mss` and verify the IAF gauntlet is survivable post-grind
(`probe_iaf_fight.lua`).  **Then** the checklist below in order (shop →
Mog+Water Rondo via the Serpent Trench → obtain Golem/Zoneseek/Sraphim).
Esper *tuning* (#6) and the esper *audit* (#7) are already done.

## The party's starting point (thamasa_done, the stop line)

L15–17, ~10 under vanilla's FC expectation; two ThunderBlades (bolt — the IAF/FC
key), empty relic slots on 3/4. Full detail in `level-curve.md`. Blackjack
repaired; the whole WoB world map is reachable.

## Enabling tooling

- ☑ Airship-driver: board → discovery → deck → party-select → IAF (`probe_iaf.lua`, #131).
- ☑ **Airship flyable + landable** (`probe_grind.lua`) — cracked, owner-guided:
  settle ~150f post-Lift-off; MOVE with **Y-strafe** (hold Y + dir = clean grid
  movement, no momentum; release stops dead) — "like walking on a grid"; A+heading
  for gross travel; **LAND with B** over OPEN interior land only (away from
  mountains/water/forest/coast edges — bad tiles bounce, `$19`~6 then reverts;
  the shadow marks the set-down tile). Proven end to end: crossed west and landed
  the party on foot (at Sabin's house). Registers: X=$33/$35, Y=$37/$39, heading
  $73, B=$05 bit7, LandAirship=$EE936E.
  - ◐ Next: land in OPEN world terrain (not on a location entrance) to grind —
    needs knowing where open plains are → decode the WoB tile landability / map.
- ☐ Chocobo rental + overworld nav (for the Serpent Trench leg).
- ☐ On-foot dungeon nav reused from the harness (navTo) for Narshe mines, the
  Serpent Trench, auction/shop menus.

## The wrap-up checklist

1. ☑ **Grind** — L21–22 (2026-08-23), extended to L24/24/25 (-08-24);
   the IAF verify ran (`probe_iaf_fight3.lua`) and produced its answer:
   NOT survivable at any pre-FC level/kit — a #132 balance signal
   (`floating-continent-route.md` has the verdict and the retune levers).
2. ☑ **Shop** — Earrings ×2 + Sniper Sight (Jidoor), RunningShoes
   (Tzen), all equipped for the verify.  Armor: the pre-FC ceiling is
   Mithril/Gaia (see the sweep).
3. ⛔ **Mog** — BLOCKED by #134 (the cliff is unreachable; chase drives
   to $023C and every mines route dead-ends — fixtures banked for repro).
4. ⛔ **Water Rondo** — BLOCKED by #134 (needs Mog aboard).  The leg is
   otherwise ready: the Crescent dive's post-scenario arm is live
   ($0041=1, "Jump?"), the mountain door is (214,148), and the deck
   party-change (talk to any crew member) covers the swap.
5. ☑ **Optional espers — obtained** (2026-08-24): Golem + Zoneseek at
   the auction, Sraphim at Tzen.  The full pre-FC esper set is aboard.
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
8. ☑ **Sweep for other WoB optional content** reachable by airship pre-FC —
   findings so far (2026-08-24):
   - **Vector burns with the story** ($0079): its shops — the only WoB
     Thunder Rod and the whole Gold armor tier — are gone pre-FC.  The
     pre-FC armor ceiling is Mithril/Gaia/bard tier; the IAF attrition
     data (wave 7 of 8 at L21/22 with that tier) is the live consequence.
     Tuning question for #132: is that ceiling intended?
   - **Colosseum**: WoR-only, nothing pre-FC.  **Moogle-den carving /
     Terrato**: verified to live in Umaro's WoR cave (map 283) — the
     esper audit's WoR gating stands.
   - **Gau rages**: the Veldt is airship-reachable pre-FC for leaps
     (optional; Gau is L15 and benched in this route).
   - The full WoB town roster is now decoded from the entrance data (45
     doors + 9 event triggers; see the 2026-08-24 commits): the gated
     doors (64,76)/(30,48)→map 55 [$010B/$010C] and (179,71)→map 117
     [$0037] are story-locked in this state.

## Then (out of scope for this goal, tracked in #132)

The FC arc itself — IAF → Floating Continent → AtmaWeapon → the humane escape →
WoR landing — once the party is prepped.  This wrap-up is #133 (milestone
v0.14) and blocks #132; commits for wrap-up work reference #133.
