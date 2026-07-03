os_release_value() {
  local file="$1"
  local key="$2"
  awk -F= -v key="$key" '
    $1 == key {
      value = substr($0, index($0, "=") + 1)
      gsub(/^"/, "", value)
      gsub(/"$/, "", value)
      print value
      exit
    }
  ' "$file"
}

detect_os() {
  OS_ID="unknown"
  OS_LIKE=""
  OS_VERSION=""
  ARCH="$(uname -m 2>/dev/null || printf unknown)"

  local os_release
  os_release="$(root_path /etc/os-release)"
  if [ -f "$os_release" ]; then
    OS_ID="$(os_release_value "$os_release" ID)"
    OS_LIKE="$(os_release_value "$os_release" ID_LIKE)"
    OS_VERSION="$(os_release_value "$os_release" VERSION_ID)"
    OS_ID="${OS_ID:-unknown}"
  fi
}

detect_pkg_manager() {
  PKG_MANAGER="manual"
  INSTALL_CMD="Install curl, tar, gzip, openssl, ca-certificates, systemd/openrc, and iproute2 with your distribution package manager."

  if [ -n "$PKG_MANAGER_OVERRIDE" ]; then
    PKG_MANAGER="$PKG_MANAGER_OVERRIDE"
  elif [[ " ${OS_ID} ${OS_LIKE} " == *" debian "* ]] || [[ " ${OS_ID} ${OS_LIKE} " == *" ubuntu "* ]]; then
    PKG_MANAGER="apt"
  elif [[ " ${OS_ID} ${OS_LIKE} " == *" rhel "* ]] || [[ " ${OS_ID} ${OS_LIKE} " == *" fedora "* ]] || [[ " ${OS_ID} ${OS_LIKE} " == *" centos "* ]] || [[ " ${OS_ID} ${OS_LIKE} " == *" rocky "* ]] || [[ " ${OS_ID} ${OS_LIKE} " == *" almalinux "* ]]; then
    PKG_MANAGER="dnf"
  elif [[ " ${OS_ID} ${OS_LIKE} " == *" suse "* ]] || [[ " ${OS_ID} ${OS_LIKE} " == *" opensuse "* ]]; then
    PKG_MANAGER="zypper"
  elif [[ " ${OS_ID} ${OS_LIKE} " == *" arch "* ]] || [[ " ${OS_ID} ${OS_LIKE} " == *" manjaro "* ]]; then
    PKG_MANAGER="pacman"
  elif [[ " ${OS_ID} ${OS_LIKE} " == *" alpine "* ]]; then
    PKG_MANAGER="apk"
  elif [ -n "$ROOT_DIR" ]; then
    PKG_MANAGER="manual"
  elif command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
  elif command -v zypper >/dev/null 2>&1; then
    PKG_MANAGER="zypper"
  elif command -v pacman >/dev/null 2>&1; then
    PKG_MANAGER="pacman"
  elif command -v apk >/dev/null 2>&1; then
    PKG_MANAGER="apk"
  fi

  case "$PKG_MANAGER" in
    apt)
    INSTALL_CMD="apt-get update && apt-get install -y curl tar gzip openssl ca-certificates systemd iproute2"
      ;;
    dnf)
    INSTALL_CMD="dnf install -y curl tar gzip openssl ca-certificates systemd iproute"
      ;;
    yum)
    INSTALL_CMD="yum install -y curl tar gzip openssl ca-certificates systemd iproute"
      ;;
    zypper)
    INSTALL_CMD="zypper --non-interactive install curl tar gzip openssl ca-certificates systemd iproute2"
      ;;
    pacman)
    INSTALL_CMD="pacman -Sy --noconfirm curl tar gzip openssl ca-certificates systemd iproute2"
      ;;
    apk)
    INSTALL_CMD="apk add --no-cache curl tar gzip openssl ca-certificates openrc iproute2"
      ;;
    manual)
      ;;
    *)
      die "Unsupported package manager override '$PKG_MANAGER_OVERRIDE'."
      ;;
  esac
}

detect_public_host() {
  if [ -n "$SERVER_HOST" ]; then
    return
  fi
  SERVER_HOST="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  if [ -z "$SERVER_HOST" ]; then
    SERVER_HOST="YOUR_SERVER_IP"
  fi
}

memory_total_mib() {
  local meminfo
  meminfo="$(root_path /proc/meminfo)"
  if [ -r "$meminfo" ]; then
    awk '/^MemTotal:/ {printf "%d\n", $2 / 1024}' "$meminfo"
  else
    printf '0\n'
  fi
}

swap_total_mib() {
  local meminfo
  meminfo="$(root_path /proc/meminfo)"
  if [ -r "$meminfo" ]; then
    awk '/^SwapTotal:/ {printf "%d\n", $2 / 1024}' "$meminfo"
  else
    printf '0\n'
  fi
}

recommended_swap_mib() {
  local mem_mib="$1"
  if [ "$mem_mib" -le 0 ]; then
    printf '1024\n'
  elif [ "$mem_mib" -lt 1024 ]; then
    printf '1024\n'
  elif [ "$mem_mib" -lt 2048 ]; then
    printf '1024\n'
  elif [ "$mem_mib" -lt 4096 ]; then
    printf '2048\n'
  else
    printf '0\n'
  fi
}
