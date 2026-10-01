#!/bin/sh
# tools/mesen/build.sh <workdir> [options] -- build Mesen 2.1.1 from the
# official repository's tag with this directory's patches, using the flags of
# upstream's own release workflow for the official Linux build
# (.github/workflows/build.yml, job linux, compiler clang_aot):
#     make USE_AOT=true LTO=true STATICLINK=true SYSTEM_LIBEVDEV=false
# then smoke-test it against the tree's official binary.  The result is one
# self-contained binary, like the official release zip, plus a record:
#     <workdir>/Mesen2/bin/linux-x64/Release/linux-x64/publish/Mesen
#     <workdir>/Mesen2/bin/linux-x64/Release/linux-x64/publish/Mesen.buildinfo
# Nothing here installs it anywhere; README.md says how a build is deployed.
#
# Options (the environment is not read; every choice is on the command line):
#   --stock            no patches and no extra compiler flags (upstream as is)
#   --patches "A B"    apply exactly these patches from this directory, in order
#                      (default: mesen-script-only.patch mesen-screenshot-sync.patch;
#                      "" for none)
#   --cflags "..."     compiler flags added for the C/C++ core (default for a
#                      patched build: -fno-semantic-interposition; MesenCore.so
#                      is built -fPIC with default visibility, so without it
#                      every call between its source files goes through the
#                      PLT and cannot be inlined)
#   --jobs N           make -j (default 8)
#   --no-smoke         skip the smoke test
#
# The smoke test runs tools/tests/battle_banner.lua through this tree's
# tools/tests/run.sh twice, on the tree's official binary (tools/Mesen-linux)
# and on the new one, and fails the build unless their [ot6] lines match.
# It needs the tree's build/ot6.sfc and battle_banner's fixture.
#
# Needs (Ubuntu 26.04, apt): git make clang lld zip libsdl2-dev zlib1g-dev
# dotnet-sdk-10.0 dotnet-sdk-aot-10.0.  The UI targets net8.0; the .NET 10 SDK
# builds it, fetching the 8.0 runtime packs and the NativeAOT compiler from
# nuget.org on the first build.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../.." && pwd)
usage() { echo "usage: build.sh <workdir> [--stock] [--patches \"A B\"] [--cflags \"...\"] [--jobs N] [--no-smoke]" >&2; exit 2; }
[ $# -ge 1 ] || usage
WORK=$1; shift
PATCHES="mesen-script-only.patch mesen-screenshot-sync.patch"
CFLAGS_EXTRA="-fno-semantic-interposition"
JOBS=8
SMOKE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --stock) PATCHES=""; CFLAGS_EXTRA="" ;;
    --patches) [ $# -ge 2 ] || usage; PATCHES=$2; shift ;;
    --cflags) [ $# -ge 2 ] || usage; CFLAGS_EXTRA=$2; shift ;;
    --jobs) [ $# -ge 2 ] || usage; JOBS=$2; shift ;;
    --no-smoke) SMOKE=0 ;;
    *) usage ;;
  esac
  shift
done
REPO=https://github.com/SourMesen/Mesen2
TAG=2.1.1
TAG_COMMIT=137ae7ce3bf3f539d007e2c4ef3cb3b6c97672a1   # what the 2.1.1 tag points at

mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd)
SRC="$WORK/Mesen2"
if [ ! -d "$SRC/.git" ]; then
  git clone --quiet "$REPO" "$SRC"
fi
cd "$SRC"
git fetch --quiet --tags origin
git checkout --quiet --force "$TAG"
# Always a clean build: the makefile has no header dependencies, so objects kept
# from an earlier build (stock or patched) would mix struct layouts silently.
git clean --quiet -fdx
[ "$(git rev-parse HEAD)" = "$TAG_COMMIT" ] || {
  echo "tag $TAG is $(git rev-parse HEAD), expected $TAG_COMMIT: refusing to build"; exit 2; }

# What this binary is: the upstream commit, each patch by content hash, the
# extra flags.  BuildSha.txt is what Mesen's About box shows (upstream's
# workflow writes the bare commit there); its first 7 characters stay the
# commit, which Mesen's updater uses to name backups.
ident="$TAG_COMMIT"
for p in $PATCHES; do
  git apply "$HERE/$p"
  echo "applied $p"
  ident="$ident $p=$(sha256sum "$HERE/$p" | cut -c1-64)"
done
[ -z "$CFLAGS_EXTRA" ] || ident="$ident cflags=$(echo "$CFLAGS_EXTRA" | tr ' ' ',')"
printf '%s\n' "$ident" > UI/Dependencies/Internal/BuildSha.txt

# The makefile sets CC/CXX with :=, so extra flags ride on the compiler name.
set -- USE_AOT=true LTO=true STATICLINK=true SYSTEM_LIBEVDEV=false
if [ -n "$CFLAGS_EXTRA" ]; then
  echo "extra compiler flags: $CFLAGS_EXTRA"
  set -- "$@" CC="clang $CFLAGS_EXTRA" CXX="clang++ $CFLAGS_EXTRA"
fi
export DOTNET_CLI_TELEMETRY_OPTOUT=1
make -j"$JOBS" -O "$@"

PUB="$SRC/bin/linux-x64/Release/linux-x64/publish"
OUT="$PUB/Mesen"
CORE="$SRC/InteropDLL/obj.linux-x64/MesenCore.so"
ilc=$(ls "$HOME/.nuget/packages/runtime.linux-x64.microsoft.dotnet.ilcompiler" 2>/dev/null | tr '\n' ' ')
{
  echo "mesen $TAG $TAG_COMMIT"
  echo "buildsha $ident"
  echo "sha256 $(sha256sum "$OUT" | cut -c1-64)"
  echo "mesencore_sha256 $(sha256sum "$CORE" | cut -c1-64)"
  echo "clang $(clang --version | head -1)"
  echo "core_comment $(readelf -p .comment "$CORE" 2>/dev/null | sed -n 's/^ *\[ *[0-9a-f]*\] *//p' | tr '\n' ';')"
  echo "dotnet_sdk $(dotnet --version)"
  echo "nativeaot_ilcompiler ${ilc:-unknown}"
  echo "sdl2 $(sdl2-config --version 2>/dev/null || echo unknown)"
  echo "make $(make --version | head -1)"
  echo "os $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") $(uname -m)"
  echo "built $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT.buildinfo"
echo "built $OUT"
cat "$OUT.buildinfo"

[ "$SMOKE" = 1 ] || { echo "smoke test skipped (--no-smoke)"; exit 0; }
# --- smoke test: battle_banner on the official binary and on this one.
[ -f "$TREE/build/ot6.sfc" ] && [ -x "$TREE/tools/Mesen-linux/Mesen" ] || {
  echo "smoke test: needs $TREE/build/ot6.sfc and $TREE/tools/Mesen-linux/Mesen (or pass --no-smoke)"; exit 2; }
S="$WORK/smoke"; rm -rf "$S"; mkdir -p "$S/art_official" "$S/art_built"
cd "$TREE"
OT6_NO_PUBLISH=1 OT6_WORKER=mesen_smoke_official OT6_ARTIFACT_DIR="$S/art_official" \
  sh tools/tests/run.sh tools/tests/battle_banner.lua "$S/official.log" > "$S/official.out" 2>&1 || true
OT6_NO_PUBLISH=1 OT6_WORKER=mesen_smoke_built OT6_ARTIFACT_DIR="$S/art_built" \
  OT6_MESEN_APP="$PUB" OT6_MESEN_CACHE="$WORK/cache" \
  sh tools/tests/run.sh tools/tests/battle_banner.lua "$S/built.log" > "$S/built.out" 2>&1 || true
grep -a '^\[ot6\]' "$S/official.log" > "$S/official.ot6" || true
grep -a '^\[ot6\]' "$S/built.log" > "$S/built.ot6" || true
grep -qE '^\[ot6\] PASS \(frame ' "$S/official.ot6" || {
  echo "smoke test: the official binary did not PASS battle_banner (see $S/official.log)"; exit 1; }
if cmp -s "$S/official.ot6" "$S/built.ot6"; then
  echo "smoke test: OK -- battle_banner's $(wc -l < "$S/built.ot6" | tr -d ' ') [ot6] lines match the official binary's"
  grep -a '^\[emulator\]' "$S/official.log" "$S/built.log"
else
  echo "smoke test: FAILED -- battle_banner's [ot6] lines differ from the official binary's:"
  diff "$S/official.ot6" "$S/built.ot6" | head -20
  exit 1
fi
