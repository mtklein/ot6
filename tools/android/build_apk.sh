#!/bin/sh
# Builds and signs the OT6 Patcher APK (android/), carrying one .bps:
#   tools/android/build_apk.sh <ot6 .bps> <versionName> <versionCode> <out.apk>
# Plain SDK tools, no Gradle: aapt2, javac, d8, zipalign, apksigner.
#
# Signing uses the release key at ~/.config/ot6/android-release.jks
# (OT6_KEYSTORE overrides), whose password is the login Keychain's
# "ot6-android-release" item.  Installed copies accept updates signed with
# that key only, so a missing key is an error here, never a new key.
set -eu
[ $# -eq 4 ] || { echo "usage: $0 <ot6 .bps> <versionName> <versionCode> <out.apk>" >&2; exit 2; }
bps=$1 name=$2 code=$3 apk=$4
. tools/android/env.sh
need_jdk
need_sdk

KS=${OT6_KEYSTORE:-$HOME/.config/ot6/android-release.jks}
if [ ! -f "$KS" ]; then
  echo "ERROR: the release keystore $KS is missing." >&2
  echo "  Every installed OT6 Patcher accepts updates signed with that key only;" >&2
  echo "  restore it from your backup (and its Keychain item, ot6-android-release)." >&2
  echo "  A new key (tools/android/new_keystore.sh) means every player reinstalls." >&2
  exit 1
fi
if ! OT6_KS_PASS=$(security find-generic-password -a ot6 -s ot6-android-release -w 2>/dev/null); then
  echo "ERROR: no login Keychain item ot6-android-release holding $KS's password" >&2
  echo "  (security find-generic-password -a ot6 -s ot6-android-release)." >&2
  exit 1
fi
export OT6_KS_PASS

work=build/android/apk
rm -rf "$work"
mkdir -p "$work/classes" "$work/dex" "$work/assets"
cp "$bps" "$work/assets/ot6.bps"

"$BT/aapt2" compile --dir android/res -o "$work/res.zip"
# OT6_APK_PACKAGE renames the package, so a test build installs beside the
# player's own copy (own settings, own update broadcasts) instead of over it,
# and labels it "OT6 Patcher TEST" so nobody mistakes it for theirs.  Test
# builds are debuggable, so `adb shell run-as <package>` can read their settings.
manifest=android/AndroidManifest.xml
debug=
if [ -n "${OT6_APK_PACKAGE:-}" ]; then
  debug=--debug-mode
  manifest=$work/AndroidManifest.xml
  sed 's/android:label="OT6 Patcher"/android:label="OT6 Patcher TEST"/' \
    android/AndroidManifest.xml > "$manifest"
fi
"$BT/aapt2" link -I "$ANDROID_JAR" --manifest "$manifest" \
  ${OT6_APK_PACKAGE:+--rename-manifest-package "$OT6_APK_PACKAGE"} $debug \
  --min-sdk-version "$MIN_SDK" --target-sdk-version "$TARGET_SDK" \
  --version-code "$code" --version-name "$name" \
  -A "$work/assets" -o "$work/unsigned.apk" "$work/res.zip"
"$JAVA_HOME/bin/javac" -source 8 -target 8 -Xlint:all -Xlint:-options -Werror \
  -bootclasspath "$ANDROID_JAR" -d "$work/classes" android/src/io/github/mtklein/ot6patcher/*.java
"$BT/d8" --release --min-api "$MIN_SDK" --lib "$ANDROID_JAR" --output "$work/dex" \
  $(find "$work/classes" -name '*.class')
(cd "$work/dex" && zip -q -X ../unsigned.apk classes.dex)
"$BT/zipalign" -f 4 "$work/unsigned.apk" "$work/aligned.apk"
mkdir -p "$(dirname "$apk")"
"$BT/apksigner" sign --ks "$KS" --ks-key-alias ot6 --ks-pass env:OT6_KS_PASS \
  --out "$apk.tmp" "$work/aligned.apk"
rm -f "$apk.tmp.idsig"
mv "$apk.tmp" "$apk"
