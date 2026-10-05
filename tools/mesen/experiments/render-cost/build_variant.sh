#!/bin/sh
# build_variant.sh <patched mesen source> -- build it the way tools/mesen/build.sh
# builds OT6's Mesen on macOS (USE_AOT=true, same extra cflags, core in
# parallel, UI serial, ad hoc signature), without its fetch/checkout/clean
# (the source is the pinned commit plus apply_variant_patch.py).  No smoke.
set -eu
renice -n 10 -p $$ >/dev/null
SRC=$(cd "$1" && pwd)
cd "$SRC"
eval "$(/opt/homebrew/bin/brew shellenv sh)"
PATH="$(/opt/homebrew/bin/brew --prefix dotnet@8)/bin:$PATH"; export PATH
CFLAGS_EXTRA="-fno-semantic-interposition -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer"
printf 40586fe8af477f65cb383ad402724b562c26babc > UI/Dependencies/Internal/BuildSha.txt
printf 'mesen %s %s %s\ncflags %s\nexperiment render-cost (apply_variant_patch.py)\n' \
  https://github.com/mtklein/mesen ot6-2.2.1-1 "40586fe8af477f65cb383ad402724b562c26babc" "$CFLAGS_EXTRA" > UI/Dependencies/Internal/BuildInfo.txt
export DOTNET_CLI_TELEMETRY_OPTOUT=1 UseSharedCompilation=false MSBUILDDISABLENODEREUSE=1
make -j8 USE_AOT=true CC="clang $CFLAGS_EXTRA" CXX="clang++ $CFLAGS_EXTRA" core
make USE_AOT=true CC="clang $CFLAGS_EXTRA" CXX="clang++ $CFLAGS_EXTRA"
APP="$SRC/bin/osx-arm64/Release/osx-arm64/publish/Mesen.app"
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP"
shasum -a 256 "$APP/Contents/MacOS/Mesen" "$SRC/InteropDLL/obj.osx-arm64/MesenCore.dylib"
echo "built $APP"
