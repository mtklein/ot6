#!/usr/bin/env python3
# ending_leo_stage.py -- for the ending_leo instrument (tools/tests/ending_leo.lua).
# Stage the reveal on a copy of wor-kt-plates-v1's battery (#552 ending lab; a declared state write, never
# route evidence): slot 3's switch $00E0 set and slot 12's record and field palette Leo's -- what gen_wor_leo's
# scene writes (name LEO, graphics $10, palette 0 in $1f70+12, the four stats and max HP +14 Ot6LeoReveal writes) -- the slot checksum
# recomputed, a manifest that names the edit.
import json, hashlib, shutil, os, struct, sys
src = 'tools/tests/checkpoints/wor-kt-plates-v1'
dst = 'build/lab/ck/wor-kt-plates-v1'
os.makedirs(dst, exist_ok=True)
m = json.load(open(src + '/manifest.json'))
d = bytearray(open(src + '/' + m['payload'], 'rb').read())
base = 0x1400
def a(addr): return base + addr - 0x1600
rec = 0x1600 + 12 * 37
print('before: actor %02X gfx %02X name %s sw %02X pal %02X avail $02FC=%d party %d' % (d[a(rec)], d[a(rec + 1)],
      d[a(rec + 2):a(rec + 8)].hex(), d[a(0x1e9c)], d[a(0x1f70 + 12)], (d[a(0x1edf)] >> 4) & 1, d[a(0x1850 + 12)] & 7))
d[a(0x1e9c)] |= 0x01
d[a(rec + 1)] = 0x10
d[a(rec + 2):a(rec + 8)] = bytes([0x8b, 0x84, 0x8e, 0xff, 0xff, 0xff])
d[a(0x1f70 + 12)] = 0x00
for i, v in enumerate((52, 38, 41, 36)):
    d[a(rec + 0x1a + i)] = max(d[a(rec + 0x1a + i)], v)
# max HP +14 (Leo's base 50 over Gogo's 36), boost bits kept, capped at 9999; current HP the same, never from 0
mx = d[a(rec + 0x0b)] | d[a(rec + 0x0c)] << 8
base = min(9999, (mx & 0x3fff) + 14)
mx = (mx & 0xc000) | base
d[a(rec + 0x0b)], d[a(rec + 0x0c)] = mx & 0xff, mx >> 8
cur = d[a(rec + 0x09)] | d[a(rec + 0x0a)] << 8
if cur:
    cur = min(9999, cur + 14)
    d[a(rec + 0x09)], d[a(rec + 0x0a)] = cur & 0xff, cur >> 8
ck = sum(d[base:base + 0x9fe]) & 0xffff
if ck == 0: ck = 0xffff
d[base + 0x9fe:base + 0xa00] = struct.pack('<H', ck)
open(dst + '/' + m['payload'], 'wb').write(d)
sha = hashlib.sha256(d).hexdigest()
m['sha256'] = sha
m['provenance'] = 'LEGACY-V0 lab copy (#552): ' + src + ' with slot 3 staged as after Leo\'s reveal by build/lab/stage_leo_battery.py (switch $00E0, slot 12 name/graphics/palette/stats); a declared state write for the ending lab, never route evidence'
json.dump(m, open(dst + '/manifest.json', 'w'), indent=2)
print('staged', dst, sha)
