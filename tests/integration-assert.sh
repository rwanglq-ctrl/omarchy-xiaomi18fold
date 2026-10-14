#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../lib/machine-id.sh
source /src/lib/machine-id.sh
machine_id_valid /etc/machine-id
cmp -s /etc/machine-id /var/lib/dbus/machine-id
echo 'PASS persistent container machine identity'
home=$(getent passwd testuser | cut -d: -f6)
checkout="$home/.local/share/omarchy"
[[ $(readlink /usr/share/omarchy) == "$checkout" ]]
for binary in Hyprland quickshell fcitx5 foot; do command -v "$binary"; done
[[ -f $home/.config/hypr/hyprland.lua ]]
base=$(cat /src/patches/BASE)
[[ $(runuser -u testuser -- git -C "$checkout" branch --show-current) == arm-port ]]
for patch in /src/patches/*.patch; do
  patch_id=$(git patch-id --stable < "$patch" | awk '{print $1}')
  runuser -u testuser -- git -C "$checkout" log -p "$base..HEAD" | git patch-id --stable | awk '{print $1}' | grep -Fx "$patch_id"
done
[[ -z $(runuser -u testuser -- git -C "$checkout" status --porcelain) ]]
install -d -o testuser -g testuser -m700 /run/omarchy-test
runuser -u testuser -- env -i HOME="$home" USER=testuser PATH=/usr/local/bin:/usr/bin XDG_RUNTIME_DIR=/run/omarchy-test Hyprland --verify-config -c "$home/.config/hypr/hyprland.lua"
# Load the actual patched singleton consumers with the installed Qt/Quickshell,
# without requiring a compositor in the package-install integration environment.
color_test=$(mktemp -d /tmp/omarchy-colors.XXXXXX)
trap 'rm -rf -- "$color_test"' EXIT
cp -a "$checkout/shell/Commons" "$color_test/Commons"
cp /src/tests/shell-colors.qml "$color_test/shell.qml"
chown -R testuser:testuser "$color_test"
runuser -u testuser -- env -i HOME="$home" USER=testuser PATH=/usr/bin XDG_RUNTIME_DIR=/run/omarchy-test QT_QPA_PLATFORM=offscreen timeout 20 qs -p "$color_test" > "$color_test/result.log" 2>&1
cat "$color_test/result.log"
grep -Fq 'PASS shell color roles and Style resolution' "$color_test/result.log"
! grep -Eq 'TypeError|ReferenceError|Failed to load configuration|FAIL shell' "$color_test/result.log"
