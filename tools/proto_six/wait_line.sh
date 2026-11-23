#!/bin/sh
# wait_line.sh [MINUTES] -- block (px13) until one of the mbp's two lines ends
# or the six-class line reports a FAILED edge it had not reported before, or
# MINUTES (default 9) pass; then print both lines' status.  The count of
# FAILED edges already seen is kept in $SEEN (default /tmp/p6-failed-seen).
MIN=${1:-9}
SEEN=${SEEN:-/tmp/p6-failed-seen}
[ -f "$SEEN" ] || echo 0 > "$SEEN"
old=$(cat "$SEEN")
n=0
while [ $n -lt $((MIN * 2)) ]; do
  now=$(ssh -o BatchMode=yes mbp.local 'grep -a -c "^FAILED" ~/work/ot6-proto-six/build/line.log; ls ~/work/ot6-proto-six/build/LINE_DONE ~/work/ot6-proto-six-base/build/LINE_DONE 2>/dev/null | wc -l' | tr '\n' ' ')
  f=$(echo "$now" | awk '{print $1}')
  d=$(echo "$now" | awk '{print $2}')
  if [ "${f:-0}" -gt "$old" ] || [ "${d:-0}" -gt 0 ]; then break; fi
  sleep 30
  n=$((n + 1))
done
echo "${f:-0}" > "$SEEN"
ssh -o BatchMode=yes mbp.local 'zsh ~/work/p6-status.sh | tail -15'
