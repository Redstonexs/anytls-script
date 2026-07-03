uninstall_service() {
  if [ -n "$ROOT_DIR" ] || [ "$DRY_RUN" -eq 1 ]; then
    return
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl disable --now sing-box-anytls.service >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
  elif command -v rc-update >/dev/null 2>&1 && command -v rc-service >/dev/null 2>&1; then
    rc-service sing-box-anytls stop >/dev/null 2>&1 || true
    rc-update del sing-box-anytls default >/dev/null 2>&1 || true
  fi
}

reload_service_manager_after_uninstall() {
  if [ -n "$ROOT_DIR" ] || [ "$DRY_RUN" -eq 1 ]; then
    return
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl reset-failed sing-box-anytls.service >/dev/null 2>&1 || true
  fi
}

remove_path_if_exists() {
  local path="$1"
  if [ -e "$path" ] || [ -L "$path" ]; then
    rm -rf "$path"
  fi
}

rmdir_if_empty() {
  local path="$1"
  [ -d "$path" ] || return 0
  rmdir "$path" 2>/dev/null || true
}

remove_anytls_files() {
  remove_path_if_exists "$(service_file)"
  remove_path_if_exists "$(openrc_service_file)"
  remove_path_if_exists "$(config_dir)/config.json"
  remove_path_if_exists "$(sysctl_file)"
  remove_path_if_exists "$(exports_dir)"
  remove_path_if_exists "$(state_dir)/swap-plan.env"
  remove_path_if_exists "$(state_dir)/swap-apply-plan.sh"

  if [ "$PURGE" -eq 1 ]; then
    remove_path_if_exists "$(root_path "$TLS_CERT_PATH")"
    remove_path_if_exists "$(root_path "$TLS_KEY_PATH")"
    remove_path_if_exists "$(password_file)"
  fi

  rmdir_if_empty "$(config_dir)"
  rmdir_if_empty "$(state_dir)"
}

print_uninstall_plan() {
  cat <<EOF
Dry-run uninstall plan, no files will be removed.

Would stop and disable:
  sing-box-anytls.service

Would remove:
  $(service_file)
  $(openrc_service_file)
  $(config_dir)/config.json
  $(sysctl_file)
  $(exports_dir)
  $(state_dir)/swap-plan.env
  $(state_dir)/swap-apply-plan.sh
EOF

  if [ "$PURGE" -eq 1 ]; then
    cat <<EOF

Would also purge:
  ${TLS_CERT_PATH}
  ${TLS_KEY_PATH}
  $(password_file)
EOF
  else
    cat <<EOF

Would keep:
  ${TLS_CERT_PATH}
  ${TLS_KEY_PATH}
  $(password_file)
EOF
  fi
}

run_uninstall() {
  detect_os
  detect_pkg_manager

  if [ "$DRY_RUN" -eq 1 ]; then
    print_uninstall_plan
    return
  fi

  if [ "$ASSUME_YES" -ne 1 ]; then
    confirm "Uninstall sing-box AnyTLS service and generated configuration?" "no" || die "Uninstall cancelled."
  fi

  uninstall_service
  remove_anytls_files
  reload_service_manager_after_uninstall

  ok "AnyTLS service and generated configuration removed."
  if [ "$PURGE" -eq 1 ]; then
    ok "TLS assets and password state purged."
  else
    info "TLS assets and password state were kept. Re-run with --uninstall --purge to remove them."
  fi
}
