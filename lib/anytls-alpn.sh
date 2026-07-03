validate_alpn() {
  if [ -z "$ALPN" ]; then
    return
  fi

  case "$ALPN" in
    *,|,*|*,,*)
      die "ANYTLS_ALPN entries must be non-empty."
      ;;
  esac

  local old_ifs="$IFS"
  local item
  IFS=,
  for item in $ALPN; do
    case "$item" in
      ''|*[!A-Za-z0-9._/+:-]*)
        IFS="$old_ifs"
        die "ANYTLS_ALPN entries may contain only letters, digits, '.', '_', '/', '+', ':', or '-'."
        ;;
    esac
  done
  IFS="$old_ifs"
}

alpn_query_param() {
  [ -n "$ALPN" ] || return 0
  printf '&alpn=%s' "$(url_encode "$ALPN")"
}

tls_alpn_json() {
  [ -n "$ALPN" ] || return 0

  local old_ifs="$IFS"
  local item separator
  separator=""
  printf ',\n        "alpn": ['
  IFS=,
  for item in $ALPN; do
    printf '%s\n          "%s"' "$separator" "$(json_escape "$item")"
    separator=","
  done
  IFS="$old_ifs"
  printf '\n        ]'
}

clash_alpn_yaml() {
  [ -n "$ALPN" ] || return 0

  local old_ifs="$IFS"
  local item
  printf '    alpn:\n'
  IFS=,
  for item in $ALPN; do
    printf '      - "%s"\n' "$item"
  done
  IFS="$old_ifs"
}
