validate_port() {
  case "$SERVER_PORT" in
    ''|*[!0-9]*)
      die "ANYTLS_PORT must be an integer between 1 and 65535."
      ;;
  esac
  if [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; then
    die "ANYTLS_PORT must be an integer between 1 and 65535."
  fi
}

validate_rule_name() {
  local name="$1"
  case "$name" in
    ''|*[!A-Za-z0-9_-]*)
      die "Custom rule_set/geosite name '$name' is invalid. Use letters, digits, '_' or '-'."
      ;;
  esac
}

validate_host() {
  local host="$1"
  case "$host" in
    ''|*[!A-Za-z0-9._:-]*)
      die "Server host must contain only letters, digits, '.', '_', ':', or '-'."
      ;;
  esac
}

validate_listen_address() {
  local address="$1"
  case "$address" in
    ''|*[!A-Za-z0-9:._%+-]*)
      die "Listen address must contain only letters, digits, ':', '.', '_', '%', '+', or '-'."
      ;;
  esac
}

validate_url() {
  local url="$1"
  case "$url" in
    https://*)
      ;;
    *)
      die "Custom rule_set URL '$url' must start with https://."
      ;;
  esac
  case "$url" in
    *[\"\<\>\\\ ]*)
      die "Custom rule_set URL '$url' contains unsupported characters."
      ;;
  esac
}

parse_custom_rule_spec() {
  local spec="$1"
  CUSTOM_TAG=""
  CUSTOM_URL=""
  CUSTOM_FORMAT="binary"
  CUSTOM_OUTBOUND="reject"

  if [ -z "$spec" ]; then
    return
  fi

  if [[ "$spec" != *"="* ]]; then
    validate_rule_name "$spec"
    CUSTOM_TAG="geosite-${spec}"
    CUSTOM_URL="https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-${spec}.srs"
    return
  fi

  local old_ifs="$IFS"
  local field key value
  IFS=,
  for field in $spec; do
    key="${field%%=*}"
    value="${field#*=}"
    case "$key" in
      tag)
        CUSTOM_TAG="$value"
        ;;
      url)
        CUSTOM_URL="$value"
        ;;
      format)
        CUSTOM_FORMAT="$value"
        ;;
      outbound)
        CUSTOM_OUTBOUND="$value"
        ;;
      *)
        IFS="$old_ifs"
        die "Unknown custom rule_set field '$key'."
        ;;
    esac
  done
  IFS="$old_ifs"

  validate_rule_name "$CUSTOM_TAG"
  validate_url "$CUSTOM_URL"
  case "$CUSTOM_FORMAT" in
    binary|source)
      ;;
    *)
      die "Custom rule_set format must be 'binary' or 'source'."
      ;;
  esac
  case "$CUSTOM_OUTBOUND" in
    reject|block|direct)
      ;;
    *)
      die "Custom rule_set outbound must be 'reject', 'block', or 'direct'."
      ;;
  esac
}

emit_custom_rule_records() {
  local records="$CUSTOM_RULE_SETS"
  local old_ifs="$IFS"
  local record item seen_tags tag
  seen_tags=""
  IFS=';'
  for record in $records; do
    if [ -z "$record" ]; then
      continue
    fi
    if [[ "$record" == *"="* ]]; then
      parse_custom_rule_spec "$record"
      tag="$CUSTOM_TAG"
      case " $seen_tags " in
        *" $tag "*)
          ;;
        *)
          seen_tags="${seen_tags} ${tag}"
          printf '%s\n' "$record"
          ;;
      esac
    else
      local comma_ifs="$IFS"
      IFS=,
      for item in $record; do
        if [ -n "$item" ]; then
          parse_custom_rule_spec "$item"
          tag="$CUSTOM_TAG"
          case " $seen_tags " in
            *" $tag "*)
              ;;
            *)
              seen_tags="${seen_tags} ${tag}"
              printf '%s\n' "$item"
              ;;
          esac
        fi
      done
      IFS="$comma_ifs"
    fi
  done
  IFS="$old_ifs"
}

validate_custom_rule_records() {
  if [ -z "$CUSTOM_RULE_SETS" ]; then
    return
  fi

  local records="$CUSTOM_RULE_SETS"
  local old_ifs="$IFS"
  local record item
  IFS=';'
  for record in $records; do
    [ -z "$record" ] && continue
    if [[ "$record" == *"="* ]]; then
      parse_custom_rule_spec "$record"
    else
      local comma_ifs="$IFS"
      IFS=,
      for item in $record; do
        [ -n "$item" ] && parse_custom_rule_spec "$item"
      done
      IFS="$comma_ifs"
    fi
  done
  IFS="$old_ifs"
}

validate_inputs() {
  validate_port
  if [ -n "$SERVER_HOST" ]; then
    validate_host "$SERVER_HOST"
  fi
  validate_listen_address "$LISTEN_ADDRESS"
  validate_alpn
  case "$INSTALL_RULE_PROFILE" in
    safe|none)
      ;;
    *)
      die "ANYTLS_RULE_PROFILE must be 'safe' or 'none'."
      ;;
  esac
  if [ "$INSTALL_RULE_PROFILE" = "none" ] && [ "$RULE_FLAGS_SET" -eq 0 ]; then
    BLOCK_CN=0
    BLOCK_BT=0
  fi

  case "$ENABLE_SWAP" in
    yes|no|ask)
      ;;
    *)
      die "ANYTLS_ENABLE_SWAP must be 'yes', 'no', or 'ask'."
      ;;
  esac

  if [ -n "$SWAP_SIZE_MIB" ]; then
    case "$SWAP_SIZE_MIB" in
      *[!0-9]*)
        die "ANYTLS_SWAP_SIZE_MIB must be a positive integer."
        ;;
    esac
    if [ "$SWAP_SIZE_MIB" -lt 256 ]; then
      die "ANYTLS_SWAP_SIZE_MIB must be at least 256."
    fi
  fi

  validate_custom_rule_records
}
