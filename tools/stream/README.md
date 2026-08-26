# tools/stream -- watch headless runs while they happen

No video anywhere: the harness's own stdout stream is the broadcast.
Every `run.sh` run emits, into its growing run log:

- `[ot6shot] <frame> <b64 png>` -- a screenshot every 128 frames
  (`OT6_LIVE=<n>` changes the interval, `OT6_LIVE=0` turns the taps off)
- `[ot6pad] <frame> <buttons>` -- the held pad, on every change
- `[ot6note] <frame> <text>` -- every `H.log` line, frame-stamped

`live.py` follows the newest run workspace (or a named one) and serves one
page with the newest frame, the frame counter, the held pad, and the
play-by-play:

```sh
python3 tools/stream/live.py            # http://127.0.0.1:8611/
python3 tools/stream/live.py build/test-runs/<ws> --port 8612
```

Started without a named workspace it channel-hops: when the followed run's
log goes quiet it switches to the newest live run, so one viewer surfs a
whole `ninja` build.  Latency is Mesen's stdout block buffering -- bursts
every second or so.
