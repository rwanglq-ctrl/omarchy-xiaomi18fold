#!/usr/bin/env bash
# omarchy-alarm-nspawn: non-boot containers need a persistent D-Bus identity.
# ROOT is a filesystem root, never a prefix to dereference absolute guest links.
machine_id_valid() {
  local file=$1 size
  [[ ! -L $file && -f $file ]] || return 1
  size=$(wc -c < "$file")
  [[ $size == 32 || $size == 33 ]] || return 1
  # Validate bytes before shell substitution can discard embedded NULs.
  # A 33rd byte is permitted only as the trailing newline, never a leading one.
  [[ $size == 32 || $(tail -c 1 -- "$file" | od -An -tu1) =~ ^[[:space:]]*10[[:space:]]*$ ]] || return 1
  LC_ALL=C grep -aqxE '[0-9a-f]{32}' "$file" || return 1
  LC_ALL=C grep -aq '[1-9a-f]' "$file"
}

ensure_machine_identity() {
  local root tmp value target
  [[ $# == 1 && $1 == /* ]] || { echo "usage: arch-machine-id [--check] ROOT" >&2; return 2; }
  root=$(realpath -e -- "$1") || return 1
  [[ $root != / ]] || root=''
  # Do not follow guest directory links into the host filesystem.
  for target in etc var var/lib var/lib/dbus; do
    [[ ! -L $root/$target ]] || { echo "machine-id-invalid: linked directory $target" >&2; return 1; }
  done
  mkdir -p "$root/etc" "$root/var/lib/dbus" || return 1
  if machine_id_valid "$root/etc/machine-id"; then
    echo 'machine-id: ok'
  else
    value=$(tr -d '-' < /proc/sys/kernel/random/uuid) || return 1
    [[ $value =~ ^[0-9a-f]{32}$ ]] || return 1
    tmp=$(mktemp "$root/etc/.machine-id.XXXXXXXX") || return 1
    if ! { printf '%s\n' "$value" > "$tmp" && chmod 444 "$tmp" && mv -fT -- "$tmp" "$root/etc/machine-id"; }; then
      rm -f -- "$tmp"; return 1
    fi
    echo 'machine-id: initialized'
  fi
  target="$root/var/lib/dbus/machine-id"
  # readlink reads the link text. cat/test -e here would resolve /etc on HOST.
  if [[ -L $target && $(readlink -- "$target") == /etc/machine-id ]]; then
    return 0
  fi
  if machine_id_valid "$target" && cmp -s -- "$root/etc/machine-id" "$target"; then
    return 0
  fi
  [[ ! -d $target || -L $target ]] || { echo 'machine-id-invalid: dbus identity is a directory' >&2; return 1; }
  rm -f -- "$target" && ln -s /etc/machine-id "$target"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  set -euo pipefail
  if [[ ${1:-} == --check ]]; then
    [[ $# == 2 && $2 == /* ]] || { echo "usage: arch-machine-id --check ROOT" >&2; exit 2; }
    root=$(realpath -e -- "$2") || exit 1; root=${root%/}
    for target in etc var var/lib var/lib/dbus; do
      [[ ! -L $root/$target ]] || { echo "machine-id-invalid: linked directory $target" >&2; exit 1; }
    done
    if machine_id_valid "$root/etc/machine-id"; then echo 'machine-id: valid'; else echo 'machine-id: missing, empty or invalid'; fi
    if [[ -L $root/var/lib/dbus/machine-id && $(readlink -- "$root/var/lib/dbus/machine-id") == /etc/machine-id ]]; then
      echo 'dbus link: ok'
    elif machine_id_valid "$root/var/lib/dbus/machine-id" && cmp -s "$root/etc/machine-id" "$root/var/lib/dbus/machine-id"; then
      echo 'dbus identity: matching regular file'
    else
      echo 'dbus link: missing or bad-target'
    fi
  else
    ensure_machine_identity "$@"
  fi
fi
