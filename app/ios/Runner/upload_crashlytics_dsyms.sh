#!/bin/sh
set -eu

# The unsigned compile-health build has no distributable symbols to upload.
if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ]; then
  exit 0
fi

# Upload release symbols only; debug builds do not represent shipped code.
if [ "${CONFIGURATION:-}" != "Release" ]; then
  exit 0
fi

pods_run="${PODS_ROOT:-}/FirebaseCrashlytics/run"
spm_run="${BUILD_DIR%Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"

if [ -f "$pods_run" ]; then
  /bin/sh "$pods_run"
elif [ -f "$spm_run" ]; then
  /bin/sh "$spm_run"
else
  echo "Crashlytics dSYM uploader not found in CocoaPods or Swift Package Manager." >&2
  exit 1
fi
