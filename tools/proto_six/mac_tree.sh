#!/bin/zsh
# mac_tree.sh DIR BRANCH [FROM] -- on a Mac (the Air or the mbp): make or
# refresh the scratch clone ~/work/DIR at origin/BRANCH, build its ROM, and,
# with FROM (host:path of another clone's root, e.g.
# mbp.local:work/ot6-proto-six, or a local path), copy that clone's generated
# states, captured checkpoints and ninja log in, so suites boot the states a
# line already played on the SAME ROM (check: the two build/rom.sha agree
# on the masked identity; python3 tools/tests/lib/compose.py --check-states).
#
#   scp tools/proto_six/mac_tree.sh air.local:work/six-tree.sh
#   ssh air.local 'zsh ~/work/six-tree.sh ot6-six-suites wt/v051-six-suites mbp.local:work/ot6-proto-six'
#
# Then run a suite by hand there, one emulator each, within the slots you
# claimed (python3 tools/stream/live.py --place N --claim <branch> on px13):
#   ssh air.local 'cd ~/work/ot6-six-suites && eval "$(/opt/homebrew/bin/brew shellenv zsh)" &&
#     caffeinate -is tools/tests/run.sh tools/tests/battle_break.lua build/lab/battle_break.log'
eval "$(/opt/homebrew/bin/brew shellenv zsh)"
set -u
W=~/work/$1
BR=$2
FROM=${3:-}
if [ ! -d $W/.git ]; then
  git clone -q https://github.com/mtklein/ot6 $W || exit 1
  cp ~/ot6/"Final Fantasy III (USA).sfc" $W/ || exit 1
fi
cd $W || exit 1
git fetch -q origin $BR && git checkout -q --detach origin/$BR || exit 1
python3 configure.py > /dev/null || exit 1
mkdir -p build/lab
ninja build/ot6.sfc > build/rom.log 2>&1 || { tail -5 build/rom.log; exit 1; }
shasum -a 256 build/ot6.sfc > build/rom.sha
echo "tree $W at $(git rev-parse --short HEAD) ($BR), rom $(cut -c1-12 build/rom.sha), identity $(python3 tools/build/rom_version.py identity build/ot6.sfc | cut -c1-12)"
if [ -n "$FROM" ]; then
  for d in states checkpoints; do
    rsync -a --exclude '*.log' --exclude 'shots' "$FROM/build/$d/" build/$d/ || exit 1
  done
  echo "states from $FROM: $(ls build/states/*.stamp 2>/dev/null | wc -l | tr -d ' ') stamps"
  python3 tools/tests/lib/compose.py --check-states 2>&1 | tail -3
fi
