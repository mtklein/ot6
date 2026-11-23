#!/bin/zsh
# progress of wt/proto-six-classes's two lines on the mbp (mbp_line.sh)
cat ~/work/proto-six-line.out ~/work/proto-six-base.out 2>/dev/null
for d in ot6-proto-six ot6-proto-six-base; do
  echo "--- $d"
  L=~/work/$d/build/line.log
  [ -f $L ] || { echo "no line.log yet"; tail -2 ~/work/$d/build/rom.log 2>/dev/null; continue; }
  head -1 $L
  echo "generate edges started: $(grep -a -c '^\[[0-9]*/[0-9]*\] generate' $L)  stamps: $(ls ~/work/$d/build/states/*.stamp 2>/dev/null | wc -l | tr -d ' ')"
  grep -a '^FAILED' $L | cut -c1-160 | head -20
  echo "deaths so far: $(grep -a -c '\[death\]' $L)"
  grep -a '^\[ot6\] \[retry\] attempt' $L | cut -c1-200 | tail -5
  tail -1 $L | cut -c1-200
  cat ~/work/$d/build/LINE_DONE 2>/dev/null
done
echo "emulators: $(pgrep -f 'Mesen --testrunner' | wc -l | tr -d ' ')"
uptime
