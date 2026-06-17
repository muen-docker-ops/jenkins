#!/usr/bin/env bash
set -euo pipefail

# Install or update AWS CLI v2 for Linux/WSL/Jenkins agents.
# This script is intentionally idempotent so it can run during every init step.

AWS_CLI_VERSION="${AWS_CLI_VERSION:-}"
INSTALL_DIR="${AWS_CLI_INSTALL_DIR:-/usr/local/aws-cli}"
BIN_DIR="${AWS_CLI_BIN_DIR:-/usr/local/bin}"
FORCE_INSTALL="${FORCE_INSTALL:-false}"

log() {
  printf '[install-aws-cli] %s\n' "$*"
}

die() {
  printf '[install-aws-cli] ERROR: %s\n' "$*" >&2
  exit 1
}

need_sudo() {
  [ "$(id -u)" -ne 0 ]
}

run_privileged() {
  if need_sudo; then
    command -v sudo >/dev/null 2>&1 || die "sudo is required when running as a non-root user"
    sudo "$@"
  else
    "$@"
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64 | amd64)
      printf 'x86_64'
      ;;
    aarch64 | arm64)
      printf 'aarch64'
      ;;
    *)
      die "unsupported CPU architecture: $(uname -m)"
      ;;
  esac
}

install_dependency_package() {
  package_name="$1"

  if command -v apt-get >/dev/null 2>&1; then
    run_privileged apt-get update
    run_privileged apt-get install -y --no-install-recommends "$package_name"
    return
  fi

  if command -v dnf >/dev/null 2>&1; then
    run_privileged dnf install -y "$package_name"
    return
  fi

  if command -v yum >/dev/null 2>&1; then
    run_privileged yum install -y "$package_name"
    return
  fi

  if command -v apk >/dev/null 2>&1; then
    run_privileged apk add --no-cache "$package_name"
    return
  fi

  die "missing dependency '${package_name}', and no supported package manager was found"
}

ensure_dependencies() {
  command -v curl >/dev/null 2>&1 || install_dependency_package curl
  command -v unzip >/dev/null 2>&1 || install_dependency_package unzip
}

current_aws_version() {
  if command -v aws >/dev/null 2>&1; then
    aws --version 2>&1 | awk '{print $1}' | sed 's#aws-cli/##'
  fi
}

download_url() {
  arch="$1"
  if [ -n "$AWS_CLI_VERSION" ]; then
    printf 'https://awscli.amazonaws.com/awscli-exe-linux-%s-%s.zip' "$arch" "$AWS_CLI_VERSION"
  else
    printf 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' "$arch"
  fi
}

main() {
  if [ "${FORCE_INSTALL}" != "true" ] && command -v aws >/dev/null 2>&1; then
    log "aws already installed: $(aws --version 2>&1)"
    log "set FORCE_INSTALL=true to reinstall/update"
    exit 0
  fi

  ensure_dependencies

  arch="$(detect_arch)"
  url="$(download_url "$arch")"
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  log "downloading AWS CLI v2 from ${url}"
  curl -fSL --retry 5 --retry-delay 2 --connect-timeout 30 \
    "$url" \
    -o "$tmp_dir/awscliv2.zip"

  log "extracting installer"
  unzip -q "$tmp_dir/awscliv2.zip" -d "$tmp_dir"

  log "installing to ${INSTALL_DIR}, bin dir ${BIN_DIR}"
  run_privileged "$tmp_dir/aws/install" \
    --install-dir "$INSTALL_DIR" \
    --bin-dir "$BIN_DIR" \
    --update

  command -v aws >/dev/null 2>&1 || die "aws command was not found after install; check PATH includes ${BIN_DIR}"
  log "installed: $(aws --version 2>&1)"
}

main "$@"

