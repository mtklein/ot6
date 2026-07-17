BASE    := Final Fantasy III (USA).sfc
SHA1    := 4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7
FLIPS   := tools/bin/flips
MESEN   := tools/Mesen.app/Contents/MacOS/Mesen
VERSION := 0.1

.PHONY: all rom patch run test verify clean goldens-capture release

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

# patch basename must differ from the ROM's, or Mesen auto-applies it on load
patch: rom
	@mkdir -p build/dist
	$(FLIPS) --create --bps "$(BASE)" build/ot6.sfc build/dist/ot6-from-ff3us10.bps
	@ls -la build/dist/ot6-from-ff3us10.bps

# release: build the ROM, run the full gate, then emit the distribution
# patch plus release notes from docs/release-notes-template.md (X.Y in
# the template becomes $(VERSION); override with `make release VERSION=0.2`).
release: test
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
	cp build/states/shots/visual_f1_menu.png tools/tests/goldens/
	@echo "goldens recaptured for the fresh state mint"
$(STATE2): $(STATE1)
	@if [ build/states/.rom-copy -nt build/states/battle2_doorstep.mss ] || [ ! -f build/states/battle2_doorstep.mss ]; then \
		tools/tests/run.sh tools/tests/gen_battle2.lua; \
	fi
	@touch $(STATE2)
# whelk doorstep: the dialog-opening boss fight battle_dlgmenu gates.
# gen_whelk boots from the SRM sidecar (build/states/playthrough_srm.mss.lua,
# local fixture from make_srm_sidecar.sh), so this mint needs that sidecar.
$(STATE3): $(STATE2)
	@if [ build/states/.rom-copy -nt build/states/whelk_doorstep.mss ] || [ ! -f build/states/whelk_doorstep.mss ]; then \
		tools/tests/run.sh tools/tests/gen_whelk.lua; \
	fi
	@touch $(STATE3)

test: rom $(STATE1) $(STATE2) $(STATE3)
	tools/tests/suite.sh

goldens: rom $(STATE1) $(STATE2)
	tools/tests/run.sh tools/tests/visual_f1.lua
	@mkdir -p tools/tests/goldens
	cp build/states/shots/visual_f1_idle.png tools/tests/goldens/
	cp build/states/shots/visual_f1_menu.png tools/tests/goldens/
	@echo "goldens captured from the current build - review before committing"

clean:
	$(MAKE) -C ff6 clean
	rm -rf build
