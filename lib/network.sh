#!/usr/bin/env bash
# shellcheck disable=SC2034
# Shared install network policy. Source before any fetch; dry runs never probe.
# auto-mode detection: both endpoints must answer (github.com reachability alone does
# not imply raw/codeload works), and no -f — a proxy 4xx still proves reachability.
network_github_reachable() {
  curl -sSI --connect-timeout 2 --max-time 4 https://github.com >/dev/null 2>&1 &&
  curl -sSI --connect-timeout 2 --max-time 4 https://raw.githubusercontent.com >/dev/null 2>&1
}
network_init() {
  MIRROR=${MIRROR:-global}
  case $MIRROR in
    auto)
      if [[ ${NETWORK_DRY_RUN:-0} == 1 ]]; then
        MIRROR=global; echo 'mirror mode: global (auto: dry run, not probing)'
      elif network_github_reachable; then
        MIRROR=global; echo 'mirror mode: global (auto: github.com and raw.githubusercontent.com reachable)'
      else
        MIRROR=cn; echo 'mirror mode: cn (auto: github unreachable)'
      fi ;;
    cn|global) echo "mirror mode: $MIRROR" ;;
    *) echo 'MIRROR must be cn, global or auto' >&2; return 2 ;;
  esac
  export MIRROR
  if [[ $MIRROR == cn ]]; then
    export npm_config_registry=https://registry.npmmirror.com
    export PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
    export GOPROXY=https://goproxy.cn
    export RUSTUP_DIST_SERVER=https://rsproxy.cn
    export RUSTUP_UPDATE_ROOT=https://rsproxy.cn/rustup
    export CARGO_REGISTRIES_CRATES_IO_INDEX=sparse+https://rsproxy.cn/index/
  fi
}
network_fetch() {
  local out=$1 url rc; shift
  local opts=(--connect-timeout 5 --max-time "${NETWORK_DOWNLOAD_TIMEOUT:-3600}"
    --retry 3 --retry-all-errors --retry-delay 2)
  for url in "$@"; do
    # Resume into $out.part and keep it across retries and candidates; callers
    # delete it only on checksum mismatch.
    if curl -fL -C - "${opts[@]}" -o "$out.part" "$url"; then
      mv "$out.part" "$out"; return 0
    else
      rc=$?
    fi
    if (( rc == 33 )); then
      # The server cannot resume (or the .part is already complete); restart clean.
      rm -f "$out.part"
      if curl -fL "${opts[@]}" -o "$out.part" "$url"; then
        mv "$out.part" "$out"; return 0
      fi
    fi
  done
  echo "All download candidates failed for $out" >&2; return 1
}
network_select_alarm() {
  local base
  if [[ -n ${OMARCHY_ALARM_TARBALL_URL:-} ]]; then ALARM_URL=$OMARCHY_ALARM_TARBALL_URL; return; fi
  if [[ $MIRROR == global ]]; then ALARM_URL=http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz; return; fi
  ALARM_CANDIDATES=(https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm https://mirrors.ustc.edu.cn/archlinuxarm https://mirrors.bfsu.edu.cn/archlinuxarm https://mirror.sjtu.edu.cn/archlinuxarm)
  for base in "${ALARM_CANDIDATES[@]}"; do
    if [[ ${NETWORK_DRY_RUN:-0} == 1 ]] || ! command -v curl >/dev/null 2>&1 || curl -fsSL --connect-timeout 3 --max-time 8 "$base/os/ArchLinuxARM-aarch64-latest.tar.gz.md5" >/dev/null; then
      ALARM_URL=$base/os/ArchLinuxARM-aarch64-latest.tar.gz; return
    fi
  done
  echo 'No mainland ALARM mirror reachable' >&2; return 1
}
network_pacman_config() {
  local file=$1
  [[ $MIRROR == cn ]] || return 0
  mkdir -p "$(dirname "$file")"
  [[ ! -f $file || -f $file.omarchy-original ]] || cp -p "$file" "$file.omarchy-original"
  cat > "$file" <<'MIRRORS'
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm/$arch/$repo
Server = https://mirrors.ustc.edu.cn/archlinuxarm/$arch/$repo
Server = https://mirrors.bfsu.edu.cn/archlinuxarm/$arch/$repo
Server = https://mirror.sjtu.edu.cn/archlinuxarm/$arch/$repo
MIRRORS
}
# Probe one mainland mirror for both Debian archives (trixie and trixie-security).
network_apt_base_ok() {
  local base=$1
  curl -fsSL --connect-timeout 3 --max-time 8 "$base/debian/dists/trixie/Release" >/dev/null &&
  curl -fsSL --connect-timeout 3 --max-time 8 "$base/debian-security/dists/trixie-security/Release" >/dev/null
}
# True when a CA bundle exists and at least one mainland mirror answers over HTTPS.
network_apt_https_ok() {
  command -v curl >/dev/null 2>&1 || return 0
  [[ -s /etc/ssl/certs/ca-certificates.crt ]] || return 1
  local base
  for base in https://mirrors.tuna.tsinghua.edu.cn https://mirrors.ustc.edu.cn https://mirrors.aliyun.com; do
    network_apt_base_ok "$base" && return 0
  done
  return 1
}
network_apt_config() {
  [[ $MIRROR == cn ]] || return 0
  local dir=${1:-/etc/apt} base file scheme host
  base=${NETWORK_APT_BASE:-}
  if [[ -z $base ]]; then
    if ! command -v curl >/dev/null 2>&1; then
      base=https://mirrors.tuna.tsinghua.edu.cn
    else
      for scheme in https http; do
        # HTTP is only the CA-bootstrap fallback (Release metadata is signature-
        # checked): before ca-certificates is installed every HTTPS probe fails.
        for host in mirrors.tuna.tsinghua.edu.cn mirrors.ustc.edu.cn mirrors.aliyun.com; do
          if network_apt_base_ok "$scheme://$host"; then base=$scheme://$host; break 2; fi
        done
      done
    fi
  fi
  [[ -n $base ]] || { echo 'No mainland Debian mirror reachable' >&2; return 1; }
  # Preserve all user sources; replace only known Debian archive URI prefixes.
  for file in "$dir/sources.list" "$dir"/sources.list.d/*.list "$dir"/sources.list.d/*.sources; do
    [[ -f $file ]] || continue
    [[ -f $file.omarchy-original ]] || cp -p "$file" "$file.omarchy-original"
    sed -i -E "s|https?://mirrors.(tuna.tsinghua.edu.cn\|ustc.edu.cn\|aliyun.com)/(debian-security\|debian)([/[:space:]]\|$)|$base/\\2\\3|g; s|https?://(deb.debian.org/debian-security\|security.debian.org/debian-security)|$base/debian-security|g; s|https?://(deb.debian.org\|ftp.debian.org)/debian([/[:space:]]\|$)|$base/debian\\2|g" "$file"
  done
}
network_unpack_omarchy() {
  local root=$1 dest=$2 staging
  [[ ! -e $dest ]] || { echo "Refusing to replace existing checkout: $dest" >&2; return 1; }
  (cd "$root/vendor" && sha256sum -c SHA256SUMS) || return 1
  mkdir -p "$(dirname "$dest")"
  staging=$(mktemp -d "${dest}.tmp.XXXXXX")
  if ! { cat "$root"/vendor/omarchy-v4.0.4.git.tar.gz.part-* | tar -xz -C "$staging" &&
         git -C "$staging" reset --hard v4.0.4; }; then
    rm -rf -- "$staging"; return 1
  fi
  mv -T "$staging" "$dest"
}

network_download_rootfs() {
  local tarball=$1 url want base
  # 790 MiB rootfs: allow a long transfer (resumed via $tarball.part) unless overridden.
  local NETWORK_DOWNLOAD_TIMEOUT=${NETWORK_ROOTFS_TIMEOUT:-${NETWORK_DOWNLOAD_TIMEOUT:-7200}}
  local candidates=("$ALARM_URL")
  if [[ $MIRROR == cn && -z ${OMARCHY_ALARM_TARBALL_URL:-} ]]; then
    for base in "${ALARM_CANDIDATES[@]}"; do
      url=$base/os/ArchLinuxARM-aarch64-latest.tar.gz
      [[ $url == "$ALARM_URL" ]] || candidates+=("$url")
    done
  fi
  for url in "${candidates[@]}"; do
    network_fetch "$tarball.md5" "$url.md5" || continue
    want=$(awk '{print $1; exit}' "$tarball.md5")
    [[ $want =~ ^[0-9a-fA-F]{32}$ ]] || continue
    if [[ ! -f $tarball || $(md5sum "$tarball" | awk '{print $1}') != "$want" ]]; then
      network_fetch "$tarball" "$url" || continue
    fi
    if [[ $(md5sum "$tarball" | awk '{print $1}') == "$want" ]]; then
      ALARM_URL=$url; return 0
    fi
    echo "Rootfs checksum mismatch from $url" >&2
    # Only a checksum mismatch discards the download; keep partials otherwise.
    rm -f "$tarball" "$tarball.part"
  done
  echo 'No mirror delivered a checksum-valid rootfs' >&2; return 1
}

network_apt_update() {
  local dir=${1:-/etc/apt} base
  local options=(-o Acquire::Retries=2 -o Acquire::http::Timeout=15
    -o Acquire::https::Timeout=15 -o APT::Update::Error-Mode=any)
  if [[ $MIRROR == global ]]; then
    DEBIAN_FRONTEND=noninteractive apt-get "${options[@]}" update; return
  fi
  if ! network_apt_https_ok; then
    # CA bootstrap over plain HTTP first: apt verifies the Release signatures anyway,
    # so this is authentic; the loop below switches the sources back to HTTPS.
    for base in http://mirrors.tuna.tsinghua.edu.cn http://mirrors.ustc.edu.cn http://mirrors.aliyun.com; do
      NETWORK_APT_BASE=$base network_apt_config "$dir" || continue
      if DEBIAN_FRONTEND=noninteractive apt-get "${options[@]}" update &&
         DEBIAN_FRONTEND=noninteractive apt-get "${options[@]}" install -y --no-install-recommends ca-certificates; then
        break
      fi
    done
  fi
  for base in https://mirrors.tuna.tsinghua.edu.cn https://mirrors.ustc.edu.cn https://mirrors.aliyun.com; do
    NETWORK_APT_BASE=$base network_apt_config "$dir" || continue
    if DEBIAN_FRONTEND=noninteractive apt-get "${options[@]}" update; then return 0; fi
  done
  echo 'All mainland apt mirrors failed to update' >&2; return 1
}
