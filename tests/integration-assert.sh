#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=../lib/machine-id.sh
source /src/lib/machine-id.sh
machine_id_valid /etc/machine-id
cmp -s /etc/machine-id /var/lib/dbus/machine-id
echo 'PASS persistent container machine identity'
home=$(getent passwd testuser | cut -d: -f6)
for directory in Work Desktop Documents Downloads Music Pictures Public Templates Videos; do
  [[ -d $home/$directory ]]
  [[ $(stat -c %U "$home/$directory") == testuser ]]
done
[[ -f $home/.config/user-dirs.dirs ]]
grep -Fxq 'XDG_DESKTOP_DIR="$HOME/Desktop"' "$home/.config/user-dirs.dirs"
grep -Fxq 'XDG_TEMPLATES_DIR="$HOME/Templates"' "$home/.config/user-dirs.dirs"
grep -Fxq 'XDG_PUBLICSHARE_DIR="$HOME/Public"' "$home/.config/user-dirs.dirs"
pacman -Q uwsm hyprland-guiutils ttf-jetbrains-mono-nerd tree-sitter-cli
[[ $(runuser -u testuser -- env PATH=/usr/local/bin:/usr/bin sh -c 'command -v uwsm-app') == /usr/local/bin/uwsm-app ]]
echo 'PASS desktop home directories, repository additions, and uwsm-app shim precedence'
checkout="$home/.local/share/omarchy"
[[ $(readlink /usr/share/omarchy) == "$checkout" ]]
for binary in Hyprland quickshell fcitx5 foot; do command -v "$binary"; done
[[ -f $home/.config/hypr/hyprland.lua ]]
grep -Fq 'kb_options = "caps:super,compose:ralt"' "$home/.config/hypr/input.lua"
if grep -Fq 'shift:both_capslock_cancel' "$home/.config/hypr/input.lua"; then
  echo 'Forbidden Shift-swallowing keyboard option' >&2; exit 1
fi
grep -Fq 'schema: luna_pinyin_simp' "$home/.local/share/fcitx5/rime/default.custom.yaml"
grep -Fq 'OK Rime schema deployment' "$home/.local/state/omarchy-alarm/desktop-config.txt"
[[ -s $home/.local/share/fcitx5/rime/build/luna_pinyin_simp.prism.bin ]]
# librime reuses the distribution's precompiled dictionary when available.
[[ -s $home/.local/share/fcitx5/rime/build/luna_pinyin.table.bin || -s /usr/share/rime-data/build/luna_pinyin.table.bin ]]
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

# A fresh desktop install must not create AI configuration, credentials or skills.
for path in .config/mise .config/herdr .config/opencode .claude .codex .pi .agents .hermes; do
  [[ ! -e $home/$path ]] || { echo "Unexpected AI user configuration: $path" >&2; exit 1; }
done
[[ -s $home/.local/state/omarchy-alarm/tool-programs.txt ]]
echo 'PASS programs-only AI boundary'
