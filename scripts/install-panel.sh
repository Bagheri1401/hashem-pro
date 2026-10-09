#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$EUID" -ne 0 ]]; then echo 'Run as root: sudo bash scripts/install-panel.sh'; exit 1; fi
SRC="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "$SRC/grefrp/app.py" ]] || { echo 'Project source not found'; exit 1; }
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-venv python3-pip iproute2 openssh-client curl tar ca-certificates
bash "$SRC/scripts/install-frp.sh"
install -d -m 0700 /etc/grefrp /etc/grefrp/nodes /var/lib/grefrp
install -d -m 0755 /opt/grefrp-manager
cp -a "$SRC/grefrp" "$SRC/templates" "$SRC/static" "$SRC/requirements.txt" /opt/grefrp-manager/
python3 -m venv /opt/grefrp-manager/.venv
/opt/grefrp-manager/.venv/bin/python -m pip install --no-cache-dir -r /opt/grefrp-manager/requirements.txt
if [[ ! -f /etc/grefrp/id_ed25519 ]]; then
  ssh-keygen -q -t ed25519 -N '' -f /etc/grefrp/id_ed25519
fi
chmod 600 /etc/grefrp/id_ed25519
chmod 644 /etc/grefrp/id_ed25519.pub
touch /etc/grefrp/known_hosts
chmod 600 /etc/grefrp/known_hosts
if [[ -e /etc/grefrp/panel.env ]]; then
  echo 'Existing panel.env retained (admin password is not reset).'
else
  read -rp 'Choose admin username [admin]: ' ADMIN_USERNAME
  ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
  [[ "$ADMIN_USERNAME" =~ ^[a-zA-Z][a-zA-Z0-9_-]{2,31}$ ]] || { echo 'Invalid username'; exit 1; }
  read -rsp 'New admin password (minimum 12 characters): ' P1; echo
  read -rsp 'Repeat password: ' P2; echo
  [[ "${#P1}" -ge 12 && "$P1" == "$P2" ]] || { echo 'Password too short or mismatch'; exit 1; }
  HASH="$(printf '%s' "$P1" | python3 -c 'import sys,os,hashlib; s=os.urandom(16); v=hashlib.pbkdf2_hmac("sha256",sys.stdin.buffer.read(),s,500000); print("pbkdf2_sha256$"+s.hex()+"$"+v.hex())')"
  unset P1 P2
  SECRET="$(python3 -c 'import secrets; print(secrets.token_urlsafe(64))')"
  umask 077
  printf 'ADMIN_USERNAME=%s\nADMIN_PASSWORD_HASH=%s\nSESSION_SECRET=%s\nSESSION_SECURE=0\nGRE_FRP_DATA=/var/lib/grefrp\nGRE_FRP_ETC=/etc/grefrp\n' \
    "$ADMIN_USERNAME" "$HASH" "$SECRET" > /etc/grefrp/panel.env
  chmod 600 /etc/grefrp/panel.env
fi
cat > /etc/systemd/system/grefrp-panel.service <<'UNIT'
[Unit]
Description=Private GRE + FRP management panel
Wants=network-online.target
After=network-online.target
[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/grefrp-manager
EnvironmentFile=/etc/grefrp/panel.env
ExecStart=/opt/grefrp-manager/.venv/bin/uvicorn grefrp.app:app --host 127.0.0.1 --port 8765 --workers 1
Restart=always
RestartSec=3
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now grefrp-panel.service
printf '\n===== Panel installed =====\n'
printf 'Local URL: http://127.0.0.1:8765\n'
printf 'Public SSH key to authorize on each foreign node:\n'
cat /etc/grefrp/id_ed25519.pub
printf '\nConnect from workstation: ssh -N -L 8765:127.0.0.1:8765 root@IRAN_SERVER_IP\n'
printf 'Do NOT expose port 8765 publicly. See README.md for verified SSH known_hosts setup.\n'
