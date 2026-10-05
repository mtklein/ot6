#!/bin/sh
# campaign.sh -- the timing batch for wt/render-cost, one emulator at a time on
# this Mac (mbp).  Variants rotate within each rep so drift spreads evenly.
cd "$(dirname "$0")/../.."
python3 /Users/mtklein/ot6/tools/stream/live.py --place 1 --claim wt/render-cost 2>&1 | sed -n 2p
V="base skip128 skipall nomixer norewind all_safe"
for rep in 1 2 3; do
  for w in rwhelk rrage rzozo; do
    for v in $V; do
      [ "$w$v$rep" = rwhelkbase1 ] && continue   # run before the campaign
      [ "$w$v$rep" = rragebase1 ] && continue
      python3 build/rc/rc_bench.py $w $v $rep
    done
  done
  V="$(echo $V | awk '{for(i=2;i<=NF;i++) printf "%s ", $i; print $1}')"
done
for w in rwhelk rrage; do python3 build/rc/rc_bench.py $w nodsp_probe 1; done
python3 /Users/mtklein/ot6/tools/stream/live.py --place 1 --claim wt/render-cost 2>&1 | sed -n 2p
for rep in 2 3; do for w in whelk rage; do for v in base norewind; do python3 build/rc/rc_bench.py $w $v $rep; done; done; done
for w in whelk rage; do python3 build/rc/rc_bench.py $w norewind 1; python3 build/rc/rc_bench.py $w skip128 1; python3 build/rc/rc_bench.py $w all_safe 1; done
for rep in 2 3; do python3 build/rc/rc_bench.py zozo base $rep; done
echo CAMPAIGN DONE
