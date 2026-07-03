#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
SCRIPT_NAME="${0##*/}"

ROOT_DIR="${ANYTLS_ROOT:-}"
ASSUME_YES="${ANYTLS_ASSUME_YES:-0}"
DRY_RUN=0
NO_COLOR=0

SING_BOX_VERSION="${SING_BOX_VERSION:-1.13.14}"
SERVER_NAME="${ANYTLS_SERVER_NAME:-anytls}"
SERVER_HOST="${ANYTLS_SERVER_HOST:-}"
SERVER_PORT="${ANYTLS_PORT:-443}"
PASSWORD="${ANYTLS_PASSWORD:-}"
TLS_CERT_PATH="${ANYTLS_TLS_CERT:-/etc/anytls/server.crt}"
TLS_KEY_PATH="${ANYTLS_TLS_KEY:-/etc/anytls/server.key}"
TLS_MODE="acme"
ACME_HOME="/root/.acme.sh"
ACME_SERVER="${ANYTLS_ACME_SERVER:-letsencrypt}"
INSTALL_RULE_PROFILE="${ANYTLS_RULE_PROFILE:-safe}"
CUSTOM_RULE_SETS="${ANYTLS_CUSTOM_RULE_SETS:-}"
DNS_STRATEGY="${ANYTLS_DNS_STRATEGY:-ipv4_only}"
ENABLE_SWAP="${ANYTLS_ENABLE_SWAP:-ask}"
SWAP_SIZE_MIB="${ANYTLS_SWAP_SIZE_MIB:-}"
LISTEN_ADDRESS="${ANYTLS_LISTEN:-0.0.0.0}"
ALPN="${ANYTLS_ALPN-}"
TLS_FINGERPRINT="${ANYTLS_FINGERPRINT-chrome}"
EXPORT_DIR="${ANYTLS_EXPORT_DIR:-}"
BLOCK_CN="${ANYTLS_BLOCK_CN:-1}"
BLOCK_BT="${ANYTLS_BLOCK_BT:-1}"
PKG_MANAGER_OVERRIDE="${ANYTLS_PACKAGE_MANAGER:-}"
SING_BOX_EXEC="/usr/local/bin/sing-box"
RULE_FLAGS_SET=0

COLOR_RESET=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_RED=""
COLOR_BLUE=""

root_path() {
  local path="$1"
  if [ -n "$ROOT_DIR" ]; then
    printf '%s%s\n' "$ROOT_DIR" "$path"
  else
    printf '%s\n' "$path"
  fi
}

set_colors() {
  if [ "$NO_COLOR" -eq 1 ] || [ ! -t 1 ]; then
    return
  fi
  COLOR_RESET="$(printf '\033[0m')"
  COLOR_GREEN="$(printf '\033[32m')"
  COLOR_YELLOW="$(printf '\033[33m')"
  COLOR_RED="$(printf '\033[31m')"
  COLOR_BLUE="$(printf '\033[34m')"
}

info() {
  printf '%s[INFO]%s %s\n' "$COLOR_BLUE" "$COLOR_RESET" "$*"
}

ok() {
  printf '%s[OK]%s %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*"
}

warn() {
  printf '%s[WARN]%s %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$*" >&2
}

die() {
  printf '%s[ERROR]%s %s\n' "$COLOR_RED" "$COLOR_RESET" "$*" >&2
  exit 1
}

config_dir() {
  root_path /etc/sing-box
}

sysctl_file() {
  root_path /etc/sysctl.d/99-anytls-tuning.conf
}

service_file() {
  root_path /etc/systemd/system/sing-box-anytls.service
}

openrc_service_file() {
  root_path /etc/init.d/sing-box-anytls
}

swap_file() {
  root_path /swapfile
}

exports_dir() {
  if [ -n "$EXPORT_DIR" ]; then
    root_path "$EXPORT_DIR"
    return
  fi
  root_path /etc/anytls/exports
}

state_dir() {
  root_path /etc/anytls
}

password_file() {
  root_path /etc/anytls/password
}

ensure_parent() {
  mkdir -p "$(dirname "$1")"
}

write_file() {
  local path="$1"
  local mode="${2:-0644}"
  local dir base tmp
  dir="$(dirname "$path")"
  base="$(basename "$path")"
  ensure_parent "$path"
  tmp="$(umask 077 && mktemp "${dir}/.${base}.XXXXXX")" || die "Cannot create temporary file for $path."
  chmod "$mode" "$tmp"
  if ! cat > "$tmp"; then
    rm -f "$tmp"
    die "Cannot write $path."
  fi
  mv "$tmp" "$path"
}

write_secret_file() {
  write_file "$1" 0600
}

write_executable_file() {
  write_file "$1" 0700
}
