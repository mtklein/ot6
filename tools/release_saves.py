#!/usr/bin/env python3
"""The release zip's saves/ folder: every tracked checkpoint's battery save,
named for players, in story order.

    release_saves.py stage DIR    write DIR/saves/NN - Title.srm + README.txt
    release_saves.py check ZIP    the zip holds exactly those saves, each the
                                  tracked bytes (size and SHA-256)
    release_saves.py list         print the order and names

Order is the savestate graph's: the checkpoints its runs save
(savestate_ninja.producers), each placed by the depth of the run that saves
it along the prev= chain.  Names are TITLES below; a tracked checkpoint
without one fails both commands, so a new checkpoint gets a name when it
lands.  The negative-* fixtures never ship.

Every tracked save holds slot 3 (battery byte $1FF0 = 3, slot 3's checksum
valid) with slots 1 and 2 zeroed, which the game shows as empty; check
refuses one that does not.
"""

from __future__ import annotations

import hashlib
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools" / "tests" / "lib"))
import savestate_ninja as sn  # noqa: E402
import sram_checkpoint as sc  # noqa: E402

CKPT = ROOT / "tools" / "tests" / "checkpoints"

TITLES = {
    "world-narshe-v1": "Outside Narshe, after the moogles",
    "world-figaro-v1": "Outside Figaro Castle, after the escape",
    "kolts-summit-v1": "Mt. Kolts, summit save point",
    "hub-v1": "Scenario choice, before Locke's scenario",
    "locke-done-v1": "Scenario choice, Locke's scenario done",
    "camp-escaped-v1": "Imperial Camp, after the escape",
    "falls-done-v1": "The Veldt, after Barren Falls",
    "sabin-done-v1": "Scenario choice, Sabin's scenario done",
    "kefka-won-v1": "Narshe, after the battle with Kefka",
    "zozo-outside-v1": "Outside Zozo",
    "post-opera-v1": "After the opera, on the way to Vector",
    "mrf-save-room-v1": "Magitek Research Facility, save point",
    "n024-entry-save-v1": "Magitek Research Facility, before Number 024",
    "minecart-platform-v1": "Magitek Research Facility, minecart platform",
    "terra-returned-v1": "After Terra's return",
    "narshe-mission-v1": "Narshe, after the meeting",
    "water-rondo-v1": "Nikeah, after Mog learns Water Rondo",
    "gate-cave-save-v1": "Cave to the Sealed Gate, save point",
    "vector-crash-v1": "After the airship crash",
    "banquet-done-v1": "Vector, after the banquet",
    "crescent-landing-v1": "Crescent Island, landing",
    "thamasa-night-v1": "Outside Thamasa, first night",
    "fire-out-v1": "Thamasa, after the fire",
    "esper-mtn-save-v1": "Esper Mountain, save point",
    "ultros-won-v1": "Esper Mountain, after Ultros",
    "thamasa-done-v1": "Thamasa, after Leo",
    "fc-landing-v1": "Floating Continent, landing",
    "fc-alcove-v1": "Floating Continent, save point",
    "wor-island-v1": "World of Ruin, Solitary Island",
    "wor-start-v1": "World of Ruin, after the raft",
    "wor-tzen-door-v1": "Tzen, before the collapsing house",
    "wor-sabin-v1": "Tzen, after Sabin joins",
    "wor-nikeah-v1": "Outside Nikeah",
    "wor-south-figaro-v1": "Outside South Figaro",
    "wor-edgar-v1": "Figaro Castle, after Edgar joins",
    "wor-figaro-sweep-v1": "Figaro Castle, after South Figaro's relics",
    "wor-kohlingen-v1": "Outside Kohlingen, after Setzer joins",
    "wor-tomb-v1": "Darill's Tomb, save point",
    "wor-falcon-v1": "The Falcon, after Darill's Tomb",
    "wor-terra-v1": "Mobliz, after Terra joins",
    "wor-mtzozo-v1": "Mt. Zozo, save point after Cyan joins",
    "wor-cyan-v1": "The Falcon, after the Storm Dragon",
    "wor-narshe-cliffs-v1": "Narshe cliffs, save point after Mog joins",
    "wor-narshe-v1": "The Falcon outside Narshe, after Umaro joins",
    "wor-owzer-v1": "Owzer's basement, save point before Chadarnook",
    "wor-tower-v1": "Outside the Fanatics' Tower, after Strago joins",
    "wor-thamasa-v1": "Outside the Fanatics' Tower, after MagiMaster",
    "wor-phoenix-v1": "Phoenix Cave, save point with the party split",
    "wor-locke-v1": "Outside Kohlingen, after Locke joins",
    "wor-ragnarok-v1": "Outside Narshe, after Ragnarok",
}

README = """\
OT6 saves

Each .srm file here is a battery save made by playing this release from
the start. The number is the order in the story. The save is in slot 3.

To use one:
1. Back up your own save file first.
2. Copy the .srm next to the patched ROM and give it the ROM's name:
   OT6.srm for the Android patcher's OT6.sfc, or
   Final Fantasy III (USA).srm when the emulator applies the patch.
3. Start the game, choose Continue on the title screen, and load slot 3.

These saves are for this release's save layout. A save from a different
release may not load correctly.
"""


class SavesError(Exception):
    pass


def tracked_keys() -> list[str]:
    return sorted(p.parent.name for p in CKPT.glob("*/manifest.json")
                  if not p.parent.name.startswith("negative"))


def ordered() -> list[tuple[str, str, Path]]:
    """[(checkpoint key, zip path, tracked payload)] in story order."""
    states = sn.load(ROOT)
    owner = {}
    for e in states:
        owner[e["state"]] = e["state"]
        for a in (e.get("also") or []):
            owner[a] = e["state"]
    by = {e["state"]: e for e in states}
    depth: dict[str, int] = {}

    def d(name: str) -> int:
        name = owner[name]
        if name not in depth:
            p = by[name].get("prev")
            depth[name] = 1 + (d(p) if p else 0)
        return depth[name]

    rank = {}
    for key, run in sn.producers(states).items():
        # ("run", state): that state's run saves it; ("cutter", gen, prev):
        # a capture-only run booted from prev saves it, just after prev.
        rank[key] = 2 * d(run[1]) if run[0] == "run" else 2 * d(run[2]) + 1
    keys = tracked_keys()
    problems = [f"{k}: no run on the savestate graph saves it"
                for k in keys if k not in rank]
    problems += [f"{k}: no title in tools/release_saves.py TITLES"
                 for k in keys if k not in TITLES]
    if problems:
        raise SavesError("\n".join(problems))
    keys.sort(key=lambda k: rank[k])
    out = []
    for i, k in enumerate(keys, 1):
        manifest, payload = sc.load(CKPT / k)
        out.append((k, f"saves/{i:02d} - {TITLES[k]}.srm", payload))
    return out


def slot_problem(data: bytes) -> str | None:
    """Why the ROM's own load check (CalcSaveSlotChecksum and
    CheckSaveSlotChecksum, ff6/src/menu/save.asm) would not load the last
    saved slot, or why another slot is not empty."""
    last = data[0x1FF0]
    if last not in sc.SLOT_PTR:
        return f"battery byte $1FF0 is {last}, not a slot 1..3"
    for slot, ptr in sc.SLOT_PTR.items():
        body = data[ptr:ptr + 0xA00]
        if slot != last:
            if any(body):
                return f"slot {slot} is not empty"
            continue
        total = sum(body[:0x9FE]) & 0xFFFF or 0xFFFF
        if total != int.from_bytes(body[0x9FE:0xA00], "little"):
            return f"slot {slot}'s checksum does not match"
    return None


def stage(dest: Path) -> None:
    saves = dest / "saves"
    if saves.exists():
        for p in saves.iterdir():
            p.unlink()
    saves.mkdir(parents=True, exist_ok=True)
    for _, name, payload in ordered():
        (dest / name).write_bytes(payload.read_bytes())
    (saves / "README.txt").write_text(README)


def check(zip_path: Path) -> None:
    want = ordered()
    with zipfile.ZipFile(zip_path) as z:
        infos = {i.filename: i for i in z.infolist()
                 if i.filename.startswith("saves/") and not i.is_dir()}
        problems = []
        expected = {name for _, name, _ in want} | {"saves/README.txt"}
        for extra in sorted(set(infos) - expected):
            problems.append(f"{extra}: not a tracked checkpoint")
        for key, name, payload in want:
            data = payload.read_bytes()
            if name not in infos:
                problems.append(f"{name}: missing ({key})")
                continue
            got = z.read(name)
            if len(got) != len(data) or len(got) != sc.SRAM_SIZE:
                problems.append(f"{name}: {len(got)} bytes, tracked "
                                f"{len(data)}")
            elif hashlib.sha256(got).hexdigest() != \
                    hashlib.sha256(data).hexdigest():
                problems.append(f"{name}: SHA-256 differs from {payload}")
            elif (p := slot_problem(got)):
                problems.append(f"{name}: {p}")
            else:
                print(f"ok {len(got)} {hashlib.sha256(got).hexdigest()[:16]}"
                      f" {name} = {key}")
        if "saves/README.txt" not in infos:
            problems.append("saves/README.txt: missing")
        elif z.read("saves/README.txt").decode() != README:
            problems.append("saves/README.txt: differs from the script's")
    if problems:
        raise SavesError("\n".join(problems))
    print(f"release saves: {zip_path} holds all {len(want)} tracked "
          f"checkpoints (negative-* excluded) and saves/README.txt")


def main(argv: list[str]) -> int:
    try:
        if len(argv) == 2 and argv[0] == "stage":
            stage(Path(argv[1]))
        elif len(argv) == 2 and argv[0] == "check":
            check(Path(argv[1]))
        elif argv == ["list"]:
            for key, name, _ in ordered():
                print(f"{name}  ({key})")
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except (SavesError, sc.CheckpointError) as exc:
        print(f"release saves: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
