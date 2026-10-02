#!/bin/sh
# The app's BPS code on the host JVM, on the real patch:
#   tools/android/bps_check.sh <base rom> <ot6 .bps> <the repo's patched rom>
# The patch must rebuild the patched ROM byte for byte (also through a
# copier header), and corrupted patches and wrong ROMs must be refused
# (android/test/BpsTest.java).
set -eu
. tools/android/env.sh
need_jdk
out=build/android/host
rm -rf "$out"
mkdir -p "$out"
"$JAVA_HOME/bin/javac" -Xlint:all -Werror -d "$out" \
  android/src/io/github/mtklein/ot6patcher/Bps.java android/test/BpsTest.java
"$JAVA_HOME/bin/java" -cp "$out" io.github.mtklein.ot6patcher.BpsTest "$@"
