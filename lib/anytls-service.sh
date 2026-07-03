write_service() {
  write_file "$(service_file)" <<EOF
[Unit]
Description=sing-box AnyTLS service
Documentation=https://sing-box.sagernet.org/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${SING_BOX_EXEC} run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  if [ "$PKG_MANAGER" = "apk" ]; then
    local openrc_command
    openrc_command="$(shell_quote "$SING_BOX_EXEC")"
    write_executable_file "$(openrc_service_file)" <<EOF
#!/sbin/openrc-run
name="sing-box AnyTLS"
command=${openrc_command}
command_args="run -c /etc/sing-box/config.json"
command_background="yes"
pidfile="/run/sing-box-anytls.pid"
depend() {
  need net
}
EOF
  fi
}

write_tls_assets() {
  local cert_target key_target
  cert_target="$(root_path "$TLS_CERT_PATH")"
  key_target="$(root_path "$TLS_KEY_PATH")"

  if [ -f "$cert_target" ] && [ -f "$key_target" ]; then
    chmod 600 "$key_target"
    ok "TLS certificate and key already exist."
    return
  fi

  ensure_parent "$cert_target"
  ensure_parent "$key_target"

  if [ -n "$ROOT_DIR" ]; then
    write_file "$cert_target" <<'EOF'
-----BEGIN CERTIFICATE-----
test anytls certificate
-----END CERTIFICATE-----
EOF
    write_secret_file "$key_target" <<'EOF'
-----BEGIN PRIVATE KEY-----
test anytls private key
-----END PRIVATE KEY-----
EOF
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    info "Dry-run: would create TLS certificate at ${TLS_CERT_PATH} and key at ${TLS_KEY_PATH}."
    return
  fi

  if ! command -v openssl >/dev/null 2>&1; then
    die "openssl is required to create TLS assets. Install openssl or set ANYTLS_TLS_CERT and ANYTLS_TLS_KEY to existing files."
  fi

  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$key_target" \
    -out "$cert_target" \
    -subj "/CN=${SERVER_HOST}" >/dev/null 2>&1
  chmod 600 "$key_target"
}
