assert_valid_scoped_ipv6_listen() {
  local fake out config
  fake="$(make_fake_root)"
  out="$fake/output.txt"

  ANYTLS_LISTEN='fe80::1%eth0' bash "$SCRIPT" \
    --root "$fake" \
    --yes \
    --domain "listen.example" \
    --password "test-password" \
    --port "9443" \
    --rules none \
    --no-color >"$out" 2>&1

  config="$fake/etc/sing-box/config.json"
  assert_file "$config"
  assert_json_valid "$config"
  assert_contains "$config" '"listen": "fe80::1%eth0"'
  assert_contains "$out" 'AnyTLS install files are ready.'

  rm -rf "$fake"
}
