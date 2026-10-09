#!/usr/bin/env bash
# Hashem Pro v0.1 - convenience installer for an Iran controller or foreign node.
# Source: https://github.com/Bagheri1401/hashem-pro
set -Eeuo pipefail

readonly REPO_URL="https://github.com/Bagheri1401/hashem-pro.git"
readonly RAW_URL="https://raw.githubusercontent.com/Bagheri1401/hashem-pro/main/install.sh"
ROLE=""
WORKDIR=""

usage() {
  cat <<'HELP'
Hashem Pro - easy installer (Ubuntu 22.04/24.04, Debian 12/13)

Usage:
  sudo bash install.sh --iran       Install panel on the Iran server
  sudo bash install.sh --foreign    Prepare a foreign server (FRP, GRE tools, SSH)
  sudo bash install.sh             Interactive role selection

One-line download-and-run (review downloaded scripts before running as root):
  curl -fsSL https://raw.githubusercontent.com/Bagheri1401/hashem-pro/main/install.sh -o /tmp/hashem-pro-install.sh && sudo bash /tmp/hashem-pro-install.sh --iran

The panel stays on 127.0.0.1:8765; connect via an SSH port forward.
The remote node still needs authorized SSH public key and verified known_hosts.
HELP
}

cleanup() {
  if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
    rm -rf -- "$WORKDIR"
  fi
}
trap cleanup EXIT

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '\n==> %s\n' "$*"; }

for arg in "$@"; do
  case "$arg" in
    --iran) [[ -z "$ROLE" ]] || fail 'Specify only one role'; ROLE='iran' ;;
    --foreign) [[ -z "$ROLE" ]] || fail 'Specify only one role'; ROLE='foreign' ;;
    -h|--help) usage; exit 0 ;;
    *) usage; fail "Unknown argument: $arg" ;;
  esac
done

[[ $EUID -eq 0 ]] || fail 'Run with sudo/root, for example: sudo bash install.sh --iran'
[[ -d /run/systemd/system ]] || fail 'This installer requires systemd (not Docker/WSL without systemd)'
[[ -f /etc/os-release ]] || fail 'Cannot detect Linux distribution'
# shellcheck disable=SC1091
source /etc/os-release
case "$ID" in
  ubuntu) [[ "${VERSION_ID:-}" == '22.04' || "${VERSION_ID:-}" == '24.04' ]] || fail 'Supported Ubuntu: 22.04 / 24.04' ;;
  debian) [[ "${VERSION_ID:-}" == '12' || "${VERSION_ID:-}" == '13' ]] || fail 'Supported Debian: 12 / 13' ;;
  *) fail 'Supported operating systems: Ubuntu 22.04/24.04 and Debian 12/13' ;;
esac

if [[ -z "$ROLE" ]]; then
  if [[ ! -t 0 ]]; then
    usage
    fail 'Non-interactive run requires --iran or --foreign'
  fi
  printf '\n  Hashem Pro | GRE + FRP tunnel manager\n'
  printf '  1) Iran (panel/controller)\n  2) Foreign (node)\n  3) Exit\n'
  read -rp 'Choose [1/2/3]: ' selection
  case "$selection" in 1) ROLE='iran';; 2) ROLE='foreign';; 3) exit 0;; *) fail 'Invalid selection';; esac
fi

# If run from a checked-out repository, avoid cloning/downloading twice.
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SOURCE_DIR/scripts/install-panel.sh" && -f "$SOURCE_DIR/scripts/install-frp.sh" ]]; then
  info "Using local repository: $SOURCE_DIR"
else
  info 'Fetching Hashem Pro from its GitHub repository'
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates git
  WORKDIR="$(mktemp -d /tmp/hashem-pro.XXXXXXXX)"
  git clone --depth 1 --single-branch --branch main "$REPO_URL" "$WORKDIR/source"
  SOURCE_DIR="$WORKDIR/source"
fi

if [[ "$ROLE" == 'iran' ]]; then
  [[ -f "$SOURCE_DIR/grefrp/app.py" && -f "$SOURCE_DIR/grefrp/core.py" && -f "$SOURCE_DIR/static/style.css" ]] ||
    fail 'Source is incomplete. Ensure Python/CSS files have proper extensions when uploaded to GitHub.'
  info 'Installing Hashem Pro control panel on IRAN server'
  # Install-panel prompts for admin credentials, keeps existing settings on upgrades.
  bash "$SOURCE_DIR/scripts/install-panel.sh"
  info 'Checking service status'
  systemctl is-active --quiet grefrp-panel.service || {
    systemctl --no-pager --full status grefrp-panel.service || true
    fail 'Panel did not start; check: journalctl -u grefrp-panel -n 100 --no-pager'
  }
  cat <<'POST'

Hashem Pro panel is running (local access only).
On your laptop/PC, run:
  ssh -N -L 8765:127.0.0.1:8765 root@YOUR_IRAN_PUBLIC_IP
Then open: http://127.0.0.1:8765
For foreign servers, use this installer with --foreign and configure verified SSH keys.
WARNING: Do not expose port 8765 to the public internet.
POST
else
  info 'Installing foreign-node dependencies and verified FRP binaries'
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl tar iproute2 kmod openssh-server
  bash "$SOURCE_DIR/scripts/install-frp.sh"
  install -d -m 0700 /etc/grefrp /etc/grefrp/nodes /root/.ssh
  touch /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
  systemctl enable --now ssh.service

  if [[ -t 0 ]]; then
    printf '\nOptional: paste the PUBLIC SSH key printed by the Iran panel installer.\n'
    printf 'Leave blank to configure it later. Never paste a private key.\n'
    read -r -p 'Iran panel SSH public key: ' PUBLIC_KEY
    if [[ -n "$PUBLIC_KEY" ]]; then
      KEYFILE="$(mktemp /tmp/hashem-key.XXXXXXXX)"
      printf '%s\n' "$PUBLIC_KEY" > "$KEYFILE"
      if ! ssh-keygen -lf "$KEYFILE" >/dev/null 2>&1; then
        rm -f "$KEYFILE"
        fail 'Invalid SSH public key. No changes to authorized_keys.'
      fi
      rm -f "$KEYFILE"
      if ! grep -Fxq -- "$PUBLIC_KEY" /root/.ssh/authorized_keys; then
        printf '%s\n' "$PUBLIC_KEY" >> /root/.ssh/authorized_keys
      fi
      info 'Added the Iran controller SSH public key for the root account'
    fi
  fi

  printf '\nForeign-node preparation complete. FRPC starts when you deploy the node in the Iran panel.\n'
  printf 'Verify the server SSH host-key fingerprint via your provider console:\n'
  if [[ -f /etc/ssh/ssh_host_ed25519_key.pub ]]; then
    ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
  fi
  printf 'Copy/verify this host key in /etc/grefrp/known_hosts on the Iran server (see README.md).\n'
  printf 'GRE protocol number 47 must be allowed through both firewalls/providers.\n'
fi
