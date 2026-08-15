#!/usr/bin/env python3
"""pin_test_saves.py <src_settings> <dst_settings> <saves_dir>

Copy the user's Mesen settings into a worker's private Mesen config home,
and set the battery-save folder to a dedicated testing directory. The
testrunner twice flushed battery data to the user's real ot6.srm; this makes
the manual-play save (~/Library/.../Saves) and the repeatable-testing saves
(build/test-workers/w<id>/saves) unable to share a file, regardless of what
the source settings say now or grow to say later.

<dst_settings> is the worker's own
<home>/Library/Application Support/Mesen2/settings.json.  run.sh points
Mesen at that home with CFFIXED_USER_HOME, so writing here isolates a worker
without giving it a private copy of the emulator (see run.sh's
"shared emulator" note).  It used to be a settings.json inside a per-worker
app bundle, which is what made the copies necessary.
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

# Mesen's per-Lua-slice watchdog defaults to 1 second; a slow frame callback
# (e.g. a BFS over the collision grid) can be killed at that setting with no
# visible message (the error only goes to the script-window log, which is not
# displayed), wedging the run.  30 s keeps the watchdog as a hang backstop
# without stopping real work.
cfg.setdefault("Debug", {}).setdefault("ScriptWindow", {})["ScriptTimeout"] = 30

# Determinism pins.  Test profiles diverge from the user's play profile on
# these three, whatever the source settings say:
snes = cfg.setdefault("Snes", {})
# FF6 reads RAM it has never written, so RamPowerOnState=Random makes identical
# runs drift (extra encounters, +-frames) and embeds garbage in the savestates
# we generate.  Default AllZeros for reproducibility; OT6_RAM_POWERON overrides
# it for the dirty-RAM reveal investigation/check (AllOnes = deterministic and
# dirty, so it exercises what a real power-on garbage boot hands the
# battle-init clear).
ram = os.environ.get("OT6_RAM_POWERON", "AllZeros")
# RamPowerOnState is the only setting that picks the fill, for WRAM, SPC RAM,
# VRAM/CGRAM/OAM and cartridge SRAM alike. EnableRandomPowerOnState does not
# touch RAM; its one use on the SNES path is randomising PPU registers
# (brightness, Mode7 matrices, BG mode, layer enables), so leaving it on for
# Random also dirties the PPU. This once wrote "AllZeros" whenever
# Random was asked for, so no headless run had ever exercised random RAM.
snes["EnableRandomPowerOnState"] = (ram == "Random")
snes["RamPowerOnState"] = ram
# Frame-skip picks which frames render based on host timing, so
# screenshots and the framebuffer embedded in savestates vary run-to-run
# (and under parallel load) unless every frame renders.
snes["DisableFrameSkipping"] = True
# Controller pin.  The harness injects input with emu.setInput(pad, 0), which
# is inert unless port 0 is a configured SnesController (see the "Controller
# input" note in tools/tests/lib/ot6.lua).  Unlike the pins above, this one
# cannot fall back to a Mesen default: a source profile that never connected a
# controller -- a fresh install, a hand-written settings.json, CI -- leaves
# port 0 empty, and then every button press does nothing.  The game sits at the
# title and every checkpoint Continue and new-game drive fails deterministically,
# presenting exactly like a stale checkpoint or a broken ROM (#120, cost hours
# on 2026-08-15).  Force the type rather than setdefault it: the harness needs a
# SnesController on port 0 whatever the play profile happened to connect.
snes.setdefault("Port1", {})["Type"] = "SnesController"
# Audio is inert under --testrunner (no device opened); pinned off anyway.
cfg.setdefault("Audio", {})["EnableAudio"] = False

with open(dst, "w", encoding="utf-8") as f:
    json.dump(cfg, f)

print(f"test saves pinned to {saves}")
