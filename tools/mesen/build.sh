#!/bin/sh
# tools/mesen/build.sh <workdir> [--stock] -- build Mesen 2.1.1 from the official
# repository's tag, with mesen-script-only.patch applied (or without it, --stock),
# using the flags of upstream's own release workflow for the official Linux build
# (.github/workflows/build.yml, job linux, compiler clang_aot):
#     make USE_AOT=true LTO=true STATICLINK=true SYSTEM_LIBEVDEV=false
# The result is one self-contained binary, like the official release zip:
#     <workdir>/Mesen2/bin/linux-x64/Release/linux-x64/publish/Mesen
# Nothing here installs it anywhere; see README.md for how a build is used.
#
# Needs (Ubuntu 26.04, apt): git make clang lld zip libsdl2-dev zlib1g-dev
# dotnet-sdk-10.0 dotnet-sdk-aot-10.0.  The UI targets net8.0; the .NET 10 SDK
# builds it, fetching the 8.0 runtime packs and the NativeAOT compiler from
# nuget.org on the first build.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=${1:?usage: build.sh <workdir> [--stock]}
STOCK=${2:-}
REPO=https://github.com/SourMesen/Mesen2
TAG=2.1.1
TAG_COMMIT=137ae7ce3bf3f539d007e2c4ef3cb3b6c97672a1   # what the 2.1.1 tag points at

mkdir -p "$WORK"
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

if [ "$STOCK" != --stock ]; then
  git apply "$HERE/mesen-script-only.patch"
  echo "applied mesen-script-only.patch ($(git diff --shortstat))"
fi
# Upstream's workflow writes the commit into the About box the same way.
git rev-parse HEAD > UI/Dependencies/Internal/BuildSha.txt

export DOTNET_CLI_TELEMETRY_OPTOUT=1
make -j"${JOBS:-8}" -O USE_AOT=true LTO=true STATICLINK=true SYSTEM_LIBEVDEV=false

OUT="$SRC/bin/linux-x64/Release/linux-x64/publish/Mesen"
echo "built $OUT"
sha256sum "$OUT"
