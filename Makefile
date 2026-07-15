BASE  := Final Fantasy III (USA).sfc
SHA1  := 4f37e4274ac3b2ea1bedb08aa149d8fc5bb676e7
FLIPS := tools/bin/flips
MESEN := tools/Mesen.app/Contents/MacOS/Mesen

.PHONY: all rom patch run test verify clean

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

patch: rom
	$(FLIPS) --create --bps "$(BASE)" build/ot6.sfc build/ot6.bps
	@ls -la build/ot6.bps

run: rom
	open -a "$(CURDIR)/tools/Mesen.app" "$(CURDIR)/build/ot6.sfc"

test: rom
	$(MESEN) --testrunner build/ot6.sfc tools/tests/smoke.lua

clean:
	$(MAKE) -C ff6 clean
	rm -rf build
