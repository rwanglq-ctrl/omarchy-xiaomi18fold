#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../lib/network.sh
source "$ROOT/lib/network.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Fake curl records attempts, fails first mainland candidate and forbidden domains.
curl() {
  printf '%s\n' "$*" >> "$work/attempts"
  case "$*" in *github.com*|*tuna.tsinghua.edu.cn*) return 7 ;; esac
  local out='' prev='' arg
  for arg in "$@"; do [[ $prev != -o ]] || out=$arg; prev=$arg; done
  [[ -z $out ]] || printf 'payload\n' > "$out"
}
MIRROR=cn; network_init
network_select_alarm
[[ $ALARM_URL == https://mirrors.ustc.edu.cn/* ]]
network_fetch "$work/download" https://mirrors.tuna.tsinghua.edu.cn/a https://mirrors.ustc.edu.cn/a
[[ $(cat "$work/download") == payload && ! -e $work/download.part ]]
network_pacman_config "$work/mirrorlist"
! grep -Eq 'os.archlinuxarm.org|mirror.archlinuxarm.org' "$work/mirrorlist"
# shellcheck disable=SC2154
[[ $npm_config_registry == https://registry.npmmirror.com && $GOPROXY == https://goproxy.cn ]]
MIRROR=auto; network_init
[[ $MIRROR == cn ]]
MIRROR=global; network_init
network_select_alarm
[[ $ALARM_URL == http://os.archlinuxarm.org/* ]]
MIRROR=invalid; if network_init; then exit 1; fi
mkdir -p "$work/apt/sources.list.d"
printf 'deb http://deb.debian.org/debian trixie main\ndeb https://security.debian.org/debian-security trixie-security main\n' > "$work/apt/sources.list"
printf 'Types: deb\nURIs: https://deb.debian.org/debian\nSuites: trixie\n' > "$work/apt/sources.list.d/debian.sources"
MIRROR=cn; network_init
network_apt_config "$work/apt"
! grep -Eq 'deb.debian.org|security.debian.org' "$work/apt/sources.list" "$work/apt/sources.list.d/debian.sources"
grep -q deb.debian.org "$work/apt/sources.list.omarchy-original"
# A metadata fetch failure must advance to the next mirror, without losing backups.
apt_calls=0
apt-get() { apt_calls=$((apt_calls + 1)); [[ $apt_calls -gt 1 ]]; }
network_apt_update "$work/apt"
[[ $apt_calls == 2 ]]
grep -q mirrors.ustc.edu.cn "$work/apt/sources.list"
# Dry-run detection cannot invoke curl.
before=$(wc -l < "$work/attempts")
MIRROR=auto; NETWORK_DRY_RUN=1 network_init
[[ $MIRROR == global && $(wc -l < "$work/attempts") == "$before" ]]
echo 'PASS mirror policy, fallback, downloads, apt backups, dry-run and invalid mode'
