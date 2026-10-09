#!/usr/bin/env bash
# Installs the LB- classifier as a systemd service on Kali Linux (or any Debian/Ubuntu).
# Usage:  sudo ./install_kali.sh              -> install / update
#         sudo ./install_kali.sh --uninstall  -> remove the service
# Needs lb_classifier.py in the same folder as this script.
set -euo pipefail

APP_DIR=/opt/lb-classifier
DATA_DIR=/srv/documents
SVC=lb-classifier
SVC_USER=lb-classifier
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${EUID}" -ne 0 ]; then
  echo "Run with sudo:  sudo ./install_kali.sh" >&2
  exit 1
fi

# ---------- uninstall ----------
if [ "${1:-}" = "--uninstall" ]; then
  systemctl disable --now "$SVC" 2>/dev/null || true
  rm -f "/etc/systemd/system/$SVC.service"
  systemctl daemon-reload
  echo "Service removed. $APP_DIR and $DATA_DIR are still there (delete them by hand if you want)."
  exit 0
fi

# ---------- checks ----------
[ -f "$HERE/lb_classifier.py" ] || { echo "lb_classifier.py must be next to this script" >&2; exit 1; }
if [ ! -d /run/systemd/system ]; then
  echo "This system is not running systemd (WSL without systemd?)." >&2
  echo "On WSL enable it in /etc/wsl.conf ([boot] systemd=true) and restart WSL," >&2
  echo "or run by hand: python3 lb_classifier.py" >&2
  exit 1
fi

# ---------- packages ----------
echo "[1/6] Installing packages..."
apt-get update -qq
apt-get install -y -qq python3 python3-venv python3-pip

# ---------- user and folders ----------
echo "[2/6] Creating user and folders..."
id -u "$SVC_USER" >/dev/null 2>&1 || \
  useradd --system --home-dir "$APP_DIR" --shell /usr/sbin/nologin "$SVC_USER"
mkdir -p "$APP_DIR" "$DATA_DIR/input" "$DATA_DIR/output"

# ---------- app + venv ----------
echo "[3/6] Installing script and dependencies (venv)..."
install -m 644 "$HERE/lb_classifier.py" "$APP_DIR/lb_classifier.py"
[ -d "$APP_DIR/.venv" ] || python3 -m venv "$APP_DIR/.venv"
"$APP_DIR/.venv/bin/pip" install -q --upgrade pip
"$APP_DIR/.venv/bin/pip" install -q requests pypdf python-docx

# ---------- configuration ----------
echo "[4/6] Configuration..."
if [ ! -f "$APP_DIR/.env" ]; then
  read -rsp "Paste your CODIV_API_KEY (sk-codiv-...): " API_KEY; echo
  cat > "$APP_DIR/.env" <<ENVEOF
CODIV_API_KEY=$API_KEY
INPUT_DIR=$DATA_DIR/input
OUTPUT_DIR=$DATA_DIR/output
PREFIX=LB-
MODEL=jevk5-0.2
CONFIDENCE_THRESHOLD=0.5
POLL_INTERVAL=5
ENVEOF
else
  echo "   .env already exists, leaving it as is."
fi
chmod 600 "$APP_DIR/.env"

# ---------- permissions ----------
echo "[5/6] Permissions..."
chown -R "$SVC_USER:$SVC_USER" "$APP_DIR"
chown root:root "$APP_DIR/.env"
chown -R "$SVC_USER:$SVC_USER" "$DATA_DIR"
chmod 2775 "$DATA_DIR" "$DATA_DIR/input" "$DATA_DIR/output"
# the user who ran sudo can drop files into input/ (scp, sftp...)
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  usermod -aG "$SVC_USER" "$SUDO_USER"
  echo "   $SUDO_USER added to group $SVC_USER (log out and back in for it to apply)."
fi

# ---------- service ----------
echo "[6/6] Creating systemd service..."
cat > "/etc/systemd/system/$SVC.service" <<UNITEOF
[Unit]
Description=LB- document classifier (Codiv System One)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SVC_USER
Group=$SVC_USER
WorkingDirectory=$APP_DIR
EnvironmentFile=$APP_DIR/.env
ExecStart=$APP_DIR/.venv/bin/python $APP_DIR/lb_classifier.py
Restart=always
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$DATA_DIR

[Install]
WantedBy=multi-user.target
UNITEOF

systemctl daemon-reload
systemctl enable --now "$SVC"
sleep 2
systemctl --no-pager --full status "$SVC" | head -n 12 || true

cat <<DONEEOF

Done.
  Input folder:   $DATA_DIR/input     (only files starting with LB- are processed)
  Results:        $DATA_DIR/output/<category>
  Logs:           journalctl -u $SVC -f
  Change config:  sudo nano $APP_DIR/.env && sudo systemctl restart $SVC
  Send a file:    scp LB-report.pdf $(hostname -I | awk '{print $1}'):$DATA_DIR/input/
DONEEOF
