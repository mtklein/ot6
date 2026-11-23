#!/usr/bin/env python3
"""stages.py -- who the player can field, stage by stage (#566), for the
holder rule (owner, 2026-11-23: "we don't want just one particular character
to be required to get through fights").

The legs of the line in graph order (build.ninja's generate edges); a stage
starts at its first leg and holds until the next.
  roster   the characters the player can field there
  forced   those the story puts in the party (None: the story fixes the whole
           roster, so all of it)
  magitek  the party rides Magitek armor (TERRA's key is TekMissile; the
           others hold none)
World of Ruin: the first four stages are the story's; after the Falcon the
roster is whoever the route has recruited so far (stage_of fills it from the
route's fights) and nobody is forced.
Optional hires (Shadow in Kohlingen, in the WoB after Narshe) are not counted
until the story brings him.
"""
import re

# the Veldt deals formations from everywhere the party has been: no stage is its own there
VELDT = {"gau_joined", "sabin_done", "wor_veldt", "wor_gau"}
ALL_WOB = {"TERRA", "LOCKE", "EDGAR", "SABIN", "CYAN", "GAU", "CELES", "SETZER", "MOG", "STRAGO", "RELM"}
STAGES = [
    # first leg, roster, forced, magitek
    ("battle_entry", {"TERRA"}, None, True),
    ("narshe_streets", {"TERRA"}, None, False),
    ("moogle_cleared", {"LOCKE", "MOG"}, None, False),
    ("worldmap_narshe", {"TERRA", "LOCKE"}, None, False),
    ("figaro_intro", {"TERRA", "LOCKE", "EDGAR"}, None, False),
    ("vargas_entry", {"TERRA", "LOCKE", "EDGAR", "SABIN"}, None, False),
    ("scenario_hub", {"TERRA", "EDGAR", "SABIN", "BANON"}, None, False),
    ("locke_scenario", {"LOCKE"}, None, False),
    ("sfigaro_escape", {"LOCKE", "CELES"}, None, False),
    ("sabin_world", {"SABIN", "SHADOW"}, {"SABIN"}, False),
    ("cyan_defence", {"SABIN", "CYAN", "SHADOW"}, {"SABIN", "CYAN"}, False),
    ("camp_escaped", {"SABIN", "CYAN", "SHADOW"}, {"SABIN", "CYAN"}, True),
    ("forest_done", {"SABIN", "CYAN", "SHADOW"}, {"SABIN", "CYAN"}, False),
    ("falls_done", {"SABIN", "CYAN"}, None, False),
    ("gau_joined", {"SABIN", "CYAN", "GAU"}, {"SABIN", "CYAN"}, False),
    ("rapids_start", {"TERRA", "EDGAR", "BANON"}, None, False),
    ("narshe_battle", {"TERRA", "LOCKE", "EDGAR", "SABIN", "CYAN", "GAU", "CELES"}, set(), False),
    ("figaro_submerged", {"LOCKE", "EDGAR", "SABIN", "CYAN", "GAU", "CELES"}, set(), False),
    ("ultros2_entry", {"LOCKE", "EDGAR", "SABIN", "CYAN", "GAU"}, {"LOCKE"}, False),
    ("vector_entry", {"LOCKE", "CELES", "EDGAR", "SABIN", "CYAN", "GAU", "SETZER"}, set(), False),
    ("vector_sneak", {"LOCKE", "CELES", "EDGAR", "SABIN", "CYAN", "GAU", "SETZER"}, {"LOCKE", "CELES"}, False),
    ("minecart_entry", {"LOCKE", "EDGAR", "SABIN", "CYAN", "GAU", "SETZER"}, {"LOCKE"}, False),
    ("narshe_mission", {"LOCKE", "EDGAR", "SABIN", "CYAN", "GAU", "SETZER"}, set(), False),
    ("wob_airship_hunt", {"LOCKE", "EDGAR", "SABIN", "CYAN", "GAU", "SETZER", "MOG"}, set(), False),
    ("gate_cave_save", {"TERRA", "LOCKE", "EDGAR", "SABIN", "CYAN", "GAU", "SETZER", "MOG", "CELES"}, {"TERRA"}, False),
    ("vector_crash", {"TERRA", "LOCKE", "EDGAR", "SABIN", "CYAN", "GAU", "SETZER", "MOG"}, set(), False),
    ("crescent_landing", {"TERRA", "LOCKE"}, None, False),
    ("thamasa_night", {"TERRA", "LOCKE", "SHADOW"}, None, False),
    ("fire_out", {"TERRA", "LOCKE", "STRAGO"}, None, False),
    ("wob_esper_mtn_hunt", {"TERRA", "LOCKE", "STRAGO", "RELM"}, None, False),
    ("thamasa_done", ALL_WOB | {"LEO"}, set(), False),
    ("fc_landing", ALL_WOB | {"SHADOW"}, {"SHADOW"}, False),
    ("wor_island", {"CELES"}, None, False),      # (the leg wor_landing is the Floating Continent's end)
    ("wor_sabin", {"CELES", "SABIN"}, None, False),
    ("wor_edgar", {"CELES", "SABIN", "EDGAR"}, None, False),
    ("wor_tomb", {"CELES", "SABIN", "EDGAR", "SETZER"}, None, False),
    ("wor_terra", None, set(), False),      # from here: everyone recruited so far
]


def line_order(build_ninja="build.ninja"):
    names = []
    for line in open(build_ninja):
        m = re.match(r"build build/states/(\w+)\.mss\.lua .*: generate", line)
        if m and not m.group(1).startswith("quick_"):
            names.append(m.group(1))
    return names


def stage_of(legs, recruited=None):
    """{leg: (stage's first leg, roster, forced, magitek)} for the legs in
    graph order; recruited: {leg: names seen fighting in it}, for the open
    stage."""
    out, cur, seen = {}, None, set()
    first = {s[0]: s for s in STAGES}
    for leg in legs:
        if leg in first:
            cur = first[leg]
            if cur[1] is not None:
                seen = set(cur[1])
        if cur is None:
            continue
        if cur[1] is None:
            seen = seen | set((recruited or {}).get(leg, ()))
            out[leg] = (cur[0], set(seen), set(), cur[3])
        else:
            out[leg] = (cur[0], set(cur[1]), set(cur[1]) if cur[2] is None else set(cur[2]), cur[3])
    return out
