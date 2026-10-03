#!/bin/sh
# One time only: makes the OT6 Patcher release key.  Every installed copy
# accepts updates signed with this key and no other, so this refuses to
# replace an existing one; back the keystore up (and its password, the login
# Keychain item "ot6-android-release") somewhere safe.
#
# The password is random, goes straight into the login Keychain, and is never
# printed or put on a command line.  Prints the certificate's SHA-256, which
# android/release-cert.sha256 pins (tools/android/verify_apk.sh checks it).
set -eu
. tools/android/env.sh
need_jdk
KS=${OT6_KEYSTORE:-$HOME/.config/ot6/android-release.jks}
if [ -e "$KS" ]; then echo "ERROR: $KS exists; refusing to replace the release key" >&2; exit 1; fi
if security find-generic-password -a ot6 -s ot6-android-release >/dev/null 2>&1; then
  echo "ERROR: the Keychain already has ot6-android-release; refusing to replace it" >&2; exit 1
fi
mkdir -p "$(dirname "$KS")"
chmod 700 "$(dirname "$KS")"
OT6_KS_PASS=$(openssl rand -hex 24)
export OT6_KS_PASS
# `security -i` reads the command from stdin, keeping the password out of argv
printf 'add-generic-password -a ot6 -s ot6-android-release -l "OT6 Android release keystore" -w %s\n' \
  "$OT6_KS_PASS" | security -i >/dev/null
[ "$(security find-generic-password -a ot6 -s ot6-android-release -w)" = "$OT6_KS_PASS" ] || {
  echo "ERROR: could not store the password in the login Keychain" >&2; exit 1; }
"$JAVA_HOME/bin/keytool" -genkeypair -keystore "$KS" -storetype PKCS12 -alias ot6 \
  -keyalg RSA -keysize 4096 -validity 36500 -dname "CN=OT6 Patcher, O=OT6" \
  -storepass:env OT6_KS_PASS -keypass:env OT6_KS_PASS
chmod 600 "$KS"
"$JAVA_HOME/bin/keytool" -list -v -keystore "$KS" -alias ot6 -storepass:env OT6_KS_PASS \
  | grep -E '^(Owner|Valid|[[:space:]]*SHA256):'
