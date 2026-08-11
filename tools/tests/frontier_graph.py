# frontier_graph.py -- THE generated-savestate graph, as data (issue #25).
#
# One entry per generated state, in play order.  frontier_ninja.py (in
# tools/tests/lib) reads this list and emits build/build.ninja; nothing else
# consumes it.  The graph used to live as ~104 make rules plus three macros
# (mint / mint_anchor / stackseed) plus a grep-generated include; every axis
# of it now rides ONE field here:
#
#   S("arvis_wake", gen="gen_arvis", prev="whelk_doorstep")
#       the plain form: boot the predecessor's savestate, run the generator,
#       publish <state>.mss + <state>.mss.lua through tools/tests/run.sh.
#
#   S("vector_doorstep", gen="gen_vector_doorstep", anchor="post-opera-v1")
#       generated from a CHECKPOINT: cold-boot the tracked SRAM checkpoint in
#       tools/tests/anchors/<key>/ instead of a predecessor savestate.
#       Cutting a step loose at a save-point boundary (the A-F sequence
#       lettered in the boundary comments below) is exactly this: prev=
#       becomes anchor=.
#
#   S("t2_rapids_start", gen="gen_rapids", prev="t2_scenario_hub", stack="t2_")
#       a STACKED state: compose.py replays the generator's route logic
#       against prefix_-named fixtures (OT6_STACK) -- see SCENARIO STACKING
#       below.
#
#   S("t2_scenario_hub", seed="locke_done")
#       a stack SEED: a pure copy of a finished chain's ending under the
#       stacked chain's boot name.  No generator, no emulator.
#
#   S("whelk_doorstep", gen="gen_whelk_poweron", after="battle2_doorstep")
#       generated from power-on (no savestate input) and ORDERED after
#       another state so the two emulator runs never race, without inheriting
#       its staleness -- ninja's order-only dependency.
#
# What participates in a state's staleness (all by CONTENT, via the
# generator's latch edges -- a checkout's mtime bump regenerates nothing):
#   * the ROM (build/ot6.sfc),
#   * the generator .lua,
#   * all three composed-in lib halves: lib/ot6.lua, lib/ot6_field.lua and
#     lib/ot6_contract.lua (the invariant-contract half rides in every
#     composed script, so a contract edit re-runs every step that asserts it),
#   * for checkpoint-booted states, the checkpoint's manifest.json and every
#     *.sram payload,
#   * the predecessor's generated state, transitively.
#
# S() takes keyword-only fields ON PURPOSE: a typo'd field name is a
# TypeError here, not a silently-plain entry downstream.


def S(state, *, gen=None, prev=None, anchor=None, seed=None, stack=None,
      after=None):
    return {"state": state, "gen": gen, "prev": prev, "anchor": anchor,
            "seed": seed, "stack": stack, "after": after}


STATES = [
    # ---- the suite's own fixtures (formerly STATE1/2/3 in the Makefile) ----
    # `make test` needs these three; they ride the same graph and the same
    # staleness mechanism as everything downstream of them.
    S("battle_doorstep", gen="gen_battle_state"),
    # first_battle: gen_battle_state's second artifact (the in-battle state
    # battle_levelup/battle_smoke boot). Under the one-edge-one-artifact
    # publish rule (#30) the battle_doorstep edge no longer republishes it,
    # so it needs its own edge or a ROM change strands it stale -- which is
    # exactly how battle_levelup broke during the Slot landing (9229881's
    # report). after= orders the two identical emulator runs, no data dep.
    S("first_battle", gen="gen_battle_state", after="battle_doorstep"),
    S("battle2_doorstep", gen="gen_battle2", prev="battle_doorstep"),
    # whelk_doorstep: the dialog-opening boss fight battle_dlgmenu tests.
    # gen_whelk_poweron generates it from COLD POWER-ON -- plays the New Game
    # intro through the Narshe gauntlet to the mines -- so it consumes no
    # predecessor savestate; `after=` only keeps the three suite states from
    # racing each other's emulator boots, exactly the order make ran them in.
    S("whelk_doorstep", gen="gen_whelk_poweron", after="battle2_doorstep"),

    # ---- the story chain past the whelk -----------------------------------
    # Each link consumes the previous link's savestate, so the order below is
    # the order the game is played:
    #
    #   whelk_doorstep  -> gen_arvis          -> arvis_wake
    #                   -> gen_narshe_escape  -> narshe_streets
    #                   -> gen_mines_chase    -> moogle_doorstep
    #                   -> gen_moogle         -> moogle_cleared
    #                   -> ...                                (this file)
    S("arvis_wake", gen="gen_arvis", prev="whelk_doorstep"),
    S("narshe_streets", gen="gen_narshe_escape", prev="arvis_wake"),
    S("moogle_doorstep", gen="gen_mines_chase", prev="narshe_streets"),
    S("moogle_cleared", gen="gen_moogle", prev="moogle_doorstep"),
    # moogle_defense: gen_moogle's second artifact (mid-set-piece, MOG
    # leading P2) -- the first_battle pattern (#41): one edge per artifact,
    # or the fixture silently goes stale while its sibling regenerates.
    # battle_dancemp consumes it (the only real MOG-with-Dance window the
    # chain has; measured 2026-08-10, the set piece is where dances are
    # learned, so no earlier fixture can host that test).
    S("moogle_defense", gen="gen_moogle", after="moogle_cleared"),
    S("worldmap_narshe", gen="gen_worldmap", prev="moogle_cleared"),
    S("figaro_doorstep", gen="gen_figaro", prev="worldmap_narshe"),
    S("figaro_intro", gen="gen_edgar", prev="figaro_doorstep"),
    # same script, later states; each keys on its own file so a half-run
    # re-runs
    S("figaro_matron", gen="gen_edgar", prev="figaro_intro"),
    S("figaro_cleared", gen="gen_edgar", prev="figaro_matron"),
    # gen_kolts: the chocobo dismount, the South Figaro cave, and the mountain
    S("south_figaro", gen="gen_kolts", prev="figaro_cleared"),
    S("kolts_doorstep", gen="gen_kolts", prev="south_figaro"),
    S("vargas_doorstep", gen="gen_kolts", prev="kolts_doorstep"),
    # gen_kolts_pool: one crossing past kolts_doorstep onto map 100 shelf F.
    # That map (95) is transit only and carries no encounter group --
    # 437 paced tiles there drew nothing -- so balance runs that want the
    # Mt. Kolts trash pool need this one, not kolts_doorstep.
    S("kolts_pool", gen="gen_kolts_pool", prev="kolts_doorstep"),
    # gen_kolts_cave: one more crossing, onto map 96.  Shelf F (map 100) is
    # encounter group 63 -- Brawler/Tusker -- and that is ONE of the
    # mountain's four groups.  Maps 96/97 carry group 61, which is CIRPIUS x3
    # at 93.75% of draws: the mountain's most common fight, and the one the
    # trash-weakness pass is built around.  kolts_pool cannot draw it, so it
    # needs its own.
    S("kolts_cave", gen="gen_kolts_cave", prev="kolts_pool"),
    # gen_vargas: the fight itself, finished by Pummel, and the reunion
    S("vargas_won", gen="gen_vargas", prev="vargas_doorstep"),

    # ---- tier 3: the road to the scenario split ----
    # gen_returner: off the mountain's north side and across the world map
    S("returner_hideout", gen="gen_returner", prev="vargas_won"),
    # gen_banon: the hideout's conversation graph, ending just before the raft
    S("banon_joined", gen="gen_banon", prev="returner_hideout"),
    # gen_lete: the short walk to the raft -- kept its own link so that a
    # failed experiment on the river replays 530 frames, not the whole hideout
    S("lete_river", gen="gen_lete", prev="banon_joined"),
    # gen_scenario: the river (steered past its vanilla loop), ULTROS, and
    # the three-way split -- the entry point of the v0.3 arc
    S("scenario_hub", gen="gen_scenario", prev="lete_river"),
    # one step PAST the hub: proves the split is dispatchable and hands the
    # v0.3 Locke chain its entry point.  The Sabin and Terra/Banon branches
    # start from scenario_hub the same way.
    S("locke_scenario", gen="gen_scenario_locke", prev="scenario_hub"),

    # ---- the TERRA/BANON scenario: the shortest of the three, from the hub -
    # gen_rapids: talk to Terra at the hub, resume the raft down the lower
    # Lete (the FORCED battle 8 plus two if_rand fights), spill onto the
    # world map.  Two states: rapids_start is the cheap entry point UPSTREAM
    # of the forced fight; rapids_done is on foot on the WoB NE of Narshe.
    S("rapids_start", gen="gen_rapids", prev="scenario_hub"),
    S("rapids_done", gen="gen_rapids", prev="rapids_start"),
    # gen_terra_narshe: the world walk into Narshe and the townsfolk's
    # turn-away at the checkpoint (which shoves the party back south, $001F)
    S("terra_narshe", gen="gen_terra_narshe", prev="rapids_done"),
    # gen_terra_caves: open the secret wall Locke used (an EXAMINE facing up
    # on (15,57)) and step into the mines -- the only fixture in this
    # scenario's random-encounter pool
    S("terra_caves", gen="gen_terra_caves", prev="terra_narshe"),
    # gen_terra_clifftop: the length of the caves -- maps 41/20-pocket/48/49/
    # 50 -- including map 49's 13-gate ordered block maze, out onto the
    # clifftop
    S("terra_clifftop", gen="gen_terra_clifftop", prev="terra_caves"),
    # gen_terra_done: into Arvis's house, onto the meeting trigger _ccb3fa,
    # and out the far side with $0021 set -- the scenario complete
    S("terra_done", gen="gen_terra_done", prev="terra_clifftop"),

    # ---- SABIN's scenario: the longest of the three v0.3 branches ----
    # gen_sabin_world: the hub dispatch, the overworld landing at (161,36),
    # SHADOW's house (map 115) and the walk to the Imperial Camp.  Two states
    # from one script so an experiment on the house replays 700 frames, not
    # the hub as well.
    S("sabin_world", gen="gen_sabin_world", prev="scenario_hub"),
    S("sabin_camp", gen="gen_sabin_world", prev="sabin_world"),
    # gen_sabin_camp: one step south of the camp gate hands the game to CYAN
    # on map 120 for ~9,000 frames (the Doma defence, name menu and all)
    # before SABIN gets it back.  cyan_defence is generated mid-run so an
    # experiment on the commander fight replays 800 frames instead of 6,000.
    S("cyan_defence", gen="gen_sabin_camp", prev="sabin_camp"),
    S("camp_intro", gen="gen_sabin_camp", prev="cyan_defence"),
    # gen_sabin_kefka: the LEO scene, the poisoning, both KEFKA
    # script-battles, the pursuit, and the handoff back to CYAN on the Doma
    # grounds.
    S("kefka_done", gen="gen_sabin_kefka", prev="camp_intro"),
    # gen_sabin_doma: CYAN's run home through the Doma Castle room maze, the
    # family scene, and the handoff back to SABIN at the castle gate.
    S("camp_cleared", gen="gen_sabin_doma", prev="kefka_done"),
    # gen_sabin_escape: the Doma courtyard defence -- three talk-to-CYAN
    # fights, CYAN joins, everyone mounts Magitek.  Stops at (14,30), the
    # escape's starting line (the escape walk itself is the next step).
    S("doma_defended", gen="gen_sabin_escape", prev="camp_cleared"),
    # gen_sabin_magitek: the Imperial Camp escape -- ride the fight/interlude
    # gauntlet out to the World of Balance.  Battles 15/16/17 are each WON BY
    # TAP-A (writing the battle-clearing flag instead softlocks on GameOver),
    # and each latchless re-firing trigger is left by holding the corridor's
    # walkable direction through the ~25% control flap (see the generator
    # header).
    S("camp_escaped", gen="gen_sabin_magitek", prev="doma_defended"),
    # gen_sabin_forest: the Phantom Forest -- world (178,82) into map 132,
    # the 132->133->134->135->140 chain (map 133's one-way recovery spring is
    # a MANDATORY conveyor past its back-exit), then boarding the Phantom
    # Train at 140 (72,11) -> map 145.  Generates forest_done on the train.
    S("forest_done", gen="gen_sabin_forest", prev="camp_escaped"),
    # gen_sabin_train: the Phantom Train, boarding to the Ghost Train's fall
    # -- the maze decoded and driven, and battle 68 fought with real Blitz
    # inputs: the 6-shield OT6_BLUDG row chip-proven at runtime.  Ends on the
    # world map at (178,93) with $003A/$003B set.
    S("train_done", gen="gen_sabin_train", prev="forest_done"),
    # gen_sabin_falls: Baren Falls -- the jump, battle 18 mid-fall (RIZOPAS
    # surfaces in slot 5 off the piranhas' death script), SHADOW's exit, GAU
    # named on the Veldt shore.
    S("falls_done", gen="gen_sabin_falls", prev="train_done"),
    # gen_sabin_gau: Mobliz's Dried Meat, the Veldt grind (GAU appears on the
    # 3/8 end-of-battle roll), and his return-visit self-recruit -- the
    # generator header documents the one concession ($3EBD bit 1).
    S("gau_joined", gen="gen_sabin_gau", prev="falls_done"),
    # gen_sabin_trench: Crescent Mountain's helmet chain (GAU-gated), the
    # Serpent Trench ridden as a real VEHICLE script, Nikeah, and the ferry's
    # option-1 prompt -- $0044=1 and the hub.  SABIN's scenario closes here.
    S("sabin_done", gen="gen_sabin_trench", prev="gau_joined"),

    # ---- tier 4: LOCKE's scenario, hub -> South Figaro -> TunnelArmr ----
    # gen_sfigaro: the occupied town.  The gate soldier (battle 11), then the
    # cafe's cider runner -- STOLEN from, not killed, because the merchant's
    # clothes come off the steal's reaction script and nothing else -- then
    # the old man's password and the rich man's secret passage.
    S("sfigaro_town", gen="gen_sfigaro", prev="locke_scenario"),
    S("sfigaro_passage", gen="gen_sfigaro", prev="sfigaro_town"),
    # gen_celes: the passage, the rich man's mansion (a warp maze, entered by
    # a deep door), the basement, the Celes chains cutscene + naming menu,
    # freeing her, and the sleeping soldier's clock key
    S("celes_freed", gen="gen_celes", prev="sfigaro_passage"),
    # gen_tunnelarmr: the clock's secret passage (the ONLY basement exit),
    # the escape through maps 87/86 to town, the world, the Figaro cave
    # walked in from the south, and TunnelArmr (battle 67, $0104) -- which
    # ends the Locke scenario ($001E=1, back at the hub).  Three states.
    S("sfigaro_escape", gen="gen_tunnelarmr", prev="celes_freed"),
    S("tunnelarmr_doorstep", gen="gen_tunnelarmr", prev="sfigaro_escape"),
    S("locke_done", gen="gen_tunnelarmr", prev="tunnelarmr_doorstep"),

    # ---- SCENARIO STACKING: the road to the reunion ------------------------
    # The reunion _caadb9 (event_main.asm:26683) needs $0021 && $001E && $0044
    # in ONE playthrough; each input-driven chain sets one.  compose.py's
    # OT6_STACK prefix replays a whole chain's ROUTE LOGIC from a different
    # boot: a stacked state composes the same generator with every .mss
    # basename prefixed, so it boots the prefixed predecessor and generates
    # prefixed artifacts -- the input-driven states are never touched.  The
    # full stack is LOCKE (input-driven) -> SABIN (s2_) -> TERRA (t3_); the
    # earlier two_done milestone (LOCKE + TERRA, t2_) proved the mechanism on
    # Terra's chain:
    #  * Terra's is the shortest chain, so that first stacking layer -- the
    #    one that had to prove the mechanism -- replays the least;
    #  * the THIRD chain's hub return fires the reunion instead of reaching
    #    the hub (the if_all at :26654), so whichever chain goes last cannot
    #    end on its own "back at the hub" check.  That final step belongs to
    #    gen_narshe_battle.  Terra takes it -- gen_terra_done's all-three
    #    fork is already reunion-aware -- so Sabin's chain goes second and
    #    its clean hub-return ending seeds the Terra layer.
    #
    # A stacked chain's "scenario_hub" IS the previous chain's ending: the
    # seed entries copy both halves (state + sidecar), and a regenerated
    # source (ROM changed, or the chain below replayed) re-seeds and the
    # stack above replays -- that is just the dependency edge now.
    S("t2_scenario_hub", seed="locke_done"),
    S("t2_rapids_start", gen="gen_rapids", prev="t2_scenario_hub",
      stack="t2_"),
    S("t2_rapids_done", gen="gen_rapids", prev="t2_rapids_start",
      stack="t2_"),
    S("t2_terra_narshe", gen="gen_terra_narshe", prev="t2_rapids_done",
      stack="t2_"),
    S("t2_terra_caves", gen="gen_terra_caves", prev="t2_terra_narshe",
      stack="t2_"),
    S("t2_terra_clifftop", gen="gen_terra_clifftop", prev="t2_terra_caves",
      stack="t2_"),
    S("t2_terra_done", gen="gen_terra_done", prev="t2_terra_clifftop",
      stack="t2_"),
    # the acceptance check: asserts BOTH flags on the stacked ending and
    # re-saves it under the canonical name (gen_two_done.lua's header says
    # why the assert lives outside the mechanically-prefixed chain).
    S("two_done", gen="gen_two_done", prev="t2_terra_done"),

    # ---- the FULL stack: SABIN second (s2_), TERRA last (t3_) --------------
    # ORDER (from the reunion spike): whichever chain returns to the hub
    # THIRD rides the reunion instead of reaching the hub, so the final step
    # must be reunion-aware -- gen_terra_done is (its all-three fork generates
    # t3_reunion_ready at the map-22 staging).  Sabin's chain replays SECOND
    # on top of locke_done, ending at his hub return ($001E+$0044).
    S("s2_scenario_hub", seed="locke_done"),
    S("s2_sabin_world", gen="gen_sabin_world", prev="s2_scenario_hub",
      stack="s2_"),
    S("s2_sabin_camp", gen="gen_sabin_world", prev="s2_sabin_world",
      stack="s2_"),
    S("s2_cyan_defence", gen="gen_sabin_camp", prev="s2_sabin_camp",
      stack="s2_"),
    S("s2_camp_intro", gen="gen_sabin_camp", prev="s2_cyan_defence",
      stack="s2_"),
    S("s2_kefka_done", gen="gen_sabin_kefka", prev="s2_camp_intro",
      stack="s2_"),
    S("s2_camp_cleared", gen="gen_sabin_doma", prev="s2_kefka_done",
      stack="s2_"),
    S("s2_doma_defended", gen="gen_sabin_escape", prev="s2_camp_cleared",
      stack="s2_"),
    S("s2_camp_escaped", gen="gen_sabin_magitek", prev="s2_doma_defended",
      stack="s2_"),
    S("s2_forest_done", gen="gen_sabin_forest", prev="s2_camp_escaped",
      stack="s2_"),
    S("s2_train_done", gen="gen_sabin_train", prev="s2_forest_done",
      stack="s2_"),
    S("s2_falls_done", gen="gen_sabin_falls", prev="s2_train_done",
      stack="s2_"),
    S("s2_gau_joined", gen="gen_sabin_gau", prev="s2_falls_done",
      stack="s2_"),
    S("s2_sabin_done", gen="gen_sabin_trench", prev="s2_gau_joined",
      stack="s2_"),
    # TERRA/BANON's chain replays LAST, on top of two completions:
    S("t3_scenario_hub", seed="s2_sabin_done"),
    S("t3_rapids_start", gen="gen_rapids", prev="t3_scenario_hub",
      stack="t3_"),
    S("t3_rapids_done", gen="gen_rapids", prev="t3_rapids_start",
      stack="t3_"),
    S("t3_terra_narshe", gen="gen_terra_narshe", prev="t3_rapids_done",
      stack="t3_"),
    S("t3_terra_caves", gen="gen_terra_caves", prev="t3_terra_narshe",
      stack="t3_"),
    S("t3_terra_clifftop", gen="gen_terra_clifftop", prev="t3_terra_caves",
      stack="t3_"),
    # gen_terra_done on the all-three boot takes its REUNION FORK: rides
    # _caadb9's cutscene to the map-22 staging and generates t3_reunion_ready.
    S("t3_reunion_ready", gen="gen_terra_done", prev="t3_terra_clifftop",
      stack="t3_"),
    # the acceptance check (gen_two_done's shape, one layer up): assert ALL
    # THREE flags + the reunion on the stacked ending and re-save it as the
    # canonical reunion_ready -- the boot gen_narshe_battle consumes.
    S("reunion_ready", gen="gen_reunion_ready", prev="t3_reunion_ready"),

    # ---- the Battle for Narshe ---------------------------------------------
    # gen_narshe_battle: reunion staging -> BANON -> the three-party
    # assignment menu (P1=TERRA+EDGAR+CELES, P2=CYAN+SABIN, P3=LOCKE+GAU) ->
    # defense live -> the measured cliff descent -> just before the KEFKA
    # fight -> the scripted win.
    S("narshe_battle", gen="gen_narshe_battle", prev="reunion_ready"),
    S("kefka_doorstep", gen="gen_narshe_battle", prev="narshe_battle"),
    # kefka_won is v0.4's FIRST link and the input-driven chain's head: the
    # win tail (esper scene, TERRA's flight, the Arvis regroup and its
    # party-select menu) generates the map-30 boot the Zozo arc consumes.
    S("kefka_won", gen="gen_kefka_won", prev="kefka_doorstep"),

    # ---- v0.4: the search for TERRA (kefka_won -> Zozo) --------------------
    # gen_zozo1_submerge: Arvis's front door -> the south gate -> the EAST
    # castle trigger world {64,76} ($010B, set by kefka_won's tail) -> keep
    # -> the WEST engine-room door -> the attendant's Kohlingen choice ->
    # the scripted crossing -> castle parked WEST ($010C).
    S("figaro_submerged", gen="gen_zozo1_submerge", prev="kefka_won"),
    # gen_zozo2_arrival: out of the west castle, the long south-then-north
    # world hook around Zozo's mountain ring (177 steps), onto {22,92} ->
    # map 221's street.
    S("zozo_arrival", gen="gen_zozo2_arrival", prev="figaro_submerged"),
    # gen_zozo3_clock: the street's CAFE door (42,28) -> the clock room (map
    # 225) -> the clock tile {98,59} -> 6:10:50 across three CHAINED choice
    # dialogs, each verified by its own $01F* latch -> the hidden staircase
    # opens ($01F0).
    S("zozo_clock_solved", gen="gen_zozo3_clock", prev="zozo_arrival"),
    # gen_zozo4_dadaluma: the crane maze -- five doors, the stair room's
    # bandit conveyor, both jump rows, and the z-level loop onto the y=13
    # strip beside DADALUMA at (30,14).  Entry point = (30,13); the fight is
    # battle 69, won by writing the battle-clearing flag like Kefka/Vargas.
    S("dadaluma_doorstep", gen="gen_zozo4_dadaluma", prev="zozo_arrival"),
    S("dadaluma_won", gen="gen_zozo4_dadaluma", prev="dadaluma_doorstep"),
    # gen_zozo5_ramuh: the tower door (33,9) -> map 226 -> TERRA (talked
    # from the WEST) -> the pure-dialog RAMUH scene -> the four magicite ->
    # the leave cutscene -> $0054=1 at {57,45}, v0.4's stop line.
    S("zozo_done", gen="gen_zozo5_ramuh", prev="dadaluma_won"),

    # ---- v0.5 Beat A: the Opera (zozo_done -> the Blackjack) ---------------
    # gen_opera1_doorstep: zozo_done -> the world -> JIDOOR -> its north BUMP
    # door -> map 209 (the opera-plot room) -> parked at {117,20} facing UP,
    # one A-press below the IMPRESARIO ({117,19}, _ca9337).  The generator
    # self-verifies (after generating) that one A-press fires _ca9337.
    S("opera_doorstep", gen="gen_opera1_doorstep", prev="zozo_done"),
    # gen_opera2_open: DRIVE the opera-open cutscene chain on map 209 ->
    # Jidoor -> world -> the OPERA HOUSE (map 237) -> parked at {60,49}
    # below the now-VISIBLE IMPRESARIO.  Generates opera_open.
    S("opera_open", gen="gen_opera2_open", prev="opera_doorstep"),
    # gen_opera3_backstage: talk the IMPRESARIO -> RIDE the performance
    # intro -> controllable BACKSTAGE, map 234 {16,46}, $0055=1.
    S("opera_backstage", gen="gen_opera3_backstage", prev="opera_open"),
    # gen_opera4_stage: ROUTE A onto the STAGE via the opera-house interior;
    # talk CELES {99,19} (_caba44) to ARM the aria ($0056=1).
    S("opera_stage", gen="gen_opera4_stage", prev="opera_backstage"),
    # gen_opera5_dance: fire the aria trigger {97,7} -> map 236 -> the lyric
    # forks {0,1,0} -> the FLOWER DANCE (hand-coded corridorFollow stair
    # segments; map 236 is z-split) -> the balcony {8,9} -> _cabe6d ->
    # $0111=1.
    S("opera_dance_done", gen="gen_opera5_dance", prev="opera_stage"),
    # gen_opera6_rafter: the RAFTER CHASE -> ultros2_doorstep, one
    # interaction before battle 104 (Ultros II).
    S("ultros2_doorstep", gen="gen_opera6_rafter", prev="opera_dance_done"),
    # gen_opera7_blackjack: battle 104 (the route writes the battle-clearing
    # flag) -> Setzer's coin-toss bargain -> first stable controllable
    # world-map frame after the Blackjack lands outside Vector.  The v0.5
    # terminal fixture.
    S("blackjack", gen="gen_opera7_blackjack", prev="ultros2_doorstep"),

    # ---- v0.6: the raid on Vector and the Magitek Research Facility --------
    # The chain hangs off the tracked 32 KiB post-Opera SRAM checkpoint rather
    # than off blackjack.mss: gen_vector_doorstep cold-boots, drives vanilla
    # Continue into slot 3, and walks the world from there.  Every later link
    # is an ordinary savestate chain.  run.sh's persistent_layout check
    # refuses the checkpoint load BEFORE boot if the generator does not
    # declare its layout; the manifest + payload ride the dependency set,
    # so editing either regenerates every state hung off the checkpoint.
    S("vector_doorstep", gen="gen_vector_doorstep", anchor="post-opera-v1"),
    # gen_vector_sneak: the Returner sympathizer's choice dialog ($01F0) and
    # the FACING-GATED ledge on {43,38} -> control at {57,34}.
    S("vector_sneak", gen="gen_vector_sneak", prev="vector_doorstep"),
    # gen_mrf_entry: the column north to the {57,2} long entrance -> map 262,
    # MAGITEK FACTORY {28,8}.
    S("mrf_entry", gen="gen_mrf_entry", prev="vector_sneak"),
    # gen_mrf_chute: the one-way conveyor chute at {19,25} -> {10,45}.
    S("mrf_chute", gen="gen_mrf_chute", prev="mrf_entry"),
    # gen_mrf_263: the {11,45} conveyor -> {20,45} -> the scripted {22,53}
    # transition -> map 263 {22,18}.
    S("mrf_263", gen="gen_mrf_263", prev="mrf_chute"),
    # gen_mrf_kefka: the {24,18} ride to {40,30}, then the {40,32} trigger
    # row and Kefka's esper-drain scene -> $005F.
    S("mrf_kefka", gen="gen_mrf_kefka", prev="mrf_263"),
    # gen_ifrit_doorstep: the {37,44} chute -> map 264 {10,7} -> parked at
    # {3,7} facing IFRIT, one A-press from battle 70.
    S("ifrit_doorstep", gen="gen_ifrit_doorstep", prev="mrf_kefka"),
    # ---- boundary B: the map-270 save room ---------------------------------
    # ifrit_doorstep above is the terminal of step A->B; gen_ifrit_doorstep
    # also walks the save room and asserts B's exit contract pre-save, and
    # gen_mrf_save_room_anchor (run by hand, never by this graph) cut the
    # tracked SRAM checkpoint from it.  The step OUT of B starts from that
    # checkpoint: gen_ifrit_magicite cold-Continues it, asserts the entry
    # contract, walks back to the alcove, then battle 70 and the
    # four-interaction hand-off -> both magicite ($1A69's give_genju bits).
    S("magicite_ifrit_shiva", gen="gen_ifrit_magicite",
      anchor="mrf-save-room-v1"),
    # gen_n024_doorstep: 264 -> 269 -> 271 -> 273, the NEW #10 save point
    # at {26,53} (boundary C: exit contract pre-save + sparkle check),
    # then parked at {25,52} facing NUMBER 024, one A-press from battle 72.
    # B->C's terminal.
    S("n024_doorstep", gen="gen_n024_doorstep", prev="magicite_ifrit_shiva"),
    # ---- boundary C: the NEW 273 save point --------------------------------
    # The step OUT of C starts from a checkpoint for BOTH of gen_esper_tubes'
    # states: one script, one cold-Continue boot, two states -- a prev= edge
    # on the second would claim a predecessor the boot never loads.  battle
    # 72, then the {25,50} door into map 274 and the entry point for the
    # facing+A-gated BIG_SWITCH trigger.
    S("n024_won", gen="gen_esper_tubes", anchor="n024-doorstep-save-v1"),
    S("esper_tubes_doorstep", gen="gen_esper_tubes",
      anchor="n024-doorstep-save-v1"),
    # gen_esper_tubes_done: the Cid/Kefka set piece -- six espers, and CELES
    # leaves the roster ($02F6=0).
    S("esper_tubes", gen="gen_esper_tubes_done", prev="esper_tubes_doorstep"),
    # gen_minecart_doorstep: the lift -> map 266 -> map 272, the platform
    # save point {3,55} (boundary D: exit contract pre-save), then parked
    # beside CID, one A-press from `cutscene TRAIN`.  C->D's terminal.
    S("minecart_doorstep", gen="gen_minecart_doorstep", prev="esper_tubes"),
    # ---- boundary D: the minecart platform save point ----------------------
    # The step OUT of D (D->E, one whole step -- Number 128 lives mid-cutscene
    # and has no entry point, ever): the ride, the escape, and the park ON
    # boundary E, the $06AE-revealed save point 240 {58,7}.  gen_n128 boots
    # this checkpoint everywhere: `make smoke` hands it the same SRAM via
    # the Makefile's SMOKE_ANCHOR_* map (the dual-boot probe is retired).
    S("n128_won", gen="gen_n128", anchor="minecart-platform-v1"),
    # ---- boundaries E and F ------------------------------------------------
    # gen_vector_escape_anchor cuts E's tracked SRAM checkpoint from n128_won.
    # The E->F step (Cranes -> Terra's return -> the Esper-World flashback ->
    # takeoff -> the grounded-Blackjack world save at (24,121)) lives WHOLE
    # in gen_terra_returned_anchor -- §5 forbids splitting it (a save inside
    # the flashback would save as the WEDGE-actor Maduin) -- and cuts F's
    # checkpoint, `terra-returned-v1`: the v0.6 stop line and the checkpoint
    # v0.7's first step will hang from.

    # ---- v0.7: the Sealed Gate area (issue #31) ----------------------------
    # ---- boundary F -> boundary G ------------------------------------------
    # The first v0.7 step, and the second checkpoint-booted state in the tree:
    # cold-boot the terra-returned-v1 checkpoint, board and fly the parked
    # Blackjack to Narshe, drive the map-30 mission meeting to $0076=1, walk
    # back out, and save at the Narshe exit spawn, world (84,34) -- boundary
    # G, `narshe-mission-v1`.  ONE generator does the step AND cuts the
    # checkpoint, gen_terra_returned_anchor's shape, because the boundary is a
    # world SRAM save with nothing to author.  Re-cutting the SRAM itself is
    # still a deliberate by-hand operation:
    #     OT6_SRAM_ANCHOR=tools/tests/anchors/terra-returned-v1 \
    #     OT6_CAPTURE_SRM=tools/tests/anchors/narshe-mission-v1/narshe-mission.sram \
    #     tools/tests/run.sh tools/tests/gen_narshe_mission.lua
    #     python3 tools/tests/lib/sram_anchor.py seal tools/tests/anchors/narshe-mission-v1
    # This graph edge runs the same generator for its savestate and its
    # contract verdict; run.sh only captures SRAM when OT6_CAPTURE_SRM is
    # set, so generating a state can never quietly rewrite a tracked
    # checkpoint.
    S("narshe_mission", gen="gen_narshe_mission", anchor="terra-returned-v1"),
    # ---- boundary G -> boundary H ------------------------------------------
    # Step G->H, whole in one generator (gen_narshe_mission's shape): cold-
    # boot the narshe-mission-v1 checkpoint, seat TERRA / bench SETZER in the
    # Blackjack swap room (chase-talk the wandering NPC, YES on $0528, the
    # NO_RESET party menu), fly to the base pass, walk the Imperial Base
    # ($0172 -- TERRA is the hard gate, _cb25d6), the cave 382 -> 383 ->
    # the map-385 TIMED FLOOR (M.phaseWalk's union-graph crossing: arm A at
    # (3,2), window (6,2)->(7,2), arm B at (11,3), three windows down the
    # east half), 384's south loop to the (62,11) face-UP+A door switch
    # ($0173), and the map-386 vanilla save point (74,53) -- boundary H,
    # `gate-cave-save-v1`, the area's only interior save.  Re-cutting the
    # SRAM is a deliberate by-hand operation:
    #     OT6_SRAM_ANCHOR=tools/tests/anchors/narshe-mission-v1 \
    #     OT6_CAPTURE_SRM=tools/tests/anchors/gate-cave-save-v1/gate-cave-save.sram \
    #     tools/tests/run.sh tools/tests/gen_gate_cave_save.lua
    #     python3 tools/tests/lib/sram_anchor.py seal tools/tests/anchors/gate-cave-save-v1
    S("gate_cave_save", gen="gen_gate_cave_save", anchor="narshe-mission-v1"),
    # ---- boundary H -> boundary I ------------------------------------------
    # Step H->I, whole in one generator: cold-boot the gate-cave-save-v1
    # checkpoint, back down to BASEMENT 3, the WEST traverse (two levers --
    # (71,15) $0174 and the (104,17) $01F5 tap-once TOGGLE -- then the
    # (121,23)->(4,37) teleport; measured (the (58,18) span and the three
    # walk-overs are NOT on the route), the Sealed Gate
    # scene (battles 121/122 spared, never cleared by a flag write), the
    # $0079 tail, the (5,43) shortcut out, the base re-cross (battle 123
    # spared, the
    # scripted crash flight), off the wreck via the map-7 hatch (8,36),
    # and the world SRAM save at the crash site (83,239) -- boundary I,
    # `vector-crash-v1`.  Re-cutting the SRAM is a deliberate by-hand
    # operation:
    #     OT6_SRAM_ANCHOR=tools/tests/anchors/gate-cave-save-v1 \
    #     OT6_CAPTURE_SRM=tools/tests/anchors/vector-crash-v1/vector-crash.sram \
    #     tools/tests/run.sh tools/tests/gen_vector_crash.lua
    #     python3 tools/tests/lib/sram_anchor.py seal tools/tests/anchors/vector-crash-v1
    S("vector_crash", gen="gen_vector_crash", anchor="gate-cave-save-v1"),
    # ---- boundary I -> boundary J ------------------------------------------
    # Step I->J, whole in one generator (banquet-decode.md is the script;
    # #10 forbids any boundary inside the banquet block, so the step is
    # atomic): cold-boot the vector-crash-v1 checkpoint (the boot tile IS the
    # wreck -- no A press until the grind), the ~117-step world grind to
    # Vector 253, the castle escort, the dais face-UP+A, the 14400-frame
    # window, the dinner Q&A, the rest-break challenge (battle 30, fought),
    # the roster strip to TERRA+LOCKE, the (23,12) messenger, the castle
    # exit, and the world SRAM save at (120,188) -- boundary J.
    #
    # THE SCORE TIER IS SETTLED BY INPUT-DRIVEN PLAY (2026-08-09, issue #75):
    # the driven canon is 70 points -- window var0=21 (15 talks + 1 clean
    # Commando; talk ~210 window-frames/+1 vs fight ~2000+/+6, so the
    # window is talk-heavy by economics), Q&A +44, challenge +5 -- which
    # clears the >=67 tier and stays <77, so Tintinabar/Charm Bangle are
    # correctly ABSENT.  The old ">=90 Charm Bangle is canon for the chain"
    # reading died with the flag write that made it look reachable.  The
    # split engage guard makes the tier robust even if the recall +5 pays
    # nothing -- live, the first question's $0231 record bit never sets
    # (banquet-decode 4's recall model is unverified; probe_banquet_qa
    # asserts it but boots a fixture that never existed -- open on #75).
    # Re-cutting the SRAM is a deliberate by-hand operation:
    #     OT6_SRAM_ANCHOR=tools/tests/anchors/vector-crash-v1 \
    #     OT6_CAPTURE_SRM=tools/tests/anchors/banquet-done-v1/banquet-done.sram \
    #     tools/tests/run.sh tools/tests/gen_banquet_done.lua
    #     python3 tools/tests/lib/sram_anchor.py seal tools/tests/anchors/banquet-done-v1
    S("banquet_done", gen="gen_banquet_done", anchor="vector-crash-v1"),
]
