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
  assert_contains "$exports/share-link.txt" 'alpn=h2%2Chttp%2F1.1'
  assert_contains "$exports/share-link.txt" 'fp=chrome'
  assert_contains "$exports/anytls-uri.txt" 'alpn=h2%2Chttp%2F1.1'
  assert_contains "$exports/v2rayn-share.txt" 'alpn=h2%2Chttp%2F1.1'
  assert_contains "$exports/v2rayn-share.txt" 'fp=chrome'
  assert_not_contains "$exports/v2rayn-share.txt" 'insecure=1'
  assert_contains "$exports/v2rayn-insecure-share.txt" 'insecure=1'
  assert_contains "$exports/v2rayn-insecure-share.txt" 'allowInsecure=1'
  assert_contains "$exports/sing-box-client.json" '"type": "anytls"'
  assert_contains "$exports/sing-box-client.json" '"alpn": ['
  assert_contains "$exports/sing-box-client.json" '"h2"'
  assert_contains "$exports/sing-box-client.json" '"http/1.1"'
  assert_contains "$exports/clash-verge.yaml" 'type: anytls'
  assert_contains "$exports/clash-verge.yaml" 'alpn:'
  assert_contains "$exports/clash-verge.yaml" 'proxy-groups:'
  assert_not_contains "$exports/clash-verge.yaml" '"http/1.1"proxy-groups:'
  assert_contains "$exports/v2rayn-share.txt" 'anytls://'
  assert_contains "$exports/subscription.txt" 'anytls://'
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
  assert_contains "$exports/share-link.txt" 'alpn=h2%2Chttp%2F1.1'
  assert_contains "$exports/share-link.txt" 'fp=chrome'
  assert_contains "$exports/share-link.txt" 'sni=2001%3Adb8%3A%3A1'
  assert_contains "$exports/subscription.txt" "sing-box-client: ${fake}/etc/anytls/exports/sing-box-client.json"

  rm -rf "$fake"
}
