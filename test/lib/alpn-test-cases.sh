assert_invalid_alpn_rejected() {
  local fake out status
  fake="$(make_fake_root)"
  out="$fake/output.txt"

  set +e
  bash "$SCRIPT" \
    --root "$fake" \
    --yes \
    --domain "203.0.113.10" \
    --password "test-password" \
    --port "9443" \
    --alpn $'h2,bad"alpn' \
    --no-color >"$out" 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "invalid ALPN should fail"
  assert_contains "$out" "ANYTLS_ALPN entries may contain only"
  assert_not_file "$fake/etc/sing-box/config.json"

  rm -rf "$fake"

  fake="$(make_fake_root)"
  out="$fake/output.txt"

  set +e
  bash "$SCRIPT" \
    --root "$fake" \
    --yes \
    --domain "203.0.113.10" \
    --password "test-password" \
    --port "9443" \
    --alpn "h2," \
    --no-color >"$out" 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "empty ALPN entry should fail"
  assert_contains "$out" "ANYTLS_ALPN entries must be non-empty."
  assert_not_file "$fake/etc/sing-box/config.json"

  rm -rf "$fake"
}
