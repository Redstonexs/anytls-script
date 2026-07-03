#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

. "$ROOT/test/lib/install-test-helpers.sh"

eval "$(sed '/^main "\$@"$/,$d' "$ROOT/install.sh")"

run_mode_recovery() {
  local tmp origin install out status
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/anytls-bootstrap-test.XXXXXX")"
  origin="$tmp/origin"
  install="$tmp/install"
  out="$tmp/output.txt"

  git init -q "$origin"
  git -C "$origin" checkout -q -b main
  git -C "$origin" config user.email test@example.invalid
  git -C "$origin" config user.name test
  printf '#!/usr/bin/env bash\nprintf v1\n' > "$origin/anytls-install.sh"
  git -C "$origin" add anytls-install.sh
  git -C "$origin" commit -q -m init

  git clone -q "$origin" "$install"
  chmod +x "$install/anytls-install.sh"

  printf '#!/usr/bin/env bash\nprintf v2\n' > "$origin/anytls-install.sh"
  chmod +x "$origin/anytls-install.sh"
  git -C "$origin" add anytls-install.sh
  git -C "$origin" commit -q -m update-installer

  REPO_URL="$origin"
  REPO_BRANCH=main
  INSTALL_DIR="$install"
  deploy_repo >"$out" 2>&1

  assert_contains "$out" "Resetting installer-managed executable bit"
  assert_contains "$install/anytls-install.sh" "printf v2"
  [ -x "$install/anytls-install.sh" ] || fail "expected updated installer to be executable"
  status="$(git -C "$install" status --short --untracked-files=no)"
  [ -z "$status" ] || fail "expected clean checkout after recovery, got: $status"

  rm -rf "$tmp"
  printf 'PASS bootstrap\n'
}

case "${1:-}" in
  mode-recovery)
    run_mode_recovery
    ;;
  *)
    fail "usage: $0 mode-recovery"
    ;;
esac
