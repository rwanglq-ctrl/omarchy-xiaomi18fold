#!/usr/bin/env bash
# Create missing desktop directories without replacing user files or links.
set -euo pipefail

for name in Work Desktop Documents Downloads Music Pictures Public Templates Videos; do
  path="$HOME/$name"
  if [[ -e $path || -L $path ]]; then
    if [[ ! -d $path ]]; then
      printf 'WARNING: keeping existing non-directory %s; directory not created.\n' "$path" >&2
    fi
  else
    mkdir -p -- "$path"
  fi
done

# Equivalent to the initial xdg-user-dirs-update defaults, but unlike running
# that program on every install, never rewrite existing user preferences.
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
if [[ -e $config_home && ! -d $config_home ]] || [[ -L $config_home && ! -d $config_home ]]; then
  printf 'WARNING: keeping non-directory %s; XDG defaults not created.\n' "$config_home" >&2
  exit 0
fi
mkdir -p -- "$config_home"
config="$config_home/user-dirs.dirs"
if [[ ! -e $config && ! -L $config ]]; then
  # noclobber also protects against a concurrent file creation.
  if ! (set -o noclobber; cat > "$config" <<'XDG'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_PUBLICSHARE_DIR="$HOME/Public"
XDG_TEMPLATES_DIR="$HOME/Templates"
XDG_VIDEOS_DIR="$HOME/Videos"
XDG
  ); then
    printf 'WARNING: unable to seed %s; existing files are preserved.\n' "$config" >&2
  fi
fi
