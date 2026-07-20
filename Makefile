BASE    := Final Fantasy III (USA).sfc
SHA1    := 4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7
FLIPS   := tools/bin/flips
MESEN   := tools/Mesen.app/Contents/MacOS/Mesen
VERSION := 0.1

# A failed recipe (e.g. the checksum step dying mid-build) leaves a half-built target the next make treats as up-to-date — bit us twice on 2026-07-18.
.DELETE_ON_ERROR:

.PHONY: all rom patch run test tested verify clean goldens-capture release frontier frontier-test

all: rom

# Refuse to build against anything but the verified FF3us 1.0 base.
verify:
	@echo "$(SHA1)  $(BASE)" | shasum -a 1 -c - >/dev/null \
		&& echo "base ROM verified (FF3us 1.0)" \
		|| { echo "ERROR: '$(BASE)' is not the FF3us 1.0 base ROM"; exit 1; }

rom: verify
	$(MAKE) -C ff6 ff6-en
	@mkdir -p build
	@# Copy only when the bytes actually differ. `rom` is PHONY, so its recipe
	@# runs on every `make frontier` (which lists rom as a prerequisite); an
	@# unconditional cp would rewrite build/ot6.sfc under the worker-isolated
	@# mints that `make -jN frontier` now runs in parallel, and a mint's Mesen
	@# reads that very file at boot. Same cmp-guard the state mints already use.
	@cmp -s ff6/rom/ff6-en.sfc build/ot6.sfc || cp ff6/rom/ff6-en.sfc build/ot6.sfc

# No distributable may be built from an untested ROM.  `test` stamps the
# sha1 of the exact ROM the suite passed on; `tested` refuses unless the
# ROM on disk is still that one.  This is structural on purpose: a human
# (or an agent) reading "green" off a scrolled-past terminal, or piping
# the suite through `tail` so the shell reports tail's exit status, is
# how v0.2 got tagged without anyone actually knowing the gate was green.
# Nothing here is allowed to depend on remembering to look.
STAMP := build/.suite-pass

tested: rom
	@test -f $(STAMP) || { \
		echo "ERROR: no suite has passed on this tree — run 'make test'"; exit 1; }
	@have=`shasum -a 1 build/ot6.sfc | cut -d' ' -f1`; \
	 want=`cat $(STAMP)`; \
	 [ "$$have" = "$$want" ] || { \
		echo "ERROR: build/ot6.sfc ($$have) is not the ROM the suite passed on"; \
		echo "       ($$want) — run 'make test' before building a distributable"; \
		exit 1; }
	@echo "suite verified green for this exact ROM"

# patch basename must differ from the ROM's, or Mesen auto-applies it on load
patch: tested
	@mkdir -p build/dist
	$(FLIPS) --create --bps "$(BASE)" build/ot6.sfc build/dist/ot6-from-ff3us10.bps
	@ls -la build/dist/ot6-from-ff3us10.bps

# release: build the ROM, run the full gate, then emit the distribution
# patch plus release notes from docs/release-notes-template.md (X.Y in
# the template becomes $(VERSION); override with `make release VERSION=0.2`).
release: test tested
	@mkdir -p build/release
	$(FLIPS) --create --bps "$(BASE)" build/ot6.sfc "build/release/ot6-v$(VERSION).bps"
	sed 's/X\.Y/$(VERSION)/g' docs/release-notes-template.md > build/release/RELEASE_NOTES.md
	@ls -la build/release/

# One GUI instance only: battery saves flush on exit, so a second instance
# exiting later silently clobbers the first one's in-game saves.
run: rom
	@if ps -axo command | grep "MacOS/Mesen" | grep -v grep | grep -qv testrunner; then \
		echo "Mesen is already running - use that window (a second instance"; \
		echo "would clobber battery saves on exit)."; \
	else \
		open -n "$(CURDIR)/tools/Mesen.app" --args "$(CURDIR)/build/ot6.sfc"; \
	fi

# savestates regenerate only when ROM CONTENT changes (the file's
# timestamp bumps on every build even when bytes are identical)
STATE1 := build/states/battle_doorstep.mss.lua
STATE2 := build/states/battle2_doorstep.mss.lua
STATE3 := build/states/whelk_doorstep.mss.lua
build/states/.rom-stamp: ff6/rom/ff6-en.sfc
	@mkdir -p build/states
	@cmp -s ff6/rom/ff6-en.sfc build/states/.rom-copy 2>/dev/null || \
		{ cp ff6/rom/ff6-en.sfc build/states/.rom-copy; echo "rom content changed"; }
	@touch build/states/.rom-stamp
# goldens are captured from the same state mint they are compared against:
# every remint shifts party hp / atb phase, so cross-mint pixel compares
# are meaningless. the canary asserts inside the tests stay mint-independent.
$(STATE1): build/states/.rom-stamp
	@if [ build/states/.rom-copy -nt $(STATE1) ] || [ ! -f $(STATE1) ]; then \
		tools/tests/run.sh tools/tests/gen_battle_state.lua; \
		$(MAKE) goldens-capture; \
	fi
	@touch $(STATE1)

goldens-capture:
	tools/tests/run.sh tools/tests/visual_f1.lua || true
	@mkdir -p tools/tests/goldens
	cp build/states/shots/visual_f1_idle.png tools/tests/goldens/
	@echo "goldens recaptured for the fresh state mint"
$(STATE2): $(STATE1)
	@if [ build/states/.rom-copy -nt build/states/battle2_doorstep.mss ] || [ ! -f build/states/battle2_doorstep.mss ]; then \
		tools/tests/run.sh tools/tests/gen_battle2.lua; \
	fi
	@touch $(STATE2)
# whelk doorstep: the dialog-opening boss fight battle_dlgmenu gates.
# gen_whelk_poweron mints it from COLD POWER-ON -- plays the New Game intro
# through the Narshe gauntlet to the mines -- so it needs no SRM sidecar and
# works on a fresh clone (the old gen_whelk booted a git-ignored human-save
# sidecar, a fresh-clone trap).
$(STATE3): $(STATE2)
	@if [ build/states/.rom-copy -nt build/states/whelk_doorstep.mss ] || [ ! -f build/states/whelk_doorstep.mss ]; then \
		tools/tests/run.sh tools/tests/gen_whelk_poweron.lua; \
	fi
	@touch $(STATE3)

# compose.py's selftest is pure python and gates the suite: it is the positive
# control for sidecar resolution, and a wrong resolution silently tests the
# wrong ROM's savestates rather than failing.
test: rom $(STATE1) $(STATE2) $(STATE3)
	python3 tools/tests/lib/compose.py --selftest
	@rm -f $(STAMP)
	tools/tests/suite.sh
	@shasum -a 1 build/ot6.sfc | cut -d' ' -f1 > $(STAMP)
	@echo "suite green — stamped `cat $(STAMP)`"

# ---------------------------------------------------------------- frontier --
# The story chain past the whelk, as gated state rules.  `test` deliberately
# does NOT depend on any of it: every one of these is a multi-minute scripted
# playthrough, and the suite's remint cost has to stay what it was.  Build it
# on demand with `make frontier` (or name one state) when you need a fixture
# deeper in the game than whelk_doorstep.
#
# Each link consumes the previous link's savestate, so the order below is the
# order the game is played, and each rule uses the same content-compare gate
# as the suite's states: re-mint only when the ROM BYTES changed (a build
# bumps every timestamp even when nothing moved).
#
#   whelk_doorstep  -> gen_arvis          -> arvis_wake
#                   -> gen_narshe_escape  -> narshe_escape_start, narshe_streets
#                   -> gen_mines_chase    -> mines_chase, moogle_doorstep
#                   -> gen_moogle         -> moogle_defense, moogle_cleared
#                   -> gen_worldmap       -> worldmap_narshe
#                   -> gen_figaro         -> figaro_doorstep
#                   -> gen_edgar          -> figaro_intro, figaro_matron,
#                                            figaro_cleared
#                   -> gen_kolts          -> south_figaro, kolts_doorstep,
#                                            vargas_doorstep
#                   -> gen_kolts_pool     -> kolts_pool
#                   -> gen_vargas         -> vargas_won
#                   -> gen_returner       -> returner_hideout
#                   -> gen_banon          -> banon_joined
#                   -> gen_lete           -> lete_river
#                   -> gen_scenario       -> scenario_hub
#                   -> gen_scenario_locke -> locke_scenario
#   scenario_hub    -> gen_rapids         -> rapids_start, rapids_done
#                   -> gen_terra_narshe   -> terra_narshe
#                   -> gen_terra_caves    -> terra_caves
#                   -> gen_terra_clifftop -> terra_clifftop
#                   -> gen_terra_done     -> terra_done
FRONTIER := arvis_wake narshe_streets moogle_doorstep moogle_cleared \
            worldmap_narshe figaro_doorstep figaro_intro figaro_matron \
            figaro_cleared south_figaro kolts_doorstep kolts_pool \
            kolts_cave vargas_doorstep vargas_won returner_hideout \
            banon_joined lete_river scenario_hub locke_scenario \
            rapids_start rapids_done terra_narshe terra_caves \
            terra_clifftop terra_done sabin_world sabin_camp \
            cyan_defence camp_intro kefka_done camp_cleared \
            doma_defended sfigaro_town sfigaro_passage celes_freed \
            sfigaro_escape tunnelarmr_doorstep locke_done \
            t2_scenario_hub t2_rapids_start t2_rapids_done \
            t2_terra_narshe t2_terra_caves t2_terra_clifftop \
            t2_terra_done two_done

# mint <state> from <script> once its ROM-content gate says it is stale.
#
# Worker-isolated, so `make -jN frontier` can mint the mutually independent
# story branches at once: everything up to scenario_hub is a serial trunk (each
# link boots the previous doorstep), but FROM the hub the three scenarios --
# locke_scenario, the rapids/terra_* chain and the sabin_* chain -- share no
# state, and kolts_pool/kolts_cave hang off the doorstep in parallel with the
# Vargas rung. A bare run.sh routes EVERYTHING through one default tree
# (build/mesen-test-home, build/mesen-test-saves, build/states/_composed.lua,
# one log), so two concurrent bare mints would race on the settings pin, the
# composed script and the srm wipe. OT6_WORKER gives each its own tree; the id
# is the STATE NAME, so distinct mints never collide and make hands out no ids.
#
# run.sh puts a worker's decoded artifacts under its own dir, so the mint lands
# in build/test-workers/w<state>/artifacts/, not build/states/. Harvest it back
# (state + sidecar) so the next link's compose.py finds it in build/states/
# exactly as before. Determinism is unaffected: a savestate captures emulator
# state, which the config-home path cannot touch, and pin_test_saves writes the
# same determinism pins into every worker -- verified byte-identical to a serial
# mint. `&&` so a failed mint skips the harvest and fails the recipe (.DELETE_ON_ERROR).
define mint
	@if [ build/states/.rom-copy -nt build/states/$(1).mss ] || [ ! -f build/states/$(1).mss ]; then \
		OT6_WORKER=$(1) tools/tests/run.sh tools/tests/$(2).lua && \
		cp "build/test-workers/w$(1)/artifacts/$(1).mss" "build/states/$(1).mss" && \
		cp "build/test-workers/w$(1)/artifacts/$(1).mss.lua" "build/states/$(1).mss.lua"; \
	fi
	@touch build/states/$(1).mss.lua
endef

build/states/arvis_wake.mss.lua: $(STATE3)
	$(call mint,arvis_wake,gen_arvis)
build/states/narshe_streets.mss.lua: build/states/arvis_wake.mss.lua
	$(call mint,narshe_streets,gen_narshe_escape)
build/states/moogle_doorstep.mss.lua: build/states/narshe_streets.mss.lua
	$(call mint,moogle_doorstep,gen_mines_chase)
build/states/moogle_cleared.mss.lua: build/states/moogle_doorstep.mss.lua
	$(call mint,moogle_cleared,gen_moogle)
build/states/worldmap_narshe.mss.lua: build/states/moogle_cleared.mss.lua
	$(call mint,worldmap_narshe,gen_worldmap)
build/states/figaro_doorstep.mss.lua: build/states/worldmap_narshe.mss.lua
	$(call mint,figaro_doorstep,gen_figaro)
build/states/figaro_intro.mss.lua: build/states/figaro_doorstep.mss.lua
	$(call mint,figaro_intro,gen_edgar)
# same script, later mints; each gates on its own file so a half-run re-runs
build/states/figaro_matron.mss.lua: build/states/figaro_intro.mss.lua
	$(call mint,figaro_matron,gen_edgar)
build/states/figaro_cleared.mss.lua: build/states/figaro_matron.mss.lua
	$(call mint,figaro_cleared,gen_edgar)
# gen_kolts: the chocobo dismount, the South Figaro cave, and the mountain
build/states/south_figaro.mss.lua: build/states/figaro_cleared.mss.lua
	$(call mint,south_figaro,gen_kolts)
build/states/kolts_doorstep.mss.lua: build/states/south_figaro.mss.lua
	$(call mint,kolts_doorstep,gen_kolts)
build/states/vargas_doorstep.mss.lua: build/states/kolts_doorstep.mss.lua
	$(call mint,vargas_doorstep,gen_kolts)
# gen_kolts_pool: one crossing past the doorstep onto map 100 shelf F.  The
# doorstep map (95) is transit only and carries no encounter group -- 437
# paced tiles there drew nothing -- so balance runs that want the Mt. Kolts
# trash pool need this one, not kolts_doorstep.
build/states/kolts_pool.mss.lua: build/states/kolts_doorstep.mss.lua
	$(call mint,kolts_pool,gen_kolts_pool)
# gen_kolts_cave: one more crossing, onto map 96.  Shelf F (map 100) is
# encounter group 63 -- Brawler/Tusker -- and that is ONE of the mountain's
# four groups.  Maps 96/97 carry group 61, which is CIRPIUS x3 at 93.75% of
# draws: the mountain's most common fight, and the one the trash-weakness
# pass is built around.  kolts_pool cannot draw it, so it needs its own.
build/states/kolts_cave.mss.lua: build/states/kolts_pool.mss.lua
	$(call mint,kolts_cave,gen_kolts_cave)
# gen_vargas: the fight itself, finished by Pummel, and the reunion
build/states/vargas_won.mss.lua: build/states/vargas_doorstep.mss.lua
	$(call mint,vargas_won,gen_vargas)
# ---- rung 3: the road to the scenario split ----
# gen_returner: off the mountain's north side and across the world map
build/states/returner_hideout.mss.lua: build/states/vargas_won.mss.lua
	$(call mint,returner_hideout,gen_returner)
# gen_banon: the hideout's conversation graph, ending on the raft's doorstep
build/states/banon_joined.mss.lua: build/states/returner_hideout.mss.lua
	$(call mint,banon_joined,gen_banon)
# gen_lete: the short walk to the raft -- kept its own link so that a failed
# experiment on the river replays 530 frames, not the whole hideout
build/states/lete_river.mss.lua: build/states/banon_joined.mss.lua
	$(call mint,lete_river,gen_lete)
# gen_scenario: the river (steered past its vanilla loop), ULTROS, and the
# three-way split -- the entry point of the v0.3 arc
build/states/scenario_hub.mss.lua: build/states/lete_river.mss.lua
	$(call mint,scenario_hub,gen_scenario)
# one step PAST the hub: proves the split is dispatchable and hands the v0.3
# Locke chain its doorstep.  The Sabin and Terra/Banon branches start from
# scenario_hub the same way; only this one is built.
build/states/locke_scenario.mss.lua: build/states/scenario_hub.mss.lua
	$(call mint,locke_scenario,gen_scenario_locke)
# ---- the TERRA/BANON scenario: the shortest of the three, from the hub ----
# gen_rapids: talk to Terra at the hub, resume the raft down the lower Lete
# (the FORCED battle 8 plus two if_rand fights), spill onto the world map.
# Two mints: rapids_start is the cheap doorstep UPSTREAM of the forced fight;
# rapids_done is on foot on the World of Balance NE of Narshe.
build/states/rapids_start.mss.lua: build/states/scenario_hub.mss.lua
	$(call mint,rapids_start,gen_rapids)
build/states/rapids_done.mss.lua: build/states/rapids_start.mss.lua
	$(call mint,rapids_done,gen_rapids)
# gen_terra_narshe: the world walk into Narshe and the townsfolk's turn-away
# at the checkpoint (which shoves the party back south, $001F set)
build/states/terra_narshe.mss.lua: build/states/rapids_done.mss.lua
	$(call mint,terra_narshe,gen_terra_narshe)
# gen_terra_caves: open the secret wall Locke used (an EXAMINE facing up on
# (15,57)) and step into the mines -- the only fixture in this scenario's
# random-encounter pool
build/states/terra_caves.mss.lua: build/states/terra_narshe.mss.lua
	$(call mint,terra_caves,gen_terra_caves)
# gen_terra_clifftop: the length of the caves -- maps 41/20-pocket/48/49/50 --
# including map 49's 13-gate ordered block maze, out onto the clifftop
build/states/terra_clifftop.mss.lua: build/states/terra_caves.mss.lua
	$(call mint,terra_clifftop,gen_terra_clifftop)
# gen_terra_done: into Arvis's house, onto the meeting trigger _ccb3fa, and
# out the far side with $0021 set -- the scenario complete, back at the hub
build/states/terra_done.mss.lua: build/states/terra_clifftop.mss.lua
	$(call mint,terra_done,gen_terra_done)
# ---- SABIN's scenario: the longest of the three v0.3 branches ----
# gen_sabin_world: the hub dispatch, the overworld landing at (161,36),
# SHADOW's house (map 115) and the walk to the Imperial Camp.  Two states
# from one script so an experiment on the house replays 700 frames, not the
# hub as well.
build/states/sabin_world.mss.lua: build/states/scenario_hub.mss.lua
	$(call mint,sabin_world,gen_sabin_world)
build/states/sabin_camp.mss.lua: build/states/sabin_world.mss.lua
	$(call mint,sabin_camp,gen_sabin_world)
# gen_sabin_camp: one step south of the camp gate hands the game to CYAN on
# map 120 for ~9,000 frames (the Doma defence, name menu and all) before
# SABIN gets it back.  cyan_defence is minted mid-run so an experiment on
# the commander fight replays 800 frames instead of 6,000.
build/states/cyan_defence.mss.lua: build/states/sabin_camp.mss.lua
	$(call mint,cyan_defence,gen_sabin_camp)
build/states/camp_intro.mss.lua: build/states/cyan_defence.mss.lua
	$(call mint,camp_intro,gen_sabin_camp)
# gen_sabin_kefka: the LEO scene, the poisoning, both KEFKA script-battles,
# the pursuit, and the handoff back to CYAN on the Doma grounds.
build/states/kefka_done.mss.lua: build/states/camp_intro.mss.lua
	$(call mint,kefka_done,gen_sabin_kefka)
# gen_sabin_doma: CYAN's run home through the Doma Castle room maze, the
# family scene, and the handoff back to SABIN at the castle gate.
build/states/camp_cleared.mss.lua: build/states/kefka_done.mss.lua
	$(call mint,camp_cleared,gen_sabin_doma)
# gen_sabin_escape: the Doma courtyard defence -- three talk-to-CYAN fights,
# CYAN joins, everyone mounts Magitek.  Stops at (14,30), the escape's
# starting line (the escape walk itself is the next leg).
build/states/doma_defended.mss.lua: build/states/camp_cleared.mss.lua
	$(call mint,doma_defended,gen_sabin_escape)

# ---- rung 4: LOCKE's scenario, hub -> South Figaro -> TunnelArmr ----
# gen_sfigaro: the occupied town.  The gate soldier (battle 11), then the
# cafe's cider runner -- STOLEN from, not killed, because the merchant's
# clothes come off the steal's reaction script and nothing else -- then the
# old man's password and the rich man's secret passage.
build/states/sfigaro_town.mss.lua: build/states/locke_scenario.mss.lua
	$(call mint,sfigaro_town,gen_sfigaro)
build/states/sfigaro_passage.mss.lua: build/states/sfigaro_town.mss.lua
	$(call mint,sfigaro_passage,gen_sfigaro)
# gen_celes: the passage, the rich man's mansion (a warp maze, entered by a
# deep door), the basement, the Celes chains cutscene + naming menu, freeing
# her, and the sleeping soldier's clock key
build/states/celes_freed.mss.lua: build/states/sfigaro_passage.mss.lua
	$(call mint,celes_freed,gen_celes)
# gen_tunnelarmr: the clock's secret passage (the ONLY basement exit), the
# escape through maps 87/86 to town, the world, the Figaro cave walked in
# from the south (world (75,102) is an event trigger, not an entrance), and
# TunnelArmr (battle 67, $0104) -- which ends the Locke scenario ($001E=1,
# back at the hub).  Three states.
build/states/sfigaro_escape.mss.lua: build/states/celes_freed.mss.lua
	$(call mint,sfigaro_escape,gen_tunnelarmr)
build/states/tunnelarmr_doorstep.mss.lua: build/states/sfigaro_escape.mss.lua
	$(call mint,tunnelarmr_doorstep,gen_tunnelarmr)
build/states/locke_done.mss.lua: build/states/tunnelarmr_doorstep.mss.lua
	$(call mint,locke_done,gen_tunnelarmr)

# ---- SCENARIO STACKING: the road to the reunion --------------------------
# The reunion _caadb9 (event_main.asm:26683) needs $0021 && $001E && $0044 in
# ONE playthrough; each honest chain sets one.  compose.py's OT6_STACK prefix
# replays a whole chain's ROUTE LOGIC from a different boot: `smint` composes
# the same generator with every .mss basename prefixed, so it boots the
# prefixed predecessor and mints prefixed artifacts -- the honest states are
# never touched.  Stack order LOCKE (honest) -> TERRA (t2_) -> SABIN (s3_):
#  * Terra's is the shortest chain, so the first stacking layer -- the one
#    that had to prove the mechanism -- replays the least;
#  * the THIRD chain's hub return fires the reunion instead of reaching the
#    hub (the if_all at :26654), so whichever chain goes last cannot end on
#    its own "back at the hub" gate.  That final leg belongs to
#    gen_narshe_battle, and Sabin's chain -- still growing its back half --
#    is the one whose ending was free to leave unconsumed.
define smint
	@if [ build/states/.rom-copy -nt build/states/$(1).mss ] || [ ! -f build/states/$(1).mss ]; then \
		OT6_STACK=$(2) tools/tests/run.sh tools/tests/$(3).lua; \
	fi
	@touch build/states/$(1).mss.lua
endef

# the seed: the stacked Terra chain's "scenario_hub" IS the Locke ending.
# cp both halves (state + sidecar) under the same content gate the mints
# use, so a locke_done re-mint (ROM changed) re-seeds and the stack replays.
build/states/t2_scenario_hub.mss.lua: build/states/locke_done.mss.lua
	@if [ build/states/.rom-copy -nt build/states/t2_scenario_hub.mss ] || [ ! -f build/states/t2_scenario_hub.mss ]; then \
		cp build/states/locke_done.mss build/states/t2_scenario_hub.mss; \
		cp build/states/locke_done.mss.lua build/states/t2_scenario_hub.mss.lua; \
		echo "stack seed: t2_scenario_hub <- locke_done"; \
	fi
	@touch build/states/t2_scenario_hub.mss.lua
build/states/t2_rapids_start.mss.lua: build/states/t2_scenario_hub.mss.lua
	$(call smint,t2_rapids_start,t2_,gen_rapids)
build/states/t2_rapids_done.mss.lua: build/states/t2_rapids_start.mss.lua
	$(call smint,t2_rapids_done,t2_,gen_rapids)
build/states/t2_terra_narshe.mss.lua: build/states/t2_rapids_done.mss.lua
	$(call smint,t2_terra_narshe,t2_,gen_terra_narshe)
build/states/t2_terra_caves.mss.lua: build/states/t2_terra_narshe.mss.lua
	$(call smint,t2_terra_caves,t2_,gen_terra_caves)
build/states/t2_terra_clifftop.mss.lua: build/states/t2_terra_caves.mss.lua
	$(call smint,t2_terra_clifftop,t2_,gen_terra_clifftop)
build/states/t2_terra_done.mss.lua: build/states/t2_terra_clifftop.mss.lua
	$(call smint,t2_terra_done,t2_,gen_terra_done)
# the acceptance gate: asserts BOTH flags on the stacked ending and re-saves
# it under the canonical name (gen_two_done.lua's header says why the assert
# lives outside the mechanically-prefixed chain).
build/states/two_done.mss.lua: build/states/t2_terra_done.mss.lua
	$(call mint,two_done,gen_two_done)
# SABIN's slot (consumed when his back half lands).  ORDER REVISED from
# "Sabin last" after the reunion spike: whichever chain returns to the hub
# THIRD rides the reunion instead of reaching the hub, so its FINAL leg
# must be reunion-aware -- and gen_terra_done (ours) already is (it mints
# reunion_ready.mss on an all-three boot; see its header).  So Sabin runs
# SECOND and Terra's chain replays LAST:
#   s2_scenario_hub <- locke_done  (cp seed, same shape as t2_)
#   s2_* : Sabin's whole chain with OT6_STACK=s2_, ending at his hub
#          return ($001E+$0044 = two flags, no reunion) -- mirror the t2_
#          rules one-for-one when his ending generator exists
#   t3_scenario_hub <- s2_<sabin-ending>
#   t3_* : gen_rapids .. gen_terra_clifftop with OT6_STACK=t3_
#   reunion_ready.mss.lua: gen_terra_done with OT6_STACK=t3_ -- its
#          all-three fork rides _caadb9's reunion to the map-22 staging
#          and mints t3_reunion_ready; a gen_two_done-shaped acceptance
#          re-saves it as reunion_ready
# Then append to FRONTIER: the s2_/t3_ names, reunion_ready,
# narshe_battle, kefka_doorstep, kefka_won -- the rules below are already
# live, just unlisted so `make frontier` stays green while the boot is
# unmintable.

# ---- the Battle for Narshe (waiting on reunion_ready) ---------------------
# gen_narshe_battle: reunion staging -> BANON -> the three-party assignment
# menu (P1=TERRA+EDGAR+CELES, P2=CYAN+SABIN, P3=LOCKE+GAU) -> defense live
# -> the measured cliff descent -> KEFKA'S doorstep -> the scripted win.
# Validated end-to-end on the poked spike twin (OT6_STACK=spike_); the
# rules run unchanged the day reunion_ready exists.
build/states/narshe_battle.mss.lua: build/states/reunion_ready.mss.lua
	$(call mint,narshe_battle,gen_narshe_battle)
build/states/kefka_doorstep.mss.lua: build/states/narshe_battle.mss.lua
	$(call mint,kefka_doorstep,gen_narshe_battle)
build/states/kefka_won.mss.lua: build/states/kefka_doorstep.mss.lua
	$(call mint,kefka_won,gen_narshe_battle)

frontier: rom $(STATE1) $(STATE2) $(STATE3) \
          $(patsubst %,build/states/%.mss.lua,$(FRONTIER))
	@echo "frontier states up to date: $(FRONTIER)"

# The suite INCLUDING its frontier-gated tests.  battle_vargas asserts on
# vargas_doorstep, and `test` deliberately does not depend on it: minting it
# replays the whole story chain, which is the cost the frontier exists to
# keep out of the gate.  suite.sh picks the test up automatically once the
# fixture is on disk and reports it as skipped when it is not, so this target
# is just "mint the frontier, then run the same suite".
frontier-test: frontier
	python3 tools/tests/lib/compose.py --selftest
	tools/tests/suite.sh

goldens: rom $(STATE1) $(STATE2)
	tools/tests/run.sh tools/tests/visual_f1.lua
	@mkdir -p tools/tests/goldens
	cp build/states/shots/visual_f1_idle.png tools/tests/goldens/
	@echo "goldens captured from the current build - review before committing"

clean:
	$(MAKE) -C ff6 clean
	rm -rf build
