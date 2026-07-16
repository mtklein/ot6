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

with open(dst, "w", encoding="utf-8") as f:
    json.dump(cfg, f)

print(f"test saves pinned to {saves}")
