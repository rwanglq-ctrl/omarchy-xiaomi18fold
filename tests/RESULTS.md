# Validation record — 2026-09-27

On native aarch64 Arch Linux ARM inside an existing Android-kernel container,
`tests/run.sh --quick` completed in 12 seconds with exit 0 and no exclusions.

| Check | Result |
| --- | --- |
| Bash syntax | PASS |
| ShellCheck 0.11.0 | PASS |
| Whole-repository privacy scan | PASS |
| Privacy scanner self-test | PASS |
| Pinned v4.0.4 SHA and sequential patch application | PASS |
| Repository package availability | PASS |
| AUR RPC package availability | PASS |
| Entrypoint/container/host dry-runs and rendered launcher syntax | PASS |
| Lua syntax | PASS |
| Repository hygiene | PASS |
| Fresh rootfs isolation and `pacman -Q` | PASS — unshare + chroot |
| Full core installation, verification and idempotence | PASS |

The official rootfs was downloaded and its published MD5 matched. Nested
systemd-nspawn failed because no system bus is available. The fallback private
mount/PID namespaces with chroot successfully queried all installed packages.
The disposable rootfs was removed after the dedicated probe; logs remain under
`~/.cache/omarchy-alarm-tests`.

A separate fresh cached upstream clone also verified the installer patch routine:
the first call created `arm-port` and committed both supplied patches with `git am`;
the second call kept the exact same HEAD and a clean working tree. No user git
identity or global git configuration was used.

`tests/run.sh --full` then completed in 246 seconds with exit 0: all eleven
checks PASS. The fresh rootfs installed the core profile with AUR disabled;
Hyprland, quickshell, fcitx5 and foot were present, both patch IDs appeared in
`arm-port` history, and Hyprland reported `config ok` as the test user. The
second installation exited zero, its package/managed-content snapshot matched
exactly, and config verification passed again. The EXIT cleanup removed the
rootfs; no test rootfs directories remained.

The successful unshare harness makes its rootfs a bind mount so pacman can
identify the mount for disk-space checks, and sets root ownership/mode on the
freshly allocated directory before installation. Earlier harness-development
runs exposed those requirements; the final successful run started fresh with
both corrections already in place.

Full evidence is retained locally in
`~/.cache/omarchy-alarm-tests/final-full.log`, `before.snapshot`, and
`after.snapshot`. The quick-only log is `quick.log` in the same directory.

The GitHub workflow has been written and reviewed locally; it has not been run
on GitHub.

## v0.2.2 validation — 2026-10-13

- Offline installer regressions: PASS, 30 checks, including host stub/uplink DNS,
  resolver symlinks, CN fallback, unsupported `[aur]`, greedy child stdin,
  cached tarball reuse, stale partial checksum retry and atomic extraction.
- `tests/china-downloads.sh`: PASS on Debian 13 arm64 through Docker/QEMU with
  overseas hosts blocked. Verified mainland apt, complete rootfs download and
  checksum, extraction, real ALARM `getent` with a synthetic host loopback stub,
  cached rootfs reuse, sync databases/package metadata, vendored upstream,
  patches, and CN dry-run dependency/command plans (including host `gnupg`).
- Real official rootfs atomic extraction smoke: PASS in a disposable user
  namespace, including resolver symlink repair and real arm64 `getent`.
- Official ALARM arm64 CI-prepared image: final `tests/run.sh --quick` PASS,
  all 11 rows, exit 0 in 168 seconds. QEMU used the documented 600-second
  budget; no checks were skipped. Image preparation was performed by `tests/ci.sh`.
- Native x86 quick suite: 10 checks PASS; ALARM repository-package check FAILs
  because the x86 host repositories do not contain `archlinuxarm-keyring`.

The simulation covers DNS and installer logic; Android display hardware and a
live nested nspawn session are outside this test. nspawn argv and stdin are
covered by regression mocks. MIMO investigation, test authoring, mutation checks
and reviews are recorded in `/tmp/mimo-logs/01-*.log` through `06-*.log`.
