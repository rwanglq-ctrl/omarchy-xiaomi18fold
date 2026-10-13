#!/usr/bin/env bash
set -euo pipefail
[[ $(uname -m) == aarch64 ]]
# Debian base lacks curl and may lack a usable CA bundle. Always bootstrap apt over
# plain HTTP first (Release metadata is signature-checked, so this is authentic);
# network_apt_update below switches the sources back to HTTPS once ca-certificates
# is installed.
sources=/etc/apt/sources.list.d/debian.sources
if [[ -f $sources ]]; then
  sed -i 's|http://deb.debian.org/debian-security|http://mirrors.tuna.tsinghua.edu.cn/debian-security|g; s|http://deb.debian.org/debian|http://mirrors.tuna.tsinghua.edu.cn/debian|g' "$sources"
fi
apt_opts=(-o Acquire::Retries=2 -o Acquire::http::Timeout=15 -o Acquire::https::Timeout=15)
apt-get "${apt_opts[@]}" update
apt-get "${apt_opts[@]}" install -y --no-install-recommends curl ca-certificates git libarchive-tools gpg
# shellcheck source=../lib/network.sh
source /src/lib/network.sh
MIRROR=auto; network_init
[[ $MIRROR == cn ]]
for host in github.com raw.githubusercontent.com google.com deb.debian.org os.archlinuxarm.org registry.npmjs.org pypi.org proxy.golang.org static.rust-lang.org; do
  if curl --noproxy '*' -fsSL --connect-timeout 1 --max-time 2 "https://$host" >/dev/null 2>&1; then echo "Block failed: $host"; exit 1; fi
done
network_apt_update
network_select_alarm
mkdir -p /tmp/downloads
network_download_rootfs /tmp/downloads/rootfs.tar.gz
mkdir /tmp/alarm
bsdtar -xpf /tmp/downloads/rootfs.tar.gz -C /tmp/alarm
network_pacman_config /tmp/alarm/etc/pacman.d/mirrorlist
# Download every configured sync DB without needing nested nspawn privileges.
for repo in core extra alarm; do
  urls=()
  for base in "${ALARM_CANDIDATES[@]}"; do urls+=("$base/aarch64/$repo/$repo.db"); done
  network_fetch "/tmp/downloads/$repo.db" "${urls[@]}"
  bsdtar -tf "/tmp/downloads/$repo.db" >/dev/null
done
mkdir -p /tmp/alarm/var/lib/pacman/sync
cp /tmp/downloads/{core,extra,alarm}.db /tmp/alarm/var/lib/pacman/sync/
mapfile -t names < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' /src/packages/repo-*.txt)
chroot /tmp/alarm /usr/bin/pacman -Si "${names[@]}" >/dev/null
network_unpack_omarchy /src /tmp/omarchy
[[ $(git -C /tmp/omarchy rev-parse HEAD) == "$(cat /src/patches/BASE)" ]]
for patch in /src/patches/*.patch; do git -C /tmp/omarchy -c user.name=test -c user.email=noreply@example.com am "$patch"; done
# Installer plans must propagate mode to host and nspawn without changing this VM.
useradd -m tester
MIRROR=cn bash /src/install.sh --dry-run --user tester --profile core
printf 'PASS Debian arm64 blocked-host apt/rootfs/extraction/pacman DB/vendor/patch/dry-run stages\n'
