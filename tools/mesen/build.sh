#!/bin/sh
# tools/mesen/build.sh <workdir> [options] -- build OT6's Mesen: the commit
# tools/mesen/EMULATOR pins in github.com/mtklein/mesen (MesenCE 2.2.1 plus
# OT6's changes, branch ot6; README.md), using the flags of upstream's own
# release workflow (.github/workflows/build.yml, compiler clang_aot) for this
# machine's build:
#     Linux (job linux):  make USE_AOT=true LTO=true STATICLINK=true SYSTEM_LIBEVDEV=false
#     macOS (job macos):  make USE_AOT=true   (the makefile turns LTO and static
#                         linking off on Darwin)
# then smoke-test it against a stock MesenCE 2.2.1 build.  The result is
# shaped like upstream's release artifacts, plus a record:
#     Linux: <workdir>/Mesen2/bin/linux-x64/Release/linux-x64/publish/Mesen
#            (one self-contained binary) and Mesen.buildinfo beside it
#     macOS: <workdir>/Mesen2/bin/osx-arm64/Release/osx-arm64/publish/Mesen.app
#            (signed ad hoc) and Mesen.app.buildinfo beside it
# Nothing here installs it anywhere; README.md says how a build is deployed.
#
# Options (the environment is not read; every choice is on the command line):
#   --stock            build stock MesenCE 2.2.1 (github.com/nesdev-org/MesenCE,
#                      tag 2.2.1) with no extra compiler flags: the smoke
#                      test's reference.  Its UI/global.json gets the fork's
#                      SDK roll-forward (rollForward latestMajor), which picks
#                      the .NET SDK and changes no code, so the .NET 10 SDK
#                      can build it too.
#   --cflags "..."     compiler flags added for the C/C++ core (default for
#                      OT6's build: -fno-semantic-interposition
#                      -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer).
#                      -fno-semantic-interposition: on Linux MesenCore.so is
#                      built -fPIC with default visibility, so without it
#                      every call between its source files goes through the
#                      PLT and cannot be inlined.  On macOS it changes
#                      nothing: Mach-O has no ELF-style interposition, clang
#                      drops it as unused and the objects come out
#                      byte-identical; it stays so both builds record the
#                      same flags.  The frame pointers (owner, 2026-10-01:
#                      profiles can be taken any time; insight is worth the
#                      1-3% they cost) are kept in every function; arm64
#                      macOS keeps them in non-leaf functions by ABI anyway,
#                      and the flags add the leaf ones (-mframe-pointer=all)
#   --jobs N           make -j (default 8)
#   --reference APP    the stock build the smoke test compares against: the
#                      binary on Linux, the .app bundle on macOS (default:
#                      ~/mesen-reference/Mesen or ~/mesen-reference/Mesen.app,
#                      accepted only when the .buildinfo beside it records a
#                      --stock build of this script's stock tag and the
#                      executable's sha256)
#   --no-smoke         skip the smoke test
#
# The smoke test runs tools/tests/battle_banner.lua through this tree's
# tools/tests/run.sh twice, on the reference and on the new build (each
# through OT6_MESEN_APP with a cache under <workdir>), and fails the build
# unless their [ot6] lines match.  It needs the tree's build/ot6.sfc and
# battle_banner's fixture.  A --stock build with no reference yet skips it:
# that build is the reference (README.md, "The reference build").
#
# Needs (Ubuntu 26.04, apt): git make clang lld zip libsdl2-dev zlib1g-dev
# dotnet-sdk-10.0 dotnet-sdk-aot-10.0.  The UI targets net8.0; the .NET 10 SDK
# builds it, fetching the 8.0 runtime packs and the NativeAOT compiler from
# nuget.org on the first build.
# Needs (macOS arm64): the Xcode command line tools (clang, codesign) and, from
# the Brewfile, sdl2 and dotnet@8 (keg-only: this script finds it under
# Homebrew's prefix when no dotnet is on PATH, as it finds sdl2-config).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=$(cd "$HERE/../.." && pwd)
usage() { echo "usage: build.sh <workdir> [--stock] [--cflags \"...\"] [--jobs N] [--reference APP] [--no-smoke]" >&2; exit 2; }
[ $# -ge 1 ] || usage
WORK=$1; shift
STOCK=0
CFLAGS_EXTRA="-fno-semantic-interposition -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer"
JOBS=8
SMOKE=1
REFERENCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --stock) STOCK=1; CFLAGS_EXTRA="" ;;
    --cflags) [ $# -ge 2 ] || usage; CFLAGS_EXTRA=$2; shift ;;
    --jobs) [ $# -ge 2 ] || usage; JOBS=$2; shift ;;
    --reference) [ $# -ge 2 ] || usage; REFERENCE=$2; shift ;;
    --no-smoke) SMOKE=0 ;;
    *) usage ;;
  esac
  shift
done
# The stock base: what OT6's fork branches from and what the reference is.
STOCK_REPO=https://github.com/nesdev-org/MesenCE
STOCK_TAG=2.2.1
STOCK_COMMIT=20ba206cef5ba207c21203176d02cb9f43dda9fb   # what MesenCE's 2.2.1 tag points at
# OT6's build: one line, "<repository> <tag> <commit>".  The same file is an
# input of every generate and suite edge (configure.py), so changing the pin
# regenerates every fixture.
read -r FORK_REPO FORK_TAG FORK_COMMIT < "$HERE/EMULATOR"
if [ "$STOCK" = 1 ]; then
  REPO=$STOCK_REPO; TAG=$STOCK_TAG; COMMIT=$STOCK_COMMIT
else
  REPO=$FORK_REPO; TAG=$FORK_TAG; COMMIT=$FORK_COMMIT
fi

sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -c1-64; }
if [ "$(uname -s)" = Darwin ]; then
  MAC=1
  case "$(uname -m)" in arm64) PLATFORM=osx-arm64 ;; *) PLATFORM=osx-x64 ;; esac
  DEFAULT_REFERENCE="$HOME/mesen-reference/Mesen.app"
  # A non-login shell (ssh <mac> <command>) has no Homebrew on PATH, and
  # dotnet@8 is keg-only either way.
  BREW=/opt/homebrew/bin/brew; [ -x "$BREW" ] || BREW=/usr/local/bin/brew
  command -v sdl2-config >/dev/null 2>&1 || [ ! -x "$BREW" ] || eval "$("$BREW" shellenv sh)"
  if ! command -v dotnet >/dev/null 2>&1 && [ -x "$BREW" ] &&
     [ -x "$("$BREW" --prefix dotnet@8)/bin/dotnet" ]; then
    PATH="$("$BREW" --prefix dotnet@8)/bin:$PATH"; export PATH
  fi
else
  MAC=0
  PLATFORM=linux-x64
  DEFAULT_REFERENCE="$HOME/mesen-reference/Mesen"
fi
for t in git make clang dotnet sdl2-config unzip; do
  command -v "$t" >/dev/null 2>&1 || { echo "build.sh: $t not found (see Needs, above)"; exit 2; }
done

mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd)
SRC="$WORK/Mesen2"
[ -d "$SRC/.git" ] || git init --quiet "$SRC"
cd "$SRC"
# Fetched by URL, so one workdir can build either repository in turn.
git fetch --quiet --no-tags "$REPO" "+refs/tags/$TAG:refs/tags/$TAG"
git checkout --quiet --force "$COMMIT"
# Always a clean build: the makefile has no header dependencies, so objects kept
# from an earlier build (stock or OT6's) would mix struct layouts silently.
git clean --quiet -fdx
[ "$(git rev-parse HEAD)" = "$COMMIT" ] && [ "$(git rev-parse "refs/tags/$TAG^{commit}")" = "$COMMIT" ] || {
  echo "$REPO tag $TAG is $(git rev-parse "refs/tags/$TAG^{commit}"), expected $COMMIT: refusing to build"; exit 2; }
if [ "$STOCK" = 0 ]; then
  # The reference is stock $STOCK_TAG, so OT6's build must be built on it.
  git fetch --quiet --no-tags "$STOCK_REPO" "+refs/tags/$STOCK_TAG:refs/tags/stock-$STOCK_TAG"
  git merge-base --is-ancestor "$STOCK_COMMIT" "$COMMIT" || {
    echo "$COMMIT is not built on $STOCK_REPO $STOCK_TAG ($STOCK_COMMIT): refusing to build"; exit 2; }
fi

# What this binary is: the repository, tag and commit, and the extra flags.
# BuildSha.txt stays the bare commit, exactly as upstream's workflow writes
# it: Mesen's About box reads the whole file into its commit link and its
# updater takes the first 7 characters for backup names.  The record goes
# beside it in BuildInfo.txt (embedded in the binary the same way,
# Dependencies/Internal/) and into the .buildinfo below.
ident=""
if [ "$STOCK" = 1 ]; then
  # MesenCE pins the .NET SDK to 8.0.x; the fork's UI/global.json commit lets
  # it roll forward (the .NET 10 SDK on Ubuntu 26.04).  It picks the SDK and
  # changes no code.
  sed 's/"rollForward": *"latestFeature"/"rollForward": "latestMajor"/' UI/global.json > UI/global.json.new
  mv UI/global.json.new UI/global.json
  grep -q '"rollForward": "latestMajor"' UI/global.json || { echo "UI/global.json: no rollForward to change"; exit 2; }
  ident="stock UI/global.json rollForward latestMajor
"
fi
[ -z "$CFLAGS_EXTRA" ] || ident="${ident}cflags $CFLAGS_EXTRA
"
git rev-parse HEAD | tr -d '\n' > UI/Dependencies/Internal/BuildSha.txt
printf 'mesen %s %s %s\n%s' "$REPO" "$TAG" "$COMMIT" "$ident" > UI/Dependencies/Internal/BuildInfo.txt

# The makefile sets CC/CXX with :=, so extra flags ride on the compiler name.
if [ "$MAC" = 1 ]; then
  set -- USE_AOT=true
else
  set -- USE_AOT=true LTO=true STATICLINK=true SYSTEM_LIBEVDEV=false
fi
if [ -n "$CFLAGS_EXTRA" ]; then
  echo "extra compiler flags: $CFLAGS_EXTRA"
  set -- "$@" CC="clang $CFLAGS_EXTRA" CXX="clang++ $CFLAGS_EXTRA"
fi
export DOTNET_CLI_TELEMETRY_OPTOUT=1
if [ "$MAC" = 1 ]; then
  # macOS's make is GNU make 3.81: no -O.  And only the core in parallel:
  # under make -j, the C# compiler server dotnet publish leaves running
  # inherits make's jobserver pipe, and make 3.81 then never exits (seen on
  # the first Air build).  No compiler server or reused build nodes either,
  # so the build leaves no process behind.
  export UseSharedCompilation=false MSBUILDDISABLENODEREUSE=1
  make -j"$JOBS" "$@" core
  make "$@"
else
  make -j"$JOBS" -O "$@"
fi

PUB="$SRC/bin/$PLATFORM/Release/$PLATFORM/publish"
CORE="$SRC/InteropDLL/obj.$PLATFORM/MesenCore.so"
if [ "$MAC" = 1 ]; then
  CORE="$SRC/InteropDLL/obj.$PLATFORM/MesenCore.dylib"
  APP="$PUB/Mesen.app"
  OUT="$APP/Contents/MacOS/Mesen"
  # Upstream signs with its own certificate and the hardened runtime; ad hoc
  # with no hardened runtime needs no entitlements.  --deep seals the bundle.
  codesign --force --deep -s - "$APP"
  codesign --verify --deep --strict "$APP"
  RECORD="$APP.buildinfo"
else
  OUT="$PUB/Mesen"
  RECORD="$OUT.buildinfo"
fi
# The NativeAOT compiler this build restored (not every version in the cache).
ilc=$(grep -o "\"runtime.$PLATFORM.Microsoft.DotNet.ILCompiler/[0-9.]*" "$SRC/UI/obj/project.assets.json" 2>/dev/null |
      sed 's/.*\///' | sort -u | tr '\n' ' ')
{
  cat UI/Dependencies/Internal/BuildInfo.txt
  echo "buildsha $(cat UI/Dependencies/Internal/BuildSha.txt)"
  echo "sha256 $(sha256 "$OUT")"
  echo "mesencore_sha256 $(sha256 "$CORE")"
  # The core as packed into the executable (UI/Dependencies.zip is embedded):
  # the copy Mesen unpacks into its home and loads, which run.sh logs as core=.
  echo "packed_mesencore_sha256 $(unzip -p "$SRC/UI/Dependencies.zip" "$(basename "$CORE")" | shasum -a 256 | cut -c1-64)"
  if [ "$MAC" = 1 ]; then
    echo "clang $(clang --version | head -1)"
    echo "core_build_version $(otool -l "$CORE" | sed -n '/LC_BUILD_VERSION/,/ntools/p' | grep -E 'minos|sdk' | tr -s ' ' | tr '\n' ' ')"
    echo "macos_sdk $(xcrun --show-sdk-version 2>/dev/null) $(xcode-select -p 2>/dev/null)"
    echo "codesign $(codesign -dv "$APP" 2>&1 | grep -E '^(Signature|CodeDirectory)' | tr '\n' ' ')"
  else
    echo "clang $(clang --version | head -1)"
    echo "core_comment $(readelf -p .comment "$CORE" 2>/dev/null | sed -n 's/^ *\[ *[0-9a-f]*\] *//p' | tr '\n' ';')"
  fi
  echo "dotnet_sdk $(dotnet --version)"
  echo "nativeaot_ilcompiler ${ilc:-unknown}"
  echo "sdl2 $(sdl2-config --version 2>/dev/null || echo unknown)"
  echo "make $(make --version | head -1)"
  if [ "$MAC" = 1 ]; then
    echo "os macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)) $(uname -m)"
  else
    echo "os $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") $(uname -m)"
  fi
  echo "built $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$RECORD"
echo "built ${APP:-$OUT}"
cat "$RECORD"

[ "$SMOKE" = 1 ] || { echo "smoke test skipped (--no-smoke)"; exit 0; }
# --- smoke test: battle_banner on the reference (stock) build and on this one.
ref_exe() { if [ "$MAC" = 1 ]; then echo "$1/Contents/MacOS/Mesen"; else echo "$1"; fi; }
if [ -z "$REFERENCE" ]; then
  REFERENCE=$DEFAULT_REFERENCE
  if [ "$STOCK" = 1 ] && [ ! -e "$REFERENCE" ]; then
    echo "smoke test skipped: no reference at $REFERENCE yet; this stock build is one (README.md, \"The reference build\")"
    exit 0
  fi
  # The default reference must be what --stock builds: its record names the
  # stock tag and commit, and the executable is the one recorded.
  info="$REFERENCE.buildinfo"
  [ -f "$(ref_exe "$REFERENCE")" ] && [ -f "$info" ] &&
    [ "$(head -n 1 "$info")" = "mesen $STOCK_REPO $STOCK_TAG $STOCK_COMMIT" ] &&
    [ "$(sed -n 2p "$info")" = "stock UI/global.json rollForward latestMajor" ] &&
    grep -qx "sha256 $(sha256 "$(ref_exe "$REFERENCE")")" "$info" || {
    echo "smoke test: $REFERENCE is not a stock $STOCK_TAG build with its $info beside it"
    echo "  (build one with --stock and install it there, README.md \"The reference build\";"
    echo "  or pass --reference <a stock build> or --no-smoke)"
    exit 2; }
fi
[ -f "$TREE/build/ot6.sfc" ] && [ -f "$(ref_exe "$REFERENCE")" ] || {
  echo "smoke test: needs $TREE/build/ot6.sfc and the reference $REFERENCE (or pass --no-smoke)"; exit 2; }
S="$WORK/smoke"; rm -rf "$S"; mkdir -p "$S/art_reference" "$S/art_built"
if [ "$MAC" = 1 ]; then
  # A bundle is already a directory of its own: run.sh copies it into its
  # cache (without any settings.json) under a name taken from its sha256.
  REF_APP=$(cd "$REFERENCE" && pwd); BUILT_APP=$APP
else
  # Each binary alone in a directory: run.sh copies OT6_MESEN_APP whole into its cache.
  mkdir -p "$S/reference" "$S/built"
  cp -p "$REFERENCE" "$S/reference/Mesen"; cp -p "$OUT" "$S/built/Mesen"
  REF_APP="$S/reference"; BUILT_APP="$S/built"
fi
echo "smoke test: reference $(sha256 "$(ref_exe "$REFERENCE")") ($REFERENCE)"
cd "$TREE"
OT6_NO_PUBLISH=1 OT6_WORKER=mesen_smoke_reference OT6_ARTIFACT_DIR="$S/art_reference" \
  OT6_MESEN_APP="$REF_APP" OT6_MESEN_CACHE="$WORK/cache" \
  sh tools/tests/run.sh tools/tests/battle_banner.lua "$S/reference.log" > "$S/reference.out" 2>&1 || true
OT6_NO_PUBLISH=1 OT6_WORKER=mesen_smoke_built OT6_ARTIFACT_DIR="$S/art_built" \
  OT6_MESEN_APP="$BUILT_APP" OT6_MESEN_CACHE="$WORK/cache" \
  sh tools/tests/run.sh tools/tests/battle_banner.lua "$S/built.log" > "$S/built.out" 2>&1 || true
grep -a '^\[ot6\]' "$S/reference.log" > "$S/reference.ot6" || true
grep -a '^\[ot6\]' "$S/built.log" > "$S/built.ot6" || true
grep -qE '^\[ot6\] PASS \(frame ' "$S/reference.ot6" || {
  echo "smoke test: the reference build did not PASS battle_banner (see $S/reference.log)"; exit 1; }
if cmp -s "$S/reference.ot6" "$S/built.ot6"; then
  echo "smoke test: OK -- battle_banner's $(wc -l < "$S/built.ot6" | tr -d ' ') [ot6] lines match the reference build's"
  grep -a '^\[emulator\]' "$S/reference.log" "$S/built.log"
else
  echo "smoke test: FAILED -- battle_banner's [ot6] lines differ from the reference build's:"
  diff "$S/reference.ot6" "$S/built.ot6" | head -20
  exit 1
fi
