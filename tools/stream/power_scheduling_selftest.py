#!/usr/bin/env python3
"""Synthetic power observations; no emulator launches or power-setting changes."""
import os
from pathlib import Path
import sys
import tempfile
import time
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/tests/lib'))
import power_source
import emu_slot
import placement


def supply(root, name, kind, online=None, scope=None, status=None):
    path = root / name
    path.mkdir()
    for key, value in {'type': kind, 'online': online, 'scope': scope, 'status': status}.items():
        if value is not None:
            (path / key).write_text(value)


def main():
    assert power_source.mac_source("Now drawing from 'Battery Power'\n100%; discharging") == 'battery'
    assert power_source.mac_source("Now drawing from 'AC Power'\n80%; not charging") == 'ac'
    assert power_source.mac_source('100%; charged') == 'unknown'
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        supply(root, 'AC0', 'Mains', '0')
        supply(root, 'BAT0', 'Battery', status='Full')
        supply(root, 'hid', 'Battery', '1', 'Device', 'Unknown')
        assert power_source.linux_source(root) == 'battery'
        (root / 'AC0/online').write_text('1')
        assert power_source.linux_source(root) == 'ac'
        (root / 'AC0/online').write_text('bogus')
        assert power_source.linux_source(root) == 'unknown'
        supply(root, 'usb', 'USB_PD', '1')
        assert power_source.linux_source(root) == 'ac'
    print('PASS: power source uses AC supply, not charge/full/HID battery status')
    now = time.time()
    def machine(name, source='ac', age=0, active=0):
        return dict(name=name, up=True, active=active, load=[0], ncpu=8, slots=8,
                    power={'source': source, 'ts': now - age})
    machines = [machine('px13', active=2), machine('air', 'battery', active=1),
                machine('mbp')]
    claims = [dict(machine='px13', ts=now-1, active0=2, n=3)]
    placed = placement.placement(machines, claims, now)
    assert placed['order'] == ['px13'] * 3 + ['mbp'] * 8
    assert placed['machines'][1]['active'] == 1
    assert placed['machines'][1]['blocked'] == 'on battery'
    for bad in [machine('px13', 'unknown'), machine('px13', age=21),
                dict(machine('px13'), power=None)]:
        assert not placement.placement([bad], [], now)['order']
    assert not placement.fill([dict(machine('px13', age=21), room=8)], now)['order']
    with tempfile.TemporaryDirectory() as directory:
        path = str(Path(directory) / 'claims')
        with patch.object(placement.time, 'time', return_value=now+0.1):
            assert placement.claim(path, placed, 4, 'a') == ['px13']*3+['mbp']
        with patch.object(placement.time, 'time', return_value=now+0.2):
            assert placement.claim(path, placed, 4, 'b') == ['mbp']*4
        with patch.object(placement.time, 'time', return_value=now+21):
            assert placement.claim(path, placed, 4, 'stale') == []
    machines[1]['power']['source'] = 'ac'
    assert placement.placement(machines, [], now)['order'].count('air') == 7
    print('PASS: placement excludes battery/unknown/stale, preserves running count and claims, resumes on AC')
    # Exercise the actual slot admission loop with synthetic observations:
    # queue on battery, unplug during the first acquisition, then start on AC.
    with tempfile.TemporaryDirectory() as directory:
        observations = iter(['battery', 'battery', 'ac', 'battery', 'ac', 'ac'])
        seen = []
        def observe():
            source = next(observations)
            seen.append(source)
            return {'source': source, 'ts': time.time()}
        ready = str(Path(directory) / 'ready')
        with patch.object(sys, 'argv', ['emu_slot.py', '--hold', str(os.getpid()), ready]), \
             patch.object(emu_slot, 'SLOT_DIR', str(Path(directory) / 'slots')), \
             patch.object(emu_slot, 'slots', return_value=1), \
             patch.object(emu_slot, 'alive', side_effect=lambda pid: not Path(ready).exists()), \
             patch.object(emu_slot.power_source, 'observe', side_effect=observe), \
             patch.object(emu_slot.time, 'sleep'), \
             patch.dict(os.environ, {}, clear=True):
            assert emu_slot.main() == 0
        assert seen == ['battery', 'battery', 'ac', 'battery', 'ac', 'ac']
        assert Path(ready).read_text().startswith('0 1 ')
    print('PASS: queued admission waits on battery and releases slot if unplugged during acquisition')


if __name__ == '__main__':
    main()
