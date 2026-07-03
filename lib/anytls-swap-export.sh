export_profiles() {
  local exports
  exports="$(exports_dir)"
  mkdir -p "$exports"

  local link password_encoded name_encoded host_encoded host_authority host_escaped name_escaped password_escaped
  password_encoded="$(url_encode "$PASSWORD")"
  name_encoded="$(url_encode "$SERVER_NAME")"
  host_encoded="$(url_encode "$SERVER_HOST")"
  host_authority="$(uri_host_authority "$SERVER_HOST")"
  host_escaped="$(json_escape "$SERVER_HOST")"
  name_escaped="$(json_escape "$SERVER_NAME")"
  password_escaped="$(json_escape "$PASSWORD")"
  link="anytls://${password_encoded}@${host_authority}:${SERVER_PORT}?security=tls&sni=${host_encoded}$(fingerprint_query_param)$(alpn_query_param)#${name_encoded}"

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
      "tls": {
        "enabled": true,
        "server_name": "${host_escaped}"$(tls_alpn_json)
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
    tls: true
    sni: "${host_escaped}"
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
${link}
EOF

  write_secret_file "$exports/subscription.txt" <<EOF
${link}
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
