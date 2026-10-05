"""Negative controls for the reference replay: each mutant must make ref fail.

    python3 tools/gpu-spike/mutants.py <capture dir> <rom> <out dir>
"""
import subprocess, sys, os

here = os.path.dirname(os.path.abspath(__file__))
cap, rom, out = sys.argv[1:4]
fails = 0
for m in ['MUT_WRAM', 'MUT_ALU']:
    exe = os.path.join(out, 'ref_' + m)
    subprocess.check_call(['clang++', '-std=c++17', '-O2', '-D' + m, '-Wno-unused-function',
                           '-o', exe, os.path.join(here, 'ref.cpp')])
    r = subprocess.run([exe, cap, rom], capture_output=True, text=True)
    print('== %s (exit %d)' % (m, r.returncode))
    print('\n'.join(l for l in r.stdout.splitlines() if not l.startswith('  $')))
    if r.returncode == 0:
        print('MUTANT SURVIVED: ' + m)
        fails += 1
sys.exit(1 if fails else 0)
