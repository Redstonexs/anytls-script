#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${ANYTLS_REPO_URL:-https://github.com/Redstonexs/anytls-script.git}"
REPO_BRANCH="${ANYTLS_REPO_BRANCH:-main}"
INSTALL_DIR="${ANYTLS_INSTALL_DIR:-/opt/anytls-script}"
SING_BOX_VERSION="${SING_BOX_VERSION:-1.13.14}"
SKIP_SING_BOX_INSTALL="${ANYTLS_SKIP_SING_BOX_INSTALL:-0}"
BOOTSTRAP_ASSUME_YES="${ANYTLS_BOOTSTRAP_ASSUME_YES:-1}"

INSTALLER_ARGS=()

log() {
  printf '[INFO] %s\n' "$*"
}

ok() {
  printf '[OK] %s\n' "$*"
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
AnyTLS bootstrap installer

Usage:
  curl -fsSL https://raw.githubusercontent.com/Redstonexs/anytls-script/main/install.sh | sudo bash -s -- [anytls options]

Bootstrap options:
  --bootstrap-install-dir PATH  Install or update the repo checkout here. Default: /opt/anytls-script
  --bootstrap-repo URL          Git repository URL. Default: ${REPO_URL}
  --bootstrap-branch NAME       Git branch. Default: ${REPO_BRANCH}
  --skip-sing-box-install       Do not install sing-box automatically.
  --interactive                 Do not append --yes to anytls-install.sh.
  --help                        Show this help.

Common AnyTLS options passed through:
  --domain HOST                 Public server DNS name for ACME certificates.
  --port PORT                   AnyTLS port. Default: 443.
  --listen ADDRESS              AnyTLS bind address. Default: 0.0.0.0.
  --fingerprint FP              TLS client fingerprint for share links. Default: chrome.
  --self-signed                 Explicitly use a self-signed certificate.
  --apply-swap                  Apply recommended swap when the host has none.
  --rules safe|none|block-cn,block-bt
  --custom-rule-set openai
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --bootstrap-install-dir)
        [ "$#" -ge 2 ] || die "--bootstrap-install-dir requires a path."
        INSTALL_DIR="$2"
        shift
        ;;
      --bootstrap-repo)
        [ "$#" -ge 2 ] || die "--bootstrap-repo requires a URL."
        REPO_URL="$2"
        shift
        ;;
      --bootstrap-branch)
        [ "$#" -ge 2 ] || die "--bootstrap-branch requires a branch name."
        REPO_BRANCH="$2"
        shift
        ;;
      --skip-sing-box-install)
        SKIP_SING_BOX_INSTALL=1
        ;;
      --interactive)
        BOOTSTRAP_ASSUME_YES=0
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      --)
        shift
        while [ "$#" -gt 0 ]; do
          INSTALLER_ARGS+=("$1")
          shift
        done
        return
        ;;
      *)
        INSTALLER_ARGS+=("$1")
        ;;
    esac
    shift
  done
}

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    die "Please run through sudo: curl -fsSL https://raw.githubusercontent.com/Redstonexs/anytls-script/main/install.sh | sudo bash -s -- --domain your-domain.example"
  fi
}

detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    printf 'apt\n'
  elif command -v dnf >/dev/null 2>&1; then
    printf 'dnf\n'
  elif command -v yum >/dev/null 2>&1; then
    printf 'yum\n'
  elif command -v zypper >/dev/null 2>&1; then
    printf 'zypper\n'
  elif command -v pacman >/dev/null 2>&1; then
    printf 'pacman\n'
  elif command -v apk >/dev/null 2>&1; then
    printf 'apk\n'
  else
    printf 'manual\n'
  fi
}

install_base_dependencies() {
  local manager="$1"
  log "Installing base dependencies with ${manager}."
  case "$manager" in
    apt)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates tar gzip openssl socat iproute2 git
      ;;
    dnf)
      dnf install -y curl ca-certificates tar gzip openssl socat iproute git
      ;;
    yum)
      yum install -y curl ca-certificates tar gzip openssl socat iproute git
      ;;
    zypper)
      zypper --non-interactive install curl ca-certificates tar gzip openssl socat iproute2 git
      ;;
    pacman)
      pacman -Sy --noconfirm curl ca-certificates tar gzip openssl socat iproute2 git
      ;;
    apk)
      apk add --no-cache curl ca-certificates tar gzip openssl socat iproute2 git openrc
      ;;
    manual)
      log "No supported package manager found; assuming curl, git, tar, gzip, openssl, socat, and iproute2 are already installed."
      ;;
    *)
      die "Unsupported package manager: ${manager}"
      ;;
  esac
}

install_sing_box() {
  local manager="$1"
  if command -v sing-box >/dev/null 2>&1; then
    ok "sing-box already installed: $(command -v sing-box)"
    return
  fi

  if [ "$SKIP_SING_BOX_INSTALL" -eq 1 ]; then
    die "sing-box is not installed and automatic sing-box installation was disabled."
  fi

  log "Installing sing-box ${SING_BOX_VERSION}."
  if [ "$manager" = "apk" ]; then
    apk add --no-cache sing-box || true
  fi

  if ! command -v sing-box >/dev/null 2>&1; then
    curl -fsSL https://sing-box.app/install.sh | sh -s -- --version "$SING_BOX_VERSION"
  fi

  command -v sing-box >/dev/null 2>&1 || die "sing-box installation did not produce a sing-box command."
  ok "sing-box installed: $(command -v sing-box)"
}

recover_installer_mode_change() {
  local status numstat
  status="$(git -C "$INSTALL_DIR" status --short --untracked-files=no)"
  [ "$status" = " M anytls-install.sh" ] || return 0

  numstat="$(git -C "$INSTALL_DIR" diff --numstat -- anytls-install.sh)"
  [ "$numstat" = "0	0	anytls-install.sh" ] || return 0

  log "Resetting installer-managed executable bit change before updating the repository."
  git -C "$INSTALL_DIR" checkout -- anytls-install.sh
}

deploy_repo() {
  log "Installing repository ${REPO_URL} (${REPO_BRANCH}) to ${INSTALL_DIR}."

  if [ -d "$INSTALL_DIR/.git" ]; then
    git -C "$INSTALL_DIR" fetch origin "$REPO_BRANCH"
    git -C "$INSTALL_DIR" checkout "$REPO_BRANCH"
    recover_installer_mode_change
    git -C "$INSTALL_DIR" pull --ff-only origin "$REPO_BRANCH"
    return
  fi

  if [ -e "$INSTALL_DIR" ] && [ "$(find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')" != "0" ]; then
    die "${INSTALL_DIR} already exists and is not an empty git checkout. Set ANYTLS_INSTALL_DIR or --bootstrap-install-dir to another path."
  fi

  rm -rf "$INSTALL_DIR"
  git clone --branch "$REPO_BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR"
}

has_non_interactive_flag() {
  local arg
  for arg in "${INSTALLER_ARGS[@]}"; do
    case "$arg" in
      --yes|-y|--non-interactive|--dry-run)
        return 0
        ;;
    esac
  done
  return 1
}

run_anytls_installer() {
  local installer="$INSTALL_DIR/anytls-install.sh"
  [ -f "$installer" ] || die "Installer not found: ${installer}"
  chmod +x "$installer"

  if [ "$BOOTSTRAP_ASSUME_YES" -eq 1 ] && ! has_non_interactive_flag; then
    log "Running anytls installer in non-interactive mode."
    bash "$installer" --yes "${INSTALLER_ARGS[@]}"
  else
    log "Running anytls installer."
    bash "$installer" "${INSTALLER_ARGS[@]}"
  fi
}

main() {
  parse_args "$@"
  require_root

  local manager
  manager="$(detect_pkg_manager)"
  install_base_dependencies "$manager"
  install_sing_box "$manager"
  deploy_repo
  run_anytls_installer
}

main "$@"
