#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/anytls-install.sh"

. "$ROOT/test/lib/install-test-helpers.sh"
. "$ROOT/test/lib/alpn-test-cases.sh"
. "$ROOT/test/lib/export-test-cases.sh"
. "$ROOT/test/lib/listen-test-cases.sh"
. "$ROOT/lib/anytls-install-binary.sh"
. "$ROOT/test/lib/service-test-cases.sh"
. "$ROOT/test/lib/install-test-cases.sh"

case "${1:-}" in
  happy)
    run_happy
    ;;
  invalid)
    run_invalid
    ;;
  service)
    run_service
    ;;
  *)
    fail "usage: $0 happy|invalid|service"
    ;;
esac
