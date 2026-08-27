#!/usr/bin/env python3
"""route_coords.py -- World of Balance (x, y) world-tile coordinates for every
segment in tools/tests/savestate_graph.py, for the live viewer's route map.

Coordinates are 256x256 WoB world tiles (the world_1_tilemap.dat grid,
docs/research/world-map-nav.md).  Interior/dungeon segments pin to their
entrance's world tile.  Provenance, per region:

  Narshe (84,33), exit spawn (84,34)      world-map-nav.md; gen_terra_narshe
  Figaro Castle (64,76)/(64,77)           world-map-nav.md; gen_figaro
  Figaro parked WEST ~(30,48)             world-map-nav.md; gen_zozo2_arrival
  South Figaro ~(84,110)                  gen_kolts ("out of town by the x=0
                                          column -> world (84,112)", grinds at
                                          (84,108)/(86,111))
  Figaro cave south mouth (75,102)        gen_tunnelarmr worldNavTo(75,102)
  Mt. Kolts (102,100), approach (100,105) world-map-nav.md; gen_kolts
  Returners' hideout (104,64)             gen_returner ("world tile is
                                          (104,64)")
  Lete river / scenario split             raft from the hideout; Terra-branch
                                          spill-out at (93,41) (gen_rapids
                                          `load_map 0, {93,41}`); hub/split
                                          points interpolated on the river
  Sabin landing (161,36)                  gen_sabin_world
  Imperial Camp (179,71)                  gen_sabin_world event trigger
  Doma ~(185,62)                          NE of the camp (well-known WoB
                                          geography; interior-only segments)
  Phantom Forest (178,82)                 gen_sabin_forest
  Phantom Train exit (178,93)             gen_sabin_train
  Baren Falls cave (185,93)               gen_sabin_falls worldToMap(185,93)
  Veldt / Crescent Mtn (214,147..149)     gen_sabin_gau / gen_sabin_trench
  Zozo (22,92)                            gen_zozo2_arrival ("{22,92} -> map
                                          221")
  Jidoor (27,129)                         gen_opera1_entry ("Jidoor entrance
                                          {27,129}")
  Opera house (45,153)                    gen_opera2_open worldNavTo(45,153)
  Vector (124,187), MRF interiors pinned  gen_vector_entry worldGrind(124,187)
  Blackjack landing outside Vector        gen_opera7 ("lands outside Vector"),
    ~(123,193)                            due south of the Vector tile
  Sealed Gate / Imperial base (167,194)   gen_gate_cave_save flyTo(163,194),
                                          pocket walk (167..168,194)
  Vector crash site (83,239)              gen_vector_crash
  Banquet exit save (120,188)             gen_banquet_done worldGrind(120,188)
  Crescent Island landing (232,150)       gen_voyage
  Thamasa (249,128)                       gen_thamasa_arrive/gen_massacre
  Esper Mountain (229,130)                gen_esper_mtn worldNavTo(229,130)

Segments sharing a tile (e.g. the 14 Vector/Magitek-facility links) are
spread by a deterministic golden-angle spiral in coords() so no two nodes
overlap; the spiral is a display offset only, keyed to play order.
"""
import math

COORDS = {
    # ---- suite fixtures + the Narshe opening ----
    "battle_entry":        (84, 33),
    "battle2_entry":       (84, 33),
    "whelk_entry":         (84, 33),
    "arvis_wake":          (84, 33),
    "narshe_streets":      (84, 33),
    "moogle_entry":        (84, 32),   # the mines
    "moogle_cleared":      (84, 32),
    "worldmap_narshe":     (84, 40),   # the plains walk south of the gate
    "figaro_entry":        (64, 77),
    "figaro_intro":        (64, 76),
    "south_figaro":        (84, 110),
    "kolts_pool":          (100, 105),
    "kolts_cave":          (102, 100),
    "vargas_won":          (102, 100),
    # ---- the road to the split ----
    "returner_hideout":    (104, 64),
    "banon_joined":        (104, 64),
    "lete_river":          (104, 62),
    "scenario_hub":        (98, 52),
    "locke_scenario":      (96, 54),
    # ---- LOCKE ----
    "sfigaro_town":        (84, 110),
    "celes_freed":         (84, 110),
    "sfigaro_escape":      (75, 102),  # Figaro cave, walked in from the south
    # ---- SABIN ----
    "sabin_world":         (161, 36),
    "cyan_defence":        (179, 71),
    "kefka_done":          (179, 71),
    "camp_cleared":        (185, 62),  # Doma castle (interior arc)
    "doma_defended":       (179, 71),
    "camp_escaped":        (178, 76),
    "forest_done":         (178, 82),
    "train_done":          (178, 93),
    "falls_done":          (185, 93),
    "gau_joined":          (214, 147),
    "sabin_done":          (214, 148),  # Crescent Mtn -> the Serpent Trench
    # ---- TERRA/BANON + the Battle for Narshe ----
    "rapids_start":        (93, 41),
    "terra_narshe":        (84, 33),
    "terra_caves":         (84, 32),
    "terra_clifftop":      (84, 31),
    "reunion_ready":       (84, 31),
    "narshe_battle":       (84, 30),
    "kefka_won":           (84, 30),
    # ---- v0.4 Zozo ----
    "figaro_submerged":    (30, 48),
    "zozo_arrival":        (22, 92),
    "zozo_clock_solved":   (22, 92),
    "dadaluma_entry":      (22, 92),
    "zozo_done":           (22, 92),
    # ---- v0.5 the Opera ----
    "opera_entry":         (27, 129),  # Jidoor
    "opera_open":          (45, 153),
    "opera_backstage":     (45, 153),
    "opera_stage":         (45, 153),
    "opera_dance_done":    (45, 153),
    "ultros2_entry":       (45, 153),
    "blackjack":           (123, 193),
    # ---- v0.6 Vector / the Magitek Research Facility ----
    "vector_entry":        (124, 187),
    "vector_sneak":        (124, 186),
    "mrf_entry":           (124, 185),
    "mrf_chute":           (124, 185),
    "mrf_263":             (124, 185),
    "mrf_kefka":           (124, 185),
    "ifrit_entry":         (124, 185),
    "magicite_ifrit_shiva": (124, 185),
    "n024_entry":          (124, 185),
    "n024_won":            (124, 185),
    "esper_tubes_entry":   (124, 185),
    "esper_tubes":         (124, 185),
    "minecart_entry":      (124, 185),
    "n128_won":            (124, 185),
    # ---- v0.7 the Sealed Gate ----
    "narshe_mission":      (84, 34),
    "gate_cave_save":      (167, 194),
    "vector_crash":        (83, 239),
    "banquet_done":        (120, 188),
    # ---- v0.12/v0.13 the voyage and Thamasa ----
    "crescent_landing":    (232, 150),
    "thamasa_night":       (249, 128),
    "fire_out":            (249, 128),
    "esper_mtn_save":      (229, 130),
    "ultros_won":          (229, 130),
    "thamasa_done":        (249, 128),
}


def coords(names):
    """{name: (x, y)} in world-tile units for the given play-ordered names.
    Names sharing a base tile fan out on a golden-angle spiral (radius
    ~2.2*sqrt(k) tiles) so stacked segments stay individually visible;
    a name this table does not know parks in the top-left ocean."""
    out, seen, unknown = {}, {}, 0
    for n in names:
        base = COORDS.get(n)
        if base is None:
            unknown += 1
            out[n] = (10.0, 8.0 + 6.0 * unknown)
            continue
        k = seen.get(base, 0)
        seen[base] = k + 1
        if k == 0:
            out[n] = (float(base[0]), float(base[1]))
        else:
            a, r = 2.39996 * k, 2.2 * math.sqrt(k)
            out[n] = (base[0] + r * math.cos(a), base[1] + r * math.sin(a))
    return out


if __name__ == "__main__":
    import os
    import runpy
    root = os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    states = runpy.run_path(
        os.path.join(root, "tools/tests/savestate_graph.py"))["STATES"]
    names = [e["state"] for e in states]
    missing = [n for n in names if n not in COORDS]
    c = coords(names)
    for n in names:
        print(f"{n:22s} ({c[n][0]:6.1f},{c[n][1]:6.1f})"
              + ("  <-- NO COORD" if n in missing else ""))
    print(f"{len(names)} segments, {len(missing)} missing")
