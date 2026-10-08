# tools/stream -- watch headless runs while they happen

No video anywhere: the harness's own stdout stream is the output.
Every `run.sh` run emits, into its growing run log:

- `[ot6shot] <frame> <b64 png>` -- a screenshot every 128 frames
  (always on: there is no flag, so a
  playing emulator is always on the worker grid)
- `[ot6pad] <frame> <buttons>` -- the held pad, on every change
- `[ot6note] <frame> <text>` -- every `H.log` line, frame-stamped

`live.py` follows the newest run workspace (or a named one) and serves one
page with the newest frame, the frame counter, the held pad, and the
play-by-play:

```sh
python3 tools/stream/live.py            # http://127.0.0.1:8611/
python3 tools/stream/live.py build/test-runs/<ws> --port 8612
```

Started without a named workspace it follows the newest run: when the
followed run's log goes quiet it switches to the newest live run, so one
viewer follows a whole `ninja` build.  Latency is Mesen's stdout block buffering -- bursts
every second or so.

## More than one machine

```sh
python3 tools/stream/live.py --peer air.local      # repeatable; host:path if not ~/ot6
```

The same pages then show every machine: a line per machine at the top
(active, frozen, load average, and which branch/worktree each worker
belongs to), tiles labelled with their machine, remote detail pages, and
the route map with segments running or done elsewhere (teal: done only on
another machine).  An unreachable peer reads `air: unreachable since
HH:MM (<ssh's reason>)` and never holds up this machine's tiles.

Nothing is started on the other machine.  For each peer the viewer runs
`ssh <host> 'cd ot6 && caffeinate -is python3 - --emit'` with its own
`live.py` on stdin, so the peer stays awake while it is watched (on a
Linux peer, `systemd-inhibit --what=idle` in place of `caffeinate -is`;
see docs/TOOLING.md "Linux worker"):
the far side scans its run logs (every worktree, plus clones under
`.claude/worktrees/` or wherever a running Mesen's command line points),
prints a JSON snapshot a second, and exits when the connection drops.  It
needs key-based ssh (BatchMode) and the repo checked out there; it opens no
port.  A peer that goes silent for 20s is shown down and redialled every
10s.

Placement (`live.py --place N --claim <branch>`) offers room only on
machines with a fresh AC-power observation. Battery-powered hosts still
show their existing workers, but receive no new work; the machine line
explains the exclusion. Unknown or stale power observations also offer no
room. Peer checkouts need `tools/tests/lib/power_source.py`; update them
when deploying the viewer. The slot gate also checks power before admission,
so a queued job waits if the host was unplugged after placement.

Check it from the viewer's machine:

```sh
curl -s 127.0.0.1:8611/grid.json | python3 -c 'import sys,json; [print(m["name"], m["up"], m["err"], m["active"], m["frozen"]) for m in json.load(sys.stdin)["machines"]]'
ssh air.local 'pgrep -fl -- "- --emit"'         # the far side, while connected
ssh air.local 'cd ot6 && python3 - --emit' < tools/stream/live.py | head -c 300   # one snapshot by hand
```
