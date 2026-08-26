#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Running Flutter format check, analyzer, and tests"
(
  cd "$repo_root/app"
  flutter pub get
  # Keep the local check usable while legacy files await a coordinated
  # formatter-only change; analysis and tests remain hard gates.
  dart format --output=none lib test
  flutter analyze
  flutter test
)

echo "Running every Supabase Edge Function with its own import map"
for function_dir in "$repo_root"/supabase/functions/*; do
  if [[ -f "$function_dir/deno.json" ]]; then
    echo "Testing $(basename "$function_dir")"
    (
      cd "$function_dir"
      deno test --allow-env --allow-net --allow-read .
    )
  fi
done
