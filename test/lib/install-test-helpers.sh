fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "expected file: $1"
}

assert_not_file() {
  [ ! -f "$1" ] || fail "unexpected file: $1"
}

assert_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq "$needle" "$file" || {
    printf -- '--- %s ---\n' "$file" >&2
    sed -n '1,220p' "$file" >&2 || true
    fail "expected '$needle' in $file"
  }
}

assert_json_valid() {
  local file="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$file" >/dev/null
  elif command -v node >/dev/null 2>&1; then
    node -e "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8'))" "$file"
  else
    fail "python3 or node is required to validate JSON"
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq "$needle" "$file"; then
    fail "did not expect '$needle' in $file"
  fi
}

assert_mode() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(stat -c %a "$file")"
  [ "$actual" = "$expected" ] || fail "expected mode $expected for $file, got $actual"
}

assert_occurrences() {
  local file="$1"
  local needle="$2"
  local expected="$3"
  local actual
  actual="$(grep -Fo "$needle" "$file" | wc -l | tr -d ' ')"
  [ "$actual" = "$expected" ] || fail "expected $expected occurrence(s) of '$needle' in $file, got $actual"
}

make_fake_root() {
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/anytls-test.XXXXXX")"
  mkdir -p "$dir/etc" "$dir/proc"
  cat > "$dir/etc/os-release" <<'EOF'
ID=debian
ID_LIKE=debian
VERSION_ID=12
EOF
  cat > "$dir/proc/meminfo" <<'EOF'
MemTotal:        786432 kB
SwapTotal:            0 kB
EOF
  printf '%s\n' "$dir"
}
