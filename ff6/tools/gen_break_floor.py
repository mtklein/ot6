#!/usr/bin/env python3
# ------------------------------------------------------------------------------
# gen_break_floor.py -- OT6 "break floor" species -> weapon-class classifier
#
# Phase 1 of the break-floor feature. Un-authored ("formula")
# monsters currently get NO breakable weapon-class weakness. This tool reads
# the monster name list and assigns every species one *reachable* physical
# class, emitting a build-time data table (OT6_FLOOR_CLASS) plus a
# human-reviewable dump so the palette can be eyeballed and tuned.
#
# The asm table is DATA ONLY in this phase -- nothing references it yet.
# The @formula wiring at Ot6SeedShields is Phase 2.
#
# Classification is keyword-driven over the (case-insensitive) monster name.
# Names are the primary signal (see monster_name_en.json). Rules live in
# CLASS_RULES below so the palette is easy to edit -- change data, not code.
#
# Six classes (v0.51, #566): the keyword families still sort a body into one
# of three PARENTS (pierce: armor, carapace, dragons; bludgeon: brutes, rock,
# ooze, bone; slash: beasts and the default), and FLOOR_CHILDREN below deals
# the parent to one class; a species whose Ot6ShieldTbl row names a class
# takes that row's lowest class bit instead.  The generator stands on its
# own: it reads the monster names, ot6_class.asm's class names and
# Ot6ShieldTbl's rows, nothing else (the migration read the bytes from
# six_class_split.json, which nothing opens any more).
#
#   python3 ff6/tools/gen_break_floor.py            write the .inc and the review
#   python3 ff6/tools/gen_break_floor.py --check    exit 1 if either file on disk
#                                                   is not what this would write
#
# stdlib only (plus tools/ot6_class.py, this repository's reader of the class
# names).
# ------------------------------------------------------------------------------

import json
import os
import re
import sys

# ------------------------------------------------------------------------------
# class bit constants -- must mirror ff6/src/battle/ot6_class.asm:10-14
OT6_SLASH = 0x01   # swords, katanas, claws
OT6_PIERCE = 0x02  # spears, daggers, thrown edges, bolts, darts
OT6_BLUDG = 0x04   # fists, staves, rods, flails, boomerangs

CLASS_NAME = {OT6_SLASH: "SLASH", OT6_PIERCE: "PIERCE", OT6_BLUDG: "BLUDGEON"}

# ------------------------------------------------------------------------------
# The floor byte (six classes).  The three constants above are the keyword
# rule's PARENTS, v0.50's classes; they are no longer class bits of the ROM.
#
#   1. A species with an Ot6ShieldTbl row that names a class takes THE ROW'S
#      LOWEST CLASS BIT.  The game never reads that byte (Ot6SeedShields takes
#      the row), but a floor byte is then always a key its own row holds: the
#      floor follows a re-split by construction, and battle_breakwor_gau's
#      "the floor's class is a class of the row" holds for every species.  The
#      rows are read through tools/ot6_class.py.
#   2. Every other species -- no row, or a row with no class (the shields-only
#      rows and the 0-shield markers) -- takes THE CHILD RULE: each parent's
#      children are the classes its own weapons went to when the six were
#      grouped (tools/proto_six/classes.py CHILDREN: slash's swords and
#      katanas; pierce's daggers, spears and bolts; bludgeon's fists and rods,
#      and the returning arcs that went to Ranged), and every family of a
#      parent deals its species to the parent's children IN TURN, in
#      species-id order: a species takes whichever child of its parent the
#      fewest species hold so far, the first-named child on a tie.
#
# The dealing runs over every species id, rowed or not, from nothing (Ranged
# is a child of two parents and has one tally), and rule 1 then replaces the
# rowed ones: so the byte of a species with no row depends on the monster
# names alone, and does not move when a row is authored or re-split.  A
# parent's bodies spread evenly over the weapon families that inherited it,
# with no keyword deciding which (a name says "armor", not "dagger, spear or
# bolt").  The children are named by their source tokens; main() refuses a
# token ot6_class.asm does not define.
FLOOR_CHILDREN = {
    OT6_SLASH:  ("OT6_SWORD", "OT6_KATANA"),
    OT6_PIERCE: ("OT6_DAGGER", "OT6_SPEAR", "OT6_RANGED"),
    OT6_BLUDG:  ("OT6_BLUNT", "OT6_RANGED"),
}

# ------------------------------------------------------------------------------
# Keyword palette (designer-authored). Each bucket is a list of lowercase
# substrings tested against the lowercased monster name.
#
# PRECEDENCE, high -> low: PIERCE, then BLUDGEON, then SLASH, then DEFAULT.
# When a name hits keywords in more than one bucket, the higher-precedence
# bucket wins. Rationale: armor is the "can't just cut it" case (pierce
# between the scales), so armored/mechanical wins over brute and over beast;
# brute/ooze/skeletal (bludgeon) wins over soft beast (slash). Anything that
# matches nothing defaults to SLASH -- humanoids, casters, ghosts, spirits.
#
# Because the keyworded families pull large armored/imperial/dragon and
# brute/ooze sets out of the default, the distribution is non-flat by
# construction (that's the point: a reachable-but-varied floor).
#
# The buckets are stored in precedence order so the first bucket that matches
# wins. To retune the palette, edit only the keyword lists below.
# ------------------------------------------------------------------------------
CLASS_RULES = [
    # (class byte, [keyword substrings])  -- listed high-precedence first
    (OT6_PIERCE, [
        # armored / mechanical / imperial ranks (a point finds the seam)
        "guard", "soldier", "trooper", "cadet", "officer", "leader",
        "templar", "rider", "armor", "armr", "iron", "steel", "knight",
        "chaser", "proto", "m-tek", "mtek", "tek", "machine", "commander",
        "commando", "marshal", "general", "veteran", "prussian", "covert",
        "forces", "1st class", "retainer", "dueller", "telstar", "hitman",
        "laser", "missile", "colossus", "guardian", "air force",
        # carapace / shelled / insects (chitin -> pierce)
        "crab", "beetle", "mantis", "mantodea", "insecare", "scorpion",
        "snail", "shell", "carapace", "hornet", "hoppr", "delta", "gilo",
        "chiton", "nautilo", "trilob", "exocite",
        # dragons + dinosaurs (between the scales)
        "dragon", "drgn", "wyrm", "wyvern", "drake", "tyrano", "brach",
        "saur", "ptero", "fossil", "ceritops", "nastidon", "dino",
    ]),
    (OT6_BLUDG, [
        # brutes / giants / monks (mass with no seam -> you crush it)
        "ogre", "ogor", "orog", "troll", "giant", "gigas", "gigant",
        "brawler", "gorilla", "slamdancer", "umaro", "pug", "monk",
        # golem / rock
        "golem", "stone", "rock", "boulder", "adaman", "coelecite",
        "primordite", "steroidite",
        # oozes
        "slime", "ooze", "blob", "pudding", "jelly", "amoeba", "flan",
        "aspik", "slurm", "vaporite",
        # skeletal / undead bodies
        "skeleton", "bone", "mummy", "zombie", "karkass", "lich",
    ]),
    (OT6_SLASH, [
        # beasts / reptiles / birds / fish / plants
        "wolf", "bear", "dog", "hound", "cat", "lion", "tiger",
        "rat", "mouse", "bird", "hawk", "eagle", "crow", "harpy",
        "snake", "serpent", "naga", "eel", "anguiform", "lizard",
        "gecko", "newt", "bat", "fish", "piranha", "shark", "boar",
        "rhino", "leaf", "vine", "flower", "cactus", "plant", "fungus",
        "spider", "worm",
    ]),
]

DEFAULT_CLASS = OT6_SLASH  # unmatched -> slash (humanoids, casters, spirits)

# Exact-name overrides (case-insensitive), HIGHEST precedence -- for names a
# keyword mis-catches. Keep this list tiny and only for genuine collisions.
OVERRIDES = {
    "iron fist": OT6_BLUDG,   # a monk, not armor -- "iron" would say pierce
    "mandrake":  OT6_SLASH,   # a plant, not a dragon -- "drake" would say pierce
}

# codex width: OT6_CODEX is 384 species wide (ot6.asm:132 "cpx #$0300").
# The floor table must match that width and species-id indexing.
CODEX_WIDTH = 384


def classify(name):
    """Return (class_byte, rule_label) for a monster name.

    rule_label names the matched keyword (or the default fallback) for the
    review dump. Precedence is the order of CLASS_RULES (pierce, bludg, slash).
    """
    low = name.lower()
    if low in OVERRIDES:
        cls = OVERRIDES[low]
        return cls, f"{CLASS_NAME[cls]}:override"
    for class_byte, keywords in CLASS_RULES:
        for kw in keywords:
            if kw in low:
                return class_byte, f"{CLASS_NAME[class_byte]}:{kw}"
    label = "DEFAULT(empty)" if name == "" else "DEFAULT"
    return DEFAULT_CLASS, label


def origin_of(label, sid, authored):
    """Bucket a row for review: AUTHORED / explicit / inferred / defaulted.

    AUTHORED means the species has an Ot6ShieldTbl row: Ot6SeedShields scans
    the authored table first (ot6_break.asm @scan) and only falls through to
    OT6_FLOOR_CLASS on a miss, so this species' floor byte is unreachable in
    the shipped game. It is still emitted (the table is species-indexed and
    must stay codex-wide) but it is NOT part of the floor's review surface.

    Of the floor-live rows:
      explicit  -- an OVERRIDES exact-name hit (a human wrote this one down)
      inferred  -- a keyword substring matched (nobody looked at this body;
                   the keyword may have fired on the wrong species, e.g.
                   'rhino' catching a machine)
      defaulted -- nothing matched; the slash fallback
    """
    if sid in authored:
        return "AUTHORED"
    if label.startswith("DEFAULT"):
        return "defaulted"
    if label.endswith(":override"):
        return "explicit"
    return "inferred"


def load_authored_species(hud_asm_path):
    """Species ids carrying an Ot6ShieldTbl row (4-byte records, $ffff-term).

    Same table check_boss_rows.py parses; only the ids are needed here.
    A missing table is a loud failure, not an empty set -- the review's
    headline counts would silently revert to counting authored species.
    """
    with open(hud_asm_path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    it = iter(enumerate(lines))
    for _i, line in it:
        if line.strip().startswith("Ot6ShieldTbl:"):
            break
    else:
        raise SystemExit(f"gen_break_floor: no Ot6ShieldTbl: in {hud_asm_path}")
    authored = set()
    for _i, line in it:
        code = line.split(";", 1)[0]
        m = re.match(r"\s*\.word\s+\$([0-9a-fA-F]{4})\s*$", code)
        if m:
            v = int(m.group(1), 16)
            if v == 0xFFFF:
                break
            authored.add(v)
    if not authored:
        raise SystemExit(f"gen_break_floor: Ot6ShieldTbl parsed empty from {hud_asm_path}")
    return authored


def load_names(json_path):
    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data["text"]


def build_rows(names):
    """Return list of (species_id, name, class_byte, rule_label), width CODEX_WIDTH.

    If the name list is shorter than the codex, the tail is padded with the
    safe default class. If longer, we still only emit CODEX_WIDTH rows (the
    table is indexed by species id and must match codex width exactly).
    """
    rows = []
    for sid in range(CODEX_WIDTH):
        if sid < len(names):
            name = names[sid]
            cls, label = classify(name)
        else:
            name = ""
            cls, label = DEFAULT_CLASS, "DEFAULT(pad)"
        rows.append((sid, name, cls, label))
    return rows


def floor_children(rows):
    """[child token] per row of build_rows(): the child rule (rule 2), dealt
    over every species id."""
    tally = {t: 0 for kids in FLOOR_CHILDREN.values() for t in kids}
    out = []
    for _sid, _name, parent, _label in rows:
        kids = FLOOR_CHILDREN[parent]
        child = min(kids, key=lambda t: (tally[t], kids.index(t)))
        tally[child] += 1
        out.append(child)
    return out


def source_classes(repo_root):
    """(ot6_class.asm's classes, {species: (shields, class byte)} of
    Ot6ShieldTbl, first row a species), through tools/ot6_class.py; every
    child token must be a class the source defines, and every class dealt."""
    sys.path.insert(0, os.path.join(repo_root, "tools"))
    import ot6_class
    C = ot6_class.read(repo_root)
    used = {t for pair in FLOOR_CHILDREN.values() for t in pair}
    missing = sorted(used - set(C.token))
    if missing:
        raise SystemExit("gen_break_floor: ot6_class.asm defines no " + ", ".join(missing))
    if used != set(C.token):
        raise SystemExit("gen_break_floor: the floor never deals " + ", ".join(sorted(set(C.token) - used))
                         + ": a class of ot6_class.asm with no parent in FLOOR_CHILDREN")
    with open(os.path.join(repo_root, ot6_class.HUD_ASM), encoding="utf-8") as f:
        table = ot6_class.shield_rows(f.read(), C)
    if not table:
        raise SystemExit("gen_break_floor: Ot6ShieldTbl parsed empty")
    shield = {}
    for sp, sh, mask, _line, _comment in table:
        shield.setdefault(sp, (sh, mask))
    return C, shield


def floor_bytes(rows, C, shield):
    """[(token, how)] per species: the row's lowest class bit where its row
    names a class (rule 1), else the dealt child (rule 2)."""
    token_of = {v: n for n, v in C.token.items()}
    out = []
    for (sid, _name, parent, _label), dealt in zip(rows, floor_children(rows)):
        mask = shield.get(sid, (0, 0))[1] & C.mask
        if mask:
            out.append((token_of[mask & -mask], "row"))
        else:
            out.append((dealt, CLASS_NAME[parent]))
    return out


def inc_text(rows, floor):
    lines = []
    lines.append("; ----------------------------------------------------------------------------")
    lines.append("; OT6 break-floor class table -- GENERATED by tools/gen_break_floor.py")
    lines.append("; DO NOT EDIT BY HAND. Re-run the generator to regenerate.")
    lines.append(";")
    lines.append("; One class byte per species, directly indexed by species id (0..383),")
    lines.append("; matching OT6_CODEX width. Ot6SeedShields' @formula reads it for a species")
    lines.append("; with no Ot6ShieldTbl row.  `row`: the lowest class bit of the species' own")
    lines.append("; row; SLASH / PIERCE / BLUDGEON: the keyword parent, dealt to a child class.")
    lines.append("; ----------------------------------------------------------------------------")
    lines.append("")
    lines.append("OT6_FLOOR_CLASS:")
    for (sid, name, _cls, _label), (six, how) in zip(rows, floor):
        shown = name if name != "" else "(unused)"
        lines.append(
            f"        .byte   {six:<12}; {sid:>3} {shown} -> {how} -> {six[4:]}"
        )
    lines.append("")
    lines.append(f"        ; {CODEX_WIDTH} bytes total (codex width)")
    lines.append("")
    return "\n".join(lines)


def review_text(rows, authored):
    """The review dump. REVIEW ONLY -- never feeds back into the .inc.

    Headline counts cover FLOOR-LIVE species only: a species with an
    Ot6ShieldTbl row never reaches @formula (ot6_break.asm scans the authored
    table first), so counting it here misstates the floor. Authored species
    are listed as AUTHORED in the full table and excluded everywhere else.

    The review surface is three-way: explicit / inferred / defaulted.
    Inferred is not the same as reviewed: a keyword substring can fire on
    the wrong body (e.g. 'rhino' matching Rhinox, which has no weakness to
    that element).
    """
    counts = {OT6_PIERCE: 0, OT6_SLASH: 0, OT6_BLUDG: 0}      # floor-live only
    origins = {"explicit": [], "inferred": [], "defaulted": []}
    n_authored = 0
    for sid, name, cls, label in rows:
        o = origin_of(label, sid, authored)
        if o == "AUTHORED":
            n_authored += 1
            continue
        counts[cls] += 1
        origins[o].append((sid, name, cls, label))

    live = sum(counts.values())
    lines = []
    lines.append("OT6 BREAK-FLOOR CLASSIFIER -- REVIEW DUMP")
    lines.append("GENERATED by tools/gen_break_floor.py -- do not edit by hand.")
    lines.append("")
    lines.append("SUMMARY COUNTS (floor-live species only)")
    lines.append(f"  total species          : {len(rows)}")
    lines.append(f"  AUTHORED (Ot6ShieldTbl): {n_authored}  <- never reach the floor; excluded below")
    lines.append(f"  floor-live             : {live}")
    lines.append(f"  PIERCE   ($02)  : {counts[OT6_PIERCE]}")
    lines.append(f"  SLASH    ($01)  : {counts[OT6_SLASH]}")
    lines.append(f"  BLUDGEON ($04)  : {counts[OT6_BLUDG]}")
    lines.append(f"  by origin: explicit {len(origins['explicit'])} / "
                 f"inferred {len(origins['inferred'])} / "
                 f"defaulted {len(origins['defaulted'])}")
    lines.append("")
    lines.append("PRECEDENCE: PIERCE > BLUDGEON > SLASH > DEFAULT(->SLASH)")
    lines.append("ORIGIN: AUTHORED = has an Ot6ShieldTbl row (floor byte unreachable);")
    lines.append("        explicit = OVERRIDES exact-name hit; inferred = keyword substring;")
    lines.append("        defaulted = nothing matched, slash fallback.")
    lines.append("")
    lines.append("FULL ASSIGNMENT TABLE")
    lines.append(f"{'id':>3} | {'name':<12} | {'class':<8} | {'origin':<9} | rule_matched")
    lines.append("-" * 66)
    for sid, name, cls, label in rows:
        shown = name if name != "" else "(unused)"
        o = origin_of(label, sid, authored)
        lines.append(f"{sid:>3} | {shown:<12} | {CLASS_NAME[cls]:<8} | {o:<9} | {label}")
    lines.append("")
    lines.append("REVIEW SURFACE -- floor-live rows nobody has looked at, worst first.")
    lines.append("")
    lines.append("DEFAULTED (nothing matched; the slash fallback)")
    lines.append(f"count: {len(origins['defaulted'])}")
    lines.append("-" * 66)
    for sid, name, _cls, label in origins["defaulted"]:
        shown = name if name != "" else "(unused/empty)"
        lines.append(f"{sid:>3} | {shown:<14} | {label}")
    lines.append("")
    lines.append("INFERRED (a keyword matched -- which is not the same as reviewed;")
    lines.append("a substring can fire on the wrong body, e.g. 'rhino' on a machine)")
    lines.append(f"count: {len(origins['inferred'])}")
    lines.append("-" * 66)
    for sid, name, cls, label in origins["inferred"]:
        shown = name if name != "" else "(unused/empty)"
        lines.append(f"{sid:>3} | {shown:<14} | {CLASS_NAME[cls]:<8} | {label}")
    lines.append("")
    lines.append("EXPLICIT (OVERRIDES exact-name entries -- floor-live ones only)")
    lines.append(f"count: {len(origins['explicit'])}")
    lines.append("-" * 66)
    for sid, name, cls, label in origins["explicit"]:
        shown = name if name != "" else "(unused/empty)"
        lines.append(f"{sid:>3} | {shown:<14} | {CLASS_NAME[cls]:<8} | {label}")
    lines.append("")
    return "\n".join(lines), counts, origins, n_authored


def main():
    tools_dir = os.path.dirname(os.path.abspath(__file__))
    ff6_dir = os.path.dirname(tools_dir)

    json_path = os.path.join(ff6_dir, "src", "text", "monster_name_en.json")
    inc_path = os.path.join(ff6_dir, "src", "battle", "ot6_break_floor.inc")
    hud_path = os.path.join(ff6_dir, "src", "battle", "ot6_hud.asm")
    review_path = os.path.join(tools_dir, "break_floor_review.txt")

    names = load_names(json_path)
    if len(names) != CODEX_WIDTH:
        print(f"NOTE: name list has {len(names)} entries, codex width is "
              f"{CODEX_WIDTH}; tail handled by padding/truncation.")

    rows = build_rows(names)
    C, shield = source_classes(os.path.dirname(ff6_dir))
    floor = floor_bytes(rows, C, shield)
    inc = inc_text(rows, floor)
    authored = load_authored_species(hud_path)
    review, counts, origins, n_authored = review_text(rows, authored)

    if "--check" in sys.argv[1:]:
        stale = []
        for path, want in ((inc_path, inc), (review_path, review)):
            with open(path, "r", encoding="utf-8", newline="") as f:
                if f.read() != want:
                    stale.append(os.path.relpath(path, os.path.dirname(ff6_dir)))
        if stale:
            print("gen_break_floor --check: " + ", ".join(stale) + " is not what the generator writes; "
                  "run python3 ff6/tools/gen_break_floor.py (the .inc is generated: never edit it by hand)")
            sys.exit(1)
        n_row = len([1 for _t, how in floor if how == "row"])
        print(f"gen_break_floor --check OK: {len(rows)} floor bytes and the review are the generator's own "
              f"({n_row} follow their row, {len(rows) - n_row} dealt)")
        return
    for path, text in ((inc_path, inc), (review_path, review)):
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)

    print(f"wrote {inc_path}")
    print(f"wrote {review_path}")
    print(f"species: {len(rows)}  authored={n_authored}  "
          f"floor-live={sum(counts.values())}  "
          f"PIERCE={counts[OT6_PIERCE]} SLASH={counts[OT6_SLASH]} "
          f"BLUDGEON={counts[OT6_BLUDG]} "
          f"(explicit={len(origins['explicit'])} "
          f"inferred={len(origins['inferred'])} "
          f"defaulted={len(origins['defaulted'])})")


if __name__ == "__main__":
    main()
