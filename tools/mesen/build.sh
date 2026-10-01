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
#   --reference BIN    the official Mesen binary the smoke test compares
#                      against (default: the tree's tools/Mesen-linux/Mesen,
#                      only while its sha256 is the official 2.1.1 Linux
#                      binary's -- after a deployment that file is a patched
#                      build, so pass the kept official copy, e.g.
#                      ~/mesen-official/Mesen)
#   --no-smoke         skip the smoke test
#
# The smoke test runs tools/tests/battle_banner.lua through this tree's
# tools/tests/run.sh twice, on the reference binary and on the new one (each
# through OT6_MESEN_APP with a cache under <workdir>), and fails the build
# unless their [ot6] lines match.  It needs the tree's build/ot6.sfc and
# battle_banner's fixture.
#
# Needs (Ubuntu 26.04, apt): git make clang lld zip libsdl2-dev zlib1g-dev
# dotnet-sdk-10.0 dotnet-sdk-aot-10.0.  The UI targets net8.0; the .NET 10 SDK
# builds it, fetching the 8.0 runtime packs and the NativeAOT compiler from
# nuget.org on the first build.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../.." && pwd)
usage() { echo "usage: build.sh <workdir> [--stock] [--patches \"A B\"] [--cflags \"...\"] [--jobs N] [--reference BIN] [--no-smoke]" >&2; exit 2; }
[ $# -ge 1 ] || usage
WORK=$1; shift
PATCHES="mesen-script-only.patch mesen-screenshot-sync.patch"
CFLAGS_EXTRA="-fno-semantic-interposition"
JOBS=8
SMOKE=1
REFERENCE=""
OFFICIAL_SHA=ae43f1438282aaaff90a009aa8ada648bc5d631b070656285d7de9cbff513b41   # Mesen_2.1.1_Linux_x64.zip's Mesen
while [ $# -gt 0 ]; do
  case "$1" in
    --stock) PATCHES=""; CFLAGS_EXTRA="" ;;
    --patches) [ $# -ge 2 ] || usage; PATCHES=$2; shift ;;
    --cflags) [ $# -ge 2 ] || usage; CFLAGS_EXTRA=$2; shift ;;
    --jobs) [ $# -ge 2 ] || usage; JOBS=$2; shift ;;
    --reference) [ $# -ge 2 ] || usage; REFERENCE=$2; shift ;;
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
# extra flags.  BuildSha.txt stays the bare commit, exactly as upstream's
# workflow writes it: Mesen's About box reads the whole file into its
# commit link and its updater takes the first 7 characters for backup names.
# The patch record goes beside it in BuildInfo.txt (embedded in the binary
# the same way, Dependencies/Internal/) and into Mesen.buildinfo below.
ident=""
for p in $PATCHES; do
  git apply "$HERE/$p"
  echo "applied $p"
  ident="${ident}patch $p $(sha256sum "$HERE/$p" | cut -c1-64)
"
done
[ -z "$CFLAGS_EXTRA" ] || ident="${ident}cflags $CFLAGS_EXTRA
"
git rev-parse HEAD | tr -d '\n' > UI/Dependencies/Internal/BuildSha.txt
printf 'mesen %s %s\n%s' "$TAG" "$TAG_COMMIT" "$ident" > UI/Dependencies/Internal/BuildInfo.txt

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
# The NativeAOT compiler this build restored (not every version in the cache).
ilc=$(grep -o '"runtime.linux-x64.Microsoft.DotNet.ILCompiler/[0-9.]*' "$SRC/UI/obj/project.assets.json" 2>/dev/null |
      sed 's/.*\///' | sort -u | tr '\n' ' ')
{
  cat UI/Dependencies/Internal/BuildInfo.txt
  echo "buildsha $(cat UI/Dependencies/Internal/BuildSha.txt)"
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
# --- smoke test: battle_banner on the reference (official) binary and on this one.
if [ -z "$REFERENCE" ]; then
  REFERENCE="$TREE/tools/Mesen-linux/Mesen"
  [ -f "$REFERENCE" ] && [ "$(sha256sum "$REFERENCE" | cut -c1-64)" = "$OFFICIAL_SHA" ] || {
    echo "smoke test: $REFERENCE is not the official 2.1.1 binary (sha256 $OFFICIAL_SHA);"
    echo "  pass --reference <official Mesen> (e.g. the ~/mesen-official/Mesen kept at deployment) or --no-smoke"
    exit 2; }
fi
[ -f "$TREE/build/ot6.sfc" ] && [ -f "$REFERENCE" ] || {
  echo "smoke test: needs $TREE/build/ot6.sfc and the reference $REFERENCE (or pass --no-smoke)"; exit 2; }
S="$WORK/smoke"; rm -rf "$S"; mkdir -p "$S/art_reference" "$S/art_built" "$S/reference" "$S/built"
# Each binary alone in a directory: run.sh copies OT6_MESEN_APP whole into its cache.
cp -p "$REFERENCE" "$S/reference/Mesen"; cp -p "$OUT" "$S/built/Mesen"
echo "smoke test: reference $(sha256sum "$S/reference/Mesen" | cut -c1-64) ($REFERENCE)"
cd "$TREE"
OT6_NO_PUBLISH=1 OT6_WORKER=mesen_smoke_reference OT6_ARTIFACT_DIR="$S/art_reference" \
  OT6_MESEN_APP="$S/reference" OT6_MESEN_CACHE="$WORK/cache" \
  sh tools/tests/run.sh tools/tests/battle_banner.lua "$S/reference.log" > "$S/reference.out" 2>&1 || true
OT6_NO_PUBLISH=1 OT6_WORKER=mesen_smoke_built OT6_ARTIFACT_DIR="$S/art_built" \
  OT6_MESEN_APP="$S/built" OT6_MESEN_CACHE="$WORK/cache" \
  sh tools/tests/run.sh tools/tests/battle_banner.lua "$S/built.log" > "$S/built.out" 2>&1 || true
grep -a '^\[ot6\]' "$S/reference.log" > "$S/reference.ot6" || true
grep -a '^\[ot6\]' "$S/built.log" > "$S/built.ot6" || true
grep -qE '^\[ot6\] PASS \(frame ' "$S/reference.ot6" || {
  echo "smoke test: the reference binary did not PASS battle_banner (see $S/reference.log)"; exit 1; }
if cmp -s "$S/reference.ot6" "$S/built.ot6"; then
  echo "smoke test: OK -- battle_banner's $(wc -l < "$S/built.ot6" | tr -d ' ') [ot6] lines match the reference binary's"
  grep -a '^\[emulator\]' "$S/reference.log" "$S/built.log"
else
  echo "smoke test: FAILED -- battle_banner's [ot6] lines differ from the reference binary's:"
  diff "$S/reference.ot6" "$S/built.ot6" | head -20
  exit 1
fi
