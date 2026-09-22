#!/usr/bin/env bash
# Prints the id of a device to run on, booting a simulator or emulator when
# nothing of that platform is running. Used by the Makefile's e2e and run.
#
#   scripts/pick-device.sh ios|android|macos [device-id]
#
# A given device id is echoed back untouched. For ios the booted iPhone
# simulator wins, else the first available iPhone simulator is booted. For
# android the first attached device or emulator wins, else the first defined
# emulator is launched and waited for. For macos the device is the desktop
# itself. Nothing here reads a physical device preference; pass its id to run
# on a phone.
set -euo pipefail

platform="${1:?usage: pick-device.sh ios|android|macos [device-id]}"
if [ -n "${2:-}" ]; then
  printf '%s\n' "$2"
  exit 0
fi

case "$platform" in
  ios)
    device=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1 || true)
    if [ -z "$device" ]; then
      device=$(xcrun simctl list devices available | grep -m1 'iPhone' | grep -oE '[0-9A-F-]{36}' || true)
      [ -n "$device" ] || { echo "no iPhone simulator; install one in Xcode" >&2; exit 2; }
      echo "booting simulator $device" >&2
      xcrun simctl boot "$device"
      xcrun simctl bootstatus "$device" -b >/dev/null
    fi
    ;;
  android)
    adb="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
    attached() { "$adb" devices | awk 'NR > 1 && $2 == "device" {print $1; exit}'; }
    device=$(attached)
    if [ -z "$device" ]; then
      emulator=$(fvm flutter emulators 2>/dev/null | awk -F ' • ' '/ • android$/ {print $1; exit}' || true)
      [ -n "$emulator" ] || { echo "no Android emulator defined; create one in Android Studio or connect a device" >&2; exit 2; }
      echo "launching emulator $emulator" >&2
      fvm flutter emulators --launch "$emulator"
      "$adb" wait-for-device
      until [ "$("$adb" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 2; done
      device=$(attached)
    fi
    ;;
  macos)
    device=macos
    ;;
  *)
    echo "unknown platform '$platform'; use ios, android or macos" >&2
    exit 2
    ;;
esac

printf '%s\n' "$device"
