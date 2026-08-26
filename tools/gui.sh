#!/bin/sh
# Open the built ROM in the Mesen GUI.  One instance only: battery saves
# flush on exit, so a second instance exiting later would overwrite the
# first one's in-game saves.
cd "$(dirname "$0")/.."
if ps -axo command | grep "MacOS/Mesen" | grep -v grep | grep -qv testrunner; then
  echo "Mesen is already running - use that window."
else
  open -n "$PWD/tools/Mesen.app" --args "$PWD/build/ot6.sfc"
fi
