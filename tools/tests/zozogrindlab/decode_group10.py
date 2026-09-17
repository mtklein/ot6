"""decode_group10.py -- world battle group 10 (the Zozo grind column): formations,
species stats (monster_prop.dat) and the Stone / Fire 2 / Fire magic_prop rows (#195)."""
import json, sys
import os
R = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..") + "/"
rd = lambda p: open(R + p, "rb").read()
rand = rd("ff6/src/field/rand_battle_group.dat")
mons = rd("ff6/src/battle/battle_monsters.dat")
bprop = rd("ff6/src/battle/battle_prop.dat")
mprop = rd("ff6/src/battle/monster_prop.dat")
magic = rd("ff6/src/battle/magic_prop_en.dat")
names = json.load(open(R + "ff6/src/text/monster_name_en.json", encoding="utf-8"))["text"]
def mp(sid):
    r = mprop[sid*32:(sid+1)*32]
    return dict(speed=r[0], atk=r[1], hit=r[2], evade=r[3], mblock=r[4], defense=r[5], mdef=r[6], mpow=r[7],
                hp=int.from_bytes(r[8:10],"little"), mp=int.from_bytes(r[10:12],"little"),
                xp=int.from_bytes(r[12:14],"little"), gil=int.from_bytes(r[14:16],"little"), level=r[16],
                special2=r[19], absorb=r[23], null=r[24], weak=r[25])
g = 10
print("world battle group %d: rand_battle_group.dat[%d*8..]" % (g, g))
for i in range(4):
    w = int.from_bytes(rand[g*8+2*i:g*8+2*i+2], "little")
    base = w & 0x1ff
    forms = [base + k for k in range(4)] if w & 0x8000 else [base]
    print(" slot %d word $%04X -> formations %s (%s)" % (i, w, forms, ("31.25%","31.25%","31.25%","6.25%")[i]))
    for f in forms:
        rec = mons[f*15:(f+1)*15]
        slots = []
        for s in range(6):
            if rec[1] & (1 << s):
                sp = rec[2+s] | (((rec[14] >> s) & 1) << 8)
                slots.append((s, sp))
        t = (int.from_bytes(bprop[f*4:f*4+2], "little") ^ 0xF0) & 0xF0
        print("   formation $%03X: %s  arrangements=$%02X" % (f, ", ".join("slot %d=%s($%03X)" % (s, names[sp], sp) for s, sp in slots), t))
seen = set()
for i in range(4):
    w = int.from_bytes(rand[g*8+2*i:g*8+2*i+2], "little"); base = w & 0x1ff
    for f in ([base + k for k in range(4)] if w & 0x8000 else [base]):
        rec = mons[f*15:(f+1)*15]
        for s in range(6):
            if rec[1] & (1 << s):
                seen.add(rec[2+s] | (((rec[14] >> s) & 1) << 8))
print()
for sp in sorted(seen):
    print("$%03X %-12s %s" % (sp, names[sp], mp(sp)))
print()
for sid, nm in ((0x9F, "Stone"), (0x05, "Fire2"), (0x00, "Fire")):
    r = magic[sid*14:(sid+1)*14]
    print("magic_prop $%02X %-6s: %s  (targeting=$%02X elem=$%02X flags1=$%02X flags2=$%02X mp=%d power=%d flags3=$%02X hit=%d special=$%02X status1=$%02X status2=$%02X status3=$%02X status4=$%02X)" % (
        sid, nm, r.hex(" "), r[0], r[1], r[2], r[3], r[4] if len(r)>4 else 0, r[6], r[7], r[8], r[9], r[10], r[11], r[12], r[13]))
