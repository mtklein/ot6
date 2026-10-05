"""Reader for capture.lua's blobs (gpu_init.bin, gpu_trace.bin).

    python3 tools/gpu-spike/trace.py <dir with the two blobs>   # summary
"""
import struct, sys, collections

REGS = '<HHHHHBBHBBQ'   # a x y sp d dbr k pc ps emu cycles
NREGS = struct.calcsize(REGS)


def read_init(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'GPUI'
    nr, ns, nt = struct.unpack_from('<III', b, 4)
    o = 16
    regs = struct.unpack_from(REGS, b, o); o += nr
    wram = b[o:o + 0x20000]; o += 0x20000
    sram = b[o:o + ns]; o += ns
    text = b[o:o + nt].decode()
    kv = dict(l.split('=', 1) for l in text.split('\n') if '=' in l)
    return regs, wram, sram, kv


def read_trace(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'GPUT'
    nev, npc, pcf = struct.unpack_from('<III', b, 4)
    o = 16
    pcs = struct.unpack_from('<%dI' % npc, b, o); o += 4 * npc
    evs = []
    for _ in range(nev):
        t = b[o]
        if t in (0x52, 0x57):
            _, ic, addr, val = struct.unpack_from('<BIIB', b, o); o += 10
            evs.append((chr(t), ic, addr, val))
        else:
            _, ic = struct.unpack_from('<BI', b, o); o += 5
            regs = struct.unpack_from(REGS, b, o); o += NREGS
            hashes = struct.unpack_from('<128I', b, o); o += 512
            evs.append((chr(t), ic, regs, hashes))
    assert o == len(b), (o, len(b))
    return pcs, pcf, evs


if __name__ == '__main__':
    d = sys.argv[1]
    regs, wram, sram, kv = read_init(d + '/gpu_init.bin')
    pcs, pcf, evs = read_trace(d + '/gpu_trace.bin')
    print('init regs', regs, 'sram', len(sram))
    print('pcs', len(pcs), 'events', len(evs))
    rd = collections.Counter(); wr = collections.Counter(); ints = collections.Counter()
    for e in evs:
        if e[0] == 'R': rd[e[2] & 0xFFFF] += 1
        elif e[0] == 'W': wr[e[2] & 0xFFFF] += 1
        else: ints[e[0]] += 1
    nints = [e for e in evs if e[0] in 'NI']
    print('interrupts', dict(ints), 'last at instr', nints[-1][1] if nints else None)
    print('reads', ' '.join('%04X:%d' % x for x in sorted(rd.items())))
    print('writes', ' '.join('%04X:%d' % x for x in sorted(wr.items())))
    banks = collections.Counter(e[2] >> 16 for e in evs if e[0] in 'RW')
    print('banks', {('%02X' % k): v for k, v in banks.items()})
