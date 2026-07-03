#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$SCRIPT_DIR/lib/anytls-state.sh"
. "$SCRIPT_DIR/lib/anytls-cli.sh"
. "$SCRIPT_DIR/lib/anytls-detect.sh"
. "$SCRIPT_DIR/lib/anytls-alpn.sh"
. "$SCRIPT_DIR/lib/anytls-validate.sh"
. "$SCRIPT_DIR/lib/anytls-util.sh"
. "$SCRIPT_DIR/lib/anytls-config.sh"
. "$SCRIPT_DIR/lib/anytls-service.sh"
. "$SCRIPT_DIR/lib/anytls-swap-export.sh"
. "$SCRIPT_DIR/lib/anytls-install-binary.sh"
. "$SCRIPT_DIR/lib/anytls-main.sh"

main "$@"
