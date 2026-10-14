# Changelog

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
  Pad visible-frame verification remains outstanding; publish to GitHub only.

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
