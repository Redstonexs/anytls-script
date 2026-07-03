print_intro() {
  cat <<EOF
AnyTLS Linux Installer
======================
Target:
  OS: ${OS_ID} ${OS_VERSION} (${OS_LIKE:-no ID_LIKE})
  Arch: ${ARCH}
  Package manager: ${PKG_MANAGER}

This guided installer will:
  1. Prepare sing-box AnyTLS server configuration.
  2. Enable BBR and conservative TCP connection tuning.
  3. Check swap and offer a one-key swap plan when the host has none.
  4. Configure safe outbound rules: reject CN geoip/geosite and BitTorrent.
  5. Issue or reuse TLS assets.
  6. Export sing-box, Clash Verge, and v2RayN import artifacts.
EOF
}

print_dry_run_plan() {
  local mem_mib swap_mib recommend_mib tls_detail
  mem_mib="$(memory_total_mib)"
  swap_mib="$(swap_total_mib)"
  recommend_mib="$(recommended_swap_mib "$mem_mib")"
  if tls_assets_exist; then
    tls_detail="  Existing certificate/key: yes; installer will reuse them."
  elif [ "$TLS_MODE" = "acme" ]; then
    tls_detail="  ACME server: ${ACME_SERVER}
  ACME note: ${SERVER_HOST} must resolve to this VPS and TCP port 80 must be free during issuance."
  else
    tls_detail="  Self-signed: explicitly requested; ACME issuance will not be attempted."
  fi

  cat <<EOF

Dry-run plan, no privileged writes will be made.

Distro and dependency detection
  Package manager: ${PKG_MANAGER}
  Suggested dependency command: ${INSTALL_CMD}

BBR and connection tuning
  Write: $(sysctl_file)
  Enable: net.ipv4.tcp_congestion_control=bbr, net.core.default_qdisc=fq

TLS assets
  Mode: ${TLS_MODE}
  Certificate: ${TLS_CERT_PATH}
  Private key: ${TLS_KEY_PATH}
${tls_detail}

Swap advisory
  Memory: ${mem_mib} MiB
  Active swap: ${swap_mib} MiB
  Recommended new swap: ${recommend_mib} MiB
  One-key apply: rerun with --apply-swap --yes

Rules and exports
  Rule profile: ${INSTALL_RULE_PROFILE}
  Listen address: ${LISTEN_ADDRESS}
  Listen port: ${SERVER_PORT}
  Built-in blocks: geoip-cn, geosite-geolocation-cn, geosite-bittorrent, protocol=bittorrent
  Custom rule sets: ${CUSTOM_RULE_SETS:-none}
  DNS strategy: ${DNS_STRATEGY}
  ALPN: ${ALPN:-none}
  Fingerprint: ${TLS_FINGERPRINT:-none}
  Export directory: $(exports_dir)
  v2RayN import: $(exports_dir)/v2rayn-share.txt uses v2rayn://anytls/<base64url-json>
  Generic share URI: anytls://<password>@${SERVER_HOST}:${SERVER_PORT}?idle_session_check_interval=30s&idle_session_timeout=30s&min_idle_session=5&insecure=0&security=tls&sni=${SERVER_HOST}$(fingerprint_query_param)$(alpn_query_param)
  Clash Verge Rev: clash-verge.yaml; sing-box-client.json is also exported
EOF
}

ensure_password() {
  local existing
  if [ -n "$PASSWORD" ]; then
    return
  fi

  if [ -f "$(password_file)" ]; then
    existing="$(cat "$(password_file)")"
    if [ -n "$existing" ]; then
      PASSWORD="$existing"
      return
    fi
    warn "$(password_file) is empty; generating a new AnyTLS password."
  fi

  if existing="$(read_existing_config_password)"; then
    PASSWORD="$existing"
    return
  fi

  PASSWORD="$(random_password)"
}

run_install() {
  validate_inputs
  detect_os
  detect_pkg_manager
  detect_public_host
  validate_certificate_host
  ensure_password

  print_intro

  if [ "$DRY_RUN" -eq 1 ]; then
    print_dry_run_plan
    return
  fi

  if [ "$ASSUME_YES" -ne 1 ]; then
    confirm "Install AnyTLS with the settings above?" "yes" || die "Install cancelled."
  fi

  install_sing_box_binary
  write_sysctl_config
  apply_sysctl
  write_tls_assets
  write_sing_box_config
  write_password_state
  write_service
  write_swap_plan
  export_profiles
  apply_service

  ok "AnyTLS install files are ready."
  ok "Server config: $(config_dir)/config.json"
  ok "Exports: $(exports_dir)"
  printf '%s\n' "Share link:"
  cat "$(exports_dir)/share-link.txt"
  printf '\n%s\n' "v2RayN import:"
  cat "$(exports_dir)/v2rayn-share.txt"
}

main() {
  parse_args "$@"
  set_colors
  run_install
}
