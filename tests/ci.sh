#!/usr/bin/env bash
set -euo pipefail
mode=${1:---quick}
[[ $mode == --quick || $mode == --full ]]
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CACHE="$HOME/.cache/omarchy-alarm-tests"
mkdir -p "$CACHE"
export TMPDIR="$CACHE"
# Reuse/resume the official checksum-valid rootfs just like the installer.
# shellcheck source=../lib/network.sh
source "$ROOT/lib/network.sh"
export MIRROR=global
network_select_alarm
network_download_rootfs "$CACHE/rootfs.tar.gz"
docker import --platform linux/arm64 "$CACHE/rootfs.tar.gz" omarchy-alarm-test:local >/dev/null
emulated=0
[[ $(uname -m) == aarch64 ]] || emulated=1
quick_budget=${ALARM_TEST_QUICK_BUDGET:-115}
if [[ $(uname -m) != aarch64 && -z ${ALARM_TEST_QUICK_BUDGET:-} ]]; then quick_budget=600; fi
args=(--rm --env ALARM_TEST_EMULATED="$emulated" --env ALARM_TEST_QUICK_BUDGET="$quick_budget" --platform linux/arm64 --network host --volume "$ROOT:/src:ro" --workdir /src)
# The full suite needs nested namespaces/mounts. Quick receives no privilege.
if [[ $mode == --full ]]; then args+=(--privileged); fi
docker run "${args[@]}" omarchy-alarm-test:local /bin/bash -euc '
  # pacman 7 downloads as the sandboxed "alpm" user under Landlock, which the runner'"'"'s
  # unprivileged Docker refuses. Disable it only in this throwaway CI container.
  grep -q "^DisableSandbox" /etc/pacman.conf || sed -i "/^\[options\]/a DisableSandbox" /etc/pacman.conf
  pacman-key --init
  pacman-key --populate archlinuxarm
  # Match the installer: the host supplies the kernel, so avoid initramfs hooks.
  if pacman -Q linux-aarch64 >/dev/null 2>&1; then pacman -Rns --noconfirm linux-aarch64 || true; fi
  pacman -Syu --noconfirm --needed git curl python lua sudo ripgrep jq which diffutils findutils util-linux bubblewrap systemd
  useradd -m -s /bin/bash tester
  printf "tester ALL=(ALL) NOPASSWD: ALL\n" > /etc/sudoers.d/tester
  chmod 440 /etc/sudoers.d/tester
  test_home=$(getent passwd tester | cut -d: -f6)
  cache="$test_home/.cache/omarchy-alarm-tests"
  install -d -o tester -g tester "$cache"
  curl -fL --retry 3 https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.aarch64.tar.xz -o "$cache/shellcheck.tar.xz"
  tar -xJf "$cache/shellcheck.tar.xz" -C "$cache"
  runuser -u tester -- env HOME="$test_home" ALARM_TEST_EMULATED="$ALARM_TEST_EMULATED" ALARM_TEST_QUICK_BUDGET="$ALARM_TEST_QUICK_BUDGET" bash /src/tests/run.sh "$1"
' bash "$mode"
