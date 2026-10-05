#!/bin/sh
# rc_profile.sh <workload> <variant> <secs> -- one rc_bench run (rep "prof"),
# with macOS `sample` (1 ms) attached to its Mesen for <secs> starting 3 s in.
# The sample report lands in build/rc/runs/<w>/<v>/rprof.sample.txt.
set -u
cd "$(dirname "$0")/../.."
w=$1; v=$2; secs=$3
out=build/rc/runs/$w/$v
mkdir -p "$out"
python3 build/rc/rc_bench.py "$w" "$v" prof > "$out/rprof.bench.txt" 2>&1 &
bpid=$!
mpid=""
while [ -z "$mpid" ] && kill -0 $bpid 2>/dev/null; do
  mpid=$(ps -axo pid=,command= | awk -v l="test-runs/rc_${w}_${v}_prof." '$2 ~ /MacOS\/Mesen$/ && index($0, l) {print $1; exit}')
  [ -n "$mpid" ] || sleep 0.1
done
sleep 3
sample "$mpid" "$secs" 1 -mayDie -file "$PWD/$out/rprof.sample.txt" > /dev/null 2>&1
wait $bpid
cat "$out/rprof.bench.txt"
