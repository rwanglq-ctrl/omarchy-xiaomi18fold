#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034  # MIRROR and friends come from lib/network.sh
# tests/installer-regressions.sh — regressions for container DNS, pacman [aur] removal
# and installer entrypoints (piped bootstrap, cached rootfs reuse).
#
# Exercises the lib/network.sh APIs wired into host/install.sh and container/install.sh:
#   network_resolv_config ROOTFS [HOST_RESOLV] [UPLINK]
#     regular rootfs/etc/resolv.conf (symlink removed), loopback (127.* / ::1) nameservers
#     filtered, the uplink file used when the host resolver is a stub, mainland fallback
#     (223.5.5.5, 119.29.29.29) when nothing usable remains in CN mode.
#   network_container_dns ROOTFS
#     systemd-nspawn --resolv-conf=off --console=pipe ... getent hosts <mirror> before
#     pacman, stdin at EOF; CN failure rewrites the fallback resolvers and retries, then
#     fails.
#   network_pacman_repos FILE
#     CN only: removes just the [aur] section, keeps every other section and the
#     FILE.omarchy-original backup.
#   network_extract_rootfs TARBALL ROOTFS
#     bsdtar extracts into a mktemp staging sibling (ROOT.omarchy-extract.XXXXXX); the
#     tree is validated (etc/arch-release plus executable usr/bin/pacman and
#     usr/bin/bash) and only then published with mv -T. A failed or interrupted
#     extraction (bsdtar failing after etc/arch-release exists) publishes nothing,
#     the subshell EXIT trap cleans the staging directory, a rerun then publishes the
#     complete rootfs, and an existing nonempty destination is never replaced.
#
# systemd-nspawn, sudo, curl and bsdtar are mocked (PATH scripts / shell functions); nothing
# outside the mktemp work directory is touched. Run: bash tests/installer-regressions.sh
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
[[ -f $ROOT/lib/network.sh ]] || { echo "Missing target/tool: lib/network.sh"; exit 1; }
# shellcheck source=../lib/network.sh
source "$ROOT/lib/network.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok   %s\n' "$*"; }
missing() {
  echo "Missing target/tool: $*"
  if [[ ${ALARM_TEST_ALLOW_MISSING:-0} == 1 ]]; then exit 77; fi
  exit 1
}
nameservers() { awk '$1 == "nameserver" { print $2 }' "$1"; }
assert_regular() { [[ -f $1 && ! -L $1 ]] || fail "$1 must be a regular file (not a symlink)"; }
assert_has()     { grep -qF -- "$2" "$1" || fail "$1 must contain: $2"; }
assert_lacks()   { ! grep -qF -- "$2" "$1" || fail "$1 must not contain: $2"; }
assert_no_loopback() {
  ! nameservers "$1" | grep -Eq '^(127\.[0-9.]+|::1)$' \
    || fail "$1 must not list loopback nameservers: $(nameservers "$1" | tr '\n' ' ')"
}

for api in network_resolv_config network_container_dns network_pacman_repos network_extract_rootfs; do
  declare -F "$api" >/dev/null || missing "$api in lib/network.sh"
done
pass 'lib/network.sh provides network_resolv_config, network_container_dns, network_pacman_repos, network_extract_rootfs'

# --- network_resolv_config: stub host falls back to the uplink file --------------------
r=$work/r1; mkdir -p "$r/etc"
printf 'nameserver 127.0.0.53\noptions edns0\nsearch lan\n' > "$work/host-stub"
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$work/uplink"
MIRROR=global; network_init >/dev/null
network_resolv_config "$r" "$work/host-stub" "$work/uplink"
assert_regular "$r/etc/resolv.conf"
assert_has "$r/etc/resolv.conf" 1.1.1.1
assert_has "$r/etc/resolv.conf" 8.8.8.8
assert_no_loopback "$r/etc/resolv.conf"
pass 'stub host resolver uses the uplink file (no 127.0.0.53 in the container)'

# --- non-stub host keeps its own servers; the uplink is not consulted ------------------
r=$work/r2; mkdir -p "$r/etc"
printf 'nameserver 9.9.9.9\n' > "$work/host-real"
network_resolv_config "$r" "$work/host-real" "$work/uplink"
assert_regular "$r/etc/resolv.conf"
assert_has "$r/etc/resolv.conf" 9.9.9.9
assert_lacks "$r/etc/resolv.conf" 1.1.1.1
pass 'usable host nameservers win; uplink only applies when the host is a stub'

# --- loopback nameservers are filtered wherever they appear ---------------------------
r=$work/r3; mkdir -p "$r/etc"
printf 'nameserver 127.0.0.54\nnameserver ::1\nnameserver 9.9.9.9\nnameserver 2001:4860:4860::8888\n' > "$work/host-mixed"
network_resolv_config "$r" "$work/host-mixed" "$work/no-such-uplink"
assert_regular "$r/etc/resolv.conf"
assert_no_loopback "$r/etc/resolv.conf"
assert_has "$r/etc/resolv.conf" 9.9.9.9
assert_has "$r/etc/resolv.conf" 2001:4860:4860::8888
pass 'mixed host resolver drops 127.* and ::1 and keeps the usable servers'

# Same, but with an uplink present: whichever source is chosen, a usable server must
# survive and no loopback address may leak into the container.
r=$work/r3b; mkdir -p "$r/etc"
network_resolv_config "$r" "$work/host-mixed" "$work/uplink"
assert_regular "$r/etc/resolv.conf"
assert_no_loopback "$r/etc/resolv.conf"
if ! grep -qF -e 9.9.9.9 -e 1.1.1.1 "$r/etc/resolv.conf"; then
  fail "mixed host + uplink must yield a usable nameserver: $(nameservers "$r/etc/resolv.conf" | tr '\n' ' ')"
fi
pass 'mixed host resolver with uplink still yields a usable, loopback-free resolv.conf'

# --- dangling rootfs symlink is replaced by a regular file ----------------------------
r=$work/r4; mkdir -p "$r/etc"
ln -s /nonexistent/target "$r/etc/resolv.conf"
network_resolv_config "$r" "$work/host-real" "$work/uplink"
assert_regular "$r/etc/resolv.conf"
assert_has "$r/etc/resolv.conf" 9.9.9.9
pass 'dangling rootfs/etc/resolv.conf symlink is removed and replaced'

# --- symlink to a real file must not be written through -------------------------------
r=$work/r5; mkdir -p "$r/etc"
printf 'nameserver 6.6.6.6\n' > "$r/etc/real-resolv"
ln -s real-resolv "$r/etc/resolv.conf"
network_resolv_config "$r" "$work/host-real" "$work/uplink"
assert_regular "$r/etc/resolv.conf"
assert_has "$r/etc/resolv.conf" 9.9.9.9
assert_has "$r/etc/real-resolv" 6.6.6.6
pass 'rootfs symlink target is left untouched; resolv.conf becomes a regular file'

# --- empty resolver: mainland fallback in CN, failure otherwise -----------------------
r=$work/r6; mkdir -p "$r/etc"
printf '# nothing here\n\n' > "$work/host-empty"
MIRROR=cn; network_init >/dev/null
network_resolv_config "$r" "$work/host-empty" "$work/no-such-uplink"
assert_regular "$r/etc/resolv.conf"
assert_has "$r/etc/resolv.conf" 223.5.5.5
assert_has "$r/etc/resolv.conf" 119.29.29.29
pass 'empty host resolver falls back to 223.5.5.5 and 119.29.29.29 in CN mode'

r=$work/r6b; mkdir -p "$r/etc"
printf 'nameserver 127.0.0.53\n' > "$work/uplink-stub"
network_resolv_config "$r" "$work/host-stub" "$work/uplink-stub"
assert_regular "$r/etc/resolv.conf"
assert_has "$r/etc/resolv.conf" 223.5.5.5
assert_has "$r/etc/resolv.conf" 119.29.29.29
pass 'loopback-only host and uplink also fall back to the mainland resolvers in CN mode'

r=$work/r6c; mkdir -p "$r/etc"
MIRROR=global; network_init >/dev/null
if network_resolv_config "$r" "$work/host-empty" "$work/no-such-uplink" 2>/dev/null; then
  fail 'global mode must not invent mainland DNS servers for an empty resolver'
fi
pass 'the mainland fallback is CN-only; global mode with no usable server fails'

# --- repeat config is idempotent ------------------------------------------------------
r=$work/r7; mkdir -p "$r/etc"
MIRROR=cn; network_init >/dev/null
network_resolv_config "$r" "$work/host-real" "$work/uplink"
first=$(nameservers "$r/etc/resolv.conf")
network_resolv_config "$r" "$work/host-real" "$work/uplink"
assert_regular "$r/etc/resolv.conf"
[[ $(nameservers "$r/etc/resolv.conf") == "$first" ]] \
  || fail 'repeat network_resolv_config changed the nameservers'
pass 'repeat network_resolv_config leaves a stable regular resolv.conf'

# --- network_pacman_repos: CN removes only [aur], keeps others and the backup ----------
pacman_fixture() {
  cat > "$1" <<'CONF'
# Pacman configuration (test fixture)

[options]
HoldPkg = pacman glibc

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[aur]
Server = https://aur.archlinux.org/$arch

[multilib]
Include = /etc/pacman.d/mirrorlist
CONF
}
pconf=$work/pacman.conf
pacman_fixture "$pconf"
cp -p "$pconf" "$work/pacman.pristine"
MIRROR=cn; network_init >/dev/null
network_pacman_repos "$pconf"
assert_lacks "$pconf" '[aur]'
assert_lacks "$pconf" 'aur.archlinux.org'
for section in '[options]' '[core]' '[extra]' '[multilib]'; do
  assert_has "$pconf" "$section"
done
assert_has "$pconf" 'HoldPkg = pacman glibc'
assert_has "$pconf" '# Pacman configuration (test fixture)'
[[ -f $pconf.omarchy-original ]] || fail "$pconf.omarchy-original backup must exist"
cmp -s "$pconf.omarchy-original" "$work/pacman.pristine" || fail 'backup must hold the original pacman.conf'
pass 'CN network_pacman_repos removes only [aur] and keeps a pristine backup'

# Repeat: still no [aur], other sections intact, backup not clobbered.
network_pacman_repos "$pconf"
assert_lacks "$pconf" '[aur]'
for section in '[options]' '[core]' '[extra]' '[multilib]'; do
  assert_has "$pconf" "$section"
done
cmp -s "$pconf.omarchy-original" "$work/pacman.pristine" || fail 'repeat run must not clobber the backup'
pass 'repeat network_pacman_repos stays [aur]-free and keeps the original backup'

# [aur] as the last section must be removed to EOF without touching anything above.
pconf2=$work/pacman-eof.conf
cat > "$pconf2" <<'CONF'
[core]
Include = /etc/pacman.d/mirrorlist

[aur]
Server = https://aur.archlinux.org/$arch
CONF
MIRROR=cn; network_init >/dev/null
network_pacman_repos "$pconf2"
assert_has "$pconf2" '[core]'
assert_lacks "$pconf2" '[aur]'
assert_lacks "$pconf2" 'aur.archlinux.org'
pass 'trailing [aur] section is removed to EOF, earlier sections survive'

# Global mode must leave pacman.conf alone.
pconf3=$work/pacman-global.conf
pacman_fixture "$pconf3"
cp -p "$pconf3" "$work/pacman-global.pristine"
MIRROR=global; network_init >/dev/null
network_pacman_repos "$pconf3"
cmp -s "$pconf3" "$work/pacman-global.pristine" || fail 'global mode must not modify pacman.conf'
pass 'global network_pacman_repos leaves pacman.conf untouched'

# --- mocked systemd-nspawn / sudo -----------------------------------------------------
# The nspawn mock is greedy: it consumes stdin completely and fails if anything was
# there, proving network_container_dns ran it at EOF (</dev/null).
cat > "$work/bin-systemd-nspawn" <<'MOCK'
#!/usr/bin/env bash
data=$(cat || true)
if [[ -n $data ]]; then
  printf 'stdin-data %s\n' "$data" >> "$NSPAWN_LOG"
  exit 99
fi
printf 'stdin-eof\n' >> "$NSPAWN_LOG"
printf 'argv %s\n' "$*" >> "$NSPAWN_LOG"
count=$(cat "$NSPAWN_COUNT" 2>/dev/null || echo 0)
count=$((count + 1))
printf '%s\n' "$count" > "$NSPAWN_COUNT"
case " $* " in
  *'getent hosts '*)
    args=$*
    host=${args##*getent hosts }
    host=${host%%[[:space:]]*}
    printf '%s\n' "$host" >> "$NSPAWN_PROBES"
    mode=$(cat "$NSPAWN_MODE" 2>/dev/null || echo ok)
    case $mode in
      ok) exit 0 ;;
      fail) exit 1 ;;
      fail-once) (( count > 1 )) && exit 0 || exit 1 ;;
      *) echo "bad NSPAWN_MODE: $mode" >&2; exit 2 ;;
    esac ;;
esac
exit 0
MOCK
mkdir -p "$work/bin"
mv "$work/bin-systemd-nspawn" "$work/bin/systemd-nspawn"
cat > "$work/bin/sudo" <<'MOCK'
#!/usr/bin/env bash
while (( $# > 1 )); do
  case $1 in
    -u|-g|-h|-p|-r|-t|-C) shift 2 ;;
    --) shift; break ;;
    -*) shift ;;
    *) break ;;
  esac
done
(( $# )) || exit 2
exec "$@"
MOCK
chmod 755 "$work/bin/systemd-nspawn" "$work/bin/sudo"
export NSPAWN_LOG=$work/nspawn.log NSPAWN_PROBES=$work/nspawn.probes
export NSPAWN_COUNT=$work/nspawn.count NSPAWN_MODE=$work/nspawn.mode
PATH="$work/bin:$PATH"; export PATH

reset_nspawn() {
  : > "$NSPAWN_LOG"
  : > "$NSPAWN_PROBES"
  rm -f "$NSPAWN_COUNT"
  printf '%s\n' "$1" > "$NSPAWN_MODE"
}
nspawn_calls() { cat "$NSPAWN_COUNT" 2>/dev/null || echo 0; }
probe_hosts() { cat "$NSPAWN_PROBES" 2>/dev/null || true; }
# Known ALARM mirror hosts (mainland candidates plus the global upstreams).
known_mirror_hosts=' mirror.archlinuxarm.org os.archlinuxarm.org mirrors.tuna.tsinghua.edu.cn mirrors.ustc.edu.cn mirrors.bfsu.edu.cn mirror.sjtu.edu.cn '
assert_probe_host() {
  local host
  while IFS= read -r host; do
    [[ -n $host ]] || fail 'nspawn probe passed no host to getent'
    host=${host#*://}
    host=${host%%/*}
    [[ $known_mirror_hosts == *" $host "* ]] \
      || fail "nspawn probed '$host'; expected one of the ALARM mirror hosts"
  done < <(probe_hosts)
  [[ -n $(probe_hosts) ]] || fail 'no getent hosts probe was executed'
}
assert_probe_argv() {
  grep -q -- '--resolv-conf\(=\|[[:space:]]\)off' "$NSPAWN_LOG" \
    || fail 'nspawn must run with --resolv-conf=off (no host stub copies)'
  grep -q -- '--console\(=\|[[:space:]]\)pipe' "$NSPAWN_LOG" \
    || fail 'nspawn must run with --console=pipe (piped, non-interactive)'
  grep -qF -- "$1" "$NSPAWN_LOG" || fail "nspawn must target the rootfs: $1"
  grep -q -- 'getent hosts' "$NSPAWN_LOG" || fail 'nspawn must probe with getent hosts'
}

# --- network_container_dns: happy path probes exactly once ---------------------------
rd=$work/dns-rootfs; mkdir -p "$rd/etc"
MIRROR=cn; network_init >/dev/null
network_resolv_config "$rd" "$work/host-real" "$work/uplink"
reset_nspawn ok
if ! network_container_dns "$rd" </dev/null; then
  fail 'network_container_dns must succeed when the probe succeeds'
fi
[[ $(nspawn_calls) == 1 ]] || fail "expected exactly one DNS probe, saw $(nspawn_calls)"
assert_probe_argv "$rd"
assert_probe_host
assert_lacks "$rd/etc/resolv.conf" 223.5.5.5
pass 'CN network_container_dns probes the selected mirror once, before pacman, via nspawn'

# --- fallback on failed getent: rewrite resolv.conf and retry -------------------------
reset_nspawn fail-once
network_resolv_config "$rd" "$work/host-real" "$work/uplink"
if ! network_container_dns "$rd" </dev/null 2>/dev/null; then
  fail 'a failed CN probe must rewrite the fallback resolvers and retry successfully'
fi
[[ $(nspawn_calls) == 2 ]] || fail "expected the probe plus one retry, saw $(nspawn_calls)"
assert_regular "$rd/etc/resolv.conf"
assert_has "$rd/etc/resolv.conf" 223.5.5.5
assert_has "$rd/etc/resolv.conf" 119.29.29.29
assert_probe_host
pass 'failed CN probe writes 223.5.5.5/119.29.29.29 and retries the probe'

# --- every probe failing: the function must fail -------------------------------------
reset_nspawn fail
network_resolv_config "$rd" "$work/host-real" "$work/uplink"
if network_container_dns "$rd" </dev/null 2>/dev/null; then
  fail 'network_container_dns must fail when the retry fails too'
fi
[[ $(nspawn_calls) -ge 2 ]] || fail 'a CN failure must retry with the fallback before failing'
assert_has "$rd/etc/resolv.conf" 223.5.5.5
assert_has "$rd/etc/resolv.conf" 119.29.29.29
pass 'CN probe failing on both attempts makes network_container_dns fail'

# --- global failure: no mainland retry, and no invented mainland DNS -----------------
rg=$work/dns-global; mkdir -p "$rg/etc"
MIRROR=global; network_init >/dev/null
network_resolv_config "$rg" "$work/host-real" "$work/uplink"
reset_nspawn fail
if network_container_dns "$rg" </dev/null 2>/dev/null; then
  fail 'network_container_dns must fail when the probe fails in global mode'
fi
assert_probe_argv "$rg"
assert_probe_host
assert_regular "$rg/etc/resolv.conf"
assert_lacks "$rg/etc/resolv.conf" 223.5.5.5
assert_lacks "$rg/etc/resolv.conf" 119.29.29.29
pass 'global probe failure fails hard without writing the mainland fallback'

# --- stdin preservation: greedy nspawn sees EOF, the caller's stdin survives ----------
MIRROR=cn; network_init >/dev/null
network_resolv_config "$rd" "$work/host-real" "$work/uplink"
reset_nspawn ok
printf 'SENTINEL-KEPT\n' > "$work/caller-stdin"
exec 3< "$work/caller-stdin"
if ! network_container_dns "$rd" <&3; then
  exec 3<&-
  fail 'network_container_dns must succeed with caller data waiting on stdin'
fi
line=''
if ! IFS= read -r line <&3; then line='<eof>'; fi
exec 3<&-
[[ $line == SENTINEL-KEPT ]] \
  || fail "nspawn consumed the caller's stdin (read back: $line); the probe must run with </dev/null"
grep -q 'stdin-eof' "$NSPAWN_LOG" || fail 'the greedy nspawn mock must observe EOF on its stdin'
assert_lacks "$NSPAWN_LOG" 'stdin-data'
[[ $(nspawn_calls) == 1 ]] || fail "expected one probe, saw $(nspawn_calls)"
assert_probe_argv "$rd"
pass 'greedy nspawn mock sees EOF while the caller sentinel stays on stdin'

# --- piped top entrypoint (curl | bash) with stubbed host/container sides -------------
if command -v git >/dev/null 2>&1; then
  fake=$work/fake-repo
  mkdir -p "$fake/host" "$fake/container" "$fake/lib"
  cp "$ROOT/install.sh" "$fake/install.sh"
  cp "$ROOT/lib/network.sh" "$fake/lib/network.sh"
  cat > "$fake/host/install.sh" <<'STUB'
#!/usr/bin/env bash
echo "STUB-HOST $*"
STUB
  cat > "$fake/container/install.sh" <<'STUB'
#!/usr/bin/env bash
echo "STUB-CONTAINER $*"
STUB
  git -C "$fake" init -q -b main 2>/dev/null || { git -C "$fake" init -q; git -C "$fake" branch -m main; }
  git -C "$fake" config commit.gpgsign false
  git -C "$fake" config user.name installer-regressions
  git -C "$fake" config user.email tests@example.com
  git -C "$fake" add -A
  git -C "$fake" commit -qm 'stub repository'
  printf 'ID=debian\nVERSION_ID=13\n' > "$work/debian-os"
  out=$work/piped.log
  if ! env OMARCHY_ALARM_REPO="file://$fake" OMARCHY_ALARM_REF=main \
       OMARCHY_ALARM_OS_RELEASE="$work/debian-os" OMARCHY_ALARM_ARCH=aarch64 MIRROR=global \
       bash -s -- --dry-run --user tester < "$ROOT/install.sh" > "$out" 2>&1; then
    fail "piped install.sh failed: $(tail -n 5 "$out")"
  fi
  assert_has "$out" 'not running from a checkout'
  assert_has "$out" 'mirror mode: global'
  assert_has "$out" 'STUB-HOST'
  assert_has "$out" '--dry-run'
  assert_has "$out" 'tester'
  assert_lacks "$out" 'STUB-CONTAINER'
  pass 'piped install.sh bootstraps via git and drives the stubbed host side in dry-run'

  # Execute both installer children with pending stdin, rather than only previewing.
  cat > "$fake/host/install.sh" <<'STUB'
#!/usr/bin/env bash
[[ -z $(cat) ]] || { echo 'host consumed installer input' >&2; exit 99; }
echo STUB-HOST-EOF
STUB
  reset_nspawn ok
  printf '==> must remain input data\n' > "$work/installer-stdin"
  exec 3< "$work/installer-stdin"
  if ! env OMARCHY_ALARM_OS_RELEASE="$work/debian-os" OMARCHY_ALARM_ARCH=aarch64 MIRROR=global \
      bash "$fake/install.sh" --user tester --rootfs "$work/copy-target" --profile core \
      <&3 > "$work/children.log" 2>&1; then
    fail "installer children failed: $(tail -n 5 "$work/children.log")"
  fi
  IFS= read -r line <&3 || fail 'installer consumed pending stdin'
  exec 3<&-
  [[ $line == '==> must remain input data' ]] || fail 'installer input changed'
  assert_has "$work/children.log" STUB-HOST-EOF
  assert_has "$NSPAWN_LOG" stdin-eof
  assert_lacks "$NSPAWN_LOG" stdin-data
  pass 'real host and container child dispatch see EOF; pending ==> input survives'
else
  echo 'note: git not installed; skipping the piped entrypoint regression'
fi

# --- existing cached rootfs reuse -----------------------------------------------------
fr=$work/cached-rootfs
mkdir -p "$fr/etc" "$work/home"
printf 'Arch\n' > "$fr/etc/arch-release"
hlog=$work/host-reuse.log
if ! env OMARCHY_ALARM_CACHE="$work/cache" HOME="$work/home" MIRROR=global \
     bash "$ROOT/host/install.sh" --dry-run --user tester --rootfs "$fr" > "$hlog" 2>&1; then
  fail "host/install.sh dry run failed: $(tail -n 5 "$hlog")"
fi
assert_has "$hlog" 'reusing it'
assert_lacks "$hlog" 'bsdtar -xpf'
assert_lacks "$hlog" 'network_fetch'
dns_line=$(grep -n 'getent before pacman' "$hlog" | head -n1 | cut -d: -f1 || true)
pacman_line=$(grep -n '==> 5/7' "$hlog" | head -n1 | cut -d: -f1 || true)
[[ -n $dns_line && -n $pacman_line && $dns_line -lt $pacman_line ]] \
  || fail 'the DNS verification must be planned before the container-side pacman work'
pass 'existing Arch rootfs is reused (no extraction) and DNS is checked before pacman'

# Cached tarball with a matching checksum must not be downloaded again.
cache=$work/cache2
mkdir -p "$cache"
tarball=$cache/ArchLinuxARM-aarch64-latest.tar.gz
printf 'cached rootfs payload\n' > "$tarball"
md5_want=$(md5sum "$tarball" | awk '{print $1}')
curl() {
  local out='' prev='' arg url
  for arg in "$@"; do [[ $prev != -o ]] || out=$arg; prev=$arg; done
  url=${!#}
  case $url in
    *.md5)
      [[ -n $out ]] || return 2
      printf '%s  ArchLinuxARM-aarch64-latest.tar.gz\n' "$md5_want" > "$out"
      return 0 ;;
    *)
      printf '%s\n' "$*" >> "$work/curl-payload.attempts"
      return 22 ;;
  esac
}
MIRROR=global; network_init >/dev/null
network_select_alarm >/dev/null
if ! network_download_rootfs "$tarball"; then
  fail 'a checksum-valid cached rootfs must be reused without downloading'
fi
[[ ! -s $work/curl-payload.attempts ]] || fail 'the cached rootfs tarball was downloaded again'
[[ $(cat "$tarball") == 'cached rootfs payload' ]] || fail 'the cached rootfs tarball was modified'
pass 'checksum-valid cached rootfs tarball is reused without a re-download'

# A stale partial of an older latest build gets one clean retry on the same URL.
(
  payload_count=0
  good_md5=$(printf 'current rootfs payload\n' | md5sum | awk '{print $1}')
  retry_tarball=$work/retry-rootfs.tar.gz
  network_fetch() {
    case $2 in
      *.md5) printf '%s\n' "$good_md5" > "$1" ;;
      *)
        payload_count=$((payload_count + 1))
        if (( payload_count == 1 )); then printf 'stale partial bytes\n' > "$1"
        else printf 'current rootfs payload\n' > "$1"; fi ;;
    esac
  }
  MIRROR=global; network_select_alarm
  network_download_rootfs "$retry_tarball" || fail 'checksum mismatch did not retry cleanly'
  [[ $payload_count == 2 ]] || fail 'expected exactly one clean retry'
  [[ $(cat "$retry_tarball") == 'current rootfs payload' ]] || fail 'retry published corrupt data'
)
pass 'stale partial checksum mismatch retries the same mirror cleanly'

# --- interrupted rootfs extraction: atomic publish, staging always cleaned --------------
# bsdtar is mocked and always writes etc/arch-release first, so "fail after arch-release
# exists" is a genuine interrupted extraction. network_extract_rootfs must extract into a
# mktemp staging sibling, validate, and publish only with mv -T; on any failure the
# subshell EXIT trap cleans the staging directory and the destination stays absent.
cat > "$work/bin/bsdtar" <<'MOCK'
#!/usr/bin/env bash
data=$(cat || true)
if [[ -n $data ]]; then
  printf 'stdin-data %s\n' "$data" >> "$BSDTAR_LOG"
  exit 99
fi
staging='' tarball='' prev=''
for arg in "$@"; do
  case $prev in
    -xpf|-f) tarball=$arg ;;
    -C) staging=$arg ;;
  esac
  prev=$arg
done
[[ -n $staging && -d $staging ]] || { echo 'bsdtar mock: missing -C staging directory' >&2; exit 2; }
printf 'tarball %s staging %s\n' "$tarball" "$staging" >> "$BSDTAR_LOG"
mkdir -p "$staging/etc"
printf 'ArchLinuxARM\n' > "$staging/etc/arch-release"
mode=$(cat "$BSDTAR_MODE" 2>/dev/null || echo ok)
case $mode in
  fail-after-arch-release)
    printf 'half-written\n' > "$staging/etc/pacman.conf.half"
    exit 2 ;;
  incomplete-pacman)
    mkdir -p "$staging/usr/bin"
    printf 'not executable\n' > "$staging/usr/bin/pacman"
    chmod 644 "$staging/usr/bin/pacman"
    printf '#!/bin/bash\n' > "$staging/usr/bin/bash"; chmod 755 "$staging/usr/bin/bash"
    exit 0 ;;
  incomplete-bash)
    mkdir -p "$staging/usr/bin"
    printf '#!/bin/bash\n' > "$staging/usr/bin/pacman"; chmod 755 "$staging/usr/bin/pacman"
    printf 'not executable\n' > "$staging/usr/bin/bash"
    chmod 644 "$staging/usr/bin/bash"
    exit 0 ;;
  ok)
    mkdir -p "$staging/usr/bin"
    printf '#!/bin/bash\n' > "$staging/usr/bin/pacman"
    printf '#!/bin/bash\n' > "$staging/usr/bin/bash"
    chmod 755 "$staging/usr/bin/pacman" "$staging/usr/bin/bash"
    printf 'rootfs-published\n' > "$staging/.extract-complete"
    exit 0 ;;
  *) echo "bad BSDTAR_MODE: $mode" >&2; exit 2 ;;
esac
MOCK
chmod 755 "$work/bin/bsdtar"
export BSDTAR_LOG=$work/bsdtar.log BSDTAR_MODE=$work/bsdtar.mode

assert_no_staging() {
  local left
  left=$(find "$(dirname "$1")" -maxdepth 1 -name "$(basename "$1").omarchy-extract.*" 2>/dev/null)
  [[ -z $left ]] || fail "staging was not cleaned up: $left"
}

xt=$work/rootfs.tar.gz
printf 'rootfs tarball fixture\n' > "$xt"

# Interruption after etc/arch-release exists: nothing may be published anywhere.
xr=$work/rootfs-interrupted
printf 'fail-after-arch-release\n' > "$BSDTAR_MODE"
: > "$BSDTAR_LOG"
if network_extract_rootfs "$xt" "$xr" </dev/null 2> "$work/extract-fail.log"; then
  fail 'an interrupted extraction must fail'
fi
[[ ! -e $xr ]] || fail "interrupted extraction left a destination behind: $xr"
assert_no_staging "$xr"
assert_has "$BSDTAR_LOG" "staging $xr.omarchy-extract."
[[ -f $xt ]] || fail 'the cached tarball must survive a failed extraction'
pass 'interrupted extraction (bsdtar fails after etc/arch-release) leaves no destination and no staging'

# Rerun after the interruption must publish the complete, validated rootfs.
printf 'ok\n' > "$BSDTAR_MODE"
network_extract_rootfs "$xt" "$xr" </dev/null || fail 'the rerun after an interruption must publish the rootfs'
[[ -d $xr && ! -L $xr ]] || fail "published rootfs must be a real directory: $xr"
assert_regular "$xr/etc/arch-release"
[[ -x $xr/usr/bin/pacman && ! -d $xr/usr/bin/pacman ]] || fail 'published rootfs must contain an executable usr/bin/pacman'
[[ -x $xr/usr/bin/bash && ! -d $xr/usr/bin/bash ]] || fail 'published rootfs must contain an executable usr/bin/bash'
assert_has "$xr/.extract-complete" 'rootfs-published'
assert_no_staging "$xr"
pass 'rerun after the interruption publishes the full validated rootfs (mv -T)'

# Validation: arch-release present but pacman or bash not executable is refused.
for mode in incomplete-pacman incomplete-bash; do
  xin=$work/rootfs-$mode
  printf '%s\n' "$mode" > "$BSDTAR_MODE"
  if network_extract_rootfs "$xt" "$xin" </dev/null 2> "$work/extract-$mode.log"; then
    fail "$mode rootfs must be refused"
  fi
  [[ ! -e $xin ]] || fail "$mode rootfs was published"
  assert_no_staging "$xin"
  assert_has "$work/extract-$mode.log" 'incomplete'
done
pass 'validation refuses rootfs trees without executable usr/bin/pacman and usr/bin/bash'

# An existing nonempty destination must never be replaced (mv -T refuses it).
xr3=$work/rootfs-existing
mkdir -p "$xr3/etc"
printf 'user data\n' > "$xr3/etc/keep-me"
printf 'ok\n' > "$BSDTAR_MODE"
if network_extract_rootfs "$xt" "$xr3" </dev/null 2> "$work/extract-existing.log"; then
  fail 'extracting over an existing nonempty destination must fail, not replace it'
fi
assert_has "$xr3/etc/keep-me" 'user data'
[[ ! -e $xr3/etc/arch-release && ! -e $xr3/.extract-complete ]] \
  || fail 'the extracted rootfs was published into/over the existing destination'
assert_no_staging "$xr3"
pass 'existing nonempty destination is left untouched and staging is still cleaned'

# Extraction runs bsdtar at EOF: pending caller input must survive untouched.
xr4=$work/rootfs-stdin
printf 'ok\n' > "$BSDTAR_MODE"; : > "$BSDTAR_LOG"
printf 'SENTINEL-EXTRACT\n' > "$work/extract-stdin"
exec 3< "$work/extract-stdin"
if ! network_extract_rootfs "$xt" "$xr4" <&3; then
  exec 3<&-
  fail 'extraction with pending caller stdin must succeed'
fi
line=''
if ! IFS= read -r line <&3; then line='<eof>'; fi
exec 3<&-
[[ $line == SENTINEL-EXTRACT ]] || fail "bsdtar consumed the caller's stdin (read back: $line)"
assert_lacks "$BSDTAR_LOG" 'stdin-data'
[[ -x $xr4/usr/bin/pacman ]] || fail 'extraction must publish an executable usr/bin/pacman'
assert_no_staging "$xr4"
pass 'bsdtar runs at EOF; the pending caller sentinel survives extraction'

echo 'PASS installer regressions: resolv stub/uplink/fallback, symlinks, [aur] removal, nspawn DNS probes, stdin, piped entrypoint, cached rootfs, atomic extraction'
