BASE    := Final Fantasy III (USA).sfc
SHA1    := 4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7
FLIPS   := tools/bin/flips
MESEN   := tools/Mesen.app/Contents/MacOS/Mesen
VERSION := 0.5

# A failed recipe (e.g. the checksum step dying mid-build) leaves a half-built target the next make treats as up-to-date — bit us twice on 2026-07-18.
.DELETE_ON_ERROR:

.PHONY: all rom patch run test tested verify clean release release-test savestates savestates-test nomp-rom

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
	@# runs on every `make savestates` (which lists rom as a prerequisite); an
	@# unconditional cp would rewrite build/ot6.sfc under the worker-isolated
	@# savestate generations that `make -jN savestates` now runs in parallel, and
	@# a generator's Mesen reads that very file at boot. Same cmp-guard the
	@# state generators already use.
	@cmp -s ff6/rom/ff6-en.sfc build/ot6.sfc || cp ff6/rom/ff6-en.sfc build/ot6.sfc

# No distributable may be built from an untested ROM.  `test` stamps the
# sha1 of the exact ROM the suite passed on; `tested` refuses unless the
# ROM on disk is still that one.  This is structural on purpose: a human
# (or an agent) reading "green" off a scrolled-past terminal, or piping
# the suite through `tail` so the shell reports tail's exit status, is
# how v0.2 got tagged without anyone actually knowing the check was green.
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

# release: build the ROM, run BOTH checks, then emit the distribution patch.
# `test` is intentionally the fast development check and lets the tests that
# need generated savestates skip when those fixtures are absent.  A release
# must also generate the complete advertised story chain and rerun the suite
# with those tests live.
release-test:
	$(MAKE) savestates
	$(MAKE) test
	$(MAKE) savestates-test
	@echo "release gate green — base + the complete savestate chain"

release: release-test tested
	@mkdir -p build/release
	$(FLIPS) --create --bps "$(BASE)" build/ot6.sfc "build/release/ot6-v$(VERSION).bps"
	@if [ -f "docs/release-notes-v$(VERSION).md" ]; then \
		cp "docs/release-notes-v$(VERSION).md" build/release/RELEASE_NOTES.md; \
	else \
		sed 's/X\.Y/$(VERSION)/g' docs/release-notes-template.md > build/release/RELEASE_NOTES.md; \
	fi
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

# ------------------------------------------------- the savestate graph -----
# EVERY generated savestate -- the suite's own three fixtures and the whole
# story chain -- lives in ONE generated ninja graph (issue #25):
#
#   tools/tests/savestate_graph.py        the graph, as data (one entry/state)
#   tools/tests/lib/savestate_ninja.py    emits it as build/build.ninja
#
# Why ninja and not make macros: this Makefile had already bypassed make's
# core value proposition -- a content stamp beside a `touch` (two staleness
# mechanisms that could disagree, and on 2026-07-27 did: "rom content
# changed" printed, then an old-ROM savestate booted against the new ROM), a
# grep-generated include whose only job was making make reconsider targets,
# and a .PHONY pattern rule that silently matched nothing.  In the ninja
# graph the staleness decision and the execution are one mechanism: every
# input is a declared dependency, content-vs-mtime is ninja's own `restat`
# on cheap latch edges, an unknown target is a hard error, and nothing can
# report success without its command running.  savestate_ninja.py's header
# holds the full story; savestate_ninja_selftest.sh proves the semantics on
# a mock tree in seconds, no emulator.
#
# The targets here stay thin entry points.  Parallelism is ninja's own
# (all cores by default); pass NINJAFLAGS=-j2 to throttle it.
NINJA_FILE := build/build.ninja
NINJAFLAGS ?=
# first_battle is gen_battle_state's SECOND artifact (battle_levelup and
# battle_smoke boot it).  It has its own graph edge since #30's
# one-edge-one-artifact publish rule, but it was missing here -- so
# `make test` never freshened it and every ROM change left it stale,
# red-herringing battle_levelup (issue #41, found twice: the Slot landing
# and the tube-six build).
SUITE_STATES := battle_entry first_battle battle2_entry whelk_entry

.PHONY: graph
graph:
	@command -v ninja >/dev/null || \
		{ echo "ERROR: ninja not installed -- run 'brew bundle'"; exit 1; }
	@python3 tools/tests/lib/savestate_ninja.py

# compose.py's selftest is pure python and guards the suite: it is the positive
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

test: rom nomp-rom graph
	ninja -f $(NINJA_FILE) $(NINJAFLAGS) $(SUITE_STATES)
	python3 tools/tests/lib/compose.py --selftest
	python3 tools/tests/lib/sram_checkpoint.py selftest
	@# The harness's own PASS/FAIL parsing.  It had no selftest until
	@# 2026-08-10, and the gap shipped a FALSE GREEN: the pass pattern was
	@# a prefix (`^[ot6] PASS`), battle_thief logs `PASSED phase N` per
	@# phase, so a run killed by the wall-clock cap mid-test scored as a
	@# pass.  Every other check here is falsifiable; the one that decides
	@# pass-vs-fail for the whole suite must be too.
	sh tools/tests/run.sh --verdict-selftest
	@# bosses-wob.md vs the shipped break data.  It carried four waivers for
	@# rows the doc authored in prose and nobody wrote into the ROM; issue #23
	@# landed all of them, the WAIVERS dict is empty, and the script is a plain
	@# check now.  It lives here rather than in suite.sh because suite discovery
	@# globs *.lua for a `-- @suite` marker and cannot see a .py file -- same
	@# reason compose.py and sram_checkpoint.py sit on these lines.
	python3 tools/check_boss_rows.py
	python3 tools/check_break_reach.py
	@# No test may WRITE emulated game state (input injection and memory
	@# reads only).  Pre-rule violations are grandfathered in
	@# tools/state_write_waivers.txt, a burn-down list that only shrinks;
	@# any NEW write anywhere in tools/tests/**/*.lua fails here.
	python3 tools/check_state_writes.py --selftest
	python3 tools/check_state_writes.py
	@# Nobody fights bare-handed.  The game strips characters at story beats
	@# and returns their gear to inventory; no generator step ever put it back, so LOCKE
	@# was unarmed in 42 fixtures and CELES in 29, and solo LOCKE punching a
	@# 495-hp HeavyArmor read as a balance wall for three runs.  Reads the
	@# savestates directly -- no emulator, ~1s for the whole tree -- so the
	@# check is cheap enough to be unconditional.  Silent on an empty
	@# build/states, because `make test` must not require the generated
	@# savestates.
	python3 tools/audit_equipment.py
	python3 tools/tests/lib/savestate_ninja.py --selftest
	sh tools/tests/lib/savestate_ninja_selftest.sh
	sh tools/tests/lib/savestate_stamp_selftest.sh
	sh tools/tests/lib/runner_isolation_selftest.sh
	@# suite.sh's own bookkeeping: the tally line below, and the guard that
	@# fails the run if a discovered test never reports.  Runs against a
	@# miniature fake tree with a stub runner, so it costs milliseconds and
	@# reaches the FAIL/xfail/dead-worker branches a green suite never does.
	sh tools/tests/lib/suite_tally_selftest.sh
	sh tools/tests/lib/checkpoint_negatives.sh
	@# Fixture provenance is a HARD CHECK (issue #75 step 5), not a warning: every
	@# stamped fixture must hash back to the sources, the artifact bytes, and
	@# the ancestor stamp it claims -- transitively, chain by chain.  A stale
	@# or unbound fixture fails HERE, with the full list and the smallest
	@# sufficient regeneration command, instead of warning from inside a composed
	@# file nobody reads until some downstream test goes red for it.
	python3 tools/tests/lib/compose.py --check-states
	@rm -f $(STAMP)
	tools/tests/suite.sh
	@echo "-- mpcost A/B: the OFF half (free — the negative control) on the nomp baseline --"
	OT6_ROM=$(CURDIR)/ff6/rom/ff6-en-nomp.sfc tools/tests/run.sh tools/tests/battle_mpcost.lua
	OT6_ROM=$(CURDIR)/ff6/rom/ff6-en-nomp.sfc tools/tests/run.sh tools/tests/battle_stealmp.lua
	@shasum -a 1 build/ot6.sfc | cut -d' ' -f1 > $(STAMP)
	@echo "suite green — stamped `cat $(STAMP)`"

# --------------------------------------------------------------- savestates --
# The story chain past the whelk, produced by the generated ninja graph
# above.  `test` deliberately depends on none of it: every state in it is
# a multi-minute scripted playthrough, and the suite's regeneration cost has
# to stay what it was.  Build it on demand -- everything with `make savestates`,
# or one state (and its stale transitive predecessors) by naming it:
#
#   ninja -f build/build.ninja vargas_entry
#
# The play-order chain, the checkpoint keys, the per-state route notes and the
# scenario-stacking story all live with the data: tools/tests/savestate_graph.py.
# SAVESTATES_JOBS bounds `make savestates` -- and ONLY that target -- by default.
# Every other ninja target here is cheap and stays on ninja's own default.
#
# WHY A BOUND AT ALL.  Each savestate generation is a Mesen process racing a
# WALL-CLOCK cap (run.sh --timeout=600).  nice(1) does not slow the wall, and
# every one of them is equally niced, so they starve EACH OTHER: unbounded,
# `savestates` fans out to cores+2 emulators, each gets well under a core, and
# the longest steps cross 600s and are killed by the timeout -- `savestates` is
# the one target that reliably provokes this, because it is the one that
# parallelises hard on its own.
# "Green" then depends on how loaded the machine happened to be.
#
# WHY 4.  It is the number that has been measured, not derived: 109 states
# generated in ~60 min with ZERO timeout kills (2026-07-29, M4 Max, other
# agents live).  Raise it
# on an idle machine -- NINJAFLAGS still overrides everything, and
# `make savestates SAVESTATES_JOBS=8` overrides just this.
SAVESTATES_JOBS ?= 4
savestates: rom graph
	@# Check generation the same way `test` is checked: a generator that pokes
	@# game state produces a fixture nobody played, and `make savestates` can be
	@# run with `make test` skipped -- so the no-state-write check runs here too.
	python3 tools/check_state_writes.py
	ninja -f $(NINJA_FILE) $(if $(NINJAFLAGS),$(NINJAFLAGS),-j$(SAVESTATES_JOBS)) savestates
	@echo "savestates up to date"

# ---------------------------------------------------------------- smoke ----
# The FAST FALSIFICATION LOOP.  `make savestates` is authoritative but serial and
# costs over an hour, which is what makes a wrong guess expensive -- and a wrong
# guess is only ever a problem when checking it is slow.
#
# For a LIB-ONLY change the existing savestates still boot, because they are tied
# to ROM contents and the ROM has not moved.  So any generator can be run
# directly, right now, from the state already on disk.  These are the ones that
# have historically caught harness regressions, each exercising a DIFFERENT way
# the harness can be lied to:
#
#   gen_moogle           multi-party field scribble in the battle-HP table
#   gen_narshe_battle    NPC activation that depended on navTo's mid-glide handoff
#   gen_sabin_gau        a navTo aimed at a tile you step through, never rest on
#   gen_zozo5_ramuh      the party menu, where a false battle reading A-hammers
#   gen_opera7_blackjack the world arrival redraw, same lie on the world map
#   gen_vector_entry     worldGrind, an event trigger, and the party-count control
#   gen_n128             cutscene TRAIN and six scripted battles
#
# Run them all at once: `make -j$(shell sysctl -n hw.perflevel0.logicalcpu 2>/dev/null || echo 4) smoke`.
# Nothing is published (OT6_NO_PUBLISH), so this cannot half-update the chain.
SMOKE := gen_moogle gen_narshe_battle gen_sabin_gau gen_zozo5_ramuh \
         gen_opera7_blackjack gen_vector_entry gen_n128
SMOKE_TARGETS := $(addprefix smoke-,$(SMOKE))

# NB: a STATIC pattern rule, not an implicit one.  GNU make does not apply
# implicit pattern rules to .PHONY targets, so `smoke-%: rom` silently matched
# nothing and `smoke` reported "all 7 passed" in 0.036s having run nothing at
# all.  The receipt count below exists because of that: a smoke target that can
# report success without executing is the exact failure this suite keeps finding.
.PHONY: smoke $(SMOKE_TARGETS)
smoke: $(SMOKE_TARGETS)
	@n=`ls build/states/smoke_*.receipt 2>/dev/null | wc -l | tr -d ' '`; \
	if [ "$$n" -ne $(words $(SMOKE)) ]; then \
	  echo "smoke: ONLY $$n of $(words $(SMOKE)) generators actually ran"; exit 1; \
	fi; \
	echo "smoke: all $(words $(SMOKE)) generators ran and passed"

# Generators that start from a checkpoint cold-load a tracked battery instead
# of booting a predecessor savestate, so smoke must hand each one its
# checkpoint exactly as the graph's checkpoint edges do (OT6_SRAM_CHECKPOINT) --
# without it the run times out waiting for the cold Continue.  One entry per
# such smoke generator, keyed by gen name; a gen with no entry boots
# savestates.  This map is what retired gen_n128's dual-boot battery probe:
# smoke now hands every such generator its battery instead of asking the
# generator to guess its boot from SRAM contents.
SMOKE_CHECKPOINT_gen_vector_entry := tools/tests/checkpoints/post-opera-v1
SMOKE_CHECKPOINT_gen_n128         := tools/tests/checkpoints/minecart-platform-v1

$(SMOKE_TARGETS): smoke-%: rom
	@rm -f build/states/smoke_$*.receipt
	@OT6_NO_PUBLISH=1 OT6_WORKER=$* \
	 $(if $(SMOKE_CHECKPOINT_$*),OT6_SRAM_CHECKPOINT=$(SMOKE_CHECKPOINT_$*),) \
	 tools/tests/run.sh tools/tests/$*.lua \
	   > build/states/smoke_$*.log 2>&1 \
	  && { touch build/states/smoke_$*.receipt; echo "  $*: pass"; } \
	  || { echo "  $*: FAIL -- build/states/smoke_$*.log"; \
	       grep -E 'FAIL|assertEq' build/states/smoke_$*.log | head -3; exit 1; }

# ---- SRAM checkpoints, keyed by milestone (issue #25) ---------------------
# tools/tests/checkpoints/<key>/ is one milestone checkpoint: manifest.json plus a
# 32 KiB battery payload generated through the game's own Save UI (#9 -- never
# synthesised).  The key is the milestone name; post-opera-v1 is the only
# real one today, and savestate_graph.py's A-F boundary section names the states
# this convention must hold (mrf-save-room, n024-entry-save, ...).  Dirs
# named negative-* are deliberately wrong fixtures for `make checkpoint-negatives`
# below; savestate_ninja.py refuses a graph entry that names one.  Generation
# from a checkpoint lives in the ninja graph (checkpoint="<key>" in
# savestate_graph.py): the manifest and payload ride that step's dependency
# set, so editing either regenerates every state hung off the checkpoint, and
# run.sh's persistent_layout check refuses the load before boot if the
# generator does not declare the checkpoint's layout.  Smoke's checkpoint
# generators get theirs through the SMOKE_CHECKPOINT_* map above.

# The stale-checkpoint regression (#25): prove both refusal paths FAIL, loudly,
# naming what differed -- the pre-boot persistent_layout check and the
# in-emulator entry contract.  A check is only evidence when its negative has
# been observed failing; a green run from a checkpoint alone cannot show that.
# Costs one short emulator boot (~1 min); not part of smoke.
.PHONY: checkpoint-negatives
checkpoint-negatives: rom
	sh tools/tests/lib/checkpoint_negatives.sh

# The suite INCLUDING the tests that need generated savestates.  battle_vargas
# asserts on vargas_entry, and `test` deliberately does not depend on it:
# generating it replays the whole story chain, which is the cost `make
# savestates` exists to keep out of `make test`.  suite.sh picks the test up
# automatically once the fixture is on disk and reports it as skipped when it
# is not, so this target is just "generate the chain, then run the same
# suite".
savestates-test: savestates
	python3 tools/tests/lib/compose.py --selftest
	tools/tests/suite.sh

clean:
	$(MAKE) -C ff6 clean
	rm -rf build
