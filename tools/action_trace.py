#!/usr/bin/env python3
"""Summarize [ot6action] JSON lines from one run.sh log; no dependencies.

Counts engine submissions separately from button attempts. A resolved command
is not necessarily effective healing. hp_net is deliberately not called heal.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import sys

PREFIX = '[ot6action] '


def summarize(lines):
    actions, errors = {}, []
    for line_no, line in enumerate(lines, 1):
        # Only canonical lines; live [ot6note] mirrors must not double-count.
        if not line.startswith(PREFIX):
            continue
        try:
            e = json.loads(line[len(PREFIX):])
            if e['v'] != 1 or e['event'] not in {
                'plan', 'confirm', 'submit', 'start', 'resolve', 'drop', 'unresolved'
            }:
                raise ValueError('unsupported event/version')
            for field in ('id', 'frame', 'elapsed_frames'):
                if type(e[field]) is not int or e[field] < 0:
                    raise ValueError(f'invalid {field}')
            required = {
                'submit': ('navigation_frames',),
                'resolve': ('kind', 'requested', 'actor', 'command', 'attack',
                            'targets', 'hp_net'),
            }
            for field in required.get(e['event'], ()):
                if field not in e:
                    raise ValueError(f'missing {field}')
            key = e['id']
            if e['event'] == 'plan':
                if key in actions:
                    raise ValueError(f'duplicate plan id {key}; use one log per run')
                actions[key] = []
            if key not in actions:
                raise ValueError(f'event without plan: {key}')
            events = actions[key]
            prev = events[-1]['event'] if events else None
            allowed = {
                'plan': {None}, 'confirm': {'plan', 'confirm'},
                'submit': {'plan', 'confirm'}, 'start': {'submit'},
                'resolve': {'start'}, 'drop': {'plan', 'confirm'},
                'unresolved': {'submit', 'start'},
            }
            if prev not in allowed[e['event']]:
                raise ValueError(f'invalid transition {prev} -> {e["event"]}')
            if events and e['frame'] < events[-1]['frame']:
                raise ValueError('frame moved backwards')
            events.append(e)
        except (ValueError, KeyError, TypeError) as exc:
            errors.append(f'line {line_no}: {exc}')
    counts = Counter(e['event'] for events in actions.values() for e in events)
    drops = Counter(events[-1].get('reason', 'unknown') for events in actions.values()
                    if events and events[-1]['event'] == 'drop')
    incomplete = sum(bool(es) and es[-1]['event'] not in {'resolve', 'drop', 'unresolved'}
                     for es in actions.values())
    nav = [e['navigation_frames'] for es in actions.values() for e in es
           if e['event'] == 'submit']
    wasted = sum(es[-1]['elapsed_frames'] for es in actions.values()
                 if es and es[-1]['event'] == 'drop')
    resolved = [e for es in actions.values() for e in es if e['event'] == 'resolve']
    return dict(counts=dict(counts), drops=dict(drops), incomplete=incomplete,
                navigation_frames=nav, dropped_plan_frames=wasted,
                resolved=resolved, errors=errors)


def render(s):
    c = s['counts']
    lines = [f'Recovery plans: {c.get("plan", 0)}',
             f'Confirm attempts: {c.get("confirm", 0)}',
             f'Engine submissions: {c.get("submit", 0)}',
             f'Commands started / resolved: {c.get("start", 0)} / {c.get("resolve", 0)}',
             f'Dropped before submission: {c.get("drop", 0)}',
             f'Unresolved after submission: {c.get("unresolved", 0)}',
             f'Incomplete at end of log: {s["incomplete"]}',
             f'Frames spent on dropped plans: {s["dropped_plan_frames"]}']
    if s['navigation_frames']:
        ns = sorted(s['navigation_frames'])
        lines.append(f'Plan-to-submission frames: mean {sum(ns)/len(ns):.1f}, max {ns[-1]}')
    for reason, n in sorted(s['drops'].items()):
        lines.append(f'  drop {reason}: {n}')
    for e in s['resolved']:
        requested = f'{e["kind"]}:${e["requested"]:02x}'
        lines.append(f'  #{e["id"]} actor {e["actor"]}: requested {requested}, '
                     f'executed cmd=${e["command"]:02x} attack=${e["attack"]:02x} '
                     f'targets=${e["targets"]:04x}; party HP net [{e["hp_net"]}]')
    lines.append('HP deltas are net changes across execution, not attributed healing.')
    if not c.get('plan'):
        lines.append('No recovery plans found; this is not evidence of a clean run.')
    if s['incomplete'] or c.get('unresolved') or s['errors']:
        lines.append('Trace is incomplete: do not treat missing outcomes as successful actions.')
    lines.extend('ERROR: ' + error for error in s['errors'])
    return '\n'.join(lines)


def selftest():
    def line(event, frame, **fields):
        return PREFIX + json.dumps(dict(v=1, id=1, event=event, frame=frame,
                                       elapsed_frames=frame, **fields))
    # Refused confirm never implies submission; unrelated log HP is ignored.
    s = summarize([line('plan', 0), line('confirm', 3),
                   '[ot6] target HP rose', line('drop', 30, reason='cursor_stalled')])
    assert not s['errors'] and s['counts'].get('submit', 0) == 0
    assert s['dropped_plan_frames'] == 30
    s = summarize([line('plan', 0), line('submit', 5, navigation_frames=5)])
    assert s['incomplete'] == 1
    assert summarize([line('plan', 0), line('resolve', 5)])['errors']
    assert summarize([PREFIX + '{bad'])['errors']
    assert summarize(['[ot6note] 10 ' + line('plan', 0)])['counts'] == {}
    print('action_trace selftest: PASS')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('log', nargs='?', type=Path)
    ap.add_argument('--json', action='store_true', help='machine-readable summary')
    ap.add_argument('--selftest', action='store_true')
    args = ap.parse_args()
    if args.selftest:
        selftest()
        return 0
    if not args.log:
        ap.error('provide one run log')
    try:
        with args.log.open(errors='replace') as f:
            summary = summarize(f)
    except OSError as exc:
        ap.error(str(exc))
    print(json.dumps(summary, indent=2) if args.json else render(summary))
    return 1 if summary['errors'] else 0


if __name__ == '__main__':
    sys.exit(main())
