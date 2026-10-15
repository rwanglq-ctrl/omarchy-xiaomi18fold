#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export HOME="$work/home"
unset XDG_CONFIG_HOME
mkdir -p "$HOME"
bash "$ROOT/lib/home-layout.sh"
for name in Work Desktop Documents Downloads Music Pictures Public Templates Videos; do
  [[ -d $HOME/$name ]]
done
[[ $(wc -l < "$HOME/.config/user-dirs.dirs") == 8 ]]
grep -Fx 'XDG_PUBLICSHARE_DIR="$HOME/Public"' "$HOME/.config/user-dirs.dirs"
before=$(sha256sum "$HOME/.config/user-dirs.dirs")
bash "$ROOT/lib/home-layout.sh"
[[ $(sha256sum "$HOME/.config/user-dirs.dirs") == "$before" ]]

# Preserve content and choices; never source arbitrary existing XDG config.
printf 'touch "%s/should-not-exist"\n' "$work" > "$HOME/.config/user-dirs.dirs"
rmdir "$HOME/Work" "$HOME/Documents" "$HOME/Templates"
printf 'existing work file\n' > "$HOME/Work"
ln -s "$work/missing-target" "$HOME/Documents"
mkdir "$work/user-templates"
ln -s "$work/user-templates" "$HOME/Templates"
before=$(sha256sum "$HOME/Work" "$HOME/.config/user-dirs.dirs")
bash "$ROOT/lib/home-layout.sh"
[[ $(sha256sum "$HOME/Work" "$HOME/.config/user-dirs.dirs") == "$before" ]]
[[ -L $HOME/Documents && ! -e $work/missing-target ]]
[[ -L $HOME/Templates && ! -e $work/should-not-exist ]]
rm "$HOME/.config/user-dirs.dirs"
ln -s "$work/missing-config" "$HOME/.config/user-dirs.dirs"
bash "$ROOT/lib/home-layout.sh"
[[ -L $HOME/.config/user-dirs.dirs && ! -e $work/missing-config ]]

export XDG_CONFIG_HOME="$work/custom-config"
bash "$ROOT/lib/home-layout.sh"
[[ -f $XDG_CONFIG_HOME/user-dirs.dirs ]]
for package in uwsm hyprland-guiutils ttf-jetbrains-mono-nerd tree-sitter-cli; do
  grep -Fxq "$package" "$ROOT/packages/repo-core.txt"
done
grep -Fq 'step initialize_home_layout ' "$ROOT/container/install.sh"
grep -Fq 'pacman -Si yaru-icon-theme' "$ROOT/container/install.sh"
echo 'PASS home layout, existing-file preservation, and core desktop packages'
