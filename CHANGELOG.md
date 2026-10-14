# Changelog

## 0.2.6 — 2026-10-14

- Make `arch-selftest` stop weston.socket before weston.service, wait for the
  session lock/seat, report live owners, clear dead PID metadata under flock,
  and restore both display units after success, failure or handled signals.
- Preserve systemd's activation socket across session logging and Weston
  fallback; close the session lock in the logger and container launcher.
- Probe in the container's explicit mount/PID namespace, root and working
  directory as the configured UID. Verify the command socket and live process,
  pass the instance signature explicitly, and fall back to socket/lock discovery
  when `hyprctl instances` fails. Record bounded probe progress.
- Capture runtime mount/permissions, sockets and real Hyprland logs inside the
  container before other diagnostics and teardown. Preserve host log retrieval
  when the container has already exited or namespace entry fails.
- Prevent direct DRM startup from connecting to the idle weston.socket as a
  parent Wayland compositor. A VM backtrace confirmed the startup roundtrip
  blocked before Hyprland created its command socket. Client environments use
  Hyprland's own socket after startup.
- Test the real gate and selftest with connected outputs flipping Virtual-2 to
  Virtual-1, discovery failures, activation races, stale/live locks, restoration
  and signals, including a watchdog restart gap and an abandoned event socket.
- Align with newly collected same-Pad gold evidence: stage Debian 13 Mesa/LLVM
  from apt-installed files with package/source versions and SHA256 provenance;
  preserve Arch packages and allow opt-out. Debian 13 arm64 is the supported
  host; the new dependency set does not support Debian 12. Use driver autodetection without
  forced AQ/LIBGL defaults. Clear parent Wayland variables and privately mask
  the idle host wayland-0 socket, preserving host fallback activation.
- Select the matching watchdog, libraries and probe client for an explicit
  custom prefix. Default remains distro Hyprland; the reference's custom 0.55
  dependency/build provenance is incomplete, so no unknown binaries are shipped.
  Physical Pad validation remains outstanding; arm64 VM startup/selftest pass
  with distro 0.56.2 plus Debian Mesa 25.0.7.
- CN continues to clone Gitee; only origin is pushed by this release task.
- Provenance: Codex **gpt-6-astra** implementation and validation; pi
  **xiaomi/mimo-v2.6-pro-ultraspeed** analysis and review in
  `/tmp/mimo-logs/v026-analysis.log`, `/tmp/mimo-logs/v026-pad-analysis.log`,
  `/tmp/mimo-logs/v026-ipc-analysis.log`,
  `/tmp/mimo-logs/v026-reference-diff.log`, `/tmp/mimo-logs/v026-review.log`,
  `/tmp/mimo-logs/v026-review-followup.log`, `v026-gold-diff.log`,
  `v026-gold-review.log`, `v026-gold-final-review.log`; independent Claude **claude-opus-5-5** review
  in `/tmp/mimo-logs/v026-claude-review.log` and
  `/tmp/mimo-logs/v026-claude-followup.log` and `v026-claude-review-3.log`. Local raw logs are not bundled.


## 0.2.5 — 2026-10-14

- Initialize a stable container machine ID before nonboot nspawn startup. The
  empty ALARM identity caused a reproduced D-Bus/Quickshell crash loop.
- Qualify Omarchy shell color references to resolve the reproduced Qt 6.12
  `QtQuick.Color` collision, restoring the themed bar, menus and notifications.
- Persist each launch's stdout/stderr, stage timestamps, actual runtime logs,
  shell log and journals before cleanup. Add foreground `arch-selftest`, private
  reports, explicit missing-log markers and post-teardown log retrieval.
- Use Linux uptime for readiness/cleanup deadlines, independent of wall-clock
  corrections; validate machine-ID bytes before shell substitution.
- Bound owned-session cleanup and signal handling; refuse competing sessions
  and suppress Weston fallback when cleanup cannot prove the machine is gone.
  Check sudo, required bind sources, seat socket and launcher before nspawn.
- Install missing Git through Debian apt, clone then check out branches/tags/full
  SHAs, and remove archive fallback. Resolve auto mirrors before fetching; keep
  piped dry runs offline. Add host prerequisites and device-group mapping.
- Expand bootstrap, identity, display and lifecycle regressions, installed
  Qt/Quickshell checks and second-install identity comparisons. Document the
  real ARM VM reproduction and its Android/crosvm fidelity limits. The Pad's
  original automatic fallback remains undiagnosed; no verified Pad fix claimed.
- Address independent review: reject leading-newline identities and linked check
  paths, retry registry queries, honor stops during cleanup, bound session logs
  to 8 MiB/ten attempts, skip root device-group membership, and document recovery.
  Restore Gitee source clones for CN, including branch/tag/SHA regression tests;
  the operator synchronizes Gitee after each origin release. Passwordless sudo is required when enabling the display hook.
- Provenance: Codex **gpt-6-astra** implemented and verified this continuation.
  pi **xiaomi/mimo-v2.6-pro-ultraspeed** provided analysis, full-path audit,
  test plan, plan review, patch review and final review against the plan:
  `/tmp/mimo-logs/v025-analysis.log`, `/tmp/mimo-logs/v025-audit.log`,
  `/tmp/mimo-logs/v025-test-plan.log`, `/tmp/mimo-logs/v025-plan-review.log`,
  `/tmp/mimo-logs/v025-patch-review.log`, `/tmp/mimo-logs/v025-final-review.log`.
  The audit and plan-review logs include `v025-baseline-plan-addendum.log`.
  Claude Code **claude-opus-5-5** provided independent review:
  `/tmp/mimo-logs/v025-claude-review.log` and
  `/tmp/mimo-logs/v025-claude-review-2.log`. GLM was not used.
  Raw local logs are not bundled with the source release.

## 0.2.4 — 2026-10-14

- Remove the Virtual-1 assumption: catch-all preferred monitor rule, any usable
  non-fallback output satisfies startup, and arch-output autodetects connected
  card0 connectors without requiring kernel/Aquamarine names to match.
- Preserve pre-fallback monitors all, filtered Arch runtime log tails (even when
  IPC failed), and DRM status in private diagnostics. Keep software GL,
  AQ_NO_MODIFIERS and software cursors.
- Correct installation hints: select Arch, fully close/reopen Linux Terminal;
  retain the early shell PATH block and verify interactive/login shells.
- Fail safely when an existing desktop has an unreadable previous leader.
- Extend display regressions for connector changes and pre-cleanup diagnostics.
  Pad visible-frame verification remains outstanding.
- How this release was made: Codex (on rwolinux) implemented the code and
  tests and ran verification (full suite 12/12 PASS). pi with
  xiaomi/mimo-v2.6-pro-ultraspeed did analysis, design, review and final
  review (/tmp/mimo-logs/v024-{analysis,design,review,review-final}.log).
  GLM 5.3 was not used.

## 0.2.3 — 2026-10-13

- Set software llvmpipe and linear DRM buffer defaults before nspawn launch;
  retain atomic modesetting with an opt-in legacy diagnostic knob.
- Explicitly enable Virtual-1 in Lua and disable hardware cursors.
- Detect alive-but-no-output startup via bounded, namespace-local hyprctl IPC;
  reject a leftover container leader, save private diagnostics and stop the
  container before Weston recovery.
- Add read-only arch-diag and arch-output helpers; defer hypr-switch --now
  to protect the Android Terminal UI. Add host bashrc/profile local-bin PATH.
- Correct CN resume to pinned Gitee URLs and document safe update/recovery.
- Support full QEMU integration by disabling Landlock only in disposable test rootfs.
- Add behavioral display regressions and record upstream analysis and
  reproduction limits.

## 0.2.2 — 2026-10-13

- Repair container DNS before pacman: replace rootfs resolver symlinks, read host
  upstream DNS instead of loopback stubs, and verify mirror resolution in nspawn.
  CN retries with AliDNS and DNSPod; nspawn preserves the managed resolver.
- Isolate installer children from piped script stdin and send diagnostic logs
  to stderr as defensive protection against script/input mixups.
- Remove the unsupported `[aur]` sync repository in CN mode (with a backup),
  and install host `gnupg` in CN mode before rootfs signature verification.
- Extract fresh rootfs into staging and rename only after success, so interrupted
  extraction cannot be mistaken for an installed container.
- Retry a mirror once from scratch after a stale partial fails its checksum.
- Confirm existing Arch containers and checksum-valid cached rootfs downloads
  are reused on resume; add resolver, stdin, repository and resume regressions.
- Support arm64 CI under QEMU with an adjustable quick-suite budget, cached
  rootfs downloads and explicit Docker platform selection.

## 0.2.1 — 2026-10-13

- Publish the Gitee mirror https://gitee.com/zenbardofsuhe/omarchy-xiaomipad9pm; `MIRROR=cn` bootstrap now
  fetches from it by default, enabling a one-line install on mainland networks.

## 0.2.0 — 2026-10-13

- Add `MIRROR=cn|global|auto` and `--mirror`, with bounded probes, downloads,
  retries and mainland mirror fallback. Keep `global` as the default.
- Configure Debian apt and ALARM pacman before their first install; back up
  original source files and propagate the mode through sudo/nspawn/runuser.
- Vendor the exact Omarchy v4.0.4 Git checkout with checksums and its MIT license.
  CN installs skip AUR and optional mise, using repository fonts and stock Rime.
- Document every install fetch, reachability results, bootstrap limitations,
  and reproducible blocked-host simulation; add mirror policy tests.
- Bootstrap `ca-certificates` over plain-HTTP mainland mirrors when the CA
  bundle is missing or HTTPS probes fail, then switch sources back to HTTPS;
  the test container always bootstraps over HTTP first and bounds HTTPS apt
  fetches with `Acquire::https::Timeout`.
- Make downloads resumable (`curl -C -`, keep `.part` across retries and
  candidates, delete only on checksum mismatch) and give the rootfs a larger,
  overridable timeout (`NETWORK_ROOTFS_TIMEOUT`).
- Bootstrap fallback: a failing `git clone` now falls back to the archive
  download (both with 300s deadlines), and the archive URL is overridable via
  `OMARCHY_ALARM_ARCHIVE_URL`.
- Single `auto` mirror detection in `lib/network.sh`, probing both github.com
  and raw.githubusercontent.com and logging the chosen mode from every entry
  point; dry runs resolve `auto` to `global` without probing.
- Bound AUR git clones with 120s deadlines and git low-speed limits.
