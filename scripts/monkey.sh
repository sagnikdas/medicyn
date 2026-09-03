#!/usr/bin/env bash
# Random tap/swipe stress on a connected Android phone or emulator.
#
# This is the UI/Application Exerciser Monkey — not flutter test. It does
# not prove a dose was recorded; it finds crashes from tap/scroll storms.
# Use a throwaway or local-only account: Monkey can hit Sign out or
# Delete account.
#
# Usage (device unlocked, USB debugging on):
#   ./scripts/monkey.sh
#   ./scripts/monkey.sh --build          # rebuild the debug APK first
#   SESSIONS=5 EVENTS=3000 ./scripts/monkey.sh
#
# Each session force-stops, launches, and waits until MainActivity holds
# focus before injecting. Otherwise a debug cold start (20s on a moto g22)
# plus Home's notification / exact-alarm / battery dialogs produce a fake
# ANR: "Application does not have a focused window".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
PACKAGE="com.sagnikdas.medicyn"
APK="$APP_DIR/build/app/outputs/flutter-apk/app-debug.apk"
SESSIONS="${SESSIONS:-3}"
EVENTS="${EVENTS:-2000}"
THROTTLE_MS="${THROTTLE_MS:-200}"
FOCUS_WAIT_S="${FOCUS_WAIT_S:-90}"
BUILD=0

prepend_path() {
  local dir="$1"
  [[ -n "$dir" && -d "$dir" && ":$PATH:" != *":$dir:"* ]] || return 0
  PATH="$dir:$PATH"
}

prepend_path "$HOME/Library/Android/sdk/platform-tools"
prepend_path "${ANDROID_HOME:+$ANDROID_HOME/platform-tools}"
prepend_path "${ANDROID_SDK_ROOT:+$ANDROID_SDK_ROOT/platform-tools}"

for arg in "$@"; do
  case "$arg" in
    --build) BUILD=1 ;;
    -h|--help)
      sed -n '2,17p' "$0"
      exit 0
      ;;
    *)
      echo "unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

need() {
  command -v "$1" >/dev/null || {
    echo "need $1 on PATH" >&2
    exit 1
  }
}

need adb

devices="$(adb devices | awk 'NR>1 && $2=="device" {print $1}')"
if [[ -z "$devices" ]]; then
  echo "no Android device in 'device' state. Plug one in or start an emulator." >&2
  adb devices >&2
  exit 1
fi

if [[ "$BUILD" -eq 1 || ! -f "$APK" ]]; then
  need flutter
  echo "building debug APK…"
  (cd "$APP_DIR" && flutter build apk --debug)
fi

if [[ ! -f "$APK" ]]; then
  echo "missing $APK — run with --build" >&2
  exit 1
fi

echo "installing $APK"
adb install -r "$APK" >/dev/null

# Runtime dialogs (camera, mic, POST_NOTIFICATIONS, exact alarms, battery
# exemption) steal focus from MainActivity. Monkey then ANRs because the
# package has no focused window. Grant what adb can; ignore API/OEM misses.
grant_perm() {
  adb shell pm grant "$PACKAGE" "$1" >/dev/null 2>&1 || true
}
grant_perm android.permission.CAMERA
grant_perm android.permission.RECORD_AUDIO
grant_perm android.permission.POST_NOTIFICATIONS
adb shell appops set "$PACKAGE" SCHEDULE_EXACT_ALARM allow >/dev/null 2>&1 || true
adb shell dumpsys deviceidle whitelist +"$PACKAGE" >/dev/null 2>&1 || true

current_focus() {
  adb shell dumpsys window 2>/dev/null | tr -d '\r' | grep 'mCurrentFocus=' || true
}

# Cold-start the activity, wait until it is displayed, then until it keeps
# window focus for a few checks (so a post-frame permission sheet is not
# still sitting on top).
launch_and_wait() {
  adb shell am force-stop "$PACKAGE" >/dev/null || true
  adb shell input keyevent KEYCODE_WAKEUP >/dev/null || true
  adb shell wm dismiss-keyguard >/dev/null || true
  echo "waiting for first frame…"
  if ! adb shell am start -W -n "${PACKAGE}/.MainActivity" \
    -a android.intent.action.MAIN \
    -c android.intent.category.LAUNCHER >/dev/null; then
    echo "am start failed" >&2
    return 1
  fi
  local got=0
  local start=$SECONDS
  while (( SECONDS - start < FOCUS_WAIT_S )); do
    if current_focus | grep -q "$PACKAGE"; then
      got=$((got + 1))
      if (( got >= 6 )); then
        return 0
      fi
    else
      got=0
    fi
    sleep 0.5
  done
  echo "timed out waiting for a focused $PACKAGE window" >&2
  current_focus >&2
  return 1
}

OUT="$(mktemp -d "${TMPDIR:-/tmp}/medicyn-monkey.XXXXXX")"
echo "logs: $OUT"
echo "warning: keep the phone unlocked. Monkey stays in $PACKAGE (no Home/Power)."

# Do not send Power / Home / app-switch events — those leave Medicyn or
# lock the device and the rest of the session is noise.
monkey_args=(
  -p "$PACKAGE"
  --throttle "$THROTTLE_MS"
  --pct-syskeys 0
  --pct-appswitch 0
  --pct-anyevent 0
  --kill-process-after-error
  -v
  "$EVENTS"
)

crashed=0
for i in $(seq 1 "$SESSIONS"); do
  session_log="$OUT/session-$i.log"
  echo
  echo "session $i/$SESSIONS — $EVENTS events"
  if ! launch_and_wait; then
    echo "SETUP FAIL in session $i — app never held window focus"
    crashed=1
    continue
  fi
  adb logcat -c
  set +e
  adb shell monkey "${monkey_args[@]}" >"$session_log" 2>&1
  monkey_rc=$?
  set -e
  adb logcat -d -v time >"$OUT/session-$i.logcat"
  {
    echo "----- monkey exit $monkey_rc -----"
    grep -E '// CRASH|// NOT RESPONDING|Monkey aborted' "$session_log" || true
    echo "----- logcat -----"
    grep -E 'FATAL EXCEPTION|AndroidRuntime|FlutterError|Fatal:|has stopped' \
      "$OUT/session-$i.logcat" || true
  } >"$OUT/session-$i.hits"

  if grep -qE '// CRASH|// NOT RESPONDING|Monkey aborted|FATAL EXCEPTION' \
    "$OUT/session-$i.hits"; then
    echo "CRASH in session $i — $OUT/session-$i.hits"
    crashed=1
  elif [[ "$monkey_rc" -ne 0 ]]; then
    echo "monkey exited $monkey_rc in session $i — $session_log"
    crashed=1
  else
    echo "session $i finished without a crash signature"
  fi
done

echo
if [[ "$crashed" -eq 0 ]]; then
  echo "OK — $SESSIONS session(s), $EVENTS events each. Full logs in $OUT"
  exit 0
fi
echo "FAILED — at least one session crashed. Start with $OUT/session-*.hits"
exit 1
