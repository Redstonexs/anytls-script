run_service() {
  local fake_bin log old_path
  fake_bin="$(mktemp -d "${TMPDIR:-/tmp}/anytls-service-test.XXXXXX")"
  log="$fake_bin/systemctl.log"

  cat > "$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$*" >> "$ANYTLS_FAKE_SYSTEMCTL_LOG"
EOF
  chmod +x "$fake_bin/systemctl"

  old_path="$PATH"
  PATH="$fake_bin:$PATH"
  ANYTLS_FAKE_SYSTEMCTL_LOG="$log"
  export ANYTLS_FAKE_SYSTEMCTL_LOG
  ROOT_DIR=""
  DRY_RUN=0

  apply_service
  uninstall_service
  reload_service_manager_after_uninstall

  PATH="$old_path"
  assert_contains "$log" "daemon-reload"
  assert_contains "$log" "enable sing-box-anytls.service"
  assert_contains "$log" "restart sing-box-anytls.service"
  assert_contains "$log" "disable --now sing-box-anytls.service"
  assert_contains "$log" "reset-failed sing-box-anytls.service"
  assert_not_contains "$log" "enable --now sing-box-anytls.service"

  rm -rf "$fake_bin"
  printf 'PASS service\n'
}
