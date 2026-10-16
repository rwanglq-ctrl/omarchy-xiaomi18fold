#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
profile=core
dry_run=false
no_aur=false
target_user=''
usage() {
  echo 'Usage: container/install.sh [--dry-run] [--profile core|full] [--no-aur] [--user NAME] [--mirror cn|global|auto]'
  echo 'Both profiles install pinned mise and AI programs without tool config or credentials.'
}
while (($#)); do
  case "$1" in
    --mirror) (($# >= 2)) || exit 2; MIRROR=$2; shift 2 ;;
    --mirror=*) MIRROR=${1#*=}; shift ;;
    --dry-run) dry_run=true; shift ;;
    --no-aur) no_aur=true; shift ;;
    --profile|--user)
      (($# >= 2)) || { usage >&2; exit 2; }
      case "$1" in --profile) profile=$2 ;; --user) target_user=$2 ;; esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ $profile == core || $profile == full ]] || { usage >&2; exit 2; }

# shellcheck source=../lib/network.sh
source "$ROOT/lib/network.sh"
NETWORK_DRY_RUN=$($dry_run && echo 1 || echo 0) network_init
if [[ $MIRROR == cn ]]; then
  echo "CN mode: programs and desktop extras use verified CN sources."
fi

step() {
  local function=$1 description=$2
  printf '\n==> %s: %s\n' "$function" "$description" >&2
  if ! $dry_run; then "$function"; fi
}
as_root() { sudo -- "$@" </dev/null; }
packages() {
  local kind=$1
  sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$ROOT/packages/$kind-core.txt"
  if [[ $profile == full ]]; then
    sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$ROOT/packages/$kind-full.txt"
  fi
}
validate_environment() {
  [[ $(uname -m) == aarch64 && -f /etc/arch-release ]] || {
    echo 'This installer requires Arch Linux ARM aarch64.' >&2; exit 2;
  }
  sudo -v
  mkdir -p "$HOME/.cache/tmp" "$HOME/.cache/makepkg" "$HOME/.local/bin" "$HOME/.local/state/omarchy-alarm"
  export TMPDIR="$HOME/.cache/tmp"
  export OMARCHY_PATH="$HOME/.local/share/omarchy"
  export PATH="$OMARCHY_PATH/bin:$HOME/.local/bin:$PATH"
}
initialize_machine_identity() { as_root bash "$ROOT/lib/machine-id.sh" /; }
initialize_home_layout() { bash "$ROOT/lib/home-layout.sh"; }
install_repo_packages() {
  local -a names
  mapfile -t names < <(packages repo)
  # A full upgrade avoids unsupported Arch partial upgrades.
  if [[ $MIRROR == cn ]]; then
    local mirrors
    mirrors=$(mktemp)
    network_pacman_config "$mirrors"
    if ! as_root test -e /etc/pacman.d/mirrorlist.omarchy-original; then
      as_root cp -p /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.omarchy-original
    fi
    as_root install -m644 "$mirrors" /etc/pacman.d/mirrorlist
    local conf
    conf=$(mktemp)
    as_root cat /etc/pacman.conf > "$conf"
    network_pacman_repos "$conf"
    if ! as_root test -e /etc/pacman.conf.omarchy-original; then
      as_root cp -p /etc/pacman.conf /etc/pacman.conf.omarchy-original
    fi
    as_root install -m644 "$conf" /etc/pacman.conf
    rm -f "$conf" "$conf.omarchy-original"
    rm -f "$mirrors" "$mirrors.omarchy-original"
  fi
  local mirror=mirror.archlinuxarm.org
  [[ $MIRROR != cn ]] || mirror=mirrors.tuna.tsinghua.edu.cn
  if ! timeout 30 getent hosts "$mirror"; then
    if [[ $MIRROR != cn ]]; then
      echo "Cannot resolve $mirror; refusing to run pacman" >&2
      return 1
    fi
    local dnsroot
    dnsroot=$(mktemp -d)
    # Explicit fallback also repairs old containers when rerun directly in Arch.
    network_resolv_config "$dnsroot" /dev/null /dev/null
    as_root rm -f /etc/resolv.conf
    as_root install -m644 "$dnsroot/etc/resolv.conf" /etc/resolv.conf
    rm -rf "$dnsroot"
    timeout 30 getent hosts "$mirror" || return 1
  fi
  as_root pacman -Syu --needed --noconfirm "${names[@]}"
  # Prefer a repository Yaru package when available; otherwise the verified
  # source bundle in install_aur_packages provides the architecture-any theme.
  if pacman -Si yaru-icon-theme >/dev/null 2>&1; then
    if ! as_root pacman -S --needed --noconfirm yaru-icon-theme; then
      echo 'WARNING: optional yaru-icon-theme installation failed; keeping installed icon themes.' >&2
    fi
  else
    echo 'yaru-icon-theme unavailable in ALARM; using the verified source bundle.' >&2
  fi
}
configure_build_directories() {
  mkdir -p "$HOME/.config/pacman" "$HOME/.cache/makepkg" "$HOME/.cache/tmp"
  local file="$HOME/.config/pacman/makepkg.conf"
  touch "$file"
  if ! grep -q '^# BEGIN omarchy-alarm build$' "$file"; then
    {
      printf '\n# BEGIN omarchy-alarm build\n'
      cat "$ROOT/config/pacman/makepkg.conf"
      printf '# END omarchy-alarm build\n'
    } >> "$file"
  fi
}
install_aur_packages() {
  mkdir -p "$HOME/.local/state/omarchy-alarm"
  : > "$HOME/.local/state/omarchy-alarm/aur-extras.txt"
  if $no_aur; then echo 'SKIPPED AUR: explicitly disabled' | tee -a "$HOME/.local/state/omarchy-alarm/aur-extras.txt"; return; fi
  if ! python3 "$ROOT/lib/desktop-extras.py" aur; then
    echo 'FAILED (nonfatal) AUR provisioning: helper failed; rerun to retry.' | tee -a "$HOME/.local/state/omarchy-alarm/aur-extras.txt" >&2
  fi
  if [[ $MIRROR == cn ]]; then
    local skipped
    mkdir -p "$HOME/.local/state/omarchy-alarm"
    while IFS= read -r skipped; do
      case "$skipped" in yay|tensaku|omawrite|aether|cliamp|ttfx|ttf-ia-writer|tree-sitter-cli|yaru-icon-theme) continue ;; esac
      printf 'SKIPPED %s: no verified CN source bundle; live AUR disabled in CN mode.\n' "$skipped" | tee -a "$HOME/.local/state/omarchy-alarm/aur-extras.txt"
    done < <(packages aur)
    return
  fi
  if ! command -v yay >/dev/null 2>&1; then
    echo 'FAILED (nonfatal) remaining AUR packages: yay unavailable.' | tee -a "$HOME/.local/state/omarchy-alarm/aur-extras.txt" >&2
    return
  fi
  local package
  while IFS= read -r package; do
    case "$package" in yay|tensaku|omawrite|aether|cliamp|ttfx|ttf-ia-writer|tree-sitter-cli|yaru-icon-theme) continue ;; esac
    if ! yay -S --needed --noconfirm "$package"; then
      printf 'FAILED (nonfatal) %s: yay installation failed.\n' "$package" | tee -a "$HOME/.local/state/omarchy-alarm/aur-extras.txt" >&2
    fi
  done < <(packages aur)
}
setup_lazyvim() {
  mkdir -p "$HOME/.local/state/omarchy-alarm"
  : > "$HOME/.local/state/omarchy-alarm/lazyvim-extras.txt"
  if ! python3 "$ROOT/lib/desktop-extras.py" lazyvim; then
    echo 'FAILED (nonfatal) LazyVim provisioning: helper failed; rerun to retry.' | tee -a "$HOME/.local/state/omarchy-alarm/lazyvim-extras.txt" >&2
  fi
}

clone_and_patch_omarchy() {
  local expected actual patch_file patch_id applied_ids
  expected=$(tr -d '\n' < "$ROOT/patches/BASE")
  if [[ ! -e $OMARCHY_PATH ]]; then
    if [[ $MIRROR == cn ]]; then network_unpack_omarchy "$ROOT" "$OMARCHY_PATH"
    else timeout 120 git clone --branch v4.0.4 --depth 1 https://github.com/basecamp/omarchy.git "$OMARCHY_PATH"; fi
  fi
  actual=$(git -C "$OMARCHY_PATH" rev-parse 'v4.0.4^{commit}')
  [[ $actual == "$expected" ]] || {
    echo 'Existing Omarchy checkout does not have the pinned base.' >&2; exit 1;
  }
  git -C "$OMARCHY_PATH" merge-base --is-ancestor "$expected" HEAD || {
    echo 'Existing Omarchy checkout is not based on the pinned release.' >&2; exit 1;
  }
  [[ -z $(git -C "$OMARCHY_PATH" status --porcelain) ]] || {
    echo 'Existing Omarchy checkout has local changes; preserve it before installing.' >&2; exit 1;
  }
  if git -C "$OMARCHY_PATH" show-ref --verify --quiet refs/heads/arm-port; then
    [[ $(git -C "$OMARCHY_PATH" branch --show-current) == arm-port ]] || {
      echo 'Existing arm-port branch is not checked out; refusing to switch user work.' >&2; exit 1;
    }
  else
    [[ $(git -C "$OMARCHY_PATH" rev-parse HEAD) == "$expected" ]] || {
      echo 'Refusing to create arm-port on an unrelated user commit.' >&2; exit 1;
    }
    git -C "$OMARCHY_PATH" switch -c arm-port
  fi
  for patch_file in "$ROOT"/patches/*.patch; do
    [[ -f $patch_file ]] || { echo 'No ARM patches found.' >&2; exit 1; }
    patch_id=$(git patch-id --stable < "$patch_file" | awk '{print $1}')
    applied_ids=$(git -C "$OMARCHY_PATH" log --pretty=format:%H -p "$expected..HEAD" | git patch-id --stable | awk '{print $1}')
    if ! grep -Fxq "$patch_id" <<< "$applied_ids"; then
      git -C "$OMARCHY_PATH" -c user.name=omarchy-alarm-nspawn -c user.email=noreply@example.com am "$patch_file"
    fi
  done
}

install_system_helpers() {
  if [[ -e /usr/share/omarchy && ! -L /usr/share/omarchy ]]; then
    echo '/usr/share/omarchy is a real directory; refusing to replace it.' >&2; exit 1
  fi
  as_root ln -sfnT "$OMARCHY_PATH" /usr/share/omarchy
  as_root install -Dm755 "$ROOT/container/bin/uwsm-app" /usr/local/bin/uwsm-app
}
seed_omarchy_config() {
  mkdir -p "$HOME/.config"
  # Seed missing defaults while retaining pre-existing user files.
  local item name
  for item in "$OMARCHY_PATH/config/"*; do
    name=${item##*/}
    case "$name" in fcitx5|nvim|herdr|opencode|mise|claude|codex|pi|crush|cursor|gh|omp) continue ;; esac
    if [[ $name == hypr ]]; then
      mkdir -p "$HOME/.config/hypr"
      local child
      for child in "$item/"* "$item/".[!.]* "$item/"..?*; do
        [[ -e $child || -L $child ]] || continue
        [[ ${child##*/} != input.lua ]] || continue
        cp -a --update=none "$child" "$HOME/.config/hypr/"
      done
    else
      cp -a --update=none "$item" "$HOME/.config/"
    fi
  done
}
install_input_defaults() {
  local target="$HOME/.config/hypr/input.lua"
  local baseline="$HOME/.local/state/omarchy-alarm/input.lua"
  local known_default=false hash
  if [[ -f $target && ! -L $target ]]; then
    hash=$(sha256sum "$target" | cut -d ' ' -f1)
    # Exact v0.2.0–v0.2.8 blob, interim v0.2.9 overlay, and released v0.2.9.
    case "$hash" in
      db40a8d86e57673cc37d3183c3307c4b98d0ff48839a46ef31d4cad1d400f805|a99d3741cd4070d9a32b6b301adda1f15273f876ae1b9438e4336db7734e1a5e|6ad1625ed77bda8fc6b0cd0921929ef6f796017a8a523b3af420a7600e5f2abe) known_default=true ;;
    esac
  fi
  # Only replace absent or byte-identical installer/upstream defaults. Never
  # follow a user symlink or overwrite an edited input file on repeat installs.
  if [[ ! -L $target ]] && { [[ ! -e $target ]] ||
      cmp -s "$target" "$baseline" ||
      cmp -s "$target" "$ROOT/config/hypr/input.lua" ||
      cmp -s "$target" "$OMARCHY_PATH/config/hypr/input.lua" ||
      $known_default; }; then
    install -Dm644 "$ROOT/config/hypr/input.lua" "$target"
    install -Dm644 "$ROOT/config/hypr/input.lua" "$baseline"
  else
    install -Dm644 "$ROOT/config/hypr/input.lua" "$baseline.dist"
    echo "Preserved edited/symlinked $target; reviewed defaults: $baseline.dist"
  fi
}
install_config_overlay() {
  local file relative
  while IFS= read -r -d '' file; do
    relative=${file#"$ROOT/config/"}
    # This file is merged by configure_build_directories, not overwritten.
    [[ $relative != pacman/makepkg.conf ]] || continue
    if [[ $relative == hypr/input.lua ]]; then install_input_defaults; continue; fi
    # IME preferences are absent-only seeds, including dangling user symlinks.
    if [[ $relative == fcitx5/* && ( -e $HOME/.config/$relative || -L $HOME/.config/$relative ) ]]; then continue; fi
    install -Dm644 "$file" "$HOME/.config/$relative"
  done < <(find "$ROOT/config" -type f -print0)
  install -Dm755 "$ROOT/container/bin/fcitx5-autostart" "$HOME/.local/bin/fcitx5-autostart"
  # Xiaomi 18 Fold helpers (display guard, touch flush, dock, OSK toggle, window menu)
  for _fold_bin in fold-display-guard fold-window-menu fold-touch-flush-req fold-dismiss-overlays \
      fold-session-rescue omarchy-osk-toggle fold-dock fold-drawer; do
    if [[ -f $ROOT/container/bin/$_fold_bin ]]; then
      install -Dm755 "$ROOT/container/bin/$_fold_bin" "$HOME/.local/bin/$_fold_bin"
    fi
  done
  install -Dm755 "$ROOT/container/bin/host-run" "$HOME/.local/bin/host-run"
  install -Dm755 "$ROOT/container/bin/portal-autostart" "$HOME/.local/bin/portal-autostart"
  install -Dm755 "$ROOT/container/bin/lock-ime-reset-autostart" "$HOME/.local/bin/lock-ime-reset-autostart"
}
configure_bashrc() {
  local rc="$HOME/.bashrc"
  touch "$rc"
  if ! grep -q '^# BEGIN omarchy-alarm shell$' "$rc"; then
    cat >> "$rc" <<'BASHRC'

# BEGIN omarchy-alarm shell
# Based on Omarchy default/bashrc, preserving the existing user file.
export OMARCHY_PATH="$HOME/.local/share/omarchy"
[[ -r "$OMARCHY_PATH/default/bash/env-bootstrap" ]] && source "$OMARCHY_PATH/default/bash/env-bootstrap"
export PATH="$OMARCHY_PATH/bin:$HOME/.local/bin:$PATH"
if [[ $- == *i* ]]; then
  source "$OMARCHY_PATH/default/bash/rc"
fi
# END omarchy-alarm shell
BASHRC
  fi
}
provision_user_headless() {
  # No graphical session or host dconf access; no copied identity or mise secrets.
  # --first-install marks shipped migrations done (bare-metal steps are wrong in nspawn).
  env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    OMARCHY_SETUP_CONTEXT=provision-owner OMARCHY_THEME_HEADLESS=1 OMARCHY_PROGRAMS_ONLY=1 \
    OMARCHY_USER_NAME='' OMARCHY_USER_EMAIL='' GSETTINGS_BACKEND=keyfile \
    "$OMARCHY_PATH/bin/omarchy-provision-user" --first-install
}
configure_input_and_fonts() {
  local rime="$HOME/.local/share/fcitx5/rime"
  local report="$HOME/.local/state/omarchy-alarm/desktop-config.txt"
  local preset="$ROOT/container/config-share/fcitx5/rime/default.custom.yaml"
  local legacy_default=false hash
  mkdir -p "$rime" "$HOME/.config/glib-2.0/settings" "${report%/*}"
  : > "$report"
  if [[ -f $rime/default.custom.yaml && ! -L $rime/default.custom.yaml ]]; then
    hash=$(sha256sum "$rime/default.custom.yaml" | cut -d ' ' -f1)
    # v0.2.8 preset blob and its schema-missing sed fallback, exactly.
    case "$hash" in
      29bc687af27a64bbdccda493acf037712ee7d0a58f8b15d5809db755f7e4b78d|b7f05d77a228ac3394fb3da4a091bca5547656f522bbfb40472bfc3ca8f2b0a2) legacy_default=true ;;
    esac
  fi
  if $legacy_default || [[ ! -e $rime/default.custom.yaml && ! -L $rime/default.custom.yaml ]]; then
    install -m644 "$ROOT/container/config-share/fcitx5/rime/default.custom.yaml" "$rime/default.custom.yaml"
    if [[ ! -f /usr/share/rime-data/rime_ice.schema.yaml ]]; then
      # Keep stock Chinese input usable if the optional schema failed.
      sed -i '/__include:/d; /schema: rime_ice/d' "$rime/default.custom.yaml"
    fi
  fi
  # Upgrade only the exact fallback this installer seeded when rime-ice was
  # unavailable. Arbitrary existing preferences and symlinks stay untouched.
  if [[ -f /usr/share/rime-data/rime_ice.schema.yaml && ! -L $rime/default.custom.yaml ]] &&
      cmp -s "$rime/default.custom.yaml" <(sed '/__include:/d; /schema: rime_ice/d' "$preset"); then
    install -m644 "$preset" "$rime/default.custom.yaml"
  fi
  if [[ -f $rime/default.custom.yaml && ! -L $rime/default.custom.yaml ]]; then
    mkdir -p "$rime/build"
    if rime_deployer --build "$rime" /usr/share/rime-data "$rime/build"; then
      echo 'OK Rime schema deployment (existing preferences retained)' | tee -a "$report"
    else
      echo 'FAILED (nonfatal) Rime schema deployment; inspect Rime build output and rerun installer.' | tee -a "$report" >&2
    fi
  else
    echo 'SKIPPED Rime deployment: preserved user configuration symlink or missing preset' | tee -a "$report"
  fi
  fc-cache -f
}
configure_stay_awake() {
  mkdir -p "$HOME/.local/state/omarchy/indicators"
  touch "$HOME/.local/state/omarchy/indicators/stay-awake"
  local status
  status=$(as_root passwd -S "$(id -un)" | awk '{print $2}')
  if [[ $status == L || $status == LK || $status == NP ]]; then
    echo 'WARNING: Password is locked or unset. Do not lock the desktop; set a password before enabling idle locking.'
  fi
  echo 'Stay-awake is ON. After setting a password, use omarchy toggle idle to enable idle locking.'
  OMARCHY_INSTALL_USER=$(id -un) "$OMARCHY_PATH/bin/omarchy-apply-lock"
}
install_tool_programs() {
  # Python catches/report failures separately for each optional program. Also
  # protect the desktop if Python/dependencies fail before that loop starts.
  mkdir -p "$HOME/.local/state/omarchy-alarm"
  : > "$HOME/.local/state/omarchy-alarm/tool-programs.txt"
  if ! python3 "$ROOT/lib/tool-programs.py"; then
    echo 'FAILED (nonfatal) AI program provisioning: helper failed; rerun to retry.' | tee -a "$HOME/.local/state/omarchy-alarm/tool-programs.txt" >&2
  fi
}

report_optional_results() {
  local report failed=false
  echo 'Optional installation results:'
  for report in aur-extras lazyvim-extras tool-programs desktop-config; do
    if [[ -f $HOME/.local/state/omarchy-alarm/$report.txt ]]; then
      cat "$HOME/.local/state/omarchy-alarm/$report.txt"
      if grep -q '^FAILED' "$HOME/.local/state/omarchy-alarm/$report.txt"; then failed=true; fi
    fi
  done
  if $failed; then
    echo 'WARNING: OPTIONAL ITEMS FAILED — the desktop is installed, but the items listed below are MISSING or INCOMPLETE. Rerun to retry.' >&2
    grep -h '^FAILED' "$HOME/.local/state/omarchy-alarm/"{aur-extras,lazyvim-extras,tool-programs,desktop-config}.txt >&2 2>/dev/null || true
  fi
}

if ! $dry_run; then
  if (( EUID == 0 )); then
    [[ -n $target_user && $target_user != root ]] || { echo 'Root must supply --user NAME.' >&2; exit 2; }
    args=(--profile "$profile")
    if $no_aur; then args+=(--no-aur); fi
    exec runuser -u "$target_user" -- env HOME="$(getent passwd "$target_user" | cut -d: -f6)" \
      MIRROR="$MIRROR" bash "$ROOT/container/install.sh" "${args[@]}"
  fi
  [[ -z $target_user || $target_user == "$(id -un)" ]] || { echo '--user must match the current user.' >&2; exit 2; }
  mkdir -p "$HOME/.cache/omarchy-alarm"
  exec > >(tee -a "$HOME/.cache/omarchy-alarm/install.log") 2>&1
fi
printf 'Omarchy ARM profile=%s dry-run=%s no-aur=%s\n' "$profile" "$dry_run" "$no_aur"
step validate_environment 'Check Arch Linux ARM, sudo access, and user build paths'
step initialize_home_layout 'Create missing Work and standard XDG user directories; preserve existing files'
step initialize_machine_identity 'Initialize persistent machine-id for non-boot D-Bus clients'
step install_repo_packages 'Install repository packages (core plus selected full extras)'
step configure_build_directories 'Set makepkg BUILDDIR and TMPDIR beneath HOME/.cache'
step install_aur_packages 'Install verified yay and requested desktop packages (unless --no-aur)'
step clone_and_patch_omarchy 'Clone upstream v4.0.4, verify patches/BASE, apply ARM patches once'
step install_system_helpers 'Link /usr/share/omarchy and install /usr/local/bin/uwsm-app'
step seed_omarchy_config 'Seed missing upstream configuration defaults'
step install_config_overlay 'Install reviewed config allowlist and fcitx5-autostart/host-run helpers'
step setup_lazyvim 'Install LazyVim only when nvim config is absent, using verified CN sources in CN mode'
step configure_bashrc 'Append marked Omarchy default bash configuration and bin PATH'
step provision_user_headless 'Run omarchy-provision-user headless; seed Tokyo Night theme'
step configure_input_and_fonts 'Install configuration-only Rime presets, local keyfile backend, CJK fonts'
step configure_stay_awake 'Default stay-awake ON, configure lock PAM, warn for locked passwords'
step install_tool_programs 'Install verified mise and AI programs only (both profiles; failures are nonfatal)'
step report_optional_results 'Report every optional installation result and highlight failures'
echo 'Container setup complete. Start the desktop using the host launcher.'
