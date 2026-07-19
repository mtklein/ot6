#!/usr/bin/env python3
"""pin_test_saves.py <src_settings> <dst_settings> <saves_dir>

Copy the user's Mesen settings into a worker's private Mesen config home,
but FORCE the battery-save folder to a dedicated testing directory. The user
was burned twice by the testrunner flushing battery to their real ot6.srm;
this makes the manual-play save (~/Library/.../Saves) and the
repeatable-testing saves (build/test-workers/w<id>/saves) physically
incapable of sharing a file, regardless of what the source settings say now
or grow to say later.

<dst_settings> is the worker's own
<home>/Library/Application Support/Mesen2/settings.json -- run.sh points
Mesen at that home with CFFIXED_USER_HOME, so writing here isolates a worker
without giving it a private copy of the emulator (see run.sh's
"shared emulator" note).  It used to be a settings.json INSIDE a per-worker
app bundle, which is what made the copies necessary in the first place.
"""
import json, os, sys

src, dst, saves = sys.argv[1], sys.argv[2], sys.argv[3]

# A worker home is disposable (run.sh re-seeds it whenever the emulator
# changes), so never assume the directory survived.
os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)

# Mesen writes its settings.json with a UTF-8 BOM; read it back the same way.
with open(src, encoding="utf-8-sig") as f:
    cfg = json.load(f)

prefs = cfg.setdefault("Preferences", {})
prefs["OverrideSaveDataFolder"] = True
prefs["SaveDataFolder"] = saves          # dedicated, isolated from the user's

# Mesen's per-Lua-slice watchdog defaults to 1 SECOND; a slow frame callback
# (e.g. a BFS over the collision grid) can be killed SILENTLY at that setting
# (the error only goes to the invisible script-window log), wedging the run.
# 30 s keeps the watchdog as a hang backstop without biting real work.
cfg.setdefault("Debug", {}).setdefault("ScriptWindow", {})["ScriptTimeout"] = 30

# Determinism pins -- test profiles deliberately diverge from the user's play
# profile on these three, whatever the source settings say:
snes = cfg.setdefault("Snes", {})
# FF6 reads RAM it has never written, so RamPowerOnState=Random makes identical
# runs drift (extra encounters, +-frames) and embeds garbage in minted savestates.
# Default AllZeros for reproducibility; OT6_RAM_POWERON overrides it for the
# dirty-RAM reveal investigation/gate (AllOnes = deterministic AND dirty, so
# it exercises what a real power-on garbage boot hands the battle-init clear).
ram = os.environ.get("OT6_RAM_POWERON", "AllZeros")
# RamPowerOnState is the ONLY thing that picks the fill -- for WRAM, SPC RAM,
# VRAM/CGRAM/OAM and cartridge SRAM alike. EnableRandomPowerOnState does not
# touch RAM at all; its one use on the SNES path is randomising PPU registers
# (brightness, Mode7 matrices, BG mode, layer enables), so leaving it on for
# Random deliberately dirties the PPU too. This once wrote "AllZeros" whenever
# Random was asked for, so no headless run had ever exercised random RAM.
snes["EnableRandomPowerOnState"] = (ram == "Random")
snes["RamPowerOnState"] = ram
# Frame-skip picks which frames actually render based on HOST timing, so
# screenshots and the framebuffer embedded in savestates vary run-to-run
# (and under parallel load) unless every frame renders.
snes["DisableFrameSkipping"] = True
# Audio is inert under --testrunner (no device opened); pinned off as hygiene.
cfg.setdefault("Audio", {})["EnableAudio"] = False

with open(dst, "w", encoding="utf-8") as f:
    json.dump(cfg, f)

print(f"test saves pinned to {saves}")
