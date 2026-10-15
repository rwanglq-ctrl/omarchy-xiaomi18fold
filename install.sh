#!/usr/bin/env bash
# install.sh — one-click entry for omarchy-alarm-nspawn.
#
#   curl -fsSL https://raw.githubusercontent.com/rwanglq-ctrl/omarchy-xiaomipad9pm/main/install.sh | bash
#   ./install.sh [--dry-run] [--user NAME] [--profile core|full] [--yes]
#
# Debian 13 aarch64 (Android Linux Terminal host):
#   host/install.sh prepares the host and the Arch Linux ARM container, then this repo is
#   copied into the container (/opt/omarchy-alarm-nspawn) and container/install.sh runs
#   inside it as the user.
# Arch Linux ARM (already inside the container): container/install.sh only.
# Anything else: error, exit 2.
#
# Extra options passed through: --rootfs DIR, --no-display-hook, --no-home-binds (host),
# --no-aur (container). Environment: OMARCHY_ALARM_REPO / OMARCHY_ALARM_REF select what a
# piped (curl | bash) run clones. Git is required; Debian can install it via apt.

set -euo pipefail

# Shared with host/install.sh by sourcing this file. Keep the piped entry
# self-contained: the checkout does not exist when session protection starts.
omarchy_session_apt() (
  set -e
  local base mode=${MIRROR:-global}
  work=
  local privilege=() options=(-o Acquire::Retries=2 -o Acquire::http::Timeout=15 -o Acquire::https::Timeout=15)
  (( EUID == 0 )) || privilege=(sudo)
  if [[ $mode == auto ]]; then
    if command -v curl >/dev/null &&
       curl -sSI --connect-timeout 2 --max-time 4 https://github.com >/dev/null 2>&1 &&
       curl -sSI --connect-timeout 2 --max-time 4 https://raw.githubusercontent.com >/dev/null 2>&1; then
      mode=global
    else
      mode=cn
    fi
  fi
  printf '%s\n' '安装 tmux / Installing tmux (apt, noninteractive)' >&2
  if [[ $mode == cn ]]; then
    # Match the git bootstrap: signed Debian metadata, temporary CN sources,
    # no changes to user sources and no GitHub access (even without CA certs).
    work=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-tmux-apt.XXXXXX") || return 1
    trap 'rm -rf -- "$work"' EXIT
    chmod 755 "$work" || return 1
    for base in mirrors.tuna.tsinghua.edu.cn mirrors.ustc.edu.cn mirrors.aliyun.com; do
      printf 'deb http://%s/debian trixie main\n' "$base" > "$work/bootstrap.list" || return 1
      chmod 644 "$work/bootstrap.list" || return 1
      if "${privilege[@]}" env DEBIAN_FRONTEND=noninteractive apt-get "${options[@]}" -o APT::Update::Error-Mode=any -o Dir::Etc::sourcelist="$work/bootstrap.list" -o Dir::Etc::sourceparts=- update &&
         "${privilege[@]}" env DEBIAN_FRONTEND=noninteractive apt-get "${options[@]}" -o Dir::Etc::sourcelist="$work/bootstrap.list" -o Dir::Etc::sourceparts=- install -y --no-install-recommends tmux ca-certificates; then
        return 0
      fi
    done
    return 1
  fi
  "${privilege[@]}" env DEBIAN_FRONTEND=noninteractive apt-get "${options[@]}" -o APT::Update::Error-Mode=any update || return 1
  "${privilege[@]}" env DEBIAN_FRONTEND=noninteractive apt-get "${options[@]}" install -y --no-install-recommends tmux ca-certificates
)

omarchy_session_instructions() {
  local log=$1 prefix=''
  # A root host child may still be on the invoking user's tmux server.
  # A fresh terminal must attach as that socket owner, not create a root server.
  if (( EUID == 0 )) && [[ -z ${TMUX:-} || $(stat -c %u "${TMUX%%,*}" 2>/dev/null || echo 0) == 0 ]]; then
    prefix='sudo '
  fi
  printf '%s\n' \
    '安装在 tmux 中运行；终端待机/SSH 断线不会终止安装（虚拟机关机或重启除外）。' \
    'Installation runs in tmux; terminal standby/SSH disconnect will not kill it (VM shutdown/reboot is excluded).' \
    "重新连接 / Reattach: ${prefix}tmux attach -t omarchy-install" \
    "日志 / Log: $log" \
    "跟随日志 / Follow log: ${prefix}tail -f '$log'" >&2
  if [[ -n ${TMUX_TMPDIR:-} ]]; then
    printf '自定义 socket 目录 / Custom socket directory: export TMUX_TMPDIR=%q\n' "$TMUX_TMPDIR" >&2
  fi
}

omarchy_install_session() {
  local dry=$1 entry=$2; shift 2
  (( ! dry )) || return 0
  if ! command -v tmux >/dev/null; then
    omarchy_session_apt || { echo '无法安装 tmux / Cannot install tmux; retry after fixing apt' >&2; return 1; }
  fi
  command -v tmux >/dev/null || { echo '无法安装 tmux / Cannot install tmux' >&2; return 1; }
  local current='' state log runner name value
  local settings='OMARCHY_*|NETWORK_*|MIRROR|TMPDIR|TMUX_TMPDIR|PATH|HOME|USER|LOGNAME|SUDO_USER|SUDO_UID|SUDO_GID|LANG|LC_*|http_proxy|https_proxy|all_proxy|no_proxy|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY'
  if [[ -n ${TMUX:-} ]]; then
    current=$(tmux display-message -p -t "${TMUX_PANE:-}" '#{session_name}' 2>/dev/null || true)
  fi
  if [[ -n ${OMARCHY_INSTALL_LOG:-} && $current != omarchy-install ]]; then
    echo '安装会话验证失败 / Cannot verify inherited install session; refusing to continue' >&2
    return 1
  fi
  if [[ $current == omarchy-install ]]; then
    # The root host child inherits the same output descriptors and log marker.
    if [[ -z ${OMARCHY_INSTALL_LOG:-} ]]; then
      state=$HOME/.local/state/omarchy-alarm
      (umask 077; mkdir -p "$state"; touch "$state/install.log")
      export OMARCHY_INSTALL_LOG=$state/install.log
      exec > >(tee -a "$OMARCHY_INSTALL_LOG") 2>&1
      printf '\n=== Install started: %s ===\n' "$(date -Is)"
    fi
    omarchy_session_instructions "$OMARCHY_INSTALL_LOG"
    return 0
  fi
  state=$HOME/.local/state/omarchy-alarm
  log=$state/install.log
  omarchy_session_instructions "$log"
  if ! tmux has-session -t '=omarchy-install' 2>/dev/null; then
    (umask 077; mkdir -p "$state"; touch "$log")
    runner=$(mktemp "$state/install-run.XXXXXX")
    # A new session on an existing server otherwise inherits stale environment.
    # Save only install settings, never unrelated API keys or login credentials.
    {
      printf '#!/usr/bin/env bash\nset -uo pipefail\n'
      # Remove stale settings inherited from an older server, including settings
      # absent in this invocation. TERM belongs to tmux and is not overridden.
      printf 'while IFS= read -r name; do case $name in %s) unset "$name" ;; esac; done < <(compgen -e)\n' "$settings"
      while IFS= read -r name; do
        case $name in
          OMARCHY_*|NETWORK_*|MIRROR|TMPDIR|TMUX_TMPDIR|PATH|HOME|USER|LOGNAME|SUDO_USER|SUDO_UID|SUDO_GID|LANG|LC_*|http_proxy|https_proxy|all_proxy|no_proxy|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY)
            [[ $name != OMARCHY_INSTALL_LOG ]] || continue
            value=${!name}; printf 'export %s=%q\n' "$name" "$value" ;;
        esac
      done < <(compgen -e)
      printf 'export OMARCHY_INSTALL_LOG=%q\n' "$log"
      printf 'exec 3>&1 4>&2\nexec > >(tee -a "$OMARCHY_INSTALL_LOG") 2>&1\nlog_pid=$!\n'
      printf 'printf "\\n=== Install started: %%s ===\\n" "$(date -Is)"\n'
      if [[ -z $entry ]]; then
        # Reconstruct the fully-read curl|bash entry before any clone or long work.
        # Its bootstrap/cleanup now belongs to the detached process, not the client.
        declare -f omarchy_session_apt omarchy_session_instructions omarchy_install_session omarchy_entry
        printf '( set -e; omarchy_entry'
      else
        printf '( bash %q' "$entry"
      fi
      if (( $# )); then printf ' %q' "$@"; fi
      printf ' ) </dev/null\nrc=$?\n'
      printf 'printf "\\n安装退出码 / Install exit status: %%s\\n" "$rc"\n'
      printf 'rm -f -- %q\n' "$runner"
      printf 'echo "安装结束；可在此重跑安装命令。/ Finished; rerun the install command here."\n'
      printf 'exec 1>&3 2>&4 3>&- 4>&-\nwait "$log_pid" || echo "Log writer failed" >&2\nunset OMARCHY_INSTALL_LOG\n'
      printf 'exec bash --noprofile --norc -i\n'
    } > "$runner"
    # Create detached first: losing the client while attaching cannot kill work.
    # Exact targets avoid matching similarly named user sessions.
    if ! tmux new-session -d -s omarchy-install -c "$PWD" bash "$runner"; then
      rm -f -- "$runner"
      tmux has-session -t '=omarchy-install' 2>/dev/null || return 1
    fi
  else
    printf '%s\n' '使用已有安装会话，本次参数未重新执行 / Using existing install session; new arguments were not executed' >&2
  fi
  if [[ -n ${TMUX:-} ]]; then
    tmux switch-client -t '=omarchy-install' || true
  elif [[ -t 1 ]]; then
    # main uses /dev/null. Reuse the real terminal fd: tmux rejects /dev/tty
    # as its tty name, even though opening that device succeeds.
    tmux attach -t '=omarchy-install' <&1
  fi
  printf '%s\n' '已交接至会话；安装结果请查看日志。/ Session handoff complete; check the log for the install result.' >&2
  # Returning would start a second installer in the original, fragile terminal.
  exit 0
}

omarchy_entry() {
# Everything lives in functions called on the last line, so a piped script is read in full
# before anything runs (and nothing below can swallow the rest of it from stdin).

REPO_URL=${OMARCHY_ALARM_REPO:-}
REPO_REF=${OMARCHY_ALARM_REF:-main}
CONTAINER_REPO=/opt/omarchy-alarm-nspawn

log()  { printf '==> %s\n' "$*" >&2; }
note() { printf '    %s\n' "$*" >&2; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }

usage() {
  cat <<'EOF'
Usage: install.sh [--dry-run] [--user NAME] [--profile core|full] [--yes]
                  [--rootfs DIR] [--no-display-hook] [--no-home-binds] [--no-aur]

  --dry-run          print what would be done; change nothing
  --user NAME        desktop user (default: the invoking user)
  --profile P        core = Omarchy desktop + Chinese input; full = core + extra apps
  --yes              allow host/install.sh to move aside a non-Arch directory at --rootfs
  --rootfs DIR       container rootfs on a Debian host (default: /var/lib/machines/arch)
  --no-display-hook  Debian host: do not hook the Android Terminal display (weston.service)
  --no-home-binds    Debian host: do not share ~/Downloads ~/Pictures ~/Videos ~/Work
  --mirror MODE      global (default), cn, or auto; also MIRROR environment
  --no-aur           container: skip yay and AUR packages
EOF
}

# q ARGS...: shell-quoted command line for display.
q() { printf ' %q' "$@"; }

# Locate the checkout this script belongs to, or clone one when run from a pipe.
find_repo() {
  local src=${BASH_SOURCE[0]:-} dir
  if [[ -n $src && -f $src ]]; then
    dir=$(cd "$(dirname "$src")" && pwd)
    if [[ -f $dir/host/install.sh && -d $dir/container ]]; then
      REPO_DIR=$dir
      return 0
    fi
  fi
  [[ -z ${OMARCHY_ALARM_BOOTSTRAPPED:-} ]] || die "bootstrapped checkout is incomplete (no host/install.sh)"
  bootstrap "$@"
}

bootstrap() (
  # This subshell owns the checkout and removes it on success, failure or signal.
  # tmp is subshell-global, not local: the EXIT trap can run after the function
  # frame is gone (errexit on the last command), where a local is unbound.
  local revision base clone_ref
  tmp=
  local privilege=() apt_options=(-o Acquire::Retries=2 -o Acquire::http::Timeout=15 -o Acquire::https::Timeout=15)
  if [[ ${MIRROR:-global} == auto ]] && (( ! dry )); then
    if command -v curl >/dev/null &&
       curl -sSI --connect-timeout 2 --max-time 4 https://github.com >/dev/null 2>&1 &&
       curl -sSI --connect-timeout 2 --max-time 4 https://raw.githubusercontent.com >/dev/null 2>&1; then
      export MIRROR=global
    else
      export MIRROR=cn
    fi
  fi
  # Select source after auto detection. Explicit CN never contacts GitHub.
  if [[ $REPO_URL == gitee || ( -z $REPO_URL && ${MIRROR:-global} == cn ) ]]; then
    REPO_URL=https://gitee.com/zenbardofsuhe/omarchy-xiaomipad9pm
  elif [[ -z $REPO_URL ]]; then
    REPO_URL=https://github.com/rwanglq-ctrl/omarchy-xiaomipad9pm
  fi
  if (( dry )); then
    log "DRY RUN: require git (Debian: apt-get update/install git ca-certificates), clone $REPO_URL, checkout $REPO_REF; no fetch or writes"
    exit 0
  fi
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-alarm-nspawn.XXXXXX")
  trap 'rm -rf -- "$tmp"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if ! command -v git >/dev/null; then
    [[ $OS == debian ]] && command -v apt-get >/dev/null || die "git is required; install git and run this installer again"
    if (( EUID != 0 )); then
      command -v sudo >/dev/null || die "git is required; ask the host administrator to install git with apt"
      privilege=(sudo)
    fi
    log 'git is required; installing git and ca-certificates with apt'
    if [[ ${MIRROR:-global} == cn ]]; then
      # Bootstrap without needing lib/network.sh or changing the user's sources.
      # HTTP transport is authenticated by Debian's signed Release metadata.
      for base in mirrors.tuna.tsinghua.edu.cn mirrors.ustc.edu.cn mirrors.aliyun.com; do
        printf 'deb http://%s/debian trixie main\n' "$base" > "$tmp/bootstrap.list"
        chmod 755 "$tmp"; chmod 644 "$tmp/bootstrap.list"
        if "${privilege[@]}" apt-get "${apt_options[@]}" -o APT::Update::Error-Mode=any -o Dir::Etc::sourcelist="$tmp/bootstrap.list" -o Dir::Etc::sourceparts=- update &&
           "${privilege[@]}" env DEBIAN_FRONTEND=noninteractive apt-get "${apt_options[@]}" -o Dir::Etc::sourcelist="$tmp/bootstrap.list" -o Dir::Etc::sourceparts=- install -y --no-install-recommends git ca-certificates; then break; fi
      done
    else
      "${privilege[@]}" apt-get "${apt_options[@]}" -o APT::Update::Error-Mode=any update
      "${privilege[@]}" env DEBIAN_FRONTEND=noninteractive apt-get "${apt_options[@]}" install -y --no-install-recommends git ca-certificates
    fi
    command -v git >/dev/null || die "git installation failed; install git with apt and retry"
  fi
  log "fetching $REPO_URL ($REPO_REF)"
  clone_ref=$REPO_REF
  # A SHA is not a branch name. Fetch main plus full history, then resolve it.
  [[ ! $REPO_REF =~ ^[[:xdigit:]]{7,40}$ ]] || clone_ref=main
  GIT_TERMINAL_PROMPT=0 timeout 300 git clone --quiet --no-checkout --branch "$clone_ref" -- "$REPO_URL" "$tmp/repo" \
    || die "git clone failed; use a reachable trusted OMARCHY_ALARM_REPO or a local checkout"
  # Clone first: --branch accepts branch/tag names, not commit SHAs.
  revision=$(git -C "$tmp/repo" rev-parse --verify --end-of-options "$REPO_REF^{commit}" 2>/dev/null) ||
    revision=$(git -C "$tmp/repo" rev-parse --verify --end-of-options "refs/remotes/origin/$REPO_REF^{commit}" 2>/dev/null) ||
    die "ref '$REPO_REF' was not found in $REPO_URL"
  git -C "$tmp/repo" checkout --quiet --detach "$revision"
  [[ -f $tmp/repo/install.sh ]] || die "fetched repo has no install.sh"
  log "source revision: $revision"
  OMARCHY_ALARM_BOOTSTRAPPED=1 bash "$tmp/repo/install.sh" "$@" </dev/null
)

detect_os() {
  local rel=${OMARCHY_ALARM_OS_RELEASE:-/etc/os-release} id ver like
  local arch=${OMARCHY_ALARM_ARCH:-$(uname -m)}
  [[ -r $rel ]] || die "cannot read $rel to detect the OS" 2
  # shellcheck disable=SC1090
  id=$(. "$rel" && echo "${ID:-}")
  # shellcheck disable=SC1090
  ver=$(. "$rel" && echo "${VERSION_ID:-}")
  # shellcheck disable=SC1090
  like=$(. "$rel" && echo "${ID_LIKE:-}")
  if [[ $id == debian && $arch == aarch64 ]]; then
    [[ $ver == 13 ]] || die "Debian $ver is not supported; this needs Debian 13 (trixie) aarch64" 2
    OS=debian
  elif [[ $arch == aarch64 && ( $id == archarm || $id == arch || $like == arch ) ]]; then
    OS=archarm
  else
    die "unsupported system: ${id:-unknown} ${ver} on $arch. Supported: Debian 13 aarch64 (host) or Arch Linux ARM aarch64 (container)" 2
  fi
}

main() {
  local dry=0 yes=0 user="" profile="" rootfs=/var/lib/machines/arch
  local host_extra=() container_extra=()
  local all_args=("$@")
  while (( $# )); do
    case "$1" in
      --dry-run) dry=1 ;;
      --yes|-y) yes=1 ;;
      --user) [[ $# -ge 2 ]] || die "--user needs a value"; user=$2; shift ;;
      --user=*) user=${1#*=} ;;
      --profile) [[ $# -ge 2 ]] || die "--profile needs a value"; profile=$2; shift ;;
      --profile=*) profile=${1#*=} ;;
      --rootfs) [[ $# -ge 2 ]] || die "--rootfs needs a value"; rootfs=$2; shift ;;
      --rootfs=*) rootfs=${1#*=} ;;
      --no-display-hook|--no-home-binds) host_extra+=("$1") ;;
      --mirror) [[ $# -ge 2 ]] || die "--mirror needs a value"; export MIRROR=$2; shift ;;
      --mirror=*) export MIRROR=${1#*=} ;;
      --no-aur) container_extra+=("$1") ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; die "unknown option: $1" 2 ;;
    esac
    shift
  done
  if [[ -n $profile && $profile != core && $profile != full ]]; then
    die "--profile must be core or full" 2
  fi
  [[ -n $profile ]] && container_extra=(--profile "$profile" "${container_extra[@]}")

  case ${MIRROR:-global} in cn|global|auto) ;; *) die "MIRROR must be cn, global or auto" 2 ;; esac
  detect_os
  if [[ $OS == debian ]]; then
    local entry=${BASH_SOURCE[0]:-}
    [[ -f $entry ]] && entry=$(realpath "$entry") || entry=''
    omarchy_install_session "$dry" "$entry" "${all_args[@]}"
  fi
  REPO_DIR=""
  find_repo "${all_args[@]}"
  # Piped bootstrap runs the complete child installer (or prints a dry plan).
  [[ -n $REPO_DIR ]] || return 0
  # shellcheck source=lib/network.sh
  source "$REPO_DIR/lib/network.sh"
  export NETWORK_DRY_RUN=$dry
  network_init
  detect_os
  (( dry )) && log "DRY RUN — nothing will be changed"
  log "repo: $REPO_DIR"
  log "system: $OS"

  if [[ $OS == archarm ]]; then
    run_container_local "$dry" "$user" "${container_extra[@]}"
  else
    run_debian "$dry" "$yes" "$user" "$rootfs" "${#host_extra[@]}" "${host_extra[@]}" "${container_extra[@]}"
  fi
}

# Already inside Arch Linux ARM: container/install.sh only.
run_container_local() {
  local dry=$1 user=$2; shift 2
  local cmd=(bash "$REPO_DIR/container/install.sh")
  (( dry )) && cmd+=(--dry-run)
  [[ -n $user ]] && cmd+=(--user "$user")
  cmd+=("$@")
  log "container plan: Omarchy on Arch Linux ARM"
  printf '  +%s\n' "$(q "${cmd[@]}")"
  if [[ ! -f $REPO_DIR/container/install.sh ]]; then
    if (( dry )); then
      warn "container/install.sh is not in this checkout yet; nothing more to show"
      return 0
    fi
    die "container/install.sh is missing from $REPO_DIR"
  fi
  "${cmd[@]}" </dev/null
}

# Debian host: host side first, then the container side inside the new rootfs.
run_debian() {
  local dry=$1 yes=$2 user=$3 rootfs=$4 nhost=$5; shift 5
  local host_extra=("${@:1:$nhost}") container_extra=("${@:$((nhost + 1))}")
  if [[ -z $user ]]; then
    if [[ $EUID -eq 0 ]]; then
      user=${SUDO_USER:-}
      [[ -n $user && $user != root ]] || die "running as root: pass --user NAME (your desktop user)"
    else
      user=$(id -un)
    fi
  fi
  local sudo=()
  [[ $EUID -eq 0 ]] || sudo=(sudo)

  local host_cmd=(bash "$REPO_DIR/host/install.sh" --user "$user" --rootfs "$rootfs" "${host_extra[@]}")
  (( yes )) && host_cmd+=(--yes)
  log "host side"
  if (( dry )); then
    "${host_cmd[@]}" --dry-run
  else
    "${sudo[@]}" env MIRROR="$MIRROR" TMUX="${TMUX:-}" TMUX_PANE="${TMUX_PANE:-}" TMUX_TMPDIR="${TMUX_TMPDIR:-}" OMARCHY_INSTALL_LOG="${OMARCHY_INSTALL_LOG:-}" TMPDIR="${TMPDIR:-/tmp}" "${host_cmd[@]}" </dev/null
  fi

  local chome=/home/$user
  local nspawn=("${sudo[@]}" env SYSTEMD_NSPAWN_LOCK=0 systemd-nspawn -q -D "$rootfs" --register=no
    --resolv-conf=off -u "$user" --chdir="$chome"
    --setenv=MIRROR="$MIRROR" --setenv=HOME="$chome" --setenv=LANG=en_US.UTF-8 --setenv=TERM="${TERM:-xterm-256color}")
  nspawn+=(--console=pipe)
  nspawn+=(bash "$CONTAINER_REPO/container/install.sh" "${container_extra[@]}")

  log "copy this repo into the container: $rootfs$CONTAINER_REPO"
  if (( dry )); then
    printf '  + rm -rf %q && mkdir -p %q\n' "$rootfs$CONTAINER_REPO" "$rootfs$CONTAINER_REPO"
    printf '  + tar -C %q --exclude=.git -cf - . | tar -C %q -xf -\n' "$REPO_DIR" "$rootfs$CONTAINER_REPO"
    log "container side (as $user inside the container)"
    printf '  +%s\n' "$(q "${nspawn[@]}")"
    note "(the container plan itself can be previewed inside Arch with: install.sh --dry-run)"
    return 0
  fi
  # Never let an empty variable turn this into rm -rf of a host directory.
  [[ -n "$rootfs" && "$rootfs" != / && "$CONTAINER_REPO" == /opt/?* ]] \
    || die "refusing to replace '$rootfs$CONTAINER_REPO'"
  "${sudo[@]}" rm -rf "$rootfs$CONTAINER_REPO"
  "${sudo[@]}" mkdir -p "$rootfs$CONTAINER_REPO"
  tar -C "$REPO_DIR" --exclude=.git -cf - . | "${sudo[@]}" tar -C "$rootfs$CONTAINER_REPO" --no-same-owner -xf -
  "${sudo[@]}" chmod -R a+rX "$rootfs$CONTAINER_REPO"

  log "container side (as $user inside the container)"
  "${nspawn[@]}" </dev/null

  log "done"
  note "set the display mode: ~/.local/bin/hypr-switch arch"
  note "then fully close and reopen the Linux Terminal app to start Arch"
  note "shell in the container: archbox (or archsh while the Arch desktop runs)"
}

main "$@" </dev/null
}

# Sourcing exposes only the session helpers and entry function to host/install.sh.
if [[ -z ${BASH_SOURCE[0]:-} || ${BASH_SOURCE[0]} == "$0" ]]; then
  omarchy_entry "$@"
fi
