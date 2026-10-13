#!/usr/bin/env bash
# Real download stages in disposable Debian 13 arm64; requires Docker + binfmt QEMU.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
args=(--rm --platform linux/arm64 --network host --volume "$ROOT:/src:ro")
blocked=(github.com raw.githubusercontent.com objects.githubusercontent.com codeload.github.com
  api.github.com release-assets.githubusercontent.com github-releases.githubusercontent.com
  google.com www.google.com dl.google.com fonts.googleapis.com fonts.gstatic.com
  accounts.google.com storage.googleapis.com www.gstatic.com googleapis.com gstatic.com
  dl-ssl.google.com www.googleapis.com fonts.google.com aur.archlinux.org
  deb.debian.org security.debian.org ftp.debian.org os.archlinuxarm.org mirror.archlinuxarm.org
  registry.npmjs.org pypi.org files.pythonhosted.org proxy.golang.org sum.golang.org
  static.rust-lang.org index.crates.io crates.io static.crates.io mise.run)
for host in "${blocked[@]}"; do args+=(--add-host "$host:0.0.0.0"); done
docker run "${args[@]}" debian:trixie bash /src/tests/china-downloads-inside.sh
