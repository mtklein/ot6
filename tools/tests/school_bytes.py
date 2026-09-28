#!/usr/bin/env python3
"""Pin the Narshe school's OT6 dialog into tools/tests/school.lua.

    python3 tools/tests/school_bytes.py          # rewrite the pinned block
    python3 tools/tests/school_bytes.py --check  # exit 1 if it is out of date

Encodes each school dialog id from ff6/src/text/dlg1_en.json with the
build's own codec (romtools, the dialog_en + dialog_escape + dte tables) and
writes the bytes, the page count and the text itself between the
BEGIN/END school_bytes markers.  school.lua compares the ROM against these
bytes, so a reverted or re-worded advisor fails the suite until the pin is
regenerated on purpose.
"""
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ff6" / "tools"))
import romtools as rt  # noqa: E402

IDS = [0x0257, 0x025D, 0x0267, 0x0264, 0x026D, 0x0270, 0x026E, 0x026F, 0x0274, 0x0276]
LUA = ROOT / "tools" / "tests" / "school.lua"


def block():
    asset = json.loads((ROOT / "ff6/src/text/dlg1_en.json").read_text("utf8"))
    os.chdir(ROOT / "ff6")  # the codec opens tools/char_table/*.json relative
    codec = rt.TextCodec(asset)
    out = ["local cases = {"]
    for i in IDS:
        text = asset["text"][i]
        enc = list(codec.encode(text))
        out.append("  {")
        out.append(f"    id = 0x{i:04X}, pages = {text.count('{page}') + 1},")
        out.append(f"    -- {text}")
        out.append("    bytes = {")
        for k in range(0, len(enc), 12):
            out.append("      " + " ".join(f"0x{b:02X}," for b in enc[k:k + 12]))
        out.append("    },")
        out.append("  },")
    out.append("}")
    return "\n".join(out) + "\n"


def main():
    src = LUA.read_text("utf8")
    pat = re.compile(r"(-- BEGIN school_bytes[^\n]*\n)(.*?)(-- END school_bytes)", re.S)
    new = pat.sub(lambda m: m.group(1) + block() + m.group(3), src, count=1)
    if "--check" in sys.argv[1:]:
        if new != src:
            print("school.lua's pinned bytes are out of date: "
                  "python3 tools/tests/school_bytes.py")
            return 1
        print("school.lua's pinned bytes match dlg1_en.json")
        return 0
    LUA.write_text(new, "utf8")
    print(f"pinned {len(IDS)} dialogs into {LUA.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
