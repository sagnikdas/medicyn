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
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
PACKAGE="com.sagnikdas.dosely"
APK="$APP_DIR/build/app/outputs/flutter-apk/app-debug.apk"
SESSIONS="${SESSIONS:-3}"
EVENTS="${EVENTS:-2000}"
THROTTLE_MS="${THROTTLE_MS:-200}"
BUILD=0

for arg in "$@"; do
  case "$arg" in
    --build) BUILD=1 ;;
    -h|--help)
      sed -n '2,14p' "$0"
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

OUT="$(mktemp -d "${TMPDIR:-/tmp}/dosely-monkey.XXXXXX")"
echo "logs: $OUT"
echo "warning: keep the phone unlocked. Monkey stays in $PACKAGE (no Home/Power)."

# Do not send Power / Home / app-switch events — those leave Dosely or
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
  adb shell am force-stop "$PACKAGE" >/dev/null || true
  adb shell input keyevent KEYCODE_WAKEUP >/dev/null || true
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
