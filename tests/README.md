# Tests

Run `tests/run.sh --quick` as an ordinary user on Arch Linux ARM aarch64.
It prints a PASS/FAIL/SKIP table and returns zero only when every required
check passes. The quick suite defaults to a 115-second total budget (network stalls
fail the affected check). `ALARM_TEST_QUICK_BUDGET` overrides the budget in
seconds (a positive integer); CI uses 600 seconds for emulated arm64 on
a non-aarch64 host. Initial CI image preparation is outside that budget.
Only `.git` metadata is excluded from syntax/hygiene traversal; privacy scanning
receives the whole repository. `tools/privacy-selftest.sh` generates its own
synthetic fixtures outside the checkout.

The suite checks Bash syntax, ShellCheck errors/warnings when installed, privacy scanner and
self-test, the pinned upstream SHA and sequential patch application, all repo
and AUR package names, both entrypoint OS paths and installer dry-runs (normalizing the checkout/cache
paths before checking for a leaked account name), rendered
host launcher syntax, Lua syntax, file sizes, backup files and escaping symlinks.
Package metadata must already be synchronized; tests never update the live system.
Upstream is shallow-cloned once under `~/.cache/omarchy-alarm-tests`.

While workers are still creating files, `ALARM_TEST_ALLOW_MISSING=1` labels
absent required targets SKIP, with an explanatory message. Such a run still
returns nonzero because it is not shippable. The default final/CI gate treats
missing targets as FAIL. Missing optional ShellCheck is a SKIP that does not
fail the suite. Lua requires `luac`, or an available Hyprland with cached upstream.

Check for ShellCheck with `pacman -Qi shellcheck`. Without installing a system
package, an aarch64 machine can download the official static release:

```bash
mkdir -p ~/.cache/omarchy-alarm-tests
curl -fL https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.aarch64.tar.xz -o ~/.cache/omarchy-alarm-tests/shellcheck.tar.xz
tar -xJf ~/.cache/omarchy-alarm-tests/shellcheck.tar.xz -C ~/.cache/omarchy-alarm-tests
```

`tests/run.sh --full` also downloads/caches the official ALARM rootfs, verifies
its published MD5, extracts a fresh copy below the test cache, probes nspawn,
unshare plus chroot, then bwrap in order, and uses the first successful method.
The documented official HTTP download and MD5 provide transfer integrity, not
authenticity. The HTTPS alias currently fails hostname certificate verification;
we never disable TLS verification. Full tests require an aarch64 environment,
noninteractive sudo and sufficient disk space (allow tens of GB).

`tests/full.sh --probe-only` proves isolation by running `pacman -Q` inside that
fresh rootfs, without installing the desktop. Probe logs and the selected method
are retained in the cache; the rootfs is always removed by an EXIT trap guarded
by its canonical cache prefix. Mounts are isolated in a private namespace.
No host configuration is modified. A failed probe is a failure, never a skip.

Full installation uses a new `testuser`, `--profile core --no-aur`, then checks
the Omarchy symlink, patch IDs in git history, required binaries, Lua config and
`Hyprland --verify-config` under a clean user environment. It reruns the installer
and compares packages, managed file contents, modes and symlinks; runtime logs,
font caches and timestamps are deliberately excluded from idempotence comparison.

CI uses `ubuntu-24.04-arm` and imports the official tarball into a local Docker
image via `tests/ci.sh`; this avoids trusting an unofficial ALARM image publisher.
Pushes and pull requests run quick checks without container privilege. A manual
workflow dispatch additionally runs full integration in a privileged disposable
container, needed for nested namespace and mount probes.

## Local isolation evidence

On 2026-09-27, in the nested Android-kernel environment, `systemd-nspawn`
failed with “Failed to open system bus”. The next method, `sudo unshare --mount
--pid --fork` with private bind mounts and `chroot`, successfully ran `pacman -Q`
in a freshly extracted official rootfs. bwrap was not needed. The rootfs was
removed after the probe. Full core installation, config verification and the
second-run idempotence check subsequently passed in 246 seconds. See `tests/RESULTS.md` for the recorded run.

China network policy: `bash tests/mirrors.sh` checks selection, failures,
artifact fallback, apt source rewriting/backups and offline dry runs.
`bash tests/china-downloads.sh` runs real download stages in Debian 13 arm64
under Docker/QEMU with overseas hosts mapped to `0.0.0.0`. Set `DOCKER_HOST`
for a rootless daemon. The image pull happens before blocking; apt itself is
bootstrapped from a mainland source. This downloads the complete ALARM rootfs.
It does not exercise Android display hardware, nested nspawn, or a desktop.

`bash tests/installer-regressions.sh` runs offline regressions for host stub DNS,
rootfs resolver symlinks, CN fallback, unsupported sync repositories, piped
installer stdin and resume behavior, including interrupted atomic extraction.
It is included in quick checks. The CN
Docker/QEMU simulation also resolves a mirror using the real ALARM `getent`
with a synthetic `127.0.0.53` host resolver and checks cached rootfs reuse.

`bash tests/display-regressions.sh` exercises output readiness, stale-instance
filtering, arbitrary connected connector detection, monitors-all snapshots,
failed-IPC log capture, IPC timeouts, fallback and failed cleanup, stop signals, safe deferred
switching, private diagnostics, renderer flags/opt-outs and interactive PATH with
offline mocks. It is included in quick and full checks. Mock recovery is not
evidence of visible frames on Android virtio_gpu; see
[display investigation](../docs/blackscreen-v0.2.3.md).

For QEMU user-mode full tests, `ALARM_TEST_EMULATED=1` disables pacman Landlock
only in the freshly extracted disposable rootfs (QEMU does not implement those
syscalls). `tests/ci.sh` sets it automatically on non-aarch64 hosts. QEMU binfmt must also
preserve credentials (`C` flag) for the real ALARM sudo binary; in rootless Docker
this can be registered in the disposable daemon user namespace without changing
the host registration. Native runs leave the fresh rootfs sandbox setting alone.

The v0.2.5 regressions also exercise real Git branch/tag/SHA checkout, missing-Git
apt bootstrap, Gitee-only CN branch/tag/SHA requests (including auto-selected CN),
zero archive requests, offline dry-run, machine-ID creation and
stable reruns, and an owned launch/cleanup lifecycle with TERM/INT/HUP and private
persistent evidence. `tests/session-regressions.sh` covers foreground selftest,
registration failures, preflight failures, stuck cleanup and fallback suppression.
Full integration loads the patched shell colors through the installed Qt and
Quickshell to catch the Qt 6.12 `Color` collision, and compares persistent machine
identity on the second install. These checks do not replace the DRM e2e gate.

The separate release e2e uses a Debian arm64 system VM, real nspawn/seatd and
virtio-gpu with the first connector off and the second on. It requires usable
Hyprland IPC, a Quickshell IPC round trip, unchanged compositor/shell processes
for at least 60 seconds, and two recognizable desktop screenshots at least
30 seconds apart. A nonblack pixel count or wallpaper alone is insufficient.
Fallback, selftest and retained diagnostics are verified separately. See
[v0.2.5 validation](../docs/v0.2.5-validation.md) for evidence and fidelity limits.
