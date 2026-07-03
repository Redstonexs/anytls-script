install_sing_box_binary() {
  local bin_path
  bin_path="$(root_path /usr/local/bin/sing-box)"
  if [ -n "$ROOT_DIR" ]; then
    SING_BOX_EXEC="/usr/local/bin/sing-box"
    write_file "$bin_path" 0755 <<'EOF'
#!/usr/bin/env sh
echo "sing-box mock"
EOF
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    info "Dry-run: would install sing-box ${SING_BOX_VERSION} to /usr/local/bin/sing-box."
    return
  fi

  if command -v sing-box >/dev/null 2>&1; then
    SING_BOX_EXEC="$(command -v sing-box)"
    ok "sing-box already exists at ${SING_BOX_EXEC}."
    return
  fi

  die "sing-box was not found. Install sing-box ${SING_BOX_VERSION} first or rerun after verifying the release manually. Suggested dependencies: ${INSTALL_CMD}"
}

apply_service() {
  if [ -n "$ROOT_DIR" ] || [ "$DRY_RUN" -eq 1 ]; then
    return
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl enable --now sing-box-anytls.service
  elif command -v rc-update >/dev/null 2>&1 && command -v rc-service >/dev/null 2>&1; then
    rc-update add sing-box-anytls default
    rc-service sing-box-anytls restart
  else
    warn "systemctl not found; service file was written but not started."
  fi
}
