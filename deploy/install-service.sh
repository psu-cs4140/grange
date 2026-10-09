#!/usr/bin/env bash
# Installs the checked-in Phoenix systemd unit on the deployment host.
set -euo pipefail

SERVICE_SOURCE="$HOME/grange/grange.service"
SERVICE_TARGET="$HOME/.config/systemd/user/grange.service"

export XDG_RUNTIME_DIR="/run/user/$(id -u)"

install -D -m 0644 "$SERVICE_SOURCE" "$SERVICE_TARGET"
systemctl --user daemon-reload
systemctl --user enable grange
