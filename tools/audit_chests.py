#!/usr/bin/env python3
"""Report the treasure the route walks past without opening.

Why this exists.  Owner, 2026-08-12: "human players love to open chests to
find out what's inside.  a typical run will open almost every chest you
see."  The route does not open any.  Measured 2026-08-12 across all 98
savestates in build/states and all 12 tracked SRAM checkpoints: every one of
the 512 treasure bits at $1E40 is clear, from power-on to the deepest link
in the chain.

That is not tidiness.  A Thunder Rod sits in a chest on map 70, one room
before the TunnelArmr fight that was losing all three attempts and blocking
the v0.10 release check, and eight more chests sit on map 75 in South Figaro,
including a Fenix Down and two Tonics.  A route that skips content reaches a
fight the designers expected it to reach armed, loses, and reports a balance
finding; this project has already spent days on three fights that turned out
to be under-preparation rather than tuning.

The two halves of the question come from different places.

WHAT CHESTS EXIST, AND WHERE.  `ff6/src/field/trigger/treasure_prop.dat`,
one 5-byte record per chest, blocked by map through the offsets in
`ff6/include/field/treasure_prop.inc`.  Layout, all confirmed in the game's
own reader `CheckTreasure` (`ff6/src/field/player.asm:719-810`):

    +$00 x tile           (`player.asm:766`, compared against $2A)
    +$01 y tile           (`player.asm:769`, compared against $2B)
    +$02 switch, 16-bit   (`player.asm:780`, `TreasureProp::Switch`)
    +$04 content          (`player.asm:778`, `TreasureProp::Content`)

    ITEM_SIZE = 5 (`treasure_prop.inc:9`), and the scan loop steps by five
    (`inx5`, `player.asm:773`).

The switch word carries both the flag and the kind.  Bits 0-8 are the index
into the treasure-bit array: `and #$01ff / lsr3` picks the byte and
`and #$0007` picks the bit (`player.asm:782-789`).  The kind is the high
nibble, tested in this order (`player.asm:797`, `:817`, `:830`, `:840`):
$8000 gil (content x 100), $4000 item, $2000 monster-in-a-box (content is an
event battle group), $1000 empty.  Ten records set NONE of the four; they
fall through to the same empty branch, because the `and #$10 / beq` at
`player.asm:840-842` branches to the instruction after it either way -- the
vendored disassembly's own comment there is "this has no effect".  So they
are empty chests and are counted as such.

The unit the game tracks is the BIT, not the record: 25 bit indices are
shared by two or three records, because the game keeps duplicate map copies
(South Figaro before and after the occupation, the two South Figaro cave
variants) and one flag has to close the chest in every copy.  Bit 19 is
shared by maps 70, 73 and 90 and the three copies hold DIFFERENT items --
Thunder Rod, Tincture, Hero Ring -- so opening it in one copy takes that
copy's item and empties the chest in the others.  Everything below counts
distinct bits and names every map a bit appears on.

WHICH MAPS THE ROUTE VISITS, AND WHAT IT OPENS.  "What it opens" is exact:
the treasure bits live at $1E40..$1E7F (`ff6/notes/field-ram.txt:1035`,
written only by `player.asm:795` and cleared only by `event.asm:5549`), which
is inside the $1600..$1FFF block the game copies into a save slot
(`CopyGameDataToSRAM`, `ff6/src/menu/save.asm:154d`), so the same offset
reads a .mss fixture and a tracked SRAM checkpoint.  `savestate_party.py`
locates $1600 in both.

"Which maps" is NOT exact, and the number below is a LOWER BOUND.  Two
mechanical sources are unioned:

  * every fixture's and checkpoint's own map id ($1F64).  Exact -- the party
    was standing there -- but it only sees the maps the route STOPS on.
  * every positive map equality in `tools/tests/gen_*.lua`
    (`H.assertEq(map(), N)`, `map() == N` and the `H.mapId()` spellings).
    In a green chain an assertion that ran and held is proof the route
    reached that map.

Neither sees a map crossed with no assertion and no fixture.  Map 72 is the
known case: gen_kolts walks the whole of it, but its map id reaches the
generator as the third argument of a file-local `crossTo(55, 32, 72, ...)`
helper, which no general pattern can safely read.  Its two chests are
therefore missing from the count.  The fix is not a cleverer grep -- it is a
map-change log written by the harness during generation and published beside
the savestate, which would make this half exact and self-maintaining; that
costs one full `make savestates` and is filed as a follow-up rather than
guessed at here.

WHAT THE CHECK IS.  `tools/chests_opened.txt` is a grow-only list of the
chests the route does open, one line per treasure bit, and the audit fails
unless the measured set matches it exactly.  It is the inverse of the
burn-down waiver lists in `audit_equipment.py` and `audit_party_hp.py`, and
deliberately so: those list defects, and a defect list here would be 94
identical lines saying "the route does not open chests", which is noise from
the day it lands and stays noise for weeks.  A list of wins is empty today,
costs nothing to read, and still fails in both directions -- a route that
stops opening a chest it used to open, and a route that opens a new one
without recording it.  A bare threshold was the other candidate and was
rejected because it cannot say WHICH chest changed.

The count of chests in scope is reported and deliberately not checked: it
moves whenever a generator gains or loses a map assertion, which has nothing
to do with treasure, and a check on it would fail for the wrong reason.

Four things fail when the check does not run, because an audit that finds no
opened chests and an audit that read nothing print the same green:

  1. the treasure table must parse to a positive number of records with
     consistent per-map bounds;
  2. at least one fixture or checkpoint must be read;
  3. every source read must show a non-empty EVENT-bit array at $1E80, the
     224 bytes immediately after the treasure bits.  A reader that landed
     on the wrong offset reports zero for both arrays; every state in this
     chain is past the intro and carries story switches (the emptiest in the
     tree has 284 bits set), so an all-zero event array means the read is
     wrong, not that the game is clean;
  4. no set treasure bit may fall outside the set of indices the table
     actually uses.  The table uses 259 of the 512, so a stray bit above
     that range is garbage rather than a chest.

`--selftest` drives the decoder against a synthetic save blob with a known
bit set, which is what fails if the reporting path is ever reduced to
printing zero.

Usage:  python3 tools/audit_chests.py [--dir build/states] [--selftest] [-v]
Exit 0 clean, 1 if the opened set disagrees with the record or a control
fails.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

# Explicit rather than relying on sys.path[0], which PYTHONSAFEPATH and
# `python3 -P` both switch off.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from savestate_party import (CHAR_BLOCK, biggest_stream, checkpoint_payloads,
                             declared_states, find_char_block, split_orphans,
                             stem_of)

RECORD = "tools/chests_opened.txt"
TREASURE_INC = "ff6/include/field/treasure_prop.inc"
TREASURE_DAT = "ff6/src/field/trigger/treasure_prop.dat"
ITEM_NAMES = "ff6/src/text/item_name_en.json"
MAP_PROP = "ff6/src/field/map_prop.dat"
MAP_TITLES = "ff6/src/text/map_title_en.json"
GENERATORS = "tools/tests/gen_*.lua"

REC_SIZE = 5                 # treasure_prop.inc:9; `inx5` at player.asm:773
TREASURE_BITS = 0x1E40       # field-ram.txt:1035, 64 bytes = 512 bits
EVENT_BITS = 0x1E80          # field-ram.txt:1037, $1E80..$1F5F
MAP_ID = 0x1F64              # live map index; H.mapId() reads the same word
MAP_PROP_SIZE = 33           # LoadMapProp copies 33 (field/map.asm:143-156)


def off(addr: int) -> int:
    """Offset of a WRAM address inside a blob whose $1600 sits at 0."""
    return addr - CHAR_BLOCK


# ---------------------------------------------------------- the chest table --

class Chest:
    """One treasure record, and the bit that says whether it is open."""

    def __init__(self, map_id: int, index: int, raw: bytes, names: list[str]):
        self.map = map_id
        self.index = index                      # record number in the file
        self.x, self.y = raw[0], raw[1]
        switch = raw[2] | (raw[3] << 8)
        self.bit = switch & 0x01FF               # player.asm:782-789
        self.content = raw[4]
        kind = switch >> 8
        if kind & 0x80:
            self.kind, self.what = "gil", f"{raw[4] * 100} gil"
        elif kind & 0x40:
            self.kind, self.what = "item", item_name(names, raw[4])
        elif kind & 0x20:
            self.kind, self.what = "monster", f"event battle group {raw[4]}"
        else:
            # $1000 and the ten records with no kind bit at all; player.asm:840
            self.kind, self.what = "empty", "(empty)"

    def where(self) -> str:
        return f"map {self.map:3d} ({self.x:2d},{self.y:2d})"


def item_name(names: list[str], item_id: int) -> str:
    """The name the player sees, without the leading item-type glyph.

    `item_name_en.json` prefixes every name with a `{...}` icon token; that
    token is the icon column the menu draws, not part of the name, and it is
    not a weapon category either (`docs/research/data-formats.md`).
    """
    if item_id >= len(names):
        return f"item ${item_id:02X}"
    return re.sub(r"^\{[^}]*\}", "", names[item_id]).strip()


def load_chests(repo: str) -> tuple[list[Chest], str | None]:
    """Every chest in the game, in table order, or ([], reason)."""
    try:
        inc = open(os.path.join(repo, TREASURE_INC)).read()
        data = open(os.path.join(repo, TREASURE_DAT), "rb").read()
        names = json.load(open(os.path.join(repo, ITEM_NAMES)))["text"]
    except (OSError, ValueError, KeyError) as e:
        return [], f"cannot read the treasure table: {e}"

    m = re.search(r"ARRAY_LENGTH = (\d+)", inc)
    if not m:
        return [], f"{TREASURE_INC} has no ARRAY_LENGTH"
    nmaps = int(m.group(1))
    starts = {int(a): int(b, 16) for a, b in
              re.findall(r"_(\d+) := TreasureProp \+ \$([0-9a-fA-F]+)", inc)}
    if len(starts) != nmaps:
        return [], (f"{TREASURE_INC} declares {nmaps} maps but carries "
                    f"{len(starts)} block offsets")

    bounds = [starts[i] for i in range(nmaps)] + [len(data)]
    out = []
    for map_id in range(nmaps):
        lo, hi = bounds[map_id], bounds[map_id + 1]
        if not (0 <= lo <= hi <= len(data)) or (hi - lo) % REC_SIZE:
            return [], (f"map {map_id}'s block is ${lo:04X}..${hi:04X}, which "
                        f"is not a whole number of {REC_SIZE}-byte records")
        for o in range(lo, hi, REC_SIZE):
            out.append(Chest(map_id, o // REC_SIZE,
                             data[o:o + REC_SIZE], names))
    return out, None


def map_titles(repo: str) -> dict[int, str]:
    """Map index -> the title the game prints, where it prints one.

    `ShowMapTitle` indexes `MapTitlePtrs` with $0520 (`field/text.asm:114`),
    which is map_prop byte +$00 (`LoadMapProp` copies 33 bytes from
    `MapProp + 33 * map` to $0520, `field/map.asm:143-156`).  Index 0 is the
    blank string, which most interiors use.
    """
    try:
        prop = open(os.path.join(repo, MAP_PROP), "rb").read()
        titles = json.load(open(os.path.join(repo, MAP_TITLES)))["text"]
    except (OSError, ValueError, KeyError):
        return {}
    out = {}
    for map_id in range(len(prop) // MAP_PROP_SIZE):
        idx = prop[map_id * MAP_PROP_SIZE]
        if idx < len(titles) and titles[idx].strip():
            out[map_id] = titles[idx].strip()
    return out


# ----------------------------------------------------------- what is opened --

def read_state(raw: bytes | None):
    """(opened bit set, event bits set, map id) out of one blob, or None.

    `raw` is a decompressed WRAM dump or a raw SRAM slot; both carry the
    $1600 block, so both are read the same way once it is located.
    """
    if raw is None:
        return None
    cb = find_char_block(raw, allow_fallback=len(raw) > 0x40000)
    if cb is None:
        return None
    treasure = raw[cb + off(TREASURE_BITS):cb + off(TREASURE_BITS) + 64]
    events = raw[cb + off(EVENT_BITS):cb + off(EVENT_BITS) + 224]
    if len(treasure) < 64 or len(events) < 224:
        return None
    opened = {i for i in range(512) if treasure[i >> 3] >> (i & 7) & 1}
    live = sum(bin(b).count("1") for b in events)
    map_id = int.from_bytes(raw[cb + off(MAP_ID):cb + off(MAP_ID) + 2],
                            "little") & 0x1FF
    return opened, live, map_id


# ----------------------------------------------------------- route coverage --

# Positive map equalities.  Every one of these is an assertion or an arrival
# predicate that HELD in a green chain, so each is proof the route reached
# that map.  Negative forms (`~=`) are not matched, and comments are stripped
# before matching so a map id named in prose does not count.
MAP_PATTERNS = [
    re.compile(r"H\.assertEq\(\s*map\(\)\s*,\s*(\d+)"),
    re.compile(r"H\.assertEq\(\s*H\.mapId\(\)\s*(?:&\s*0x1ff\s*)?,\s*(\d+)"),
    re.compile(r"\bmap\(\)\s*==\s*(\d+)"),
    re.compile(r"\bH\.mapId\(\)\s*(?:&\s*0x1ff\s*)?==\s*(\d+)"),
]


def maps_from_generators(repo: str) -> dict[int, set[str]]:
    out: dict[int, set[str]] = {}
    for path in sorted(glob.glob(os.path.join(repo, GENERATORS))):
        who = os.path.basename(path)
        try:
            src = open(path).read()
        except OSError:
            continue
        for line in src.splitlines():
            code = line.split("--")[0]
            for pat in MAP_PATTERNS:
                for m in pat.finditer(code):
                    out.setdefault(int(m.group(1)), set()).add(who)
    return out


# --------------------------------------------------------------- the record --

def load_record(repo: str) -> tuple[dict[int, str], str | None]:
    """bit -> description, from tools/chests_opened.txt.

    Two tab-separated columns, treasure bit / what it is.  `#` comments and
    blank lines ignored.  Missing file is an empty record, which is the
    correct reading of "the route opens nothing yet".
    """
    out = {}
    path = os.path.join(repo, RECORD)
    try:
        lines = open(path).read().splitlines()
    except OSError:
        return {}, None
    for n, line in enumerate(lines, 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = [p.strip() for p in line.split("\t") if p.strip()]
        if len(parts) < 2 or not parts[0].isdigit():
            return {}, (f"{RECORD}:{n} is not `bit<TAB>description`: "
                        f"{line!r}")
        out[int(parts[0])] = parts[1]
    return out, None


# ---------------------------------------------------------------- selftest --

def selftest(repo: str = ".") -> int:
    """Drive the decoder over data whose answer is known independently.

    Without this, a reader broken into always returning an empty set would
    print the same "0 opened" as the tree genuinely prints today, and the
    fixtures cannot tell the two apart because the real answer IS zero.
    """
    bad = []
    chests, err = load_chests(repo)
    if err:
        print(f"audit_chests selftest: {err}")
        return 1

    # The table itself, against three facts established elsewhere in the tree.
    if len(chests) != 286:
        bad.append(f"expected 286 treasure records, decoded {len(chests)}")
    by_map = {}
    for c in chests:
        by_map.setdefault(c.map, []).append(c)
    # docs/design/thamasa-route.md: five minor chests on map 343 only, and
    # "Fire Rod (4,52) and Ice Rod (45,7)" on map 351 -- a coordinate pair
    # that is not symmetric, so it fails if x and y are ever read the wrong
    # way round (`player.asm:766`, `:769`).
    if len(by_map.get(343, [])) != 5:
        bad.append(f"map 343 should carry 5 chests, decoded "
                   f"{len(by_map.get(343, []))}")
    rods = sorted((c.x, c.y, c.what) for c in by_map.get(351, []))
    if rods != [(4, 52, "Fire Rod"), (45, 7, "Ice Rod")]:
        bad.append("map 351 should be Fire Rod at (4,52) and Ice Rod at "
                   f"(45,7), decoded {rods}")
    # docs/design/bosses-wob.md:386: map 153, a monster-in-a-box whose
    # content is event battle group 34.
    m153 = [c for c in by_map.get(153, []) if c.kind == "monster"]
    if len(m153) != 1 or m153[0].content != 34:
        bad.append("map 153's monster-in-a-box should be event battle "
                   f"group 34, decoded {[(c.kind, c.content) for c in m153]}")
    # The motivating chest, named in the issue.
    m70 = by_map.get(70, [])
    if len(m70) != 1 or m70[0].what != "Thunder Rod":
        bad.append("map 70 should carry exactly the Thunder Rod, decoded "
                   f"{[c.what for c in m70]}")
    # The bit index is nine bits wide, not eight, and only three records in
    # the table prove it: an `and #$00ff` in place of the game's `and #$01ff`
    # (player.asm:784) would alias map 89's chest onto bit 0 and still decode
    # every other record correctly.
    ninebit = sorted((c.bit, c.map) for c in chests if c.bit >= 0x100)
    if ninebit != [(256, 89), (257, 378), (258, 207)]:
        bad.append("the three nine-bit treasure indices should be 256 on map "
                   f"89, 257 on 378 and 258 on 207, decoded {ninebit}")
    # The kind nibble, tallied.  Ten records set no kind bit at all and are
    # empty chests by fallthrough (player.asm:840-842); pinning the tally is
    # what fails if that reading is ever quietly changed.
    tally = {k: sum(1 for c in chests if c.kind == k)
             for k in ("item", "monster", "gil", "empty")}
    if tally != {"item": 258, "monster": 11, "gil": 7, "empty": 10}:
        bad.append(f"kind tally should be 258 item / 11 monster / 7 gil / "
                   f"10 empty, decoded {tally}")
    # Gil records hold hundreds, not units: `lda $1a / sta hWRMPYA /
    # lda #100 / sta hWRMPYB` (player.asm:800-803).  Map 30's is the biggest
    # in the game and the one a reader would notice.
    m30gil = [c.what for c in by_map.get(30, []) if c.kind == "gil"]
    if m30gil != ["5000 gil"]:
        bad.append("map 30's gil chest should read 5000 gil, decoded "
                   f"{m30gil}")

    # The reader, against a synthetic blob.  A save slot is $0A00 bytes of
    # $1600..$1FFF (save.asm:154d), so a blob of that length with $1600 at 0
    # is exactly what read_state has to cope with; the character-table shape
    # signature is what locates it, so records 0..10 carry actor ids whose
    # low nibble is the record index.
    #
    # The three offsets below are written as LITERALS, not through off(), so
    # that a wrong address constant fails here instead of agreeing with
    # itself: $1E40 - $1600 = $840, $1E80 - $1600 = $880, $1F64 - $1600 =
    # $964.
    blob = bytearray(0x0A00)
    for c in range(11):
        blob[37 * c] = c
    blob[0x964] = 75
    blob[0x880] = 0xFF                    # a state with story switches set
    want = m70[0].bit if m70 else 19
    blob[0x840 + (want >> 3)] |= 1 << (want & 7)
    got = read_state(bytes(blob))
    if got is None:
        bad.append("read_state could not locate $1600 in a synthetic slot")
    else:
        opened, live, map_id = got
        if opened != {want}:
            bad.append(f"a slot with only bit {want} set read back as "
                       f"{opened}")
        if live != 8:
            bad.append(f"event-bit control read {live} bits, expected 8")
        if map_id != 75:
            bad.append(f"map id read {map_id}, expected 75")
    # And the negative: an untouched slot must report nothing opened, or the
    # positive above proves only that the reader answers yes to everything.
    blob[0x840 + (want >> 3)] = 0
    got = read_state(bytes(blob))
    if got is None or got[0]:
        bad.append(f"a slot with no treasure bit set read back as {got}")

    for b in bad:
        print(f"  FAIL {b}")
    if bad:
        print(f"audit_chests selftest: {len(bad)} failure(s)")
        return 1
    print("audit_chests selftest: table and reader both hold")
    return 0


# -------------------------------------------------------------------- main --

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="build/states")
    ap.add_argument("--repo", default=".")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest(args.repo)

    chests, err = load_chests(args.repo)
    if err or not chests:
        print("audit_chests: "
              + (err or "the treasure table decoded to nothing"))
        return 1
    known_bits = {c.bit for c in chests}
    titles = map_titles(args.repo)

    # ---- what the route opens, read from every state we have -------------
    declared = declared_states(args.repo)
    files = sorted(glob.glob(os.path.join(args.dir, "*.mss")))
    files, orphans = split_orphans(files, declared)
    sources = [(stem_of(p), biggest_stream(p)) for p in files]
    sources += [(name, open(path, "rb").read())
                for name, path in checkpoint_payloads(args.repo)]

    opened: set[int] = set()
    fixture_maps: dict[int, set[str]] = {}
    unreadable, blind = [], []
    for name, raw in sources:
        got = read_state(raw)
        if got is None:
            unreadable.append(name)
            continue
        bits, live, map_id = got
        if live == 0:
            blind.append(name)
        opened |= bits
        fixture_maps.setdefault(map_id, set()).add(name)

    print(f"chest audit: {len(chests)} treasure records over "
          f"{len({c.map for c in chests})} maps, {len(known_bits)} distinct "
          f"chests; {len(sources) - len(unreadable)} state(s) read")
    if orphans:
        print(f"  ({len(orphans)} file(s) in {args.dir} that the graph no "
              f"longer declares, SKIPPED: " + ", ".join(orphans) + ")")

    # ---- control 2: something must have been read ------------------------
    if not sources or len(unreadable) == len(sources):
        print("  NOTHING READ -- no fixture under "
              f"{args.dir} and no tracked SRAM checkpoint could be decoded.\n"
              "  The checkpoints are tracked in git, so this is the reader "
              "broken, not an empty tree.")
        return 1
    for name in unreadable:
        print(f"  ?    {name}: character table not located")

    # ---- control 3: the read has to land on real save data ---------------
    if blind:
        print(f"\n{len(blind)} state(s) read an EMPTY event-bit array at "
              f"$1E80, which no state in this chain has:\n"
              "  the treasure bits sit 64 bytes before it, so this is a "
              "mislocated read reporting a clean tree.\n  "
              + ", ".join(sorted(blind)))
        return 1

    # ---- control 4: every set bit has to be a chest -----------------------
    stray = sorted(opened - known_bits)
    if stray:
        print(f"\n{len(stray)} treasure bit(s) set that no record in "
              f"{TREASURE_DAT} claims: " + ", ".join(str(b) for b in stray)
              + "\n  The table uses "
              f"{min(known_bits)}..{max(known_bits)}; a bit outside it is "
              "garbage, not a chest.")
        return 1

    # ---- the route's maps -------------------------------------------------
    gen_maps = maps_from_generators(args.repo)
    route = sorted(set(gen_maps) | set(fixture_maps))
    on_route = [c for c in chests if c.map in route]
    bits_on_route = {c.bit for c in on_route}
    opened_on_route = bits_on_route & opened

    print(f"  route reaches at least {len(route)} maps "
          f"({len(fixture_maps)} witnessed by a fixture or checkpoint, the "
          f"rest by a map assertion that held in a generator)")
    print(f"  {len(bits_on_route)} chests on those maps, "
          f"{len(opened_on_route)} opened, "
          f"{len(bits_on_route) - len(opened_on_route)} walked past")
    print("  (a LOWER bound: a map the route only crosses, with no fixture "
          "and no assertion, is invisible here --\n   map 72 and its two "
          "chests are the known case, see this file's header)")

    # ---- the record -------------------------------------------------------
    record, rerr = load_record(args.repo)
    if rerr:
        print(f"\n{rerr}")
        return 1

    # Group the unopened by map for the report.
    by_map: dict[int, list[Chest]] = {}
    for c in on_route:
        if c.bit not in opened:
            by_map.setdefault(c.map, []).append(c)
    if by_map:
        print(f"\nUnopened, by map ({sum(len(v) for v in by_map.values())} "
              f"records, {len(bits_on_route) - len(opened_on_route)} distinct "
              f"chests -- some maps are copies sharing one bit):")
        for map_id in sorted(by_map):
            who = (sorted(fixture_maps[map_id])[0] if map_id in fixture_maps
                   else sorted(gen_maps.get(map_id, ["?"]))[0])
            title = titles.get(map_id, "")
            print(f"  map {map_id:3d}{(' ' + title) if title else ''}"
                  f"  ({len(by_map[map_id])})  [{who}]")
            for c in sorted(by_map[map_id], key=lambda c: c.bit):
                print(f"      bit {c.bit:3d}  ({c.x:2d},{c.y:2d})  "
                      f"{c.kind:7s} {c.what}")
    if args.verbose:
        print("\nEvery map the route is known to reach:")
        for map_id in route:
            src = ("fixture " + ", ".join(sorted(fixture_maps[map_id]))
                   if map_id in fixture_maps
                   else ", ".join(sorted(gen_maps.get(map_id, []))))
            n = len({c.bit for c in chests if c.map == map_id})
            print(f"  map {map_id:3d}  {n} chest(s)  {src}")

    # ---- the verdict ------------------------------------------------------
    missing = sorted(set(record) - opened)      # recorded, no longer opened
    extra = sorted(opened - set(record))        # opened, not recorded
    if missing:
        print(f"\n{len(missing)} chest(s) in {RECORD} that the chain no "
              f"longer opens -- the route lost them:")
        for b in missing:
            print(f"  bit {b}: {record[b]}")
    if extra:
        text = {c.bit: c for c in chests}
        print(f"\n{len(extra)} chest(s) the chain opens that {RECORD} does "
              f"not list.  The list only grows; add:")
        for b in extra:
            c = text[b]
            print(f"  {b}\t{c.where()} {c.what}")
    if missing or extra:
        return 1

    if not opened:
        print(f"\nThe route opens NO chests at all -- {len(bits_on_route)} "
              f"walked past and none taken.  That is the recorded state "
              f"({RECORD} is empty),\nso this is not a failure yet; it is "
              f"the measurement issue #84 exists to hold still while the "
              f"route work lands.")
    else:
        print(f"\n  OK -- the chain opens exactly the {len(opened)} chest(s) "
              f"{RECORD} records")
    return 0


if __name__ == "__main__":
    sys.exit(main())
