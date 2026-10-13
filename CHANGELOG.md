# Changelog

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
