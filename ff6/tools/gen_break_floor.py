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
        # armored / mechanical / imperial / shelled + dragons
        "guard", "soldier", "trooper", "cadet", "officer", "leader",
        "templar", "rider", "armor", "iron", "steel", "knight", "chaser",
        "proto", "m-tek", "mtek", "tek", "machine", "commander",
        "crab", "beetle", "mantis", "scorpion", "snail", "shell", "carapace",
        "dragon", "wyrm", "wyvern", "drake", "tyrano", "brachio", "dino",
    ]),
    (OT6_BLUDG, [
        # brutes / oozes / rock / skeletal
        "ogre", "troll", "giant", "brawler", "gorilla", "golem",
        "stone", "rock", "boulder",
        "slime", "ooze", "blob", "pudding", "jelly", "amoeba", "flan",
        "skeleton", "bone", "mummy", "zombie",
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

# codex width: OT6_CODEX is 384 species wide (ot6.asm:132 "cpx #$0300").
# The floor table must match that width and species-id indexing.
CODEX_WIDTH = 384


def classify(name):
    """Return (class_byte, rule_label) for a monster name.

    rule_label names the matched keyword (or the default fallback) for the
    review dump. Precedence is the order of CLASS_RULES (pierce, bludg, slash).
    """
    low = name.lower()
    for class_byte, keywords in CLASS_RULES:
        for kw in keywords:
            if kw in low:
                return class_byte, f"{CLASS_NAME[class_byte]}:{kw}"
    label = "DEFAULT(empty)" if name == "" else "DEFAULT"
    return DEFAULT_CLASS, label


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


def emit_review(rows, out_path):
    counts = {OT6_PIERCE: 0, OT6_SLASH: 0, OT6_BLUDG: 0}
    defaulted = []  # rows that hit the slash fallback (taste-review surface)
    for sid, name, cls, label in rows:
        counts[cls] += 1
        if label.startswith("DEFAULT"):
            defaulted.append((sid, name, label))

    lines = []
    lines.append("OT6 BREAK-FLOOR CLASSIFIER -- REVIEW DUMP")
    lines.append("GENERATED by tools/gen_break_floor.py -- do not edit by hand.")
    lines.append("")
    lines.append("SUMMARY COUNTS")
    lines.append(f"  total species   : {len(rows)}")
    lines.append(f"  PIERCE   ($02)  : {counts[OT6_PIERCE]}")
    lines.append(f"  SLASH    ($01)  : {counts[OT6_SLASH]}")
    lines.append(f"  BLUDGEON ($04)  : {counts[OT6_BLUDG]}")
    lines.append(f"  (of SLASH, defaulted/unmatched: {len(defaulted)})")
    lines.append("")
    lines.append("PRECEDENCE: PIERCE > BLUDGEON > SLASH > DEFAULT(->SLASH)")
    lines.append("")
    lines.append("FULL ASSIGNMENT TABLE")
    lines.append(f"{'id':>3} | {'name':<12} | {'class':<8} | rule_matched")
    lines.append("-" * 56)
    for sid, name, cls, label in rows:
        shown = name if name != "" else "(unused)"
        lines.append(f"{sid:>3} | {shown:<12} | {CLASS_NAME[cls]:<8} | {label}")
    lines.append("")
    lines.append("DEFAULT / UNMATCHED LIST (fell through to SLASH fallback)")
    lines.append("These are the taste-review surface: misfires show up here.")
    lines.append(f"count: {len(defaulted)}")
    lines.append("-" * 56)
    for sid, name, label in defaulted:
        shown = name if name != "" else "(unused/empty)"
        lines.append(f"{sid:>3} | {shown:<14} | {label}")
    lines.append("")
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    return counts, defaulted


def main():
    tools_dir = os.path.dirname(os.path.abspath(__file__))
    ff6_dir = os.path.dirname(tools_dir)

    json_path = os.path.join(ff6_dir, "src", "text", "monster_name_en.json")
    inc_path = os.path.join(ff6_dir, "src", "battle", "ot6_break_floor.inc")
    review_path = os.path.join(tools_dir, "break_floor_review.txt")

    names = load_names(json_path)
    if len(names) != CODEX_WIDTH:
        print(f"NOTE: name list has {len(names)} entries, codex width is "
              f"{CODEX_WIDTH}; tail handled by padding/truncation.")

    rows = build_rows(names)
    emit_inc(rows, inc_path)
    counts, defaulted = emit_review(rows, review_path)

    print(f"wrote {inc_path}")
    print(f"wrote {review_path}")
    print(f"species: {len(rows)}  "
          f"PIERCE={counts[OT6_PIERCE]} SLASH={counts[OT6_SLASH]} "
          f"BLUDGEON={counts[OT6_BLUDG]} (defaulted={len(defaulted)})")


if __name__ == "__main__":
    main()
