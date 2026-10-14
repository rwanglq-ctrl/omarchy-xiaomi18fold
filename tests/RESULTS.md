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

## v0.2.5 — 2026-10-14

Release validation uses two independent environments: an Arch Linux ARM
QEMU-user runner for `tests/run.sh --full`, and a Debian 13 arm64 system VM for
real nspawn/seatd/virtio-gpu desktop tests. Docker carries no display claim.
The final source snapshot after the CN correction is
`/tmp/v025-suite-source-cn-final.tar`, with its digest in
`/tmp/v025-tested-cn-final-source.sha256`; its full-suite log is
`/tmp/v025-full-suite-8.log` (final verdict recorded below).
Run 6, on `/tmp/v025-suite-source-review`, passed the eleven quick checks
but failed integration after a libwebp package download timed out (640 seconds,
exit 1). It is not counted as a pass.
The preceding source was `/tmp/v025-suite-source-final.tar`, digest
`/tmp/v025-tested-source.sha256`, and log `/tmp/v025-full-suite-5.log`.
The previous frozen full run (`/tmp/v025-full-suite-4.log`) passed all 12 checks
in 924 seconds. Run 5 includes the subsequent uptime-deadline and strict
NUL-byte identity fixes and passed **all 12 checks in 898 seconds, exit 0**,
including fresh installation, real Qt/Quickshell checks and second-run idempotence.

| Live check | Result and evidence under `/tmp/v025-evidence/` |
| --- | --- |
| Unchanged `d5476ce` reproduction | Hyprland IPC ready, shell FAIL: empty machine ID caused D-Bus aborts; `stage-verdict.md`, `baseline-app-probe2.log` |
| Installed Qt collision | Reproduced QQuickColor shadowing, explicit Omarchy namespace succeeds; `color-collision-probe.log` |
| Final full VM reinstall / upgrade | PASS; `/tmp/v025-final-vm-install.log`, applies patch 0004 onto the existing three-patch installation |
| Real service startup and IPC | PASS; `final-probe-1.log`, `final-probe-2.log`, `final-selftests.log`; usable Virtual-2 1024×768, Quickshell IPC returns `ok` |
| Visible shell and application | PASS; `final-scanout-1.png` and `final-scanout-2.png`, 47 seconds apart; Codex inspected both: themed bar, notifications, wallpaper; second also has a real foot terminal |
| Stable compositor and shell | PASS; same Hyprland/Quickshell PIDs and start times across 114 seconds of probes; no automatic fallback or restart; `final-layers.json` lists Omarchy surfaces |
| Service stop | PASS; four seconds, service inactive, machine gone, owner file removed; `final-selftests.log` |
| Injected missing launcher → Weston | PASS; `fallback-live.log`, `fallback-scanout.png`; decisive preflight error retained before cleanup/fallback |
| Selftest success and USR1 timeout | PASS; exit0/124 respectively, private one-attempt logs printed, cleanup verified, no Weston; `final-selftests.log` |
| Diagnostics after teardown | PASS; `v025-after-teardown-logs.txt`, private attempt/reports retained under `vm-final-state/` |
| Real missing-Git CN bootstrap + SHA | PASS; `bootstrap-live-no-git-sha.log`: apt reinstalls Git and fixture child reports exactly the requested SHA; full desktop install tested separately |
| Mutation checks | PASS; `mutations.log` detects removed identity repair, skipped checkout and discarded diagnostics; `qt-mutation.log` rejects the unqualified Style consumer |

The final VM install used actual ArchARM Hyprland 0.56.2-4, Quickshell 0.3.2-1,
Qt base 6.12.0-2/declarative 6.12.0-1, software llvmpipe and AQ_NO_MODIFIERS=1.
Virtual-1 was forced off and Virtual-2 on. This reproduces the connector-status
and Hyprland-output predicates, **not Android/crosvm's display negotiation or
16-connector layout**. The VM has a minimal base weston.service plus the exact
installed drop-in; user linger keeps that service alive after SSH logout.
Its first harness run stopped on logout before linger was enabled; this was a
normal service teardown, not a compositor failure.

The Pad's original automatic fallback was not reproduced. No exact Pad root
cause or verified Pad fix is claimed. Aquamarine initMgpu errors also occur with
working scanout; no renderer patch was inferred from them. Existing nonboot
container limitations (audio, system-bus panels, portal/polkit services) remain.

Earlier full-suite attempts were **not passes**: one test incorrectly treated
an empty runner-host ID as a leaked string; the accelerated one-second session
mock gate and an early-exit registration assertion were timing-sensitive under
emulation; one fresh-rootfs package sync timed out fetching ALARM aur.db.
The mock gate now has an explicit emulation budget and early-exit assertions
accept either observed registration state while requiring the exact failure
status and launch evidence. Production's 30-second gate is unchanged. A
concurrent exploratory test read a changing test script; the release run uses
a frozen snapshot to avoid that harness error.

Existing tests were retained or deliberately updated: the old lifecycle block
in display-regressions is replaced by the dedicated session suite (its old
cleanup expectations contradicted owned-session refusal); the raw-log assertion
now requires Window/client lines because private diagnostics must retain decisive
evidence; the piped dry-run expectation now requires zero fetches/writes.
Actual output JSON, stale-socket, namespace failure, signal, renderer and PATH
checks remain covered. MIMO's patch review findings and their resolutions are
in `/tmp/mimo-logs/v025-patch-review.log` and
`/tmp/mimo-logs/v025-patch-review-resolutions.md`.

The final deadline implementation uses Linux `/proc/uptime`; Bash 5.3's SECONDS
uses gettimeofday and can move with wall-clock corrections (source inspection
saved as `/tmp/v025-evidence/bash-variables.c`). A test repeatedly resets SECONDS
while waiting for unavailable output and still requires bounded failure/cleanup.
Strict machine-ID validation also rejects a 32-hex-byte file followed by NUL;
the old shell substitution discarded that byte although dbus-uuidgen rejected
it. The invalid-ID matrix now covers this counterexample.

The final uptime/byte-validation revision was reinstalled through the full VM
installer (`/tmp/v025-release-vm-install.log`). `release-nul-test.log` proves the
actual launcher repairs a malformed NUL-terminated ID before nspawn and reaches
usable output. `release-probe-1.log` / `release-probe-2.log` and the matching
`release-scanout-1.png` / `release-scanout-2.png` repeat IPC and recognizable-UI
checks 77 seconds apart, with unchanged compositor/shell PIDs. Both images were
visually inspected. `release-selftests.log` repeats service stop (five seconds,
inactive), selftest success and USR1 timeout, with no remaining machine.

Independent Claude review 1 found additional issues but could not read external
evidence because of CLI permissions; it is not counted as independent evidence
verification. Resolutions in `/tmp/mimo-logs/v025-claude-review-resolutions.md`
cover mirror publication policy, registry retries/recovery, bounded capture, cleanup-time
signals, leading-newline identities, linked check paths, GID0 exclusion and
no-display-hook sudo policy. The revised full suite is frozen separately above.

The revised code passed a complete real VM reinstall
(`/tmp/v025-review-vm-install.log`). `review-id-tests.log` proves leading-newline
and NUL identities are repaired before successful real selftests. Both
`review-probe-1.log` / `review-probe-2.log` return shell IPC `ok`, 74 seconds apart,
with the same Hyprland26752/Quickshell26836 and service invocation. The matching
`review-scanout-1.png` / `review-scanout-2.png` were visually inspected: themed
bar/notifications, and a real foot terminal plus wallpaper in the second.
An initial probe before shell IPC registration reported `Target not found`
(`review-probe-startup.log`); subsequent probes succeeded without a process restart.
`review-launch-stream.log` records output readiness until intentional TERM,
with no automatic fallback. `review-selftests.log` verifies a five-second normal
stop and success/USR1 selftests, leaving no container/owner. `review-fallback.log`
and the visually inspected `review-fallback-scanout.png` prove injected-launcher
failure recovery; `review-fallback-stop.log` proves clean stop. Raw attempts in
`vm-review-state/` retain final diagnostics before cleanup and satisfy private
file modes, ten-file retention and the 8 MiB session cap.

CN correction supersedes review 1's GitHub-only M3 remedy. The operator mirrors
Gitee after every origin release. The new real-Git fixture matrix checks Gitee
main/topic/tag/full SHA, literal gitee alias, explicit URL, auto-selected CN,
no GitHub clone and no archive/curl request in explicit CN. It preserves all
clone arguments through the transport wrapper. Live `git ls-remote` confirms
Gitee main is reachable at baseline d5476ce before publication (`cn-gitee-refs.log`).
This is not a claim that unpublished v0.2.5 was downloaded from Gitee.

Run 7 was stopped after quick checks exposed two test issues: the docs edit
shifted the previously allowlisted public release URL from line 108 to 110,
and the failed-cleanup mock accepted a direct child TERM, racing its own
expectation that the registry remain occupied. The mock now preserves the registry entry
in that case even when its child exits, modeling stale machined state. Production code is
unchanged by this test repair; failed cleanup must still suppress fallback.
The narrow public-URL allowlist was moved to its new line. Run 8 uses a new
frozen snapshot and must pass the entire suite.

The correction was repeated in the Debian arm64 VM: CN branch/tag/SHA fixture
regressions passed (`cn-bootstrap-live.log`), and a fresh main-branch fixture
proved real missing-Git apt recovery and exact SHA checkout
(`cn-bootstrap-live-2.log`). The latter log's subsequent reset-failed command
failed on an unloaded inactive service; a separate normal start succeeded.
`cn-runtime-match.log` verifies the VM source matches all current runtime code.
`cn-probe-1.log` / `cn-probe-2.log` show successful shell IPC and unchanged
Hyprland30761/Quickshell30842 over 86 seconds. Both `cn-scanout-1.png` and
`cn-scanout-2.png` were visually inspected: recognizable themed shell, wallpaper
and notifications; the second also shows a real terminal. Early startup output
is retained separately and is not counted as a successful visual check.
`cn-selftests.log` passes normal stop (seven seconds), successful foreground
selftest and USR1 exit124, with no remaining container/owner.
`cn-fallback.log`, visually inspected `cn-fallback-scanout.png` and
`cn-fallback-stop.log` pass injected missing-launcher recovery and clean stop.
`cn-log-verification.log` checks the retained private bounded logs in
`vm-cn-state/`, including the decisive failure before cleanup/fallback.
All these paths are beneath `/tmp/v025-evidence/`.

Final G4 PASS: `/tmp/v025-full-suite-8.log` passed **all 12 checks in 969 seconds, exit 0**, with ShellCheck present, real Qt/Quickshell verification, fresh core installation and second-run idempotence. `/tmp/v025-evidence/cn-final-source-match.log` verifies all runtime/config/test/tool files match the frozen snapshot; only evidence documentation differs. G5 live repeat also passed as recorded above.

Independent Claude review 2: **code PASS, evidence gate PASS**, with no permission blocks. It independently inspected screenshots/logs, checked the source snapshot, ran eight regression scripts plus five session repeats, and reproduced CN/SHA/auto mutations. Two low documentation findings were corrected; the only non-Markdown difference from tested source is the explanatory comment on arch-log line 2 (executable body unchanged). Evidence: `/tmp/mimo-logs/v025-claude-review-2.log`, `v025-claude-review-2-resolutions.md`, `/tmp/v025-evidence/cn-postreview-source-match.log`. Docker mount metadata in `full-suite-8-mounts.json` confirms the frozen source was mounted read-only at `/src`.

MIMO final review against the plan: **release gate PASS**, no blocking findings (`/tmp/mimo-logs/v025-final-review.log`). It independently checked source fidelity, the full-suite log, screenshots, CN requirements and review resolutions. All release gates passed before commit/tag/push. The operator synchronizes Gitee main and v0.2.5 after the origin push; CN commands serve this release after that sync. Repeated upstream migration notifications remain a cosmetic limitation. The Pad fallback remains undiagnosed.
