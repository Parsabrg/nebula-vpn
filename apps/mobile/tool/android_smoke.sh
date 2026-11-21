#!/usr/bin/env bash
# One Android version's smoke test, run on an emulator by
# .github/workflows/android-versions.yml: install the APK, open the app,
# choose free mode, press Connect, accept the VPN prompt, and fail on any
# crash of the app along the way. Screenshots and the log are left in
# $OUT for the run's artifacts.
#
# It checks that the app runs on that Android version, not that a tunnel
# gets through: CI's network is not the one the app is built for. A crash
# like getOwnerUid() on Android 10 (2026-11-21) is what it catches.
set -u
APK=$1
OUT=${2:-smoke}
PKG=org.nebulavpn.nebula_mobile
mkdir -p "$OUT"
api=$(adb shell getprop ro.build.version.sdk | tr -d '\r')
echo "Android API $api"

shot() { adb exec-out screencap -p > "$OUT/api$api-$1.png" 2>/dev/null || true; }

# The view's bounds of the first node whose text or description is $1.
tap_on() {
  local xml bounds
  for _ in $(seq 1 10); do
    xml=$(adb exec-out uiautomator dump /dev/tty 2>/dev/null)
    bounds=$(printf '%s' "$xml" | grep -oE "(text|content-desc)=\"$1\"[^>]*bounds=\"\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]\"" |
      head -1 | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]')
    if [ -n "$bounds" ]; then
      read -r x1 y1 x2 y2 < <(echo "$bounds" | sed 's/\]\[/ /; s/[][]//g; s/,/ /g')
      adb shell input tap $(((x1 + x2) / 2)) $(((y1 + y2) / 2))
      echo "tapped \"$1\""
      return 0
    fi
    sleep 2
  done
  echo "did not find \"$1\""
  return 1
}

crashed() {
  adb logcat -d -b crash 2>/dev/null | grep -A20 "Process: $PKG" > "$OUT/api$api-crash.txt"
  [ -s "$OUT/api$api-crash.txt" ]
}

fail() {
  echo "::error::Android API $api: $1"
  shot failed
  adb logcat -d > "$OUT/api$api-logcat.txt" 2>/dev/null || true
  exit 1
}

adb logcat -c
adb install -r "$APK" || fail "the APK did not install"
adb shell am start -W -n "$PKG/.MainActivity" > /dev/null
sleep 20
shot started
crashed && fail "the app crashed on start: $(head -3 "$OUT/api$api-crash.txt" | tr '\n' ' ')"
adb shell pidof "$PKG" > /dev/null || fail "the app is not running after start"

# Free mode (no account), then Connect and Android's VPN prompt. A missing
# button is not a failure: the screen's text depends on the device's size.
tap_on "I don't have a server" && sleep 6
shot free
tap_on "Connect" && sleep 5
tap_on "OK" && sleep 20
shot connect
crashed && fail "the app crashed while connecting: $(head -3 "$OUT/api$api-crash.txt" | tr '\n' ' ')"
adb shell pidof "$PKG" > /dev/null || fail "the app is gone after Connect"
adb shell dumpsys connectivity | grep -qE "VPN.*$PKG|VPN CONNECTED" && echo "a VPN is up" || echo "no VPN up (not required here)"

# Leave and come back, as a person switching apps would.
adb shell input keyevent KEYCODE_HOME
sleep 3
adb shell am start -W -n "$PKG/.MainActivity" > /dev/null
sleep 6
shot resumed
crashed && fail "the app crashed on resume: $(head -3 "$OUT/api$api-crash.txt" | tr '\n' ' ')"
adb logcat -d > "$OUT/api$api-logcat.txt" 2>/dev/null || true
echo "Android API $api: no crash"
