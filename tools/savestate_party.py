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

import glob
import importlib.util
import json
import os
import zlib

GRAPH = "tools/tests/savestate_graph.py"
CHECKPOINTS = "tools/tests/checkpoints"

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


def declared_states(repo: str) -> set[str]:
    """The fixture names this tree's savestate graph still declares.

    Both audits glob `build/states/*.mss`, and that directory outlives the
    graph: renaming a state writes the new name and leaves the old .mss
    sitting there, because nothing ever deletes one.  On 2026-08-12
    build/states held 98 fixtures of which 19 were leftovers -- the whole
    `*_doorstep` -> `*_entry` rename (1e54ef8), plus mines_chase ->
    moogle_entry, narshe_escape_start -> narshe_streets, the dev_* scratch
    states and _scratch_vargas_p2.

    That is not tidiness.  One of those leftovers, kefka_doorstep, was a
    pre-rename copy of kefka_entry taken before gen_narshe_battle got its
    care stop (b31ca37), and it carried CELES dead at 0/217.  So the party-hp
    audit named a casualty that no generator produces, that no regeneration
    can clear, and that no edit to any generator can fix -- and it was worked
    as a live route bug.  An orphan cannot be repaired, only deleted, so the
    audits have to be able to tell one apart from a fixture.

    `tools/tests/savestate_graph.py` is the single list `make savestates`
    builds from, which makes it the answer to "is this file still a fixture".
    Reading it is milliseconds and needs no build.ninja and no emulator,
    which matters because `make test` runs both audits without either.

    Returns an empty set if the graph cannot be read at all; callers treat
    that as "cannot tell" and fall back to auditing every file, which is the
    behaviour from before this existed.
    """
    path = os.path.join(repo, GRAPH)
    try:
        spec = importlib.util.spec_from_file_location("savestate_graph", path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return {s["state"] for s in mod.STATES}
    except Exception:
        return set()


def split_orphans(files: list[str], declared: set[str]):
    """Partition globbed fixtures into (live, orphan stems).

    With an unreadable graph (`declared` empty) everything is live and
    nothing is an orphan, so a caller that cannot read the graph audits the
    whole directory exactly as it used to.
    """
    if not declared:
        return list(files), []
    live = [p for p in files if stem_of(p) in declared]
    orphans = sorted(stem_of(p) for p in files if stem_of(p) not in declared)
    return live, orphans


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


def find_char_block(raw: bytes, allow_fallback: bool = True) -> int | None:
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

    `allow_fallback` is the fixed-offset guess below, and it is a fact about
    Mesen's WRAM dump.  A 32 KiB SRAM checkpoint is long enough to reach that
    offset and would take the guess without meaning it, so read_party_sram
    passes False: a checkpoint either matches the signature or reports
    nothing.  Every checkpoint in the tree matches it at length 11, the
    least ambiguous the signature gets.
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
    if allow_fallback and len(raw) > FALLBACK_CB + REC * 16 + 0x300:
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
    return party_at(raw, cb), None


def party_at(raw: bytes, cb: int) -> list[dict]:
    """The party records, given the blob and where the table starts.

    Split out of read_party when the checkpoint reader arrived: the two
    differ only in how they get `raw` and `cb`, and the part worth having
    exactly one copy of is the record layout.
    """
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
    return out


def read_party_sram(path: str):
    """Everybody in the party inside a tracked SRAM checkpoint.

    The checkpoints under tools/tests/checkpoints/ are the OTHER thing a
    generator can boot from: five states cold-Continue out of one instead of
    resuming a predecessor's .mss, so a casualty in a checkpoint is inherited
    by every state below it exactly the way a casualty in a fixture is.  The
    fixture audit could not see them, because a checkpoint is a 32 KiB
    battery image and not a savestate, and that blind spot is where four of
    them were sitting: gate-cave-save-v1 with TERRA dead, and
    n024-entry-save-v1, narshe-mission-v1 and terra-returned-v1 each with
    EDGAR and SABIN dead.

    The save slot mirrors the $1600 character table record-for-record, so the
    same shape signature that locates it in a WRAM dump locates it here, and
    the same record layout reads it.  Cross-checked against an independent
    measurement: the table resolves at 0x1400 in every checkpoint in the
    tree, and the four records it reads out of n024-entry-save-v1 (LOCKE
    353/353 88/98, EDGAR 0/398 81/107, SABIN 0/407 78/104, CELES 349/349
    106/106) are the same four the emulator logged from live WRAM after
    booting it.

    Returns (records, None) or (None, reason).
    """
    try:
        raw = open(path, "rb").read()
    except OSError as e:
        return None, str(e)
    # No fixed-offset fallback here: see find_char_block.
    cb = find_char_block(raw, allow_fallback=False)
    if cb is None:
        return None, "character table not located (or ambiguous)"
    return party_at(raw, cb), None


def checkpoint_payloads(repo: str) -> list[tuple[str, str]]:
    """(checkpoint name, payload path) for every tracked SRAM checkpoint.

    Read off each manifest.json rather than globbing *.sram, so a directory
    whose manifest names a payload that is not there is skipped here and
    fails in sram_checkpoint.load, which is the code that owns that error.
    """
    out = []
    pattern = os.path.join(repo, CHECKPOINTS, "*", "manifest.json")
    for mf in sorted(glob.glob(pattern)):
        d = os.path.dirname(mf)
        try:
            with open(mf) as f:
                m = json.load(f)
        except (OSError, ValueError):
            continue
        payload = os.path.join(d, m.get("payload", ""))
        if os.path.isfile(payload):
            out.append((os.path.basename(d), payload))
    return out


def stem_of(path: str) -> str:
    base = os.path.basename(path)
    return base[:-4] if base.endswith(".mss") else base
