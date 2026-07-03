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
