v2rayn_anytls_json() {
  local allow_insecure="$1"
  local host_escaped name_escaped password_escaped fingerprint_json cert_json cert_value
  host_escaped="$(json_escape "$SERVER_HOST")"
  name_escaped="$(json_escape "$SERVER_NAME")"
  password_escaped="$(json_escape "$PASSWORD")"
  fingerprint_json=""
  cert_json=""

  if [ -n "$TLS_FINGERPRINT" ]; then
    fingerprint_json=",\"Fingerprint\":\"$(json_escape "$TLS_FINGERPRINT")\""
  fi
  cert_value="$(certificate_pem_json_value)"
  if [ -n "$cert_value" ]; then
    cert_json=",\"Cert\":\"${cert_value}\""
  fi

  printf '{"ConfigType":11,"CoreType":24,"ConfigVersion":4,"Remarks":"%s","Address":"%s","Port":%s,"Password":"%s","StreamSecurity":"tls","AllowInsecure":"%s","Sni":"%s"%s%s}' \
    "$name_escaped" \
    "$host_escaped" \
    "$SERVER_PORT" \
    "$password_escaped" \
    "$allow_insecure" \
    "$host_escaped" \
    "$fingerprint_json" \
    "$cert_json"
}

v2rayn_anytls_link() {
  local allow_insecure="$1"
  printf 'v2rayn://anytls/%s' "$(v2rayn_anytls_json "$allow_insecure" | base64_url_encode)"
}

sing_box_client_cert_pin_json() {
  local public_key
  public_key="$(certificate_public_key_sha256_base64)"
  [ -n "$public_key" ] || return 0
  printf '        "certificate_public_key_sha256": [\n'
  printf '          "%s"\n' "$(json_escape "$public_key")"
  printf '        ],\n'
}

sing_box_client_utls_json() {
  [ -n "$TLS_FINGERPRINT" ] || return 0
  printf ',\n        "utls": {\n'
  printf '          "enabled": true,\n'
  printf '          "fingerprint": "%s"\n' "$(json_escape "$TLS_FINGERPRINT")"
  printf '        }'
}

clash_cert_fingerprint_yaml() {
  local fingerprint
  fingerprint="$(certificate_sha256_fingerprint)"
  [ -n "$fingerprint" ] || return 0
  printf '    fingerprint: "%s"\n' "$fingerprint"
}

clash_client_fingerprint_yaml() {
  [ -n "$TLS_FINGERPRINT" ] || return 0
  printf '    client-fingerprint: "%s"\n' "$(json_escape "$TLS_FINGERPRINT")"
}

export_profiles() {
  local exports
  exports="$(exports_dir)"
  mkdir -p "$exports"

  local link v2rayn_link v2rayn_insecure_link password_encoded name_encoded host_encoded host_authority host_escaped name_escaped password_escaped
  password_encoded="$(url_encode "$PASSWORD")"
  name_encoded="$(url_encode "$SERVER_NAME")"
  host_encoded="$(url_encode "$SERVER_HOST")"
  host_authority="$(uri_host_authority "$SERVER_HOST")"
  host_escaped="$(json_escape "$SERVER_HOST")"
  name_escaped="$(json_escape "$SERVER_NAME")"
  password_escaped="$(json_escape "$PASSWORD")"
  link="anytls://${password_encoded}@${host_authority}:${SERVER_PORT}?idle_session_check_interval=30s&idle_session_timeout=30s&min_idle_session=5&insecure=0&security=tls&sni=${host_encoded}$(certificate_pem_query_param)$(fingerprint_query_param)$(alpn_query_param)#${name_encoded}"
  v2rayn_link="$(v2rayn_anytls_link false)"
  v2rayn_insecure_link="$(v2rayn_anytls_link true)"

  write_secret_file "$exports/share-link.txt" <<EOF
${link}
EOF

  write_secret_file "$exports/anytls-uri.txt" <<EOF
${link}
EOF

  write_secret_file "$exports/sing-box-client.json" <<EOF
{
  "outbounds": [
    {
      "type": "anytls",
      "tag": "anytls-out",
      "server": "${host_escaped}",
      "server_port": ${SERVER_PORT},
      "password": "${password_escaped}",
      "idle_session_check_interval": "30s",
      "idle_session_timeout": "30s",
      "min_idle_session": 5,
      "tls": {
        "enabled": true,
$(sing_box_client_cert_pin_json)        "server_name": "${host_escaped}"$(sing_box_client_utls_json)$(tls_alpn_json)
      }
    }
  ]
}
EOF

  write_secret_file "$exports/clash-verge.yaml" <<EOF
proxies:
  - name: "${name_escaped}"
    type: anytls
    server: "${host_escaped}"
    port: ${SERVER_PORT}
    password: "${password_escaped}"
$(clash_client_fingerprint_yaml)
    udp: true
    idle-session-check-interval: 30
    idle-session-timeout: 30
    tls: true
    sni: "${host_escaped}"
    skip-cert-verify: false
$(clash_cert_fingerprint_yaml)
$(clash_alpn_yaml)
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - "${name_escaped}"
rules:
  - MATCH,Proxy
EOF

  write_secret_file "$exports/v2rayn-share.txt" <<EOF
${v2rayn_link}
EOF

  write_secret_file "$exports/v2rayn-insecure-share.txt" <<EOF
${v2rayn_insecure_link}
EOF

  write_secret_file "$exports/subscription.txt" <<EOF
${link}
v2rayn: ${exports}/v2rayn-share.txt
v2rayn-insecure: ${exports}/v2rayn-insecure-share.txt
sing-box-client: ${exports}/sing-box-client.json
EOF
}

write_swap_apply_script() {
  local size_mib="$1"
  local path quoted_path
  path="$(swap_file)"
  quoted_path="$(shell_quote "$path")"
  write_executable_file "$(state_dir)/swap-apply-plan.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
fallocate -l ${size_mib}M ${quoted_path}
chmod 600 ${quoted_path}
mkswap ${quoted_path}
swapon ${quoted_path}
EOF
}

write_swap_plan() {
  local mem_mib swap_mib recommend_mib action
  mem_mib="$(memory_total_mib)"
  swap_mib="$(swap_total_mib)"
  recommend_mib="$(recommended_swap_mib "$mem_mib")"
  action="none"

  if [ "$swap_mib" -eq 0 ] && [ "$recommend_mib" -gt 0 ]; then
    action="recommended"
    if [ -z "$SWAP_SIZE_MIB" ]; then
      SWAP_SIZE_MIB="$recommend_mib"
    fi
    write_swap_apply_script "$SWAP_SIZE_MIB"
  fi

  mkdir -p "$(state_dir)"
  write_file "$(state_dir)/swap-plan.env" <<EOF
MEMORY_MIB=${mem_mib}
SWAP_MIB=${swap_mib}
RECOMMENDED_SWAP_MIB=${recommend_mib}
ACTION=${action}
SWAP_FILE=$(swap_file)
EOF

  if [ "$swap_mib" -eq 0 ] && [ "$recommend_mib" -gt 0 ]; then
    warn "No active swap detected. Recommended swap: ${SWAP_SIZE_MIB} MiB for ${mem_mib} MiB RAM."
    if [ "$ENABLE_SWAP" = "yes" ]; then
      create_swap "$SWAP_SIZE_MIB"
    elif [ "$ENABLE_SWAP" = "ask" ] && [ "$ASSUME_YES" -eq 0 ] && confirm "Create and enable ${SWAP_SIZE_MIB} MiB swap now?" "no"; then
      create_swap "$SWAP_SIZE_MIB"
    else
      info "Swap not changed. One-key plan: $(state_dir)/swap-apply-plan.sh or rerun with --apply-swap."
    fi
  else
    ok "Swap check: ${swap_mib} MiB active; no new swap needed."
  fi
}

create_swap() {
  local size_mib="$1"
  local path
  path="$(swap_file)"
  if [ -n "$ROOT_DIR" ] || [ "$DRY_RUN" -eq 1 ]; then
    write_swap_apply_script "$size_mib"
    return
  fi
  if [ -e "$path" ]; then
    warn "$path already exists; leaving it unchanged."
    return
  fi
  fallocate -l "${size_mib}M" "$path"
  chmod 600 "$path"
  mkswap "$path" >/dev/null
  swapon "$path"
  if ! grep -q "^${path} " /etc/fstab; then
    printf '%s none swap sw 0 0\n' "$path" >> /etc/fstab
  fi
}
