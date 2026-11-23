#!/bin/sh
# pull_logs.sh -- copy the two lines' leg logs from the mbp's scratch clones
# into build/attempts/wt/v051-six-classes/line/{six,base}/ (run on px13, from
# the repo root), with each clone's line.log, ROM hash and done marker.
set -eu
OUT=build/attempts/wt/v051-six-classes/line
for pair in "ot6-proto-six six" "ot6-proto-six-base base"; do
  set -- $pair
  mkdir -p "$OUT/$2"
  rsync -a --include '*.log' --exclude '*' "mbp.local:work/$1/build/states/" "$OUT/$2/"
  rsync -a "mbp.local:work/$1/build/line.log" "mbp.local:work/$1/build/rom.sha" "$OUT/$2/../$2-line/" 2>/dev/null || {
    mkdir -p "$OUT/$2-line"
    rsync -a "mbp.local:work/$1/build/line.log" "mbp.local:work/$1/build/rom.sha" "$OUT/$2-line/"
  }
  rsync -a "mbp.local:work/$1/build/LINE_DONE" "$OUT/$2-line/" 2>/dev/null || true
done
ls "$OUT/six" | wc -l
ls "$OUT/base" | wc -l
