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
  5. Export sing-box, Clash Verge, and v2RayN import artifacts.
EOF
}

print_dry_run_plan() {
  local mem_mib swap_mib recommend_mib
  mem_mib="$(memory_total_mib)"
  swap_mib="$(swap_total_mib)"
  recommend_mib="$(recommended_swap_mib "$mem_mib")"

  cat <<EOF

Dry-run plan, no privileged writes will be made.

Distro and dependency detection
  Package manager: ${PKG_MANAGER}
  Suggested dependency command: ${INSTALL_CMD}

BBR and connection tuning
  Write: $(sysctl_file)
  Enable: net.ipv4.tcp_congestion_control=bbr, net.core.default_qdisc=fq

TLS assets
  Certificate: ${TLS_CERT_PATH}
  Private key: ${TLS_KEY_PATH}

Swap advisory
  Memory: ${mem_mib} MiB
  Active swap: ${swap_mib} MiB
  Recommended new swap: ${recommend_mib} MiB
  One-key apply: rerun with --apply-swap --yes

Rules and exports
  Rule profile: ${INSTALL_RULE_PROFILE}
  Built-in blocks: geoip-cn, geosite-geolocation-cn, geosite-bittorrent, protocol=bittorrent
  Custom rule sets: ${CUSTOM_RULE_SETS:-none}
  ALPN: ${ALPN:-none}
  Fingerprint: ${TLS_FINGERPRINT:-none}
  Export directory: $(exports_dir)
  v2RayN/share URI: anytls://<password>@${SERVER_HOST}:${SERVER_PORT}?security=tls&sni=${SERVER_HOST}$(fingerprint_query_param)$(alpn_query_param)
  Clash Verge Rev: direct anytls:// URI import; sing-box-client.json is also exported
EOF
}

run_install() {
  validate_inputs
  detect_os
  detect_pkg_manager
  detect_public_host
  if [ -z "$PASSWORD" ]; then
    PASSWORD="$(random_password)"
  fi

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
  write_service
  write_swap_plan
  export_profiles
  apply_service

  ok "AnyTLS install files are ready."
  ok "Server config: $(config_dir)/config.json"
  ok "Exports: $(exports_dir)"
  printf '%s\n' "Share link:"
  cat "$(exports_dir)/share-link.txt"
}

main() {
  parse_args "$@"
  set_colors
  run_install
}
