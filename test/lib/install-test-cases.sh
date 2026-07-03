run_happy() {
  local fake out config exports
  fake="$(make_fake_root)"
  out="$fake/output.txt"
  mkdir -p "$fake/etc/anytls"
  printf 'existing cert\n' > "$fake/etc/anytls/server.crt"
  printf 'existing key\n' > "$fake/etc/anytls/server.key"
  chmod 0644 "$fake/etc/anytls/server.key"

  umask 022
  bash "$SCRIPT" \
    --root "$fake" \
    --non-interactive \
    --domain "203.0.113.10" \
    --password $'test pass@word/1\tquoted"slash\\' \
    --port "9443" \
    --alpn "h2,http/1.1" \
    --apply-swap \
    --rules block-cn,block-bt \
    --custom-rule-set openai \
    --custom-rule-set openai \
    --custom-rule-set tag=geosite-netflix,url=https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-netflix.srs,outbound=block,format=binary \
    --no-color >"$out" 2>&1

  config="$fake/etc/sing-box/config.json"
  exports="$fake/etc/anytls/exports"
  assert_file "$config"
  assert_json_valid "$config"
  assert_file "$fake/etc/systemd/system/sing-box-anytls.service"
  assert_file "$fake/etc/sysctl.d/99-anytls-tuning.conf"
  assert_file "$fake/etc/anytls/server.crt"
  assert_file "$fake/etc/anytls/server.key"
  assert_export_artifacts "$exports" "$fake"
  assert_mode "$config" 600
  assert_mode "$fake/etc/anytls/server.key" 600
  assert_file "$fake/etc/anytls/swap-plan.env"
  assert_file "$fake/etc/anytls/swap-apply-plan.sh"
  assert_mode "$fake/etc/anytls/swap-apply-plan.sh" 700

  assert_contains "$config" '"type": "anytls"'
  assert_contains "$config" '"listen_port": 9443'
  assert_contains "$config" '"password": "test pass@word/1\tquoted\"slash\\"'
  assert_contains "$config" '"certificate_path": "/etc/anytls/server.crt"'
  assert_contains "$config" '"key_path": "/etc/anytls/server.key"'
  assert_contains "$config" '"alpn": ['
  assert_contains "$config" '"h2"'
  assert_contains "$config" '"http/1.1"'
  assert_contains "$config" '"geoip-cn"'
  assert_contains "$config" '"geosite-geolocation-cn"'
  assert_contains "$config" '"geosite-bittorrent"'
  assert_contains "$config" '"protocol": ['
  assert_contains "$config" '"bittorrent"'
  assert_contains "$config" '"action": "reject"'
  assert_contains "$config" '"geosite-openai"'
  assert_contains "$config" '"geosite-netflix"'
  assert_occurrences "$config" '"geosite-openai"' 2
  assert_occurrences "$config" '"geosite-netflix"' 2
  if command -v sing-box >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    local check_config
    check_config="$fake/sing-box-check.json"
    python3 - "$config" "$check_config" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as source:
    config = json.load(source)
config["inbounds"][0]["tls"] = {"enabled": False}
with open(sys.argv[2], "w", encoding="utf-8") as target:
    json.dump(config, target)
PY
    sing-box check -c "$check_config" >/dev/null
  fi
  assert_contains "$fake/etc/sysctl.d/99-anytls-tuning.conf" 'net.ipv4.tcp_congestion_control = bbr'
  assert_contains "$fake/etc/sysctl.d/99-anytls-tuning.conf" 'net.core.default_qdisc = fq'
  assert_contains "$fake/etc/anytls/swap-plan.env" 'ACTION=recommended'
  assert_contains "$fake/etc/anytls/swap-apply-plan.sh" 'fallocate -l 1024M'
  assert_contains "$out" 'AnyTLS install files are ready.'

  rm -rf "$fake"

  assert_valid_scoped_ipv6_listen
  assert_ipv6_share_uri

  fake="$(make_fake_root)"
  out="$fake/output.txt"
  bash "$SCRIPT" \
    --root "$fake" \
    --yes \
    --domain "203.0.113.10" \
    --password "test-password" \
    --self-signed \
    --rules none \
    --no-color >"$out" 2>&1

  config="$fake/etc/sing-box/config.json"
  exports="$fake/etc/anytls/exports"
  assert_file "$config"
  assert_json_valid "$config"
  assert_contains "$config" '"listen_port": 443'
  assert_contains "$exports/share-link.txt" 'anytls://test-password@203.0.113.10:443'

  rm -rf "$fake"

  fake="$(make_fake_root)"
  out="$fake/output.txt"
  bash "$SCRIPT" \
    --root "$fake" \
    --yes \
    --domain "rules.example" \
    --password "test-password" \
    --port "9443" \
    --rules none \
    --custom-rule-set openai \
    --no-color >"$out" 2>&1

  config="$fake/etc/sing-box/config.json"
  assert_file "$config"
  assert_json_valid "$config"
  assert_not_contains "$config" '"geoip-cn"'
  assert_not_contains "$config" '"geosite-bittorrent"'
  assert_contains "$config" '"geosite-openai"'
  assert_contains "$fake/etc/anytls/swap-plan.env" 'ACTION=recommended'
  assert_contains "$fake/etc/anytls/swap-apply-plan.sh" 'fallocate -l 1024M'
  assert_contains "$out" 'Fake-root: would issue and install an ACME certificate with acme.sh.'
  assert_contains "$out" 'Swap not changed.'
  assert_contains "$out" 'AnyTLS install files are ready.'

  rm -rf "$fake"

  fake="$(make_fake_root)"
  out="$fake/output.txt"
  cat > "$fake/etc/os-release" <<'EOF'
ID=alpine
ID_LIKE=alpine
VERSION_ID=3.20
EOF
  bash "$SCRIPT" \
    --root "$fake" \
    --yes \
    --domain "alpine.example" \
    --password "test-password" \
    --port "9443" \
    --no-color >"$out" 2>&1

  assert_file "$fake/etc/init.d/sing-box-anytls"
  assert_contains "$fake/etc/init.d/sing-box-anytls" 'command=/usr/local/bin/sing-box'
  assert_contains "$out" 'Package manager: apk'

  rm -rf "$fake"
  printf 'PASS happy\n'
}

run_invalid() {
  local fake out status
  fake="$(make_fake_root)"
  out="$fake/output.txt"

  set +e
  bash "$SCRIPT" \
    --root "$fake" \
    --yes \
    --domain "203.0.113.10" \
    --password "test-password" \
    --port "70000" \
    --custom-rule-set bad/name \
    --no-color >"$out" 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "invalid input should fail"
  assert_contains "$out" 'ANYTLS_PORT must be an integer between 1 and 65535.'
  assert_not_file "$fake/etc/sing-box/config.json"
  assert_not_file "$fake/etc/systemd/system/sing-box-anytls.service"
  assert_not_file "$fake/etc/anytls/exports/share-link.txt"

  rm -rf "$fake"

  fake="$(make_fake_root)"
  out="$fake/output.txt"
  set +e
  ANYTLS_LISTEN=$'bad"listen' \
  bash "$SCRIPT" \
    --root "$fake" \
    --yes \
    --domain "203.0.113.10" \
    --password "test-password" \
    --port "9443" \
    --no-color >"$out" 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "invalid listen address should fail"
  assert_contains "$out" "Listen address must contain only"
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
    --custom-rule-set bad/name \
    --no-color >"$out" 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "invalid custom rule should fail"
  assert_contains "$out" "Custom rule_set/geosite name 'bad/name' is invalid."
  assert_not_file "$fake/etc/sing-box/config.json"
  assert_not_file "$fake/etc/systemd/system/sing-box-anytls.service"
  assert_not_file "$fake/etc/anytls/exports/share-link.txt"

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
    --custom-rule-set tag=bad,url=ftp://example.invalid/rule.srs,outbound=block,format=binary \
    --no-color >"$out" 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "invalid custom rule URL should fail"
  assert_contains "$out" "must start with https://"
  assert_not_file "$fake/etc/sing-box/config.json"

  rm -rf "$fake"

  assert_invalid_alpn_rejected

  fake="$(make_fake_root)"
  out="$fake/output.txt"
  set +e
  bash "$SCRIPT" \
    --root "$fake" \
    --yes \
    --domain "203.0.113.10" \
    --password "test-password" \
    --fingerprint $'bad"fp' \
    --no-color >"$out" 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "invalid fingerprint should fail"
  assert_contains "$out" "ANYTLS_FINGERPRINT may contain only"
  assert_not_file "$fake/etc/sing-box/config.json"

  rm -rf "$fake"

  out="$(mktemp "${TMPDIR:-/tmp}/anytls-invalid-acme.XXXXXX")"
  set +e
  bash "$SCRIPT" \
    --dry-run \
    --yes \
    --domain "203.0.113.10" \
    --password "test-password" \
    --no-color >"$out" 2>&1
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "ACME mode with an IP address should fail"
  assert_contains "$out" "ACME certificate mode requires a DNS name"
  rm -f "$out"

  printf 'PASS invalid\n'
}
