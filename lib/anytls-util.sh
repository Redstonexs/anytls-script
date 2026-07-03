url_encode() {
  local value="$1"
  local encoded=""
  local i char hex
  local length=${#value}
  for ((i = 0; i < length; i++)); do
    char="${value:i:1}"
    case "$char" in
      [a-zA-Z0-9.~_-])
        encoded+="$char"
        ;;
      *)
        printf -v hex '%%%02X' "'$char"
        encoded+="$hex"
        ;;
    esac
  done
  printf '%s' "$encoded"
}

shell_quote() {
  printf '%q' "$1"
}

uri_host_authority() {
  case "$1" in
    *:*)
      printf '[%s]' "$1"
      ;;
    *)
      printf '%s' "$1"
      ;;
  esac
}

random_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 24
  elif command -v head >/dev/null 2>&1 && [ -r /dev/urandom ]; then
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
    printf '\n'
  else
    printf 'change-me-%s\n' "$(date +%s)"
  fi
}

json_unescape_simple() {
  local value="$1"
  value="${value//\\\"/\"}"
  value="${value//\\\\/\\}"
  value="${value//\\\//\/}"
  value="${value//\\b/$'\b'}"
  value="${value//\\f/$'\f'}"
  value="${value//\\n/$'\n'}"
  value="${value//\\r/$'\r'}"
  value="${value//\\t/$'\t'}"
  printf '%s' "$value"
}

json_escape() {
  local value="$1"
  local escaped=""
  local index char code
  for ((index = 0; index < ${#value}; index++)); do
    char="${value:index:1}"
    case "$char" in
      '"')
        escaped+='\"'
        ;;
      "\\")
        escaped+='\\'
        ;;
      $'\b')
        escaped+='\b'
        ;;
      $'\f')
        escaped+='\f'
        ;;
      $'\n')
        escaped+='\n'
        ;;
      $'\r')
        escaped+='\r'
        ;;
      $'\t')
        escaped+='\t'
        ;;
      *)
        LC_ALL=C printf -v code '%d' "'$char"
        if [ "$code" -lt 32 ]; then
          printf -v char '\\u%04x' "$code"
        fi
        escaped+="$char"
        ;;
    esac
  done
  printf '%s' "$escaped"
}

base64_url_encode() {
  if base64 --help 2>/dev/null | grep -q -- '-w'; then
    base64 -w0
  else
    base64 | tr -d '\n'
  fi | tr '+/' '-_' | tr -d '='
}

certificate_sha256_fingerprint() {
  local cert_file output
  cert_file="$(root_path "$TLS_CERT_PATH")"
  [ -s "$cert_file" ] || return 0
  output="$(openssl x509 -fingerprint -noout -sha256 -in "$cert_file" 2>/dev/null)" || return 0
  printf '%s' "${output#*=}"
}

certificate_public_key_sha256_base64() {
  local cert_file output
  cert_file="$(root_path "$TLS_CERT_PATH")"
  [ -s "$cert_file" ] || return 0
  output="$(
    openssl x509 -in "$cert_file" -pubkey -noout 2>/dev/null \
      | openssl pkey -pubin -outform der 2>/dev/null \
      | openssl dgst -sha256 -binary 2>/dev/null \
      | openssl enc -base64 2>/dev/null
  )" || return 0
  printf '%s' "$output" | tr -d '\n'
}

certificate_public_pem_blocks() {
  local cert_file
  cert_file="$(root_path "$TLS_CERT_PATH")"
  [ -s "$cert_file" ] || return 0
  command -v openssl >/dev/null 2>&1 || return 0
  openssl crl2pkcs7 -nocrl -certfile "$cert_file" 2>/dev/null \
    | openssl pkcs7 -print_certs 2>/dev/null \
    | awk '
      /^-----BEGIN CERTIFICATE-----$/ { in_cert = 1 }
      in_cert { print }
      /^-----END CERTIFICATE-----$/ { in_cert = 0 }
    '
}

certificate_pem_json_value() {
  local cert_pem
  cert_pem="$(certificate_public_pem_blocks)" || return 0
  [ -n "$cert_pem" ] || return 0
  printf '%s\n' "$cert_pem" | awk '{
      gsub(/\\/, "\\\\")
      gsub(/"/, "\\\"")
      printf "%s\\r\\n", $0
  }'
}

certificate_pem_query_param() {
  local cert_pem cert_value
  cert_pem="$(certificate_public_pem_blocks)" || return 0
  [ -n "$cert_pem" ] || return 0
  cert_value="$(
    printf '%s\n' "$cert_pem" | awk '{ printf "%s,", $0 }' | sed 's/,$//'
  )"
  [ -n "$cert_value" ] || return 0
  printf '&tls_certificate=%s' "$(url_encode "$cert_value")"
}
