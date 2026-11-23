#!/usr/bin/env python3
"""party_share.py -- by analysis (no emulator): the share of the species the
game deals (and gauges) that a party can weapon-key, under v0.50's four
classes and under the prototype's six (#566).

A party keys a species when it holds one of the species' weapon-weakness
classes.  What a party holds is read two ways:

  signature  each member's signature weapon family and the class-bearing
             skills that come with the member (KIT below): what a player who
             never re-arms anyone for a key holds
  widest     every class of every weapon the member can equip in the ROM
             (vanilla's equip masks, which OT6 keeps), whenever the weapon is
             found, plus the same skills: the ceiling a player who re-arms
             for keys can reach

The parties are bosses-wob.md's Party lines for the World of Balance (a free
pick filled with the members named in PICK), and the World of Ruin's from the
v0.50 Ot6ShieldTbl block comments, which cite the route docs.

    python3 tools/proto_six/party_share.py
"""
import importlib.util
import itertools
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("split", ROOT / "tools/proto_six/split.py")
split = importlib.util.module_from_spec(spec)
spec.loader.exec_module(split)
S, P, B, X = 1, 2, 4, 8
SW, DA, FI, AR, KA, SP = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20
N4 = {S: "slash", P: "pierce", B: "bludgeon", X: "special"}
N6 = split.NEW_NAME

# signature kits: (four-class mask, six-class mask), and what they are
KIT = {
    "TERRA":  (S, SW, "sword"),
    "TERRA*": (P, SP, "Magitek armor: TekMissile"),
    "LOCKE":  (P, DA, "dagger; Mug, Trickshot"),
    "EDGAR":  (P, SP, "spear; AutoCrossbow, Drill"),
    "EDGAR+": (P | S, SP | SW, "spear; AutoCrossbow, Drill; Chain Saw (from Zozo)"),
    "SABIN":  (S | B, FI, "claws; Pummel, Suplex, Bum Rush"),
    "CYAN":   (S, KA, "katana; SwdTech"),
    "SHADOW": (P, KA | DA, "ninja blade; Throw"),
    "CELES":  (S, SW, "sword"),
    "SETZER": (X, AR, "cards, dice; Coin Toss"),
    "MOG":    (P, SP, "spear"),
    "GAU":    (B, FI, "bare hands"),
    "STRAGO": (B, AR, "rod"),
    "RELM":   (X, AR, "brush"),
    "UMARO":  (B, FI, "bone club; Charge, Throw"),
    "BANON":  (B, AR, "rod (a guest: his Punisher)"),
}
CHARS = ["TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO", "RELM", "SETZER", "MOG", "GAU",
         "GOGO", "UMARO"]
# the class-bearing skills in a member's widest kit (as KIT's, less the weapon)
SKILL = {"LOCKE": (P, DA), "EDGAR": (P | S, SP | SW), "SABIN": (B, FI), "CYAN": (S, KA), "SHADOW": (P, DA),
         "SETZER": (X, AR), "UMARO": (B, FI), "TERRA*": (P, SP)}

STAGES = [
    ("WoB 1  Whelk (Narshe mines)", ["TERRA*"]),
    ("WoB 2  Marshal (Narshe escape)", ["LOCKE", "MOG"]),
    ("WoB 3  Mt. Kolts to Vargas", ["TERRA", "LOCKE", "EDGAR"]),
    ("WoB 4  Lete River, Ultros 1", ["TERRA", "LOCKE", "EDGAR", "SABIN", "BANON"]),
    ("WoB 5a Locke's scenario (solo)", ["LOCKE"]),
    ("WoB 5b TunnelArmr", ["LOCKE", "CELES"]),
    ("WoB 6  Imperial camp", ["SABIN", "SHADOW"]),
    ("WoB 8  Phantom Train", ["SABIN", "CYAN", "SHADOW"]),
    ("WoB 9  Baren Falls, the trench, the Veldt", ["SABIN", "CYAN", "GAU"]),
    ("WoB 9b Terra's scenario", ["TERRA", "EDGAR", "BANON"]),
    ("WoB 11 Zozo, Dadaluma (pick: LOCKE CELES EDGAR SABIN)", ["LOCKE", "CELES", "EDGAR+", "SABIN"]),
    ("WoB 11 Zozo, Dadaluma (pick: LOCKE CELES CYAN GAU)", ["LOCKE", "CELES", "CYAN", "GAU"]),
    ("WoB 12 Opera, Ultros 2 (pick: LOCKE EDGAR SABIN CYAN)", ["LOCKE", "EDGAR+", "SABIN", "CYAN"]),
    ("WoB 13 Magitek factory (pick: LOCKE CELES EDGAR SABIN)", ["LOCKE", "CELES", "EDGAR+", "SABIN"]),
    ("WoB 13 Magitek factory (pick: LOCKE CELES SETZER CYAN)", ["LOCKE", "CELES", "SETZER", "CYAN"]),
    ("WoB 17 Sealed Gate, Ultros 3 (pick: TERRA LOCKE EDGAR SABIN)", ["TERRA", "LOCKE", "EDGAR+", "SABIN"]),
    ("WoB 18 Thamasa, FlameEater", ["TERRA", "LOCKE", "STRAGO"]),
    ("WoB 19 airship deck (pick: TERRA EDGAR SABIN)", ["TERRA", "EDGAR+", "SABIN"]),
    ("WoB 21 Floating Continent (pick + SHADOW)", ["TERRA", "EDGAR+", "SABIN", "SHADOW"]),
    ("WoB 21 Floating Continent (pick: TERRA SETZER RELM + SHADOW)", ["TERRA", "SETZER", "RELM", "SHADOW"]),
    ("WoR    the island to Tzen", ["CELES"]),
    ("WoR    Tzen to Edgar", ["CELES", "SABIN"]),
    ("WoR    the Falcon", ["CELES", "SABIN", "EDGAR+", "SETZER"]),
    ("WoR    Mt. Zozo (Cyan joins)", ["CELES", "SABIN", "EDGAR+", "CYAN"]),
    ("WoR    Narshe (Mog, then Umaro)", ["TERRA", "CELES", "CYAN", "MOG"]),
    ("WoR    Thamasa arc (Relm, Strago)", ["TERRA", "CELES", "RELM", "STRAGO"]),
    ("WoR    Phoenix Cave party 1", ["TERRA", "STRAGO", "SABIN", "CYAN"]),
    ("WoR    Phoenix Cave party 2", ["CELES", "RELM", "MOG", "UMARO"]),
    ("WoR    Veldt cave", ["CELES", "TERRA", "RELM", "GAU"]),
    ("WoR    Ebot's Rock, the Zone Eater", ["TERRA", "CELES", "STRAGO", "RELM"]),
    ("WoR    Ancient Castle", ["TERRA", "CELES", "RELM", "CYAN"]),
]


def old_weapon_classes():
    """v0.50's Ot6WeapClassTbl: item id -> four-class mask."""
    text = subprocess.run(["git", "show", "v0.50:ff6/src/battle/ot6_class.asm"], cwd=ROOT, check=True,
                          capture_output=True, text=True).stdout
    return _weapon_table(text, {"OT6_SLASH": S, "OT6_PIERCE": P, "OT6_BLUDG": B, "OT6_SPECIAL": X})


def new_weapon_classes():
    return _weapon_table((ROOT / "ff6/src/battle/ot6_class.asm").read_text(),
                         {"OT6_SWORD": SW, "OT6_DAGGER": DA, "OT6_FIST": FI, "OT6_ARCANE": AR, "OT6_KATANA": KA,
                          "OT6_SPEAR": SP})


def _weapon_table(text, bits):
    out, item, on = {}, 0, False
    for line in text.splitlines():
        if line.startswith("Ot6WeapClassTbl:"):
            on = True
            continue
        if on and line and not line[0].isspace() and not line.startswith(";"):
            break
        if not on:
            continue
        r = re.match(r"\s+\.res\s+\$([0-9a-f]+) - \$([0-9a-f]+)", line)
        m = re.match(r"\s+\.byte\s+(\S+)", line)
        if r:
            item = int(r.group(1), 16)
        elif m:
            if "OT6_NULLBRK" not in m.group(1):
                out[item] = sum(bits.get(t, 0) for t in m.group(1).split("|"))
            item += 1
    return out


def widest():
    """member -> (four-class, six-class): every weapon the ROM lets them equip."""
    rom = (ROOT / "Final Fantasy III (USA).sfc").read_bytes()
    if len(rom) % 0x8000:
        rom = rom[0x200:]
    o, n = old_weapon_classes(), new_weapon_classes()
    out = {}
    for k, name in enumerate(CHARS):
        m4 = m6 = 0
        for i in range(0x5a):
            rec = rom[0x185000 + i * 30: 0x185000 + i * 30 + 30]
            if (rec[1] | (rec[2] << 8)) >> k & 1 and not rec[2] & 0x40:     # (not an Imp item)
                m4 |= o.get(i, 0)
                m6 |= n.get(i, 0)
        s4, s6 = SKILL.get(name, (0, 0))
        out[name] = (m4 | s4, m6 | s6)
    out["BANON"] = (B, AR)
    out["TERRA*"] = SKILL["TERRA*"]
    out["EDGAR+"] = out["EDGAR"]
    out["GAU"] = (out["GAU"][0] | B, out["GAU"][1] | FI)       # bare hands
    return out


def share(masks, m):
    return 100.0 * sum(1 for v in masks.values() if v & m) / len(masks)


def names(m, table):
    return "+".join(n for b, n in table.items() if m & b) or "-"


def main():
    r = split.compute()
    g = r["gauged"]
    m4 = {sp: r["rows"][sp][1] for sp in g}
    m6 = {sp: r["new"][sp] for sp in g}
    w = widest()
    print("the share of the %d species the game deals and gauges that a party can weapon-key" % len(g))
    print("(tools/proto_six/party_share.py; four = v0.50, six = the prototype)")
    print()
    print("held classes, how many of the species they key:")
    for k in range(1, 7):
        v4 = [share(m4, sum(c)) for c in itertools.combinations((S, P, B, X), k)] if k <= 4 else []
        v6 = [share(m6, sum(c)) for c in itertools.combinations((SW, DA, FI, AR, KA, SP), k)]
        print("  any %d class(es): four %s   six %.1f-%.1f%% (mean %.1f%%)" % (
            k, ("%.1f-%.1f%% (mean %.1f%%)" % (min(v4), max(v4), sum(v4) / len(v4))) if v4 else "-",
            min(v6), max(v6), sum(v6) / len(v6)))
    print()
    print("members, signature kit / widest kit:")
    for name in KIT:
        k4, k6, what = KIT[name]
        w4, w6 = w[name]
        print("  %-7s %-52s four %-22s %5.1f%% | six %-22s %5.1f%% | widest: four %-28s %5.1f%% | six %-34s %5.1f%%" % (
            name, what, names(k4, N4), share(m4, k4), names(k6, N6), share(m6, k6),
            names(w4, N4), share(m4, w4), names(w6, N6), share(m6, w6)))
    print()
    print("%-62s %-32s %7s  %-32s %7s  %9s %9s" % ("party (signature kits)", "four holds", "keys", "six holds", "keys",
                                                 "widest 4", "widest 6"))
    for label, members in STAGES:
        k4 = k6 = w4 = w6 = 0
        for mname in members:
            k4 |= KIT[mname][0]
            k6 |= KIT[mname][1]
            w4 |= w[mname][0]
            w6 |= w[mname][1]
        print("%-62s %-32s %6.1f%%  %-32s %6.1f%%  %8.1f%% %8.1f%%" % (
            label, names(k4, N4), share(m4, k4), names(k6, N6), share(m6, k6), share(m4, w4), share(m6, w6)))


if __name__ == "__main__":
    sys.exit(main())
