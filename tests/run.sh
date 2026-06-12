#!/usr/bin/env bash
# Run the full test suite. Pass --bench to include the real-model benchmark.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
bash "$DIR/test-hooks.sh" || rc=1
echo
bash "$DIR/test-install.sh" || rc=1
if [[ "${1:-}" == "--bench" ]]; then
  echo
  bash "$DIR/benchmark.sh" || rc=1
fi
exit $rc
