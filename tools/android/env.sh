# Sourced by tools/android/*.sh.  Finds the JDK and the Android SDK pieces
# the OT6 Patcher APK is built with, or stops with what is missing and how
# to install it (docs/TOOLING.md, "Android patcher").

BUILD_TOOLS=35.0.1        # sdkmanager "build-tools;35.0.1"
PLATFORM=android-35       # sdkmanager "platforms;android-35"
MIN_SDK=26
TARGET_SDK=35

INSTALL_HINT="install with: brew bundle  (openjdk@21, android-commandlinetools), then
  JAVA_HOME=/opt/homebrew/opt/openjdk@21 sdkmanager --sdk_root=/opt/homebrew/share/android-commandlinetools 'build-tools;$BUILD_TOOLS' 'platforms;$PLATFORM'"

need_jdk() {
  if [ -z "${JAVA_HOME:-}" ]; then
    for j in /opt/homebrew/opt/openjdk@21 /usr/local/opt/openjdk@21; do
      if [ -x "$j/bin/javac" ]; then JAVA_HOME=$j; break; fi
    done
  fi
  if [ -z "${JAVA_HOME:-}" ] && [ -x /usr/libexec/java_home ]; then
    JAVA_HOME=$(/usr/libexec/java_home 2>/dev/null) || JAVA_HOME=
  fi
  if [ -z "${JAVA_HOME:-}" ] && command -v javac >/dev/null 2>&1 \
     && javac -version >/dev/null 2>&1; then
    JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")
  fi
  if [ -z "${JAVA_HOME:-}" ] || ! "$JAVA_HOME/bin/javac" -version >/dev/null 2>&1; then
    echo "ERROR: no JDK found (set JAVA_HOME, or $INSTALL_HINT)" >&2
    exit 1
  fi
  export JAVA_HOME
  PATH="$JAVA_HOME/bin:$PATH"   # d8 and apksigner run `java`
  export PATH
}

need_sdk() {
  ANDROID_HOME=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/opt/homebrew/share/android-commandlinetools}}
  BT=$ANDROID_HOME/build-tools/$BUILD_TOOLS
  ANDROID_JAR=$ANDROID_HOME/platforms/$PLATFORM/android.jar
  for f in "$BT/aapt2" "$BT/d8" "$BT/zipalign" "$BT/apksigner" "$ANDROID_JAR"; do
    if [ ! -e "$f" ]; then
      echo "ERROR: $f is missing: the APK needs Android SDK build-tools $BUILD_TOOLS" \
           "and platform $PLATFORM under ANDROID_HOME=$ANDROID_HOME;" >&2
      echo "  $INSTALL_HINT" >&2
      exit 1
    fi
  done
}
