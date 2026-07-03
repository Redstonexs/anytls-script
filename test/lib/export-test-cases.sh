assert_v2rayn_anytls_profile() {
  local file="$1"
  local expected_allow_insecure="$2"
  local expected_host="$3"
  local expected_port="$4"
  local expected_password="$5"
  local expected_fingerprint="$6"
  local cert_contains="${7:-}"

  python3 - "$file" "$expected_allow_insecure" "$expected_host" "$expected_port" "$expected_password" "$expected_fingerprint" "$cert_contains" <<'PY'
import base64
import json
import pathlib
import sys

file, expected_allow, expected_host, expected_port, expected_password, expected_fp, cert_contains = sys.argv[1:]
uri = pathlib.Path(file).read_text(encoding="utf-8").strip()
prefix = "v2rayn://anytls/"
if not uri.startswith(prefix):
    raise SystemExit(f"expected v2rayn anytls URI, got: {uri[:80]}")
payload = uri[len(prefix):]
payload += "=" * (-len(payload) % 4)
profile = json.loads(base64.urlsafe_b64decode(payload).decode("utf-8"))

expected = {
    "ConfigType": 11,
    "CoreType": 24,
    "ConfigVersion": 4,
    "Address": expected_host,
    "Port": int(expected_port),
    "Password": expected_password,
    "StreamSecurity": "tls",
    "AllowInsecure": expected_allow,
    "Sni": expected_host,
}
for key, value in expected.items():
    if profile.get(key) != value:
        raise SystemExit(f"{key}: expected {value!r}, got {profile.get(key)!r}")
if expected_fp:
    if profile.get("Fingerprint") != expected_fp:
        raise SystemExit(f"Fingerprint: expected {expected_fp!r}, got {profile.get('Fingerprint')!r}")
elif "Fingerprint" in profile:
    raise SystemExit("unexpected Fingerprint field")
if cert_contains:
    cert = profile.get("Cert", "")
    if cert_contains not in cert:
        raise SystemExit("expected embedded certificate in v2rayN profile")
if "Alpn" in profile:
    raise SystemExit("v2RayN AnyTLS profile should follow fscarmen format without Alpn")
PY
}

assert_export_artifacts() {
  local exports="$1"
  local root="$2"

  assert_file "$exports/share-link.txt"
  assert_file "$exports/anytls-uri.txt"
  assert_file "$exports/sing-box-client.json"
  assert_file "$exports/clash-verge.yaml"
  assert_file "$exports/v2rayn-share.txt"
  assert_file "$exports/v2rayn-insecure-share.txt"
  assert_file "$exports/subscription.txt"
  assert_json_valid "$exports/sing-box-client.json"
  assert_mode "$exports/share-link.txt" 600
  assert_mode "$exports/anytls-uri.txt" 600
  assert_mode "$exports/sing-box-client.json" 600
  assert_mode "$exports/v2rayn-insecure-share.txt" 600
  assert_mode "$exports/subscription.txt" 600

  assert_contains "$exports/share-link.txt" 'anytls://test%20pass%40word%2F1%09quoted%22slash%5C@203.0.113.10:9443'
  assert_contains "$exports/share-link.txt" 'idle_session_check_interval=30s'
  assert_contains "$exports/share-link.txt" 'idle_session_timeout=30s'
  assert_contains "$exports/share-link.txt" 'min_idle_session=5'
  assert_not_contains "$exports/share-link.txt" 'tls_certificate='
  assert_contains "$exports/share-link.txt" 'alpn=h2%2Chttp%2F1.1'
  assert_contains "$exports/share-link.txt" 'fp=chrome'
  assert_contains "$exports/anytls-uri.txt" 'alpn=h2%2Chttp%2F1.1'
  assert_v2rayn_anytls_profile "$exports/v2rayn-share.txt" false "203.0.113.10" 9443 $'test pass@word/1\tquoted"slash\\' chrome
  assert_not_contains "$exports/v2rayn-share.txt" 'insecure=1'
  assert_not_contains "$exports/v2rayn-share.txt" 'type=tcp'
  assert_not_contains "$exports/v2rayn-share.txt" 'headerType=none'
  assert_v2rayn_anytls_profile "$exports/v2rayn-insecure-share.txt" true "203.0.113.10" 9443 $'test pass@word/1\tquoted"slash\\' chrome
  assert_contains "$exports/sing-box-client.json" '"type": "anytls"'
  assert_contains "$exports/sing-box-client.json" '"idle_session_check_interval": "30s"'
  assert_contains "$exports/sing-box-client.json" '"idle_session_timeout": "30s"'
  assert_contains "$exports/sing-box-client.json" '"min_idle_session": 5'
  assert_contains "$exports/sing-box-client.json" '"utls": {'
  assert_contains "$exports/sing-box-client.json" '"fingerprint": "chrome"'
  assert_contains "$exports/sing-box-client.json" '"alpn": ['
  assert_contains "$exports/sing-box-client.json" '"h2"'
  assert_contains "$exports/sing-box-client.json" '"http/1.1"'
  assert_contains "$exports/clash-verge.yaml" 'type: anytls'
  assert_contains "$exports/clash-verge.yaml" 'client-fingerprint: "chrome"'
  assert_contains "$exports/clash-verge.yaml" 'udp: true'
  assert_contains "$exports/clash-verge.yaml" 'idle-session-check-interval: 30'
  assert_contains "$exports/clash-verge.yaml" 'idle-session-timeout: 30'
  assert_contains "$exports/clash-verge.yaml" 'skip-cert-verify: false'
  assert_contains "$exports/clash-verge.yaml" 'alpn:'
  assert_contains "$exports/clash-verge.yaml" 'proxy-groups:'
  assert_not_contains "$exports/clash-verge.yaml" '"http/1.1"proxy-groups:'
  assert_contains "$exports/v2rayn-share.txt" 'v2rayn://anytls/'
  assert_contains "$exports/subscription.txt" 'anytls://'
  assert_contains "$exports/subscription.txt" "v2rayn: ${root}/etc/anytls/exports/v2rayn-share.txt"
  assert_contains "$exports/subscription.txt" "v2rayn-insecure: ${root}/etc/anytls/exports/v2rayn-insecure-share.txt"
  assert_contains "$exports/subscription.txt" "sing-box-client: ${root}/etc/anytls/exports/sing-box-client.json"
}

assert_ipv6_share_uri() {
  local fake out exports
  fake="$(make_fake_root)"
  out="$fake/output.txt"

  bash "$SCRIPT" \
    --root "$fake" \
    --yes \
    --domain "2001:db8::1" \
    --password "test-password" \
    --port "9443" \
    --self-signed \
    --rules none \
    --no-color >"$out" 2>&1

  exports="$fake/etc/anytls/exports"
  assert_file "$exports/share-link.txt"
  assert_contains "$exports/share-link.txt" 'anytls://test-password@[2001:db8::1]:9443'
  assert_not_contains "$exports/share-link.txt" 'alpn='
  assert_contains "$exports/share-link.txt" 'fp=chrome'
  assert_contains "$exports/share-link.txt" 'sni=2001%3Adb8%3A%3A1'
  assert_v2rayn_anytls_profile "$exports/v2rayn-share.txt" false "2001:db8::1" 9443 "test-password" chrome
  assert_contains "$exports/subscription.txt" "sing-box-client: ${fake}/etc/anytls/exports/sing-box-client.json"

  rm -rf "$fake"
}

assert_valid_certificate_exports() {
  command -v openssl >/dev/null 2>&1 || return 0

  local fake out exports
  fake="$(make_fake_root)"
  out="$fake/output.txt"
  mkdir -p "$fake/etc/anytls"
  openssl req -x509 -newkey rsa:2048 -sha256 -days 1 -nodes \
    -keyout "$fake/etc/anytls/server.key" \
    -out "$fake/etc/anytls/server.crt" \
    -subj "/CN=cert.example" >/dev/null 2>&1

  bash "$SCRIPT" \
    --root "$fake" \
    --yes \
    --domain "cert.example" \
    --password "test-password" \
    --rules none \
    --no-color >"$out" 2>&1

  exports="$fake/etc/anytls/exports"
  assert_contains "$exports/share-link.txt" 'tls_certificate='
  assert_contains "$exports/share-link.txt" 'BEGIN%20CERTIFICATE'
  assert_contains "$exports/sing-box-client.json" '"certificate_public_key_sha256": ['
  assert_contains "$exports/clash-verge.yaml" 'fingerprint: "'
  assert_v2rayn_anytls_profile "$exports/v2rayn-share.txt" false "cert.example" 443 "test-password" chrome "BEGIN CERTIFICATE"

  rm -rf "$fake"
}

assert_empty_fingerprint_override() {
  local fake out exports
  fake="$(make_fake_root)"
  out="$fake/output.txt"

  ANYTLS_FINGERPRINT= \
  bash "$SCRIPT" \
    --root "$fake" \
    --yes \
    --domain "nofp.example" \
    --password "test-password" \
    --rules none \
    --no-color >"$out" 2>&1

  exports="$fake/etc/anytls/exports"
  assert_not_contains "$exports/share-link.txt" 'fp='
  assert_not_contains "$exports/sing-box-client.json" '"utls": {'
  assert_not_contains "$exports/clash-verge.yaml" 'client-fingerprint:'
  assert_v2rayn_anytls_profile "$exports/v2rayn-share.txt" false "nofp.example" 443 "test-password" ""

  rm -rf "$fake"
}

assert_combined_pem_does_not_export_private_key() {
  command -v openssl >/dev/null 2>&1 || return 0

  local fake out exports decoded_cert
  fake="$(make_fake_root)"
  out="$fake/output.txt"
  mkdir -p "$fake/etc/anytls"
  openssl req -x509 -newkey rsa:2048 -sha256 -days 1 -nodes \
    -keyout "$fake/etc/anytls/server.key" \
    -out "$fake/etc/anytls/server.crt" \
    -subj "/CN=combined.example" >/dev/null 2>&1
  cat "$fake/etc/anytls/server.key" >> "$fake/etc/anytls/server.crt"

  bash "$SCRIPT" \
    --root "$fake" \
    --yes \
    --domain "combined.example" \
    --password "test-password" \
    --rules none \
    --no-color >"$out" 2>&1

  exports="$fake/etc/anytls/exports"
  assert_not_contains "$exports/share-link.txt" 'PRIVATE'
  assert_not_contains "$exports/anytls-uri.txt" 'PRIVATE'
  assert_not_contains "$exports/sing-box-client.json" 'PRIVATE'
  assert_not_contains "$exports/clash-verge.yaml" 'PRIVATE'
  decoded_cert="$(
    python3 - "$exports/v2rayn-share.txt" <<'PY'
import base64
import json
import pathlib
import sys

uri = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").strip()
payload = uri.removeprefix("v2rayn://anytls/")
payload += "=" * (-len(payload) % 4)
print(json.loads(base64.urlsafe_b64decode(payload).decode("utf-8")).get("Cert", ""))
PY
  )"
  case "$decoded_cert" in
    *"BEGIN CERTIFICATE"* ) ;;
    * ) fail "expected v2RayN Cert to include the certificate block" ;;
  esac
  case "$decoded_cert" in
    *"PRIVATE KEY"* ) fail "v2RayN Cert must not include private-key material" ;;
  esac

  rm -rf "$fake"
}
