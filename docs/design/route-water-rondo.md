# Water Rondo: the World of Balance detour (#428)

MOG learns Water Rondo from a battle on the `UNDERWATER` background, and
the only such battles are the Serpent Trench's. The detour that reaches
them is played the first time the airship belongs to the party, between
the Narshe mission meeting and the Imperial Base (`gen_water_rondo`,
between `narshe-mission-v1` and the new cut `water-rondo-v1`). The owner
set this route:

1. **Lone Wolf, for MOG.** `_ccd3ce` fires on the elder's house's
   arrival tile (30 (79,17)) once `$0070` is set. The chase runs 20
   (49,37), 20 (38,20), and 21 (31,22) ("Persistent, aren't you!"). It
   then goes north through the mines: 21 (30,20) → 43, 43 (113,45) → 41,
   41 (57,21) → 41 (25,58), 41 (18,51) → 21, 21 (24,10) → 41, and 41
   (117,12) → 21 (32,10). From there it goes over the snowfield (22) to
   the cliff (23 (22,20)). At 23 (9,18), "Halt!" starts a 240-frame timer
   (`_ccd4fe`). The party stands still until it runs out (a step back onto
   (8,19), (10,19) or (9,20) is `_ccd523`, which stops it). "Kupo!!": MOG
   and the wolf fall to the two ledges (`_ccd52d`). Talking to MOG on the
   west ledge (obj 28 at (5,16), `_ccd5df`) sets `$02FA` and `$029F` and
   opens his naming menu. **A player who takes MOG gives up the Gold
   Hairpin**: the wolf's ledge (`_ccd594`) is the other choice, and only
   one of the two runs. The way out is the chase's way back, through the
   mines.
2. **The swap room.** MOG is seated in the Blackjack's swap room and
   SETZER is benched. MOG wears the bag's best helmet and armor.
3. **Nikeah's chocobo.** The airship lands on (116,61). The stable (173,
   keeper (85,45), talked to across the counter from (87,45), `_ca8fb4`)
   rents a chocobo for 150 gil and sets the ride down at world (116,61).
   The chocobo stops at tiles with WorldTileProp bit `$0001` set
   (world/move.asm). A live BFS over that bit finds a 204-step path to the
   tile beside Barren Falls (185,93). The bird is steered with up plus
   left/right against the heading word `$73`. It cannot enter the falls,
   so B dismounts beside it, and the bird returns to its pen.
4. **Barren Falls to the Veldt.** The route is 166 (7,4) → 155, 155
   (10,4) → 156. Facing up onto row 10 (`_cbc03f`, `$01B0`) asks
   "Jump?". With `$003F` set, the leap ends on the Veldt at world
   (192,106) (`_cbc1fb`).
5. **The trench.** The party crosses the Veldt to Crescent Mountain
   (214,148), then goes 167 (25,26) → 168. The (8,11) "Jump?" (`_cbc84d`)
   gates only on `$0041`. The dive (`_ca8ae3`) is gen_sabin_trench's ride
   with the same three-attempt reload ladder, holding LEFT. Its battles
   19/20/21 teach Water Rondo (`$1D4C` bit 5) with MOG present.
6. **Nikeah.** The dive lands on Nikeah's dock (187), where the Blackjack
   waits. The cut is the world save on its tile, (116,61). The
   `water-rondo-v1` contract holds `$1D4C` bit 5, `$02FA`, `$029F` and the
   party LOCKE EDGAR SABIN MOG.

Downstream, `gen_gate_cave_save` boots `water-rondo-v1` on the Blackjack's
tile at Nikeah and seats TERRA in MOG's place. In the World of Ruin, MOG's
meeting takes the `$029F` branch ("You're alive!", no naming menu;
route-wor-narshe.md item 3).

Evidence: the dev run on px13 (`build/lab/wr/g2.log`) reads
`[wr] dive attempt 1 LANDED at Nikeah f54321, dances $61` and
`PASS (frame 56786)`. `$61` is bit 5 (Water Rondo), bit 6 (Dusk Requiem, known at
boot), and bit 0 (Wind Song, from the Veldt's grass).

Varied luck (8628f28d, from the qualified narshe-mission-v1): twelve seed
shifts, plus K = 1 to 4 world battles fought outside Narshe before the
chase (K = 2 and K = 4 also at shift 7). 18 of 18 passed, each on its
first attempt, with no retries, no deaths, and every dive landing on
attempt 1 with `dances $61`. The runs fought 97 battles over 155
distinct battle keys (`be..-g....`). Logs are in
`build/attempts/wt-v029-waterrondo/varied-keys-8628f28d/`, and the lab
generator is `build/lab/make_wr_variant.py`.
