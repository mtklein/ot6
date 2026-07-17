#!/usr/bin/env python3
"""pin_test_saves.py <src_settings> <dst_settings> <saves_dir>

Copy the user's Mesen settings into the portable test app, but FORCE the
battery-save folder to a dedicated testing directory. The user was burned
twice by the testrunner flushing battery to their real ot6.srm; this makes
the manual-play save (~/Library/.../Saves) and the repeatable-testing saves
(build/mesen-test-saves) physically incapable of sharing a file, regardless
of what the source settings say now or grow to say later.
"""
import json, sys

src, dst, saves = sys.argv[1], sys.argv[2], sys.argv[3]

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
# FF6 reads uninitialized RAM, so RamPowerOnState=Random makes identical runs
# drift (extra encounters, +-frames) and embeds garbage in minted savestates.
snes["RamPowerOnState"] = "AllZeros"
# Frame-skip picks which frames actually render based on HOST timing, so
# screenshots and the framebuffer embedded in savestates vary run-to-run
# (and under parallel load) unless every frame renders.
snes["DisableFrameSkipping"] = True
# Audio is inert under --testrunner (no device opened); pinned off as hygiene.
cfg.setdefault("Audio", {})["EnableAudio"] = False

with open(dst, "w", encoding="utf-8") as f:
    json.dump(cfg, f)

print(f"test saves pinned to {saves}")
