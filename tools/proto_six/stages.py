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

HELD: through the opening (docs/design/opening.md) a member holds what a new
player's hands hold there, not the class's signature: the weapon the
character JOINS with (ff6/src/field/char_prop.asm) until a shop sells
another, and the class-bearing skills learned by then.  TERRA wakes with a
Mithril Knife and has a sword from South Figaro's shop; EDGAR joins with a
Mithril Blade and the AutoCrossbow, and the first pike on sale is Narshe's,
before the defense (the automated route strips MOG's for him in the moogle
defense); SABIN joins with a MetalKnuckle, and the first claw on sale is
Mobliz's.  The moogle defense fields ten moogles beside LOCKE and MOG.  A
stage with no entry reads classes.py's signatures.
"""
import re

# the Veldt deals formations from everywhere the party has been: no stage is its own there
VELDT = {"gau_joined", "sabin_done", "wor_veldt", "wor_gau"}
ALL_WOB = {"TERRA", "LOCKE", "EDGAR", "SABIN", "CYAN", "GAU", "CELES", "SETZER", "MOG", "STRAGO", "RELM"}
STAGES = [
    # first leg, roster, forced, magitek
    ("battle_entry", {"TERRA"}, None, True),
    ("narshe_streets", {"TERRA"}, None, False),
    ("moogle_cleared", {"LOCKE", "MOG", "KUPEK", "KUPOP", "KUMAMA", "KUKU", "KUTAN", "KUPAN", "KUSHU", "KURIN",
                        "KURU", "KAMOG"}, None, False),
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
    ("thamasa_done", ALL_WOB, set(), False),
    ("fc_landing", ALL_WOB | {"SHADOW"}, {"SHADOW"}, False),
    ("wor_landing", {"CELES"}, None, False),
    ("wor_sabin", {"CELES", "SABIN"}, None, False),
    ("wor_edgar", {"CELES", "SABIN", "EDGAR"}, None, False),
    ("wor_falcon", {"CELES", "SABIN", "EDGAR", "SETZER"}, None, False),
    ("wor_terra", None, set(), False),      # from here: everyone recruited so far
]

_TRIO = {"TERRA": {"sword"}, "LOCKE": {"dagger"}, "EDGAR": {"sword", "crossbow"}}
_SABIN = {"knuckle", "fist", "blitz"}
_SHADOW = {"ninja blade", "star"}
_CYAN = {"katana", "swdtech"}
# first leg of the stage -> {member: the weapon kinds (classes.py KIND_CLASS) held there}
HELD = {
    "narshe_streets": {"TERRA": {"dagger"}},
    # the three squads (event_main.asm's char_party lines): LOCKE's, MOG's, KUSHU's
    "moogle_cleared": {"LOCKE": {"dagger"}, "KUPEK": {"spear"}, "KUPOP": {"flail"}, "KUMAMA": {"claw"},
                       "MOG": {"spear"}, "KUKU": {"flail"}, "KUTAN": {"sword"}, "KUPAN": {"boomerang"},
                       "KUSHU": {"brush"}, "KURIN": {"spear"}, "KURU": {"sword"}, "KAMOG": {"boomerang"}},
    "worldmap_narshe": {"TERRA": {"dagger"}, "LOCKE": {"dagger"}},
    # the knife through the cave, a sword from South Figaro's shop on (one leg plays both)
    "figaro_intro": dict(_TRIO, TERRA={"dagger", "sword"}),
    "vargas_entry": dict(_TRIO, SABIN=_SABIN),
    "scenario_hub": {"TERRA": {"sword"}, "EDGAR": {"sword", "crossbow"}, "SABIN": _SABIN, "BANON": {"rod"}},
    # Trickshot from the Lete on (switch $001A): LOCKE's kit holds Dagger whatever is in his hand
    "locke_scenario": {"LOCKE": {"dagger", "thief hit"}},
    "sfigaro_escape": {"LOCKE": {"dagger", "thief hit"}, "CELES": {"sword"}},
    "sabin_world": {"SABIN": _SABIN, "SHADOW": _SHADOW},
    "cyan_defence": {"SABIN": _SABIN, "SHADOW": _SHADOW, "CYAN": _CYAN},
    "forest_done": {"SABIN": _SABIN, "SHADOW": _SHADOW, "CYAN": _CYAN},
    "falls_done": {"SABIN": _SABIN, "CYAN": _CYAN},
    # Mobliz's shop sells the Mithril Claw: SABIN may Fight with Katana from here
    "gau_joined": {"SABIN": _SABIN | {"claw"}, "CYAN": _CYAN, "GAU": {"fang"}},
    "rapids_start": {"TERRA": {"sword"}, "EDGAR": {"sword", "crossbow"}, "BANON": {"rod"}},
    # Narshe's shop, open before the defense, sells the first Mithril Pike
    "narshe_battle": {"TERRA": {"sword"}, "LOCKE": {"dagger", "thief hit"}, "EDGAR": {"sword", "spear", "crossbow"},
                      "SABIN": _SABIN | {"claw"}, "CYAN": _CYAN, "GAU": {"fang"}, "CELES": {"sword"}},
    # Figaro's tool merchant sells the Drill once the castle has dived
    "figaro_submerged": {"LOCKE": {"dagger", "thief hit"}, "EDGAR": {"sword", "spear", "drill", "crossbow"},
                         "SABIN": _SABIN | {"claw"}, "CYAN": _CYAN, "GAU": {"fang"}, "CELES": {"sword"}},
}


def held_kinds(first_leg, name):
    """the weapon kinds a member holds at a stage (by its first leg): HELD's
    where it says, else the signature's (None: read classes.SIGNATURE)."""
    return HELD.get(first_leg, {}).get(name)


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
