usage() {
  cat <<EOF
AnyTLS Linux installer ${VERSION}

Usage:
  bash ${SCRIPT_NAME} [options]

Options:
  --dry-run          Show the guided installation plan without writing files.
  --yes             Non-interactive install using defaults or environment values.
  --non-interactive Alias of --yes.
  --root PATH       Install below PATH. Intended for tests and image builds.
  --domain HOST     Public server DNS name for ACME certificates and exports.
  --port PORT       AnyTLS listen port. Default: 443.
  --listen ADDRESS  AnyTLS bind address. Default: 0.0.0.0.
  --password VALUE  AnyTLS user password.
  --alpn LIST       Optional comma-separated TLS ALPN list, e.g. h2,http/1.1.
  --fingerprint FP  TLS client fingerprint for share links. Default: chrome.
  --cert-file PATH  TLS certificate path. Default: /etc/anytls/server.crt.
  --key-file PATH   TLS private key path. Default: /etc/anytls/server.key.
  --acme            Use acme.sh for certificate issuance and renewal. Default.
  --self-signed     Explicitly create a self-signed certificate instead of ACME.
  --rules LIST      Comma list: block-cn,block-bt,none.
  --custom-rule-set VALUE
                    Rule name such as openai, or tag=...,url=...,outbound=...,format=...
  --dns-strategy VALUE
                    DNS strategy for direct outbound. Default: ipv4_only.
                    Use system to keep sing-box defaults.
  --apply-swap      Create recommended swap when swap is absent.
  --no-swap         Only write the swap recommendation and one-key apply script.
  --export-dir PATH Export artifact directory. Default: /etc/anytls/exports.
  --no-color        Disable ANSI colors.
  --help            Show this help text.

Environment:
  ANYTLS_SERVER_HOST       Public server DNS name for ACME certificates and exports.
  ANYTLS_PORT              AnyTLS listen port. Default: 443.
  ANYTLS_LISTEN            AnyTLS bind address. Default: 0.0.0.0.
  ANYTLS_PASSWORD          User password. Reuse existing or auto-generate if empty.
  ANYTLS_ALPN              Optional comma-separated TLS ALPN list. Default: empty.
  ANYTLS_FINGERPRINT       TLS client fingerprint for share links. Default: chrome.
  ANYTLS_ACME_SERVER       ACME CA server alias. Default: letsencrypt.
  ANYTLS_RULE_PROFILE      safe, none. Default: safe.
  ANYTLS_CUSTOM_RULE_SETS  Comma list of extra geosite/rule_set names, e.g. openai,netflix.
  ANYTLS_DNS_STRATEGY      ipv4_only, prefer_ipv4, prefer_ipv6, ipv6_only, or system.
                           Default: ipv4_only.
  ANYTLS_ENABLE_SWAP       yes, no, ask. Default: ask.
  ANYTLS_SWAP_SIZE_MIB     Swap size when applying swap.
  ANYTLS_ROOT              Test/fakeroot prefix. Normal installs leave this empty.

The safe rule profile rejects outbound traffic matching CN geoip/geosite rule sets
and BitTorrent protocol/rule sets before the default direct outbound.
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      --yes|-y)
        ASSUME_YES=1
        ;;
      --non-interactive)
        ASSUME_YES=1
        ;;
      --root)
        [ "$#" -ge 2 ] || die "--root requires a path."
        ROOT_DIR="$2"
        shift
        ;;
      --domain|--host)
        [ "$#" -ge 2 ] || die "$1 requires a host."
        SERVER_HOST="$2"
        shift
        ;;
      --port)
        [ "$#" -ge 2 ] || die "--port requires a value."
        SERVER_PORT="$2"
        shift
        ;;
      --listen)
        [ "$#" -ge 2 ] || die "--listen requires an address."
        LISTEN_ADDRESS="$2"
        shift
        ;;
      --password)
        [ "$#" -ge 2 ] || die "--password requires a value."
        PASSWORD="$2"
        shift
        ;;
      --alpn)
        [ "$#" -ge 2 ] || die "--alpn requires a comma list."
        ALPN="$2"
        shift
        ;;
      --fingerprint)
        [ "$#" -ge 2 ] || die "--fingerprint requires a value."
        TLS_FINGERPRINT="$2"
        shift
        ;;
      --cert-file)
        [ "$#" -ge 2 ] || die "--cert-file requires a path."
        TLS_CERT_PATH="$2"
        shift
        ;;
      --key-file)
        [ "$#" -ge 2 ] || die "--key-file requires a path."
        TLS_KEY_PATH="$2"
        shift
        ;;
      --acme)
        TLS_MODE="acme"
        ;;
      --self-signed)
        TLS_MODE="self-signed"
        ;;
      --rules)
        [ "$#" -ge 2 ] || die "--rules requires a comma list."
        set_rule_flags "$2"
        shift
        ;;
      --custom-rule-set)
        [ "$#" -ge 2 ] || die "--custom-rule-set requires a value."
        if [ -n "$CUSTOM_RULE_SETS" ]; then
          CUSTOM_RULE_SETS="${CUSTOM_RULE_SETS};$2"
        else
          CUSTOM_RULE_SETS="$2"
        fi
        shift
        ;;
      --dns-strategy)
        [ "$#" -ge 2 ] || die "--dns-strategy requires a value."
        DNS_STRATEGY="$2"
        shift
        ;;
      --apply-swap)
        ENABLE_SWAP=yes
        ;;
      --no-swap)
        ENABLE_SWAP=no
        ;;
      --export-dir)
        [ "$#" -ge 2 ] || die "--export-dir requires a path."
        EXPORT_DIR="$2"
        shift
        ;;
      --no-color)
        NO_COLOR=1
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
    shift
  done
}

set_rule_flags() {
  local list="$1"
  local old_ifs="$IFS"
  local item
  RULE_FLAGS_SET=1
  BLOCK_CN=0
  BLOCK_BT=0
  IFS=,
  for item in $list; do
    case "$item" in
      block-cn)
        BLOCK_CN=1
        ;;
      block-bt)
        BLOCK_BT=1
        ;;
      none)
        BLOCK_CN=0
        BLOCK_BT=0
        ;;
      safe)
        BLOCK_CN=1
        BLOCK_BT=1
        ;;
      "")
        ;;
      *)
        die "Unknown rule preset '$item'. Use block-cn, block-bt, safe, or none."
        ;;
    esac
  done
  IFS="$old_ifs"
}

confirm() {
  local prompt="$1"
  local default="${2:-yes}"
  local answer

  if [ "$ASSUME_YES" -eq 1 ]; then
    [ "$default" = "yes" ]
    return
  fi

  if [ "$default" = "yes" ]; then
    printf '%s [Y/n] ' "$prompt"
  else
    printf '%s [y/N] ' "$prompt"
  fi
  read -r answer || answer=""
  case "$answer" in
    y|Y|yes|YES)
      return 0
      ;;
    n|N|no|NO)
      return 1
      ;;
    "")
      [ "$default" = "yes" ]
      ;;
    *)
      return 1
      ;;
  esac
}
