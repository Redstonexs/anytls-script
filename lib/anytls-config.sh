write_sysctl_config() {
  write_file "$(sysctl_file)" <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
EOF
}

apply_sysctl() {
  if [ -n "$ROOT_DIR" ] || [ "$DRY_RUN" -eq 1 ]; then
    return
  fi
  if command -v sysctl >/dev/null 2>&1; then
    sysctl --system >/dev/null || warn "sysctl --system failed; tuning file was still written."
  fi
}

safe_rule_set_json() {
  if [ "$BLOCK_CN" -ne 1 ] && [ "$BLOCK_BT" -ne 1 ]; then
    return
  fi

  local separator=""
  if [ "$BLOCK_CN" -eq 1 ]; then
    cat <<'EOF'
      {
        "type": "remote",
        "tag": "geoip-cn",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs"
      },
      {
        "type": "remote",
        "tag": "geosite-geolocation-cn",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs"
      }
EOF
    separator="      ,"
  fi

  if [ "$BLOCK_BT" -eq 1 ]; then
    printf '%s' "$separator"
    cat <<'EOF'
      {
        "type": "remote",
        "tag": "geosite-bittorrent",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-pt.srs"
      }
EOF
  fi
}

custom_rule_set_json() {
  if [ -z "$CUSTOM_RULE_SETS" ]; then
    return
  fi

  local old_ifs="$IFS"
  local record
  local separator=""
  while IFS= read -r record; do
    parse_custom_rule_spec "$record"
    local tag_escaped url_escaped format_escaped
    tag_escaped="$(json_escape "$CUSTOM_TAG")"
    url_escaped="$(json_escape "$CUSTOM_URL")"
    format_escaped="$(json_escape "$CUSTOM_FORMAT")"
    printf '%s' "$separator"
    cat <<EOF
      {
        "type": "remote",
        "tag": "${tag_escaped}",
        "format": "${format_escaped}",
        "url": "${url_escaped}"
      }
EOF
    separator="      ,"
  done < <(emit_custom_rule_records)
  IFS="$old_ifs"
}

route_rules_json() {
  cat <<'EOF'
      {
        "action": "sniff"
      }
EOF

  if [ "$BLOCK_BT" -eq 1 ]; then
    cat <<'EOF'
      ,
      {
        "protocol": [
          "bittorrent"
        ],
        "action": "reject"
      }
EOF
  fi

  if [ "$BLOCK_CN" -eq 1 ] || [ "$BLOCK_BT" -eq 1 ]; then
    local safe_sets=""
    if [ "$BLOCK_CN" -eq 1 ]; then
      safe_sets='          "geoip-cn",
          "geosite-geolocation-cn"'
    fi
    if [ "$BLOCK_BT" -eq 1 ]; then
      if [ -n "$safe_sets" ]; then
        safe_sets="${safe_sets},
          \"geosite-bittorrent\""
      else
        safe_sets='          "geosite-bittorrent"'
      fi
    fi
    cat <<EOF
      ,
      {
        "rule_set": [
${safe_sets}
        ],
        "action": "reject"
      }
EOF
  fi

  if [ -z "$CUSTOM_RULE_SETS" ]; then
    return
  fi
  local old_ifs="$IFS"
  local record action_json
  while IFS= read -r record; do
    parse_custom_rule_spec "$record"
    local tag_escaped
    tag_escaped="$(json_escape "$CUSTOM_TAG")"
    if [ "$CUSTOM_OUTBOUND" = "direct" ]; then
      action_json='"action": "route",
        "outbound": "direct"'
    else
      action_json='"action": "reject"'
    fi
    cat <<EOF
      ,
      {
        "rule_set": [
          "${tag_escaped}"
        ],
        ${action_json}
      }
EOF
  done < <(emit_custom_rule_records)
  IFS="$old_ifs"
}

route_rule_sets_json() {
  local wrote=0
  if [ "$BLOCK_CN" -eq 1 ] || [ "$BLOCK_BT" -eq 1 ]; then
    safe_rule_set_json
    wrote=1
  fi

  if [ -n "$CUSTOM_RULE_SETS" ]; then
    if [ "$wrote" -eq 1 ]; then
      printf '      ,\n'
    fi
    custom_rule_set_json
  fi
}

write_sing_box_config() {
  local listen_escaped name_escaped password_escaped host_escaped cert_escaped key_escaped
  listen_escaped="$(json_escape "$LISTEN_ADDRESS")"
  name_escaped="$(json_escape "$SERVER_NAME")"
  password_escaped="$(json_escape "$PASSWORD")"
  host_escaped="$(json_escape "$SERVER_HOST")"
  cert_escaped="$(json_escape "$TLS_CERT_PATH")"
  key_escaped="$(json_escape "$TLS_KEY_PATH")"

  write_secret_file "$(config_dir)/config.json" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "${listen_escaped}",
      "listen_port": ${SERVER_PORT},
      "users": [
        {
          "name": "${name_escaped}",
          "password": "${password_escaped}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${host_escaped}",
        "certificate_path": "${cert_escaped}",
        "key_path": "${key_escaped}"$(tls_alpn_json)
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
$(route_rules_json)
      ,
      {
        "action": "route",
        "outbound": "direct"
      }
    ],
    "rule_set": [
$(route_rule_sets_json)
    ]
  },
  "experimental": {
    "cache_file": {
      "enabled": true
    }
  }
}
EOF
}

read_existing_config_password() {
  local config value
  config="$(config_dir)/config.json"
  [ -f "$config" ] || return 1

  value="$(awk '
    /"users"[[:space:]]*:/ { in_users = 1 }
    in_users && /"password"[[:space:]]*:/ {
      line = $0
      sub(/^[^:]*:[[:space:]]*"/, "", line)
      sub(/",?[[:space:]]*$/, "", line)
      print line
      exit
    }
  ' "$config")"
  [ -n "$value" ] || return 1
  json_unescape_simple "$value"
}

write_password_state() {
  printf '%s' "$PASSWORD" | write_secret_file "$(password_file)"
}
