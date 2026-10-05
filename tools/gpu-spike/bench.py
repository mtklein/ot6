"""Run the spike's measurement matrix and log every run verbatim.

    python3 tools/gpu-spike/bench.py <build dir with spike/cpubench> <capture> <rom> <ckpt> <log> <suite>

suites: scale (N = 1, 100, 1k, 10k coherent and staggered), sat (20k, 40k),
diverge (N=10k, K = 1..64), layout (contig at 10k), cpu (host threads),
tg (threadgroup sizes at 10k staggered).
"""
import subprocess, sys, time, os

bdir, cap, rom, ckpt, log, suite = sys.argv[1:7]
spike = os.path.join(bdir, 'spike')
cpub = os.path.join(bdir, 'cpubench')

runs = {
    'scale': [[spike, cap, rom, ckpt, str(n)] + (['--stagger', '64'] if st else [])
              for st in (False, True) for n in (1, 100, 1000, 10000)],
    'sat': [[spike, cap, rom, ckpt, str(n)] + (['--stagger', '64'] if st else [])
            for st in (False, True) for n in (20000, 40000)],
    'diverge': [[spike, cap, rom, ckpt, '10000', '--stagger', str(k)] for k in (1, 2, 4, 8, 16, 32, 64)],
    'layout': [[spike, cap, rom, ckpt, '10000', '--layout', 'contig'] + (['--stagger', '64'] if st else [])
               for st in (False, True)],
    'tg': [[spike, cap, rom, ckpt, '10000', '--stagger', '64', '--tg', str(t)] for t in (32, 128, 256)],
    'cpu': [[cpub, cap, rom, ckpt, str(n), str(t), str(k)]
            for k in (1, 64) for (n, t) in ((14, 1), (280, 14))],
}[suite]

with open(log, 'a') as f:
    def out(s):
        print(s, flush=True)
        f.write(s + '\n'); f.flush()
    for r in runs:
        load = subprocess.run(['uptime'], capture_output=True, text=True).stdout.strip()
        out('## %s  %s' % (time.strftime('%Y-%m-%d %H:%M:%S'), load))
        out('$ ' + ' '.join(r))
        p = subprocess.run(r, capture_output=True, text=True)
        for line in (p.stdout + p.stderr).splitlines():
            out(line)
        out('exit %d' % p.returncode)
