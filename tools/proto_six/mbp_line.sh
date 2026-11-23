#!/bin/zsh
# The six-class prototype's line on the mbp (wt/proto-six-classes, #566): a
# scratch clone under ~/work/ot6-proto-six, the branch's ROM built there, and
# every generated state (the generate edges only: no suite, audit or
# selftest) replayed from power-on with `ninja -k 0`.
#
#   scp tools/proto_six/mbp_line.sh mbp.local:work/proto-six-line.sh
#   ssh mbp.local 'nohup caffeinate -is zsh ~/work/proto-six-line.sh <sha> > ~/work/proto-six-line.out 2>&1 < /dev/null &'
#
# Log: ~/work/ot6-proto-six/build/line.log (ninja's output, every leg's log
# inline); each leg's own log: build/states/<state>.log; done marker:
# build/LINE_DONE (ninja's exit status and the time).
eval "$(/opt/homebrew/bin/brew shellenv zsh)"
set -u
SHA=$1
J=${2:-6}
W=${3:-~/work/ot6-proto-six}
BR=${4:-wt/proto-six-classes}
if [ ! -d $W/.git ]; then
  git clone -q https://github.com/mtklein/ot6 $W || exit 1
  cp ~/ot6/"Final Fantasy III (USA).sfc" $W/ || exit 1
fi
cd $W || exit 1
git fetch -q origin $BR && git checkout -q $SHA || exit 1
python3 configure.py > /dev/null || exit 1
mkdir -p build
rm -f build/LINE_DONE
ninja build/ot6.sfc > build/rom.log 2>&1 || { tail -5 build/rom.log; exit 1; }
shasum -a 256 build/ot6.sfc > build/rom.sha
# the first output of every generate edge
grep -E ': generate(_capture)? ' build.ninja | awk '{print $2}' | grep -v '/quick_' > build/line-targets.txt
echo "line: start $(date -u +%FT%TZ) sha=$(git rev-parse HEAD) rom=$(cut -c1-12 build/rom.sha) targets=$(wc -l < build/line-targets.txt) -j$J" > build/line.log
ninja -k 0 -j$J $(cat build/line-targets.txt) >> build/line.log 2>&1
rc=$?
echo "line: end $(date -u +%FT%TZ) rc=$rc" >> build/line.log
echo "rc=$rc $(date -u +%FT%TZ)" > build/LINE_DONE
