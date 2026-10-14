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


## v0.2.3 — 2026-10-13

`tests/run.sh --full` passed all twelve checks, with ShellCheck present, in
858 seconds (exit 0) inside a disposable ALARM arm64 rootfs under QEMU on
x86_64. This included real core installation, Hyprland configuration verification
and second-run package/config/mode/symlink idempotence. The runtime packages
were Hyprland 0.56.2-4 and Aquamarine 0.15.1-1. `unshare` plus chroot passed
the isolation probe; nspawn failed its QEMU namespace clone and was not used.

The rootless test runner needed credential-preserving binfmt `POCF` in its own
Docker user namespace (the host registration remained `PF`) and
`ALARM_TEST_EMULATED=1` to disable unsupported Landlock in only the fresh
disposable test rootfs. Initial runs exposed these environment limitations;
the final run used real ALARM sudo and real installation commands, not a sudo
stub. The fresh rootfs and runner were removed after testing.

The final display regressions passed both natively and under arm64 emulation,
including the final stateful previous-leader and real-probe regression added
after the full run. This host-script-only addition does not change container installation.
Native Hyprland 0.56.2 accepted both minimal and complete Lua configs. A device-
isolated launch with no DRM/parent Wayland aborted at CBackend::create()
(exit 134); this did not reproduce the Pad's black screen. Read-only observation
of an existing real 0.56.2 FALLBACK monitor (DPMS off) was correctly rejected.
Actual Android virtio_gpu scanout remains untested; see the
[investigation](../docs/blackscreen-v0.2.3.md).

Release workstation evidence:

- `/tmp/v023-final-full.log`: twelve PASS rows, integration/idempotence, exit 0.
- `/tmp/v023-display-tests.log` and `/tmp/v023-arm-display-tests.log`: final
  focused behavioral regressions, including previous-container leader filtering.
- `/tmp/v023-full-config.log`: real 0.56.2 full Lua verification.
- `/tmp/v023-repro/headless.log`: failed isolated headless attempt.
- `/tmp/mimo-logs/blackscreen-analysis.log`, `blackscreen-drafting.log`,
  `blackscreen-review.log`: MIMO prompts, retries, analysis, drafting and reviews.

## v0.2.4 — 2026-10-14

`tests/run.sh --full` passed all twelve checks in 781 seconds (exit 0) in a
fresh disposable ALARM arm64 rootfs under QEMU on x86_64. ShellCheck was present.
This includes the extended display regressions, real core installation,
Hyprland 0.56.2-4 configuration verification (`config ok`) and second-run
package/config/mode/symlink idempotence. The isolation probe selected unshare
plus chroot. The runner used credential-preserving POCF binfmt in its own
rootless namespace and ALARM_TEST_EMULATED=1 only in disposable roots.

Native focused display regressions, ShellCheck and full Lua configuration
verification also passed. Native quick package validation cannot find
archlinuxarm-keyring in the workstation's x86_64 repositories; the authoritative
ALARM full run passed that check. Initial runner setup attempts hit network and
binfmt namespace limitations; an initial suite read a test during replacement.
The final full run used the frozen patch and passed without those failures.

Covered display changes include Virtual-2/Virtual-16 and arbitrary real outputs,
synthetic fallback rejection, card0 connected discovery and name mismatch,
raw monitors all vs redacted summaries, newest-four bounded failed-IPC log tails,
private pre-cleanup diagnostics, unknown previous leader recovery, renderer
knobs and interactive/profile PATH. The Pad's Weston observation establishes
connector variance, not visible Hyprland scanout; device frames and touchscreen
mapping remain unverified.

Release workstation logs:

- `/tmp/v024-final-full.log`: twelve PASS rows, exit 0.
- `/tmp/v024-display-tests.log`: final native display regressions.
- `/tmp/v024-config-verify.log`: native complete Lua configuration verification.
- `/tmp/v024-shellcheck.log`: final native ShellCheck, exit 0.
- `/tmp/mimo-logs/v024-analysis.log`: MIMO analysis prompt and output.
- `/tmp/mimo-logs/v024-design.log`: MIMO patch-design prompt and output.
- `/tmp/mimo-logs/v024-review.log`: MIMO initial review prompt and output.
- `/tmp/mimo-logs/v024-review-final.log`: MIMO final review, no blocking findings.
