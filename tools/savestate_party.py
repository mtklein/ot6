#!/usr/bin/env python3
"""Read the party out of a Mesen savestate, with no emulator.

Shared by tools/audit_equipment.py and tools/audit_party_hp.py.  It started
inside audit_equipment.py; the second reader of the same table is what moved
it here, because the part that is easy to get wrong is locating the character
block, and two copies of that would drift.

A .mss is a short header then zlib streams; the biggest one carries WRAM.
The character table ($1600, 16 records of 37 bytes) is located by its own
shape rather than by a hardcoded offset, which would break the first time
Mesen changed its state layout.  Then, per record (offsets confirmed in
`ff6/notes/field-ram.txt:885-923` and again in code, tabulated in
`docs/research/field-care-menu.md` section 4):

    +$00 actor index      +$08 level          +$09 current HP (word)
    +$0B boost|max HP     +$0D current MP     +$0F boost|max MP
    +$14 status 1         +$15 status 4       +$1F..+$23 equipment

Party membership is $1850 + c, low three bits (the party number, 0 = not in
one); bit $40 is the enabled flag and bits 3-4 the battle order.  The
currently active party number is $1A6D.

Reading the whole tree costs about a second, against a `make savestates`
measured in hours, which is what makes the audits cheap enough to be
unconditional in `make test`.
"""

from __future__ import annotations

import os
import zlib

CHAR_BLOCK = 0x1600          # WRAM address of the character table
PARTY = 0x1850               # WRAM address of the party/order bytes
CUR_PARTY = 0x1A6D           # WRAM address of the active party number
REC = 37                     # bytes per character record
WEAPON = 0x1F                # offset of the equipped weapon within a record
EMPTY = 0xFF
# Where the shape-signature resolves to in every fixture that has one.  Used
# only as a cross-checked fallback for the early fixtures that do not.
FALLBACK_CB = 0x1844

# Status 1 is `weicmpzd` (field-ram.txt:901-909): wound, petrify, imp, clear,
# magitek, poison, zombie, dark.
ST1_WOUND = 0x80
ST1_PETRIFY = 0x40
ST1_ZOMBIE = 0x02
# The mask the game itself applies when it asks whether a character can be
# healed (CheckCanUseItem, `item.asm:2249-2258`) or picked for Skills
# (CheckSkillValid, `field_menu.asm:722-731`).
ST1_OUT = ST1_WOUND | ST1_PETRIFY | ST1_ZOMBIE

NAMES = {0: "TERRA", 1: "LOCKE", 2: "CYAN", 3: "SHADOW", 4: "EDGAR",
         5: "SABIN", 6: "CELES", 7: "STRAGO", 8: "RELM", 9: "SETZER",
         10: "MOG", 11: "GAU", 12: "GOGO", 13: "UMARO"}


def load_waivers(repo: str, path: str) -> dict[tuple[str, str], str]:
    """(fixture, character) pairs where the story is what put them there.

    A burn-down list, like the state-write list: a line that matches nothing
    is an error, so a fixture that gets fixed upstream cannot keep a stale
    exemption.  Format is three tab-separated columns, fixture / CHARACTER /
    reason; `#` comments and blank lines are ignored.
    """
    out = {}
    try:
        for line in open(os.path.join(repo, path)):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 3:
                continue
            out[(parts[0].strip(), parts[1].strip())] = parts[2].strip()
    except OSError:
        pass
    return out


def calc_max(word: int, cap: int) -> int:
    """Unpack a `bbnnnnnn nnnnnnnn` max-HP/MP word the way the menu does.

    CalcMaxHPMP (`menu_common.asm:2377-2400`) is a four-entry jump table whose
    arms fall through each other, so the percentages are not in table order:
    code 1 is +25%, code 2 is +50%, code 3 is +12.5%.  ValidateMaxHP clamps
    to 9999 and ValidateMaxMP to 999 (`menu_common.asm:2424-2447`).

    Every World of Balance record dumped so far reads a bare base with no
    boost bits set (measured across all 98 fixtures in the tree, 2026-08-11),
    so this is latent today; it is here so the first boosted fixture does not
    silently report a max that the menu never draws.
    """
    base, code = word & 0x3FFF, word >> 14
    add = (0, base // 4, base // 2, base // 8)[code]
    return min(base + add, cap)


def biggest_stream(path: str) -> bytes | None:
    """The decompressed zlib stream that carries WRAM."""
    data = open(path, "rb").read()
    best, i = None, 0
    while True:
        i = data.find(b"\x78\x01", i)
        if i < 0:
            break
        try:
            out = zlib.decompressobj().decompress(data[i:])
            if best is None or len(out) > len(best):
                best = out
        except zlib.error:
            pass
        i += 2
    return best


def find_char_block(raw: bytes) -> int | None:
    """Offset of $1600 inside the blob, located by the table's own shape.

    Records 0..10 carry actor ids whose low nibble is the record index; the
    high nibble is join state (a fixture mid-chain reads 00 01 12 13 04 15
    ..., which is why an equality test on the whole byte finds nothing).

    The run length varies: the earliest fixtures (power-on, the first
    battle, Arvis's house) have not filled the whole table yet, so an
    eleven-record signature finds nothing there.  Try the longest run first,
    since it is the least ambiguous, and shorten it only until one candidate
    survives.  Stop at six: below that the signature starts matching
    ordinary counting data elsewhere in WRAM, and a wrong offset would
    report wrong results, which is worse than reporting nothing.
    """
    for n in range(11, 7, -1):
        hits = [b for b in range(0, len(raw) - REC * n)
                if all((raw[b + REC * c] & 0x0F) == c for c in range(n))]
        if len(hits) == 1:
            return hits[0]
    # Early fixtures have no such run: at power-on only TERRA exists and
    # the rest of the table is $FF, so there is no sequence to match.  The
    # dump is a fixed 348964 bytes with a fixed layout, so fall back to the
    # offset the signature resolves to everywhere it does work, and check
    # it here rather than trusting it: record 0 must be actor 0, and
    # somebody must be in the party.
    if len(raw) > FALLBACK_CB + REC * 16 + 0x300:
        cb = FALLBACK_CB
        party = cb + (PARTY - CHAR_BLOCK)
        if raw[cb] == 0 and any(raw[party + c] & 0x07 for c in range(16)):
            return cb
    return None


def read_party(path: str):
    """Everybody assigned to a party in one fixture, or (None, reason).

    "Assigned to a party" is `$1850 + c` low three bits nonzero, which during
    the three-scenario split is true of all three parties at once, not only
    the one the player is steering.  That is deliberate in both audits: a
    character the story will hand back to the player in ten minutes is
    shipping in this fixture just as much as the one on screen.  `active`
    says which of them the player is holding right now ($1A6D).
    """
    raw = biggest_stream(path)
    if raw is None:
        return None, "no zlib stream"
    cb = find_char_block(raw)
    if cb is None:
        return None, "character table not located (or ambiguous)"
    party_off = cb + (PARTY - CHAR_BLOCK)
    cur = raw[cb + (CUR_PARTY - CHAR_BLOCK)]
    out = []
    for c in range(16):
        pb = raw[party_off + c]
        if not pb & 0x07:
            continue
        rec = cb + REC * c
        word = lambda o: int.from_bytes(raw[rec + o:rec + o + 2], "little")
        out.append({
            "char": c,
            "name": NAMES.get(c, f"#{c}"),
            "level": raw[rec + 8],
            "hp": word(9),
            "maxhp": calc_max(word(11), 9999),
            "mp": word(13),
            "maxmp": calc_max(word(15), 999),
            "status1": raw[rec + 20],
            "status4": raw[rec + 21],
            "party": pb & 0x07,
            "active": (pb & 0x07) == (cur & 0x07),
            "weapon": raw[rec + WEAPON],
            "gear": list(raw[rec + WEAPON:rec + WEAPON + 5]),
        })
    return out, None


def stem_of(path: str) -> str:
    base = os.path.basename(path)
    return base[:-4] if base.endswith(".mss") else base
