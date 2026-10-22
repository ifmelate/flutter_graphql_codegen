#!/usr/bin/env bash
# Runs the live checks: for every package, download the schema with
# fetch_schema, generate with build_runner, analyze, and run bin/main.dart
# against the real API. Usage: tool/live_check/run.sh [package...]
# The GitHub check needs GITHUB_TOKEN in the environment and is skipped
# without it. Each package's full output goes to tool/live_check/<pkg>.log.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
packages=("$@")
if [ ${#packages[@]} -eq 0 ]; then
  packages=(countries rick_and_morty gitlab github)
fi

failed=0
for pkg in "${packages[@]}"; do
  log="$here/$pkg.log"
  : > "$log"
  echo "== $pkg"
  if [ "$pkg" = github ] && [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "SKIP GITHUB_TOKEN is not set"
    continue
  fi
  cd "$here/$pkg" || exit 1
  step() {
    if ! "$@" >> "$log" 2>&1; then
      echo "FAIL $* (see $log)"
      return 1
    fi
  }
  step dart pub get &&
    step dart run flutter_graphql_codegen:fetch_schema &&
    step dart run build_runner build --delete-conflicting-outputs &&
    step dart analyze --no-fatal-warnings lib bin || { failed=1; continue; }
  if ! dart run bin/main.dart 2>&1 | tee -a "$log"; then
    failed=1
  fi
  if grep -q '^FAIL' "$log"; then
    failed=1
  fi
done
exit $failed
