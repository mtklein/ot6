#!/usr/bin/env python3
"""rom_version.py -- the build's version fields, and the ROM identity that
leaves them out.

A built ROM says which OT6 it is in two fixed-size, fixed-address fields,
written after the link (tools/build/link_rom.sh, before fix_checksum.py)
from the repo's VERSION file:

    Ot6VersionText  c0/ffa0, 16 bytes   OT6_VERSION_CELLS (15) menu-font
                    cells, "OT6 v<VERSION>" centered and padded with spaces
                    ($ff), then $00 (ff6/include/ot6_version.inc).  The
                    Config screen (menu/ot6_version.asm) and the boot splash
                    (cutscene/ot6_version.asm) each draw all 15 cells, so
                    every VERSION runs the same code for the same cycles.
    SnesHeader      c0/ffc0, 21 bytes   the internal header title, ASCII
                    "OT6 V<VERSION>", space-padded, for tools that read it.

and fix_checksum.py then writes the header checksum (c0/ffdc, 4 bytes) over
the whole ROM, these fields included.

The ROM identity is sha256 of the ROM with those three ranges (VERSION_FIELDS)
set to zero.  It is what a fixture, a checkpoint capture and a test result
bind to (lib/stamps.py's `input build/ot6.sfc` line; the ROM copy edge below), so the release
commit's VERSION bump, which changes only these bytes, stales nothing that
was qualified, while any other byte change still changes the identity.  The
version text itself is checked on the shipped bytes by the
menu_configversion and title_version suites, which depend on the ROM file
and VERSION, not only the identity.

Usage:
    rom_version.py stamp ROM VERSION DBG
        # write both fields; DBG (ff6-en.dbg) must place Ot6VersionText and
        # SnesHeader where VERSION_FIELDS says, and "OT6 v<VERSION>" must fit
        # OT6_VERSION_CELLS
    rom_version.py check VERSION     # the VERSION grammar (configure.py runs it)
    rom_version.py identity ROM      # the masked sha256
    rom_version.py read ROM          # the two fields, decoded
    rom_version.py copy-if-identity-changed SRC DST
        # ninja's copy of the ROM: DST gets SRC's bytes, but keeps its mtime
        # when the identities agree, so restat prunes a version-only change
    rom_version.py selftest
"""

import hashlib
import json
import os
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent

# (name, file offset, size): the bytes a VERSION bump may change.  HiROM, so
# c0/xxxx is file offset $00xxxx.
VERSION_TEXT = ("Ot6VersionText", 0xFFA0, 16)
HEADER_TITLE = ("SnesHeader", 0xFFC0, 21)
HEADER_CHECKSUM = ("checksum", 0xFFDC, 4)
VERSION_FIELDS = (VERSION_TEXT, HEADER_TITLE, HEADER_CHECKSUM)

TEXT_PREFIX = "OT6 v"
# The one VERSION grammar (configure.py checks it when it configures, and
# derives the APK versionCode from it): major.minor[.patch][-rcN], minor and
# patch 0-99, N 1-99, and "OT6 v<VERSION>" no wider than the 15 cells the ROM
# shows it in.  So 0.24, 0.24-rc1, 0.24.1, 0.24.1-rc1 and 10.24-rc10 are
# versions; 0.24.10-rc10 (17 characters) is not.
VERSION_RE = re.compile(r"(\d+)\.(\d+)(?:\.(\d+))?(?:-rc([1-9]\d?))?")
SPACE = 0xFF                            # the menu font's blank cell
TITLE_PREFIX = "OT6 V"
# the menu font's small-text table (ff6/tools/encode_menu_text.py's
# SMALL_CHAR_TABLES_EN): the version text is drawn with DrawPosTextFar
CHAR_TABLES = ("null_terminated_en", "text_en", "small_symbols_en")


def _codec():
    enc, dec = {}, {}
    for name in CHAR_TABLES:
        path = ROOT / "ff6" / "tools" / "char_table" / f"{name}.json"
        for code, value in json.loads(path.read_text()).items():
            code = int(code, 0)
            values = value if isinstance(value, list) else [value]
            for v in values:
                enc.setdefault(v, code)
            dec.setdefault(code, values[0])
    return enc, dec


def check_version(version):
    """(major, minor, patch, rc) for a VERSION the grammar above accepts
    (patch and rc 0 when absent); ValueError, saying why, for any other."""
    m = VERSION_RE.fullmatch(version)
    if not m:
        raise ValueError(f"VERSION {version!r} is not major.minor[.patch][-rcN]")
    major, minor, patch, rc = (int(g) if g else 0 for g in m.groups())
    if minor > 99 or patch > 99:
        raise ValueError(f"VERSION {version!r}: minor and patch are 0-99 "
                         f"(the APK versionCode gives each two digits)")
    cells = version_cells()
    if len(TEXT_PREFIX + version) > cells:
        raise ValueError(f"VERSION {version!r}: {(TEXT_PREFIX + version)!r} is "
                         f"{len(TEXT_PREFIX + version)} characters; the ROM shows "
                         f"it in {cells} cells")
    return major, minor, patch, rc


def apk_version_code(version):
    """The APK's versionCode, ordering releases and their candidates:
    major*1000000 + minor*10000 + patch*100 + (N for -rcN, else 99), so
    0.24-rc1 -> 240001 < 0.24 -> 240099 < 0.24.1 -> 240199."""
    major, minor, patch, rc = check_version(version)
    return major * 1000000 + minor * 10000 + patch * 100 + (rc or 99)


def version_cells():
    """OT6_VERSION_CELLS, from the include the asm assembles with; it must
    leave the field one byte for its $00."""
    inc = (ROOT / "ff6" / "include" / "ot6_version.inc").read_text()
    m = re.search(r"^OT6_VERSION_CELLS\s*=\s*(\d+)", inc, re.M)
    if not m:
        raise ValueError("ff6/include/ot6_version.inc defines no OT6_VERSION_CELLS")
    cells = int(m.group(1))
    if cells + 1 != VERSION_TEXT[2]:
        raise ValueError(f"OT6_VERSION_CELLS is {cells}; Ot6VersionText holds "
                         f"{VERSION_TEXT[2]} bytes, so it must be {VERSION_TEXT[2] - 1}")
    return cells


def field_bytes(version):
    """Ot6VersionText's 16 bytes for `version`: the text centered in the
    cells, space-padded, then $00."""
    cells = version_cells()
    text = menu_text(version)
    if len(text) > cells:
        raise ValueError(f"{(TEXT_PREFIX + version)!r} is {len(text)} characters; "
                         f"the version displays are {cells} cells wide")
    left = (cells - len(text)) // 2
    body = bytes([SPACE] * left) + text + bytes([SPACE] * (cells - left - len(text)))
    return body + b"\0"


def menu_text(version):
    """'OT6 v<version>' as menu-font bytes, unterminated."""
    enc, _ = _codec()
    text = TEXT_PREFIX + version
    out = []
    for ch in text:
        if ch not in enc or enc[ch] > 0xFF or enc[ch] == 0:
            raise ValueError(f"{text!r}: {ch!r} has no menu-font glyph")
        out.append(enc[ch])
    return bytes(out)


def header_title(version):
    title = (TITLE_PREFIX + version).upper()
    if not re.fullmatch(r"[ -~]*", title):
        raise ValueError(f"{title!r}: the header title is printable ASCII")
    return title.encode("ascii")


def identity_bytes(data):
    """The ROM with VERSION_FIELDS zeroed (a field past the end of a short
    file is skipped: a mock ROM's identity is its plain sha256)."""
    out = bytearray(data)
    for _name, off, size in VERSION_FIELDS:
        end = min(off + size, len(out))
        if off < end:
            out[off:end] = bytes(end - off)
    return bytes(out)


def identity(data):
    return hashlib.sha256(identity_bytes(data)).hexdigest()


def _dbg_symbols(dbg_text, names):
    """{name: 24-bit value} for each label named, from a ca65 .dbg file; a
    name defined more than once (or not at all) is an error."""
    found = {}
    for line in dbg_text.splitlines():
        if not line.startswith("sym\t"):
            continue
        attrs = dict(kv.split("=", 1) for kv in line[4:].split(",") if "=" in kv)
        name = attrs.get("name", "").strip('"')
        if name not in names or attrs.get("type") != "lab" or "val" not in attrs:
            continue
        val = int(attrs["val"], 16)
        if name in found and found[name] != val:
            raise ValueError(f"{name} is defined twice in the .dbg")
        found[name] = val
    missing = [n for n in names if n not in found]
    if missing:
        raise ValueError(f"the .dbg defines no {', '.join(missing)}")
    return found


def stamp(data, version, dbg_text):
    """The ROM bytes with both fields written for `version`."""
    syms = _dbg_symbols(dbg_text, [VERSION_TEXT[0], HEADER_TITLE[0]])
    for name, off, _size in (VERSION_TEXT, HEADER_TITLE):
        if syms[name] & 0x3FFFFF != off:
            raise ValueError(f"{name} is at ${syms[name]:06X} in the .dbg; "
                             f"rom_version.py masks ${off:06X}.  Move it back "
                             f"or update VERSION_FIELDS (and re-cut nothing: "
                             f"a layout move is a ROM change anyway)")
    check_version(version)
    end = max(off + size for _name, off, size in VERSION_FIELDS)
    if len(data) < end:
        raise ValueError(f"the ROM is {len(data)} bytes, too short for the "
                         f"version fields (they end at ${end:06X})")
    out = bytearray(data)
    _, off, size = VERSION_TEXT
    out[off:off + size] = field_bytes(version)
    title = header_title(version)
    _, off, size = HEADER_TITLE
    if len(title) > size:
        raise ValueError(f"header title {title!r} is longer than {size}")
    out[off:off + size] = title + b" " * (size - len(title))
    if len(out) != len(data):
        raise ValueError("stamping changed the ROM's length")
    return bytes(out)


def read(data):
    """(menu text, header title) as strings."""
    _, dec = _codec()
    _, off, size = VERSION_TEXT
    raw = data[off:off + size]
    raw = raw[:raw.index(0)] if 0 in raw else raw
    text = "".join(dec.get(b, f"{{${b:02x}}}") for b in raw).strip(" ")
    _, off, size = HEADER_TITLE
    return text, data[off:off + size].decode("ascii", "replace").rstrip(" ")


def copy_if_identity_changed(src, dst):
    """cmp -s || cp, except that a ROM whose identity did not move keeps
    DST's old mtime (so ninja's restat sees no change) while DST still takes
    SRC's bytes."""
    new = Path(src).read_bytes()
    try:
        old = Path(dst).read_bytes()
        st = os.stat(dst)
    except FileNotFoundError:
        old, st = None, None
    if old == new:
        return
    os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
    same = old is not None and identity(old) == identity(new)
    tmp = dst + ".tmp"
    with open(tmp, "wb") as f:
        f.write(new)
    shutil.copymode(src, tmp)
    os.replace(tmp, dst)
    if same:
        os.utime(dst, ns=(st.st_atime_ns, st.st_mtime_ns))


def _fix_checksum(rom):
    """ff6/tools/fix_checksum.py's checksum, as link_rom.sh writes it."""
    sys.path.insert(0, str(ROOT / "ff6" / "tools"))
    import fix_checksum
    off = HEADER_CHECKSUM[1]
    out = bytearray(rom)
    out[off:off + 4] = (0xAAAA).to_bytes(2, "little") + (0x5555).to_bytes(2, "little")  # its dummy
    s = fix_checksum.mirror_sum(out)
    out[off:off + 4] = (s ^ 0xFFFF).to_bytes(2, "little") + s.to_bytes(2, "little")
    return bytes(out)


def selftest():
    import tempfile
    fails = []

    def check(what, cond):
        print(f"  {'ok' if cond else 'FAIL'}: {what}")
        if not cond:
            fails.append(what)

    dbg = ('sym\tid=1,name="Ot6VersionText",addrsize=absolute,scope=0,'
           'def=1,val=0xC0FFA0,seg=1,type=lab\n'
           'sym\tid=2,name="SnesHeader",addrsize=absolute,scope=0,'
           'def=2,val=0xC0FFC0,seg=2,type=lab\n')
    rom = bytes(b"\xa5" * 0x40000)

    def build(version):
        """As link_rom.sh does: stamp, then the checksum over the result."""
        return _fix_checksum(stamp(rom, version, dbg))

    a, b = build("0.23"), build("0.24")
    check("two versions build different bytes", a != b)
    check("...in the checksum too (so the mask must cover it)",
          a[0xFFDC:0xFFE0] != b[0xFFDC:0xFFE0])
    check("...with the same identity", identity(a) == identity(b))
    check("read decodes the menu text and title",
          read(a) == ("OT6 v0.23", "OT6 V0.23"))
    check("the field is the text centered in 15 cells, space-padded, then $00",
          a[0xFFA0:0xFFB0] == bytes([0xFF] * 3 + [0x8E, 0x93, 0xBA, 0xFF, 0xAF,
                                     0xB4, 0xC5, 0xB6, 0xB7] + [0xFF] * 3 + [0]))
    check("the title is space-padded ASCII",
          a[0xFFC0:0xFFD5] == b"OT6 V0.23" + b" " * 12)
    for v, text in (("0.24-rc1", "OT6 v0.24-rc1"), ("0.24.1", "OT6 v0.24.1"),
                    ("0.24-rc10", "OT6 v0.24-rc10"), ("10.24-rc10", "OT6 v10.24-rc10")):
        c = build(v)
        check(f"VERSION {v!r} builds: {read(c)[0]!r}, same identity",
              read(c)[0] == text and identity(c) == identity(a))
    outside = [0xFF9F, 0xFFB0, 0xFFD5, 0xFFDB, 0xFFE0, 0x0000, 0x3FFFF]
    for off in outside:
        m = bytearray(a)
        m[off] ^= 0x01
        check(f"a flip at ${off:06X} (outside the fields) moves the identity",
              identity(_fix_checksum(bytes(m))) != identity(a))
    for name, off, size in VERSION_FIELDS:
        m = bytearray(a)
        m[off + size - 1] ^= 0x01
        check(f"a flip in {name}'s last byte does not",
              identity(bytes(m)) == identity(a))
    check("a short file's identity is its plain sha256",
          identity(b"rom v1\n") == hashlib.sha256(b"rom v1\n").hexdigest())
    for v, code in (("0.24-rc1", 240001), ("0.24", 240099), ("0.24.1", 240199),
                    ("0.24.1-rc1", 240101), ("10.24-rc10", 10240010)):
        check(f"VERSION {v!r}: APK versionCode {code}", apk_version_code(v) == code)
    for bad, why in (("0.24-rc1000", "not the grammar"), ("", "empty"),
                     (" 0.23", "padded"), ("0.2@", "not the grammar"),
                     ("0.24.10-rc10", "wider than 15 cells"),
                     ("0.100", "minor over 99"), ("0.24-rc0", "rc 0")):
        try:
            stamp(rom, bad, dbg)
            check(f"VERSION {bad!r} refused ({why})", False)
        except ValueError:
            check(f"VERSION {bad!r} refused ({why})", True)
    try:
        stamp(rom, "0.23", dbg.replace("0xC0FFA0", "0xC0FF90"))
        check("a moved Ot6VersionText refused", False)
    except ValueError:
        check("a moved Ot6VersionText refused", True)
    try:
        stamp(rom[:0xFFD0], "0.23", dbg)
        check("a ROM too short for the fields refused, not grown", False)
    except ValueError:
        check("a ROM too short for the fields refused, not grown", True)
    with tempfile.TemporaryDirectory() as d:
        src, dst = os.path.join(d, "src.sfc"), os.path.join(d, "dst.sfc")
        Path(src).write_bytes(a)
        copy_if_identity_changed(src, dst)
        os.utime(dst, ns=(1_000_000_000, 1_000_000_000))
        Path(src).write_bytes(b)
        copy_if_identity_changed(src, dst)
        check("a version-only change: the copy takes the new bytes",
              Path(dst).read_bytes() == b)
        check("...and keeps its mtime", os.stat(dst).st_mtime_ns == 1_000_000_000)
        m = bytearray(b)
        m[0x1234] ^= 1
        Path(src).write_bytes(_fix_checksum(bytes(m)))
        copy_if_identity_changed(src, dst)
        check("any other change: the copy's mtime moves",
              os.stat(dst).st_mtime_ns != 1_000_000_000
              and Path(dst).read_bytes() == _fix_checksum(bytes(m)))
    print(f"rom_version selftest: {'FAIL' if fails else 'ok'}"
          f" ({len(fails)} failure(s))")
    return 1 if fails else 0


def main(argv):
    try:
        if len(argv) == 4 and argv[0] == "stamp":
            rom = Path(argv[1])
            out = stamp(rom.read_bytes(), argv[2], Path(argv[3]).read_text())
            rom.write_bytes(out)
            print(f"rom_version: stamped {read(out)[0]!r} / {read(out)[1]!r};"
                  f" identity {identity(out)}")
        elif len(argv) == 2 and argv[0] == "check":
            print(f"VERSION {argv[1]}: {check_version(argv[1])}, "
                  f"APK versionCode {apk_version_code(argv[1])}")
        elif len(argv) == 2 and argv[0] == "identity":
            print(identity(Path(argv[1]).read_bytes()))
        elif len(argv) == 2 and argv[0] == "read":
            text, title = read(Path(argv[1]).read_bytes())
            print(f"menu {text}\ntitle {title}")
        elif len(argv) == 3 and argv[0] == "copy-if-identity-changed":
            copy_if_identity_changed(argv[1], argv[2])
        elif argv == ["selftest"]:
            return selftest()
        else:
            print(__doc__.split("Usage:")[1], file=sys.stderr)
            return 2
    except (OSError, ValueError) as exc:
        print(f"rom_version: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
