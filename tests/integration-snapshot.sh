#!/usr/bin/env bash
set -euo pipefail
# Compare installed packages and managed content/modes/links. Logs, font caches,
# access times and the installer's own log are runtime data, not managed config.
# Rime updates user.yaml's last_build_time on every deploy; compare all other
# Rime configuration and compiled content, and retain its mode/path check.
home=$(getent passwd testuser | cut -d: -f6)
pacman -Q | sort
for path in /etc/machine-id /var/lib/dbus/machine-id "$home/.config" "$home/.local/bin" "$home/.local/share/omarchy" "$home/.local/share/fcitx5/rime" "$home/.bashrc" /usr/local/bin/uwsm-app /usr/share/omarchy; do
  find "$path" -type f -not -path '*/.git/*' -not -path "$home/.local/share/fcitx5/rime/user.yaml" -print0 | sort -z | xargs -0 -r sha256sum
  find "$path" -not -path '*/.git/*' -printf '%p %m %u %g %l\n' | sort
 done
