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
	cp ff6/rom/ff6-en.sfc build/ot6.sfc

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
FRONTIER := arvis_wake narshe_streets moogle_doorstep moogle_cleared \
            worldmap_narshe figaro_doorstep figaro_intro figaro_matron \
            figaro_cleared south_figaro kolts_doorstep kolts_pool \
            kolts_cave vargas_doorstep vargas_won returner_hideout \
            banon_joined lete_river scenario_hub locke_scenario

# mint <state> from <script> once its ROM-content gate says it is stale
define mint
	@if [ build/states/.rom-copy -nt build/states/$(1).mss ] || [ ! -f build/states/$(1).mss ]; then \
		tools/tests/run.sh tools/tests/$(2).lua; \
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
