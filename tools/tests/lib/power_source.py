#!/usr/bin/env python3
"""Observe the host's power source, independently of its battery charge.

Only a positive AC observation admits new workers. Missing or unreadable
power information is unknown, not evidence that the host is plugged in.
"""
import json
import platform
from pathlib import Path
import subprocess
import time

MAX_AGE_SEC = 20


def mac_source(text):
    first = text.splitlines()[0] if text.splitlines() else ""
    if first == "Now drawing from 'AC Power'":
        return "ac"
    if first == "Now drawing from 'Battery Power'":
        return "battery"
    return "unknown"


def linux_source(root=Path('/sys/class/power_supply')):
    external = []
    battery = False
    try:
        supplies = list(Path(root).iterdir())
    except OSError:
        return "unknown"
    for supply in supplies:
        try:
            kind = (supply / 'type').read_text().strip()
            # Peripheral/HID batteries are not the laptop's power source.
            scope = (supply / 'scope').read_text().strip() if (supply / 'scope').exists() else ''
            if scope == 'Device':
                continue
            if kind == 'Battery':
                battery = True
            elif kind in ('Mains', 'Wireless') or kind.startswith('USB'):
                online = (supply / 'online').read_text().strip()
                external.append(online if online in ('0', '1') else None)
        except OSError:
            external.append(None)
    if '1' in external:
        return 'ac'
    if battery and external and all(value == '0' for value in external):
        return 'battery'
    return 'unknown'


def observe():
    system = platform.system()
    source = 'unknown'
    if system == 'Darwin':
        try:
            result = subprocess.run(['/usr/bin/pmset', '-g', 'batt'],
                                    capture_output=True, text=True, timeout=3)
            if result.returncode == 0:
                source = mac_source(result.stdout)
        except (OSError, subprocess.SubprocessError):
            pass
    elif system == 'Linux':
        source = linux_source()
    return {'source': source, 'ts': time.time()}


def blocked(power, now):
    """Reason new work cannot start, or None for a fresh AC observation."""
    if not isinstance(power, dict):
        return 'power source unknown'
    stamp = power.get('ts')
    if not isinstance(stamp, (int, float)) or not 0 <= now - stamp <= MAX_AGE_SEC:
        return 'power observation stale'
    if power.get('source') == 'battery':
        return 'on battery'
    if power.get('source') != 'ac':
        return 'power source unknown'
    return None


if __name__ == '__main__':
    print(json.dumps(observe()))
