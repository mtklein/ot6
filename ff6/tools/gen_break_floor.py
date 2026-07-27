#!/usr/bin/env python3
# ------------------------------------------------------------------------------
# gen_break_floor.py -- OT6 "break floor" species -> weapon-class classifier
#
# Phase 1 of the break-floor feature (issue #6). Un-authored ("formula")
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
# stdlib only.
# ------------------------------------------------------------------------------

import json
import os
import re

# ------------------------------------------------------------------------------
# class bit constants -- must mirror ff6/src/battle/ot6_class.asm:10-14
OT6_SLASH = 0x01   # swords, katanas, claws
OT6_PIERCE = 0x02  # spears, daggers, thrown edges, bolts, darts
OT6_BLUDG = 0x04   # fists, staves, rods, flails, boomerangs

CLASS_NAME = {OT6_SLASH: "SLASH", OT6_PIERCE: "PIERCE", OT6_BLUDG: "BLUDGEON"}
CLASS_CONST = {OT6_SLASH: "OT6_SLASH", OT6_PIERCE: "OT6_PIERCE", OT6_BLUDG: "OT6_BLUDG"}

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


def emit_inc(rows, out_path):
    lines = []
    lines.append("; ----------------------------------------------------------------------------")
    lines.append("; OT6 break-floor class table -- GENERATED by tools/gen_break_floor.py")
    lines.append("; DO NOT EDIT BY HAND. Re-run the generator to regenerate.")
    lines.append(";")
    lines.append("; One class byte per species, directly indexed by species id (0..383),")
    lines.append("; matching OT6_CODEX width. DATA ONLY -- not yet referenced by ot6.asm")
    lines.append("; (the @formula lookup wiring is Phase 2). Class bits mirror ot6_class.asm.")
    lines.append("; ----------------------------------------------------------------------------")
    lines.append("")
    lines.append("OT6_FLOOR_CLASS:")
    for sid, name, cls, _label in rows:
        shown = name if name != "" else "(unused)"
        lines.append(
            f"        .byte   {CLASS_CONST[cls]:<12}; {sid:>3} {shown} -> {CLASS_NAME[cls]}"
        )
    lines.append("")
    lines.append(f"        ; {CODEX_WIDTH} bytes total (codex width)")
    lines.append("")
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def emit_review(rows, out_path, authored):
    """Write the review dump. REVIEW ONLY -- never feeds back into the .inc.

    Headline counts cover FLOOR-LIVE species only: a species with an
    Ot6ShieldTbl row never reaches @formula (ot6_break.asm scans the authored
    table first), so counting it here misstates the floor. Authored species
    are listed as AUTHORED in the full table and excluded everywhere else.

    The review surface is three-way (issue #11's first acceptance criterion):
    explicit / inferred / defaulted. Two-way triage (defaulted only) hid the
    keyword misfires -- Rhinox (no weakness, absorbs the Vector band's key
    element) matched 'rhino' and was invisible to review.
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
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    return counts, origins, n_authored


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
    emit_inc(rows, inc_path)
    authored = load_authored_species(hud_path)
    counts, origins, n_authored = emit_review(rows, review_path, authored)

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
