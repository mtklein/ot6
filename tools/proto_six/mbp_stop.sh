#!/bin/zsh
# Stop what the six-classes branch started on this Mac (mbp_line.sh): the
# line scripts, each ninja whose working directory is one of its scratch
# clones (ninja's own command line names no tree), and every process started
# out of those clones.  Nothing else on the machine is touched.
pkill -f 'proto-six-line.sh'
for pid in $(pgrep -x ninja); do
  cwd=$(lsof -a -p $pid -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
  case "$cwd" in
    $HOME/work/ot6-proto-six*) kill $pid ;;
  esac
done
sleep 1
pkill -f "$HOME/work/ot6-proto-six"
sleep 3
echo "left: $(pgrep -f "$HOME/work/ot6-proto-six" | wc -l | tr -d ' ')"
