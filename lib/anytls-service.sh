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
    if [ "$TLS_MODE" = "self-signed" ]; then
      info "Fake-root: would create a self-signed TLS certificate."
    else
      info "Fake-root: would issue and install an ACME certificate with acme.sh."
    fi
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
    if [ "$TLS_MODE" = "self-signed" ]; then
      info "Dry-run: would create a self-signed TLS certificate at ${TLS_CERT_PATH} and key at ${TLS_KEY_PATH}."
    else
      info "Dry-run: would issue ${SERVER_HOST} with acme.sh standalone mode and install fullchain/key to ${TLS_CERT_PATH} and ${TLS_KEY_PATH}."
    fi
    return
  fi

  if [ "$TLS_MODE" = "acme" ]; then
    issue_acme_certificate "$cert_target" "$key_target"
    return
  fi

  create_self_signed_certificate "$cert_target" "$key_target"
}

acme_sh_command() {
  if command -v acme.sh >/dev/null 2>&1; then
    command -v acme.sh
    return 0
  fi
  if [ -x "$ACME_HOME/acme.sh" ]; then
    printf '%s\n' "$ACME_HOME/acme.sh"
    return 0
  fi
  return 1
}

install_acme_sh() {
  if acme_sh_command >/dev/null 2>&1; then
    return
  fi
  if ! command -v curl >/dev/null 2>&1; then
    die "curl is required to install acme.sh. Re-run install.sh or install curl manually."
  fi

  info "Installing acme.sh for automatic certificate issuance and renewal."
  curl -fsSL https://get.acme.sh | sh
  if ! acme_sh_command >/dev/null 2>&1; then
    die "acme.sh installation finished but ${ACME_HOME}/acme.sh was not found."
  fi
}

issue_acme_certificate() {
  local cert_target="$1"
  local key_target="$2"
  local acme reload_cmd

  validate_certificate_host
  if ! command -v socat >/dev/null 2>&1; then
    die "socat is required for acme.sh standalone certificate issuance. Re-run install.sh or install socat manually."
  fi

  install_acme_sh
  acme="$(acme_sh_command)" || die "acme.sh command was not found."

  info "Issuing ACME certificate for ${SERVER_HOST}. Make sure DNS resolves here and TCP port 80 is reachable."
  if ! "$acme" --issue --standalone -d "$SERVER_HOST" --server "$ACME_SERVER"; then
    warn "acme.sh did not issue a new certificate; trying to install any existing certificate for ${SERVER_HOST}."
  fi

  reload_cmd="systemctl restart sing-box-anytls.service >/dev/null 2>&1 || rc-service sing-box-anytls restart >/dev/null 2>&1 || true"
  "$acme" --install-cert -d "$SERVER_HOST" \
    --key-file "$key_target" \
    --fullchain-file "$cert_target" \
    --reloadcmd "$reload_cmd"
  chmod 600 "$key_target"
  ok "ACME certificate installed. acme.sh will renew it and rerun the service reload command."
}

create_self_signed_certificate() {
  local cert_target="$1"
  local key_target="$2"

  if ! command -v openssl >/dev/null 2>&1; then
    die "openssl is required to create a self-signed certificate. Install openssl or use the default ACME mode with a valid domain."
  fi

  warn "Creating a self-signed certificate because --self-signed was explicitly requested."
  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$key_target" \
    -out "$cert_target" \
    -subj "/CN=${SERVER_HOST}" >/dev/null 2>&1
  chmod 600 "$key_target"
}
