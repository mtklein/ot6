#!/bin/sh
# Checks a built OT6 Patcher APK:
#   tools/android/verify_apk.sh <apk> <versionName> <versionCode> <tested .bps>
# - apksigner verifies it, signed by the release certificate pinned in
#   android/release-cert.sha256 (a different key would break every update);
# - aapt2's badging has the versionCode, versionName and SDK levels asked for,
#   asks for no permissions (no notifications) and is not debuggable;
# - the patch it carries is byte for byte the one bps_check.sh tested.
set -eu
[ $# -eq 4 ] || { echo "usage: $0 <apk> <versionName> <versionCode> <tested .bps>" >&2; exit 2; }
apk=$1 name=$2 code=$3 tested=$4
. tools/android/env.sh
need_jdk
need_sdk

certs=$("$BT/apksigner" verify --verbose --print-certs "$apk")
echo "$certs" | grep -E '^Verified using|^Signer #1 certificate (DN|SHA-256)'
want=$(cat android/release-cert.sha256)
got=$(echo "$certs" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')
[ "$got" = "$want" ] || {
  echo "FAIL: signed by $got, not the release certificate $want (android/release-cert.sha256)" >&2
  exit 1; }

badging=$("$BT/aapt2" dump badging "$apk")
echo "$badging" | grep -E "^(package|minSdkVersion|targetSdkVersion|application-label):"
fail=0
for want in "package: name='$PACKAGE' " "versionCode='$code'" "versionName='$name'"; do
  echo "$badging" | grep "^package:" | grep -q "$want" || { echo "FAIL: badging lacks $want" >&2; fail=1; }
done
echo "$badging" | grep -qx "minSdkVersion:'$MIN_SDK'" || { echo "FAIL: minSdk is not $MIN_SDK" >&2; fail=1; }
echo "$badging" | grep -qx "targetSdkVersion:'$TARGET_SDK'" || { echo "FAIL: targetSdk is not $TARGET_SDK" >&2; fail=1; }
echo "$badging" | grep -qx "application-label:'$LABEL'" || { echo "FAIL: the label is not $LABEL (a test build?)" >&2; fail=1; }
echo "$badging" | grep -q "^application-debuggable" && { echo "FAIL: the APK is debuggable (a test build?)" >&2; fail=1; }
echo "$badging" | grep "^uses-permission:" && { echo "FAIL: the APK asks for permissions; it needs none" >&2; fail=1; }
unzip -p "$apk" assets/ot6.bps | cmp -s - "$tested" || { echo "FAIL: the APK's assets/ot6.bps is not $tested" >&2; fail=1; }
[ $fail -eq 0 ]
echo "android_apk: $apk is v$name ($code), release-signed, carrying $(wc -c < "$tested" | tr -d ' ') bytes of tested patch"
