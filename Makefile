BASE    := Final Fantasy III (USA).sfc
SHA1    := 4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7
FLIPS   := tools/bin/flips
MESEN   := tools/Mesen.app/Contents/MacOS/Mesen
VERSION := 0.4

# A failed recipe (e.g. the checksum step dying mid-build) leaves a half-built target the next make treats as up-to-date — bit us twice on 2026-07-18.
.DELETE_ON_ERROR:

.PHONY: all rom patch run test tested verify clean release frontier frontier-test nomp-rom

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
$(STATE1): build/states/.rom-stamp
	@if [ build/states/.rom-copy -nt $(STATE1) ] || [ ! -f $(STATE1) ]; then \
		tools/tests/run.sh tools/tests/gen_battle_state.lua; \
	fi
	@touch $(STATE1)
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
# ot6 v0.5 "every ability costs MP": now LIVE in the shipped ROM. This builds
# the INVERSE control -- the OT6_MP_COSTS=0 baseline (ff6-en-nomp), the
# pre-feature vanilla-OT6 build. Only the battle module reads the flag, so
# ff6-en-nomp rebuilds just that object and relinks against the stock en
# objects (see ff6/Makefile). The shipped ON ROM MUST differ from this OFF
# baseline or the flag is dead code. The suite runs battle_mpcost.lua on the
# shipped (ON, default) ROM -- asserting the CHARGE and the insufficient-mp
# REFUSAL; the `test` recipe below runs the SAME self-detecting script on this
# OFF baseline, asserting the verb stays FREE and the cost table is ABSENT
# (the pre-feature negative control). Two runs, both states, one instrument --
# the fix_checksum rewrite's A/B technique lifted to behavior.
nomp-rom: rom
	$(MAKE) -C ff6 ff6-en-nomp
	@if cmp -s build/ot6.sfc ff6/rom/ff6-en-nomp.sfc; then \
		echo "ERROR: OT6_MP_COSTS=0 baseline is byte-identical to the shipped ON ROM — flag is dead"; \
		exit 1; fi
	@echo "OT6_MP_COSTS=0 baseline built and confirmed distinct from the shipped ON ROM"

test: rom nomp-rom $(STATE1) $(STATE2) $(STATE3)
	python3 tools/tests/lib/compose.py --selftest
	sh tools/tests/lib/frontier_stamp_selftest.sh
	@rm -f $(STAMP)
	tools/tests/suite.sh
	@echo "-- mpcost A/B: the OFF half (free — the negative control) on the nomp baseline --"
	OT6_ROM=$(CURDIR)/ff6/rom/ff6-en-nomp.sfc tools/tests/run.sh tools/tests/battle_mpcost.lua
	OT6_ROM=$(CURDIR)/ff6/rom/ff6-en-nomp.sfc tools/tests/run.sh tools/tests/battle_stealmp.lua
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
# order the game is played.  A minted state is a function of the ROM bytes,
# its generator .lua, and the shared test library every generator dofile()s --
# both halves of it, lib/ot6.lua and lib/ot6_field.lua, since compose.py
# inlines the pair into every composed script -- and the gate re-mints when
# ANY of them changed by CONTENT (a build or a checkout bumps timestamps
# without moving bytes, so mtime alone would re-mint spuriously).  ROM bytes
# ride the .rom-copy clock as before; the generator+lib half is
# frontier_stamp.sh, wired in below.  Issue #2: keying on the ROM alone
# silently kept fixtures a since-edited generator or lib would no longer mint
# the same way.
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

# The generator+lib half of the freshness gate (issue #2).  For a generator or
# lib edit to re-mint, make has to RECONSIDER the state's target, which it only
# does when a declared prerequisite is newer -- so each state's .mss.lua must
# depend on the .lua that mints it and on both lib halves.  That state->generator
# map already lives in the $(call mint,...) lines, so rather than hand-list it a
# second time (and have it rot as the Zozo route adds links), frontier_deps.sh
# greps it back out into a generated fragment we -include.  A new link is thus
# gated the moment it is added.  The prerequisite makes make LOOK; the recipe's
# frontier_stamp.sh gate is what decides mint-or-skip by CONTENT, so a bumped
# mtime with identical bytes still re-mints nothing.
build/states/frontier-deps.mk: Makefile tools/tests/lib/frontier_deps.sh
	@mkdir -p build/states
	@sh tools/tests/lib/frontier_deps.sh Makefile > $@
-include build/states/frontier-deps.mk

# mint <state> from <script> once its (ROM, generator, lib) gate says it is stale.
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
#
# An optional THIRD arg makes it a STACKED mint: <state>,<script>,<prefix>
# adds OT6_STACK=<prefix> to the run, so compose.py replays the generator's
# route logic against prefix_-named fixtures instead of the honest ones --
# the SCENARIO STACKING section below owns that story.  Empty third arg
# (every two-arg call) is a plain mint, exactly as before the fold.
define mint
	@if sh tools/tests/lib/frontier_stamp.sh needsmint $(1) $(2); then \
		echo "[frontier] mint $(1) <- $(2)$(if $(3), (stack $(3)))"; \
		OT6_WORKER=$(1)$(if $(3), OT6_STACK=$(3)) tools/tests/run.sh tools/tests/$(2).lua && \
		cp "build/test-workers/w$(1)/artifacts/$(1).mss" "build/states/$(1).mss" && \
		cp "build/test-workers/w$(1)/artifacts/$(1).mss.lua" "build/states/$(1).mss.lua" && \
		sh tools/tests/lib/frontier_stamp.sh write $(1) $(2); \
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
# gen_sabin_magitek: the Imperial Camp escape -- ride the fight/interlude
# gauntlet out to the World of Balance.  Battles 15/16/17 are each WON BY
# TAP-A (kill-bit -> GameOver softlock), and each latchless re-firing trigger
# is left by holding the corridor's walkable direction through the ~25% control
# flap (navTo drops its plan on the flap; see the generator header).
build/states/camp_escaped.mss.lua: build/states/doma_defended.mss.lua
	$(call mint,camp_escaped,gen_sabin_magitek)
# gen_sabin_forest: the Phantom Forest -- world (178,82) into map 132, the
# 132->133->134->135->140 chain (map 133's one-way recovery spring is a
# MANDATORY conveyor past its back-exit; each map's arrival brushes a back-exit
# so crossings pick interior waypoints), then boarding the Phantom Train at 140
# (72,11) -> map 145.  Mints forest_done on the train.
build/states/forest_done.mss.lua: build/states/camp_escaped.mss.lua
	$(call mint,forest_done,gen_sabin_forest)
# gen_sabin_train: the Phantom Train, boarding to the Ghost Train's fall --
# the maze decoded and driven (car interiors are REUSED per physical car
# with $017E/$0180 as bookkeeping; the chase, the two-pull lever, the strip
# route, the valves, and battle 68 fought with real Blitz inputs: the
# 6-shield OT6_BLUDG row chip-proven at runtime).  Ends on the world map
# at (178,93) with $003A/$003B set.
build/states/train_done.mss.lua: build/states/forest_done.mss.lua
	$(call mint,train_done,gen_sabin_train)
# gen_sabin_falls: Baren Falls -- the jump, battle 18 mid-fall (RIZOPAS
# surfaces in slot 5 off the piranhas' death script, its authored
# 5-shield SLASH|BLUDG row read live), SHADOW's exit, GAU named on the
# Veldt shore.
build/states/falls_done.mss.lua: build/states/train_done.mss.lua
	$(call mint,falls_done,gen_sabin_falls)
# gen_sabin_gau: Mobliz's Dried Meat, the Veldt grind (GAU appears on the
# 3/8 end-of-battle roll), and his return-visit self-recruit -- the
# generator header documents the one concession ($3EBD bit 1) and the
# measured reason the first-visit feed cannot be driven.
build/states/gau_joined.mss.lua: build/states/falls_done.mss.lua
	$(call mint,gau_joined,gen_sabin_gau)
# gen_sabin_trench: Crescent Mountain's helmet chain (GAU-gated), the
# Serpent Trench ridden as a real VEHICLE script (LEFT held through both
# arrow windows = the mainline), Nikeah, and the ferry's option-1 prompt --
# $0044=1 and the hub.  SABIN's scenario closes here.
build/states/sabin_done.mss.lua: build/states/gau_joined.mss.lua
	$(call mint,sabin_done,gen_sabin_trench)
# SABIN's continuation states join the frontier additively (a += line, kept off
# the base := list so the other scenario agents' FRONTIER edits never collide
# with this one).  Extended in place as each leg lands.
FRONTIER += camp_escaped forest_done train_done falls_done gau_joined \
            sabin_done

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
# replays a whole chain's ROUTE LOGIC from a different boot: a stacked mint
# ($(call mint,<state>,<script>,<prefix>)) composes the same generator with
# every .mss basename prefixed, so it boots the prefixed predecessor and
# mints prefixed artifacts -- the honest states are never touched.  The full
# stack is LOCKE (honest) -> SABIN (s2_) -> TERRA (t3_); the earlier two_done
# milestone (LOCKE + TERRA, t2_) proved the mechanism on Terra's chain:
#  * Terra's is the shortest chain, so that first stacking layer -- the one
#    that had to prove the mechanism -- replays the least;
#  * the THIRD chain's hub return fires the reunion instead of reaching the
#    hub (the if_all at :26654), so whichever chain goes last cannot end on
#    its own "back at the hub" gate.  That final leg belongs to
#    gen_narshe_battle.  Terra takes it -- gen_terra_done's all-three fork is
#    already reunion-aware -- so Sabin's (now-complete) chain goes second and
#    its clean hub-return ending seeds the Terra layer.
# Worker-isolated exactly like the plain mints -- the stack mints (a separate
# `smint` macro before the fold) used to run BARE, and under `make -jN` the
# s2_/t2_/t3_ stacks become runnable together (all three hang off
# locke_done), so two bare stack mints raced on the ONE default composed file
# and settings pin -- the precise hazard the worker-isolation comment above
# describes.  Measured fallout (2026-07-20 remint): t2_terra_narshe minted
# with the party on map 3 while its own run reported PASS (it had executed a
# concurrent stack's composed script), and t2_terra_caves's rule "succeeded"
# -- touch and all -- without ever writing its state.  The `&&` chain also
# makes a failed stack mint fail its RULE, which the bare form did not
# guarantee.  OT6_WORKER and OT6_STACK compose fine: the worker picks the
# tree, the stack prefix picks the state names inside it.

# stackseed <prefixed hub> <source state> -- a stacked chain's "scenario_hub"
# IS the previous chain's ending.  cp both halves (state + sidecar) under the
# same content gate the mints use, so a source re-mint (ROM changed, or the
# chain below replayed) re-seeds and the stack above replays.  No generator
# and no worker: seeding is a pure copy, so there is nothing to isolate and
# frontier_deps.sh correctly finds no .lua to tie it to.
define stackseed
	@if [ build/states/.rom-copy -nt build/states/$(1).mss ] || [ ! -f build/states/$(1).mss ] || [ build/states/$(2).mss -nt build/states/$(1).mss ]; then \
		cp build/states/$(2).mss build/states/$(1).mss; \
		cp build/states/$(2).mss.lua build/states/$(1).mss.lua; \
		echo "stack seed: $(1) <- $(2)"; \
	fi
	@touch build/states/$(1).mss.lua
endef

# the seed: the stacked Terra chain's "scenario_hub" IS the Locke ending.
build/states/t2_scenario_hub.mss.lua: build/states/locke_done.mss.lua
	$(call stackseed,t2_scenario_hub,locke_done)
build/states/t2_rapids_start.mss.lua: build/states/t2_scenario_hub.mss.lua
	$(call mint,t2_rapids_start,gen_rapids,t2_)
build/states/t2_rapids_done.mss.lua: build/states/t2_rapids_start.mss.lua
	$(call mint,t2_rapids_done,gen_rapids,t2_)
build/states/t2_terra_narshe.mss.lua: build/states/t2_rapids_done.mss.lua
	$(call mint,t2_terra_narshe,gen_terra_narshe,t2_)
build/states/t2_terra_caves.mss.lua: build/states/t2_terra_narshe.mss.lua
	$(call mint,t2_terra_caves,gen_terra_caves,t2_)
build/states/t2_terra_clifftop.mss.lua: build/states/t2_terra_caves.mss.lua
	$(call mint,t2_terra_clifftop,gen_terra_clifftop,t2_)
build/states/t2_terra_done.mss.lua: build/states/t2_terra_clifftop.mss.lua
	$(call mint,t2_terra_done,gen_terra_done,t2_)
# the acceptance gate: asserts BOTH flags on the stacked ending and re-saves
# it under the canonical name (gen_two_done.lua's header says why the assert
# lives outside the mechanically-prefixed chain).
build/states/two_done.mss.lua: build/states/t2_terra_done.mss.lua
	$(call mint,two_done,gen_two_done)
# ---- the FULL stack: SABIN second (s2_), TERRA last (t3_) ----------------
# ORDER (from the reunion spike): whichever chain returns to the hub THIRD
# rides the reunion instead of reaching the hub, so the final leg must be
# reunion-aware -- gen_terra_done is (its all-three fork mints
# t3_reunion_ready at the map-22 staging).  Sabin's chain replays SECOND on
# top of locke_done, ending at his hub return ($001E+$0044, no reunion).
build/states/s2_scenario_hub.mss.lua: build/states/locke_done.mss.lua
	$(call stackseed,s2_scenario_hub,locke_done)
build/states/s2_sabin_world.mss.lua: build/states/s2_scenario_hub.mss.lua
	$(call mint,s2_sabin_world,gen_sabin_world,s2_)
build/states/s2_sabin_camp.mss.lua: build/states/s2_sabin_world.mss.lua
	$(call mint,s2_sabin_camp,gen_sabin_world,s2_)
build/states/s2_cyan_defence.mss.lua: build/states/s2_sabin_camp.mss.lua
	$(call mint,s2_cyan_defence,gen_sabin_camp,s2_)
build/states/s2_camp_intro.mss.lua: build/states/s2_cyan_defence.mss.lua
	$(call mint,s2_camp_intro,gen_sabin_camp,s2_)
build/states/s2_kefka_done.mss.lua: build/states/s2_camp_intro.mss.lua
	$(call mint,s2_kefka_done,gen_sabin_kefka,s2_)
build/states/s2_camp_cleared.mss.lua: build/states/s2_kefka_done.mss.lua
	$(call mint,s2_camp_cleared,gen_sabin_doma,s2_)
build/states/s2_doma_defended.mss.lua: build/states/s2_camp_cleared.mss.lua
	$(call mint,s2_doma_defended,gen_sabin_escape,s2_)
build/states/s2_camp_escaped.mss.lua: build/states/s2_doma_defended.mss.lua
	$(call mint,s2_camp_escaped,gen_sabin_magitek,s2_)
build/states/s2_forest_done.mss.lua: build/states/s2_camp_escaped.mss.lua
	$(call mint,s2_forest_done,gen_sabin_forest,s2_)
build/states/s2_train_done.mss.lua: build/states/s2_forest_done.mss.lua
	$(call mint,s2_train_done,gen_sabin_train,s2_)
build/states/s2_falls_done.mss.lua: build/states/s2_train_done.mss.lua
	$(call mint,s2_falls_done,gen_sabin_falls,s2_)
build/states/s2_gau_joined.mss.lua: build/states/s2_falls_done.mss.lua
	$(call mint,s2_gau_joined,gen_sabin_gau,s2_)
build/states/s2_sabin_done.mss.lua: build/states/s2_gau_joined.mss.lua
	$(call mint,s2_sabin_done,gen_sabin_trench,s2_)
# TERRA/BANON's chain replays LAST, on top of two completions:
build/states/t3_scenario_hub.mss.lua: build/states/s2_sabin_done.mss.lua
	$(call stackseed,t3_scenario_hub,s2_sabin_done)
build/states/t3_rapids_start.mss.lua: build/states/t3_scenario_hub.mss.lua
	$(call mint,t3_rapids_start,gen_rapids,t3_)
build/states/t3_rapids_done.mss.lua: build/states/t3_rapids_start.mss.lua
	$(call mint,t3_rapids_done,gen_rapids,t3_)
build/states/t3_terra_narshe.mss.lua: build/states/t3_rapids_done.mss.lua
	$(call mint,t3_terra_narshe,gen_terra_narshe,t3_)
build/states/t3_terra_caves.mss.lua: build/states/t3_terra_narshe.mss.lua
	$(call mint,t3_terra_caves,gen_terra_caves,t3_)
build/states/t3_terra_clifftop.mss.lua: build/states/t3_terra_caves.mss.lua
	$(call mint,t3_terra_clifftop,gen_terra_clifftop,t3_)
# gen_terra_done on the all-three boot takes its REUNION FORK: rides
# _caadb9's cutscene to the map-22 staging and mints t3_reunion_ready.
build/states/t3_reunion_ready.mss.lua: build/states/t3_terra_clifftop.mss.lua
	$(call mint,t3_reunion_ready,gen_terra_done,t3_)
# the acceptance gate (gen_two_done's shape, one layer up): assert ALL
# THREE flags + the reunion on the stacked ending and re-save it as the
# canonical reunion_ready -- the boot gen_narshe_battle consumes.
build/states/reunion_ready.mss.lua: build/states/t3_reunion_ready.mss.lua
	$(call mint,reunion_ready,gen_reunion_ready)
FRONTIER += s2_scenario_hub s2_sabin_world s2_sabin_camp s2_cyan_defence \
            s2_camp_intro s2_kefka_done s2_camp_cleared s2_doma_defended \
            s2_camp_escaped s2_forest_done s2_train_done s2_falls_done \
            s2_gau_joined s2_sabin_done t3_scenario_hub t3_rapids_start \
            t3_rapids_done t3_terra_narshe t3_terra_caves \
            t3_terra_clifftop t3_reunion_ready reunion_ready \
            narshe_battle kefka_doorstep kefka_won

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
# kefka_won is v0.4's FIRST link and the honest chain's head: the win tail
# (esper scene, TERRA's flight, the Arvis regroup and its party-select
# menu) mints the map-30 boot the Zozo arc consumes.  Issue #3 -- the
# scene stalling every walker -- is closed; the three waits it was made of
# are decoded in gen_kefka_won's header.
build/states/kefka_won.mss.lua: build/states/kefka_doorstep.mss.lua
	$(call mint,kefka_won,gen_kefka_won)

# ---- v0.4: the search for TERRA (kefka_won -> Zozo) -----------------------
# gen_zozo1_submerge: Arvis's front door (the rung-1 blocker NPC is gone;
# the corridor exit's clifftop perch is post-battle ISOLATED) -> the south
# gate -> the EAST castle trigger world {64,76} ($010B, set by kefka_won's
# tail) -> keep -> the WEST engine-room door -> the attendant's Kohlingen
# choice (index 0 in $056E) -> the scripted crossing -> castle parked WEST
# ($010C).  NO underwater battles on this route -- battle 19/20/21 belong
# to Sabin's Serpent Trench, a survey confusion this chain retires.
build/states/figaro_submerged.mss.lua: build/states/kefka_won.mss.lua
	$(call mint,figaro_submerged,gen_zozo1_submerge)
# gen_zozo2_arrival: out of the west castle (row y=43 exits to the parent
# the ride re-pinned), the long south-then-north world hook around Zozo's
# mountain ring (177 steps, verified against the same tile-prop rule the
# engine walks), onto {22,92} -> map 221's street.
build/states/zozo_arrival.mss.lua: build/states/figaro_submerged.mss.lua
	$(call mint,zozo_arrival,gen_zozo2_arrival)
# gen_zozo3_clock: the street's CAFE door (42,28) -> the clock room (map
# 225) -> the clock tile {98,59} (an A+facing-up tile interaction, not an
# NPC) -> 6:10:50 across three CHAINED choice dialogs, each verified by its
# own $01F* latch -> the hidden staircase opens ($01F0).
build/states/zozo_clock_solved.mss.lua: build/states/zozo_arrival.mss.lua
	$(call mint,zozo_clock_solved,gen_zozo3_clock)
# gen_zozo4_dadaluma: the crane maze.  The city is a DIRECTED island graph
# once door tiles are modeled as the walk-on teleports they are: five doors
# (P9/P10b/P11a/P12b/P14a/P15b in probe_climb's pair naming), the stair
# room's bandit conveyor (seven walkers own its one-wide column forever --
# followed, not pathed), both jump rows ($1EB6 facing-gated step-on
# triggers, chained under one held direction), and the z-level loop onto
# the y=13 strip beside DADALUMA at (30,14).  Doorstep = (30,13), one
# A-press short; the fight is battle 69 (formation 438, $0107 + 2x $006C),
# won by the kill-bit like Kefka/Vargas (_ca5ea9 gates on b-switch $40).
# The win clears $034A and opens the tower porch gen_zozo5 climbs.
build/states/dadaluma_doorstep.mss.lua: build/states/zozo_arrival.mss.lua
	$(call mint,dadaluma_doorstep,gen_zozo4_dadaluma)
build/states/dadaluma_won.mss.lua: build/states/dadaluma_doorstep.mss.lua
	$(call mint,dadaluma_won,gen_zozo4_dadaluma)
# gen_zozo5_ramuh: the tower door (33,9) -> map 226 -> TERRA (talked from the
# WEST, {80,17} facing right: her tile is z-upper and the south tile z-lower,
# CheckNPCs' z-match rejects it) -> the pure-dialog RAMUH scene -> the four
# magicite (SIREN/KIRIN/STRAY bumped from {82,13}, collision tiles one row
# below their prop coords) -> the leave cutscene (its party_menu wants START)
# -> $0054=1 at {57,45}, v0.4's stop line.  Terra found catatonic, no rejoin.
build/states/zozo_done.mss.lua: build/states/dadaluma_won.mss.lua
	$(call mint,zozo_done,gen_zozo5_ramuh)
FRONTIER += figaro_submerged zozo_arrival zozo_clock_solved \
            dadaluma_doorstep dadaluma_won zozo_done

# ---- v0.5 Beat A: the Opera (zozo_done -> the Blackjack) ------------------
# gen_opera1_doorstep: zozo_done -> the world -> JIDOOR (map 198, entered at
# {15,61}) -> its north BUMP door {16,13}->{16,12} -> map 209 (the opera-plot
# room) -> parked at {117,20} facing UP, one A-press below the IMPRESARIO
# ({117,19}, _ca9337).  The survey's "park at the opera-house foyer impresario"
# is WRONG: the opera house (map 237, world {45,154}) keeps its impresario
# HIDDEN ($0340) behind a "closed" sign until the opera-open cutscene -- which
# BEGINS at this map-209 talk ("Maria!?" -> the letter $0331 -> the Setzer
# name-menu -> $0340=1).  The generator self-verifies (after the mint) that
# one A-press fires _ca9337, so the banked state is never a dead press short.
build/states/opera_doorstep.mss.lua: build/states/zozo_done.mss.lua
	$(call mint,opera_doorstep,gen_opera1_doorstep)
FRONTIER += opera_doorstep
# gen_opera2_open: opera_doorstep -> DRIVE the opera-open cutscene chain on map
# 209 (talk _ca9337 -> the letter $0331 -> the Setzer intro + name_menu ->
# $0340=1, the opera opens) -> travel 209 -> Jidoor (198, its south edge exits
# to world {27,132}) -> world -> the OPERA HOUSE (map 237, world {45,154}) ->
# parked at {60,49} below the now-VISIBLE IMPRESARIO ({60,48}, _caae15).  Mints
# opera_open, one A-press from the performance (the aria).  The name_menu and
# every TEXT_ONLY page ride on a hasControl-gated A/START stall fallback.
build/states/opera_open.mss.lua: build/states/opera_doorstep.mss.lua
	$(call mint,opera_open,gen_opera2_open)
FRONTIER += opera_open
# gen_opera3_backstage: opera_open -> talk the IMPRESARIO (_caae15) -> RIDE the
# performance intro -> the party lands controllable BACKSTAGE in the theater,
# map 234 {16,46}, $0055=1 (performance underway).  Mints opera_backstage.
build/states/opera_backstage.mss.lua: build/states/opera_open.mss.lua
	$(call mint,opera_backstage,gen_opera3_backstage)
FRONTIER += opera_backstage
# gen_opera4_stage: opera_backstage -> ROUTE A onto the STAGE.  The theater's
# stage doors {4,24}/{28,24} land in a disconnected 238 backstage, so the stage
# is reached via the opera-house interior: 234 {25,49}->237 {72,32}, walk to
# 237 {82,32}->238 {100,22}; then talk CELES {99,19} (_caba44) to ARM the aria
# ($0056=1).  Mints opera_stage, parked {99,20} one navTo from the aria {97,7}.
build/states/opera_stage.mss.lua: build/states/opera_backstage.mss.lua
	$(call mint,opera_stage,gen_opera4_stage)
FRONTIER += opera_stage
# gen_opera5_dance: opera_stage -> fire the aria trigger {97,7} -> map 236 -> the
# lyric forks {0,1,0} -> the FLOWER DANCE.  Map 236 is z-split (09 upper / 02
# lower / 03,0b bridges), which breaks bfsPath, so the two stair legs run on
# HAND-CODED per-tile tables (corridorFollow).  Waltz DRACO (obj#19 @ {12,19})
# x3 by greedy-chase in the uniform basin -> flowers (obj#16) -> $0057; then
# climb the z-split stairs to the balcony {8,9} -> _cabe6d stops the timer and
# rides the wedding-waltz finale (load 233 rafters -> load 238) -> $0111=1.
# Mints opera_dance_done on map 238 {98,7} -- the aria solved (blocker cracked).
build/states/opera_dance_done.mss.lua: build/states/opera_stage.mss.lua
	$(call mint,opera_dance_done,gen_opera5_dance)
FRONTIER += opera_dance_done

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

clean:
	$(MAKE) -C ff6 clean
	rm -rf build
