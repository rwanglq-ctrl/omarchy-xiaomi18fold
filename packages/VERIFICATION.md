# Package verification

## v0.2.9 additions (2026-10-15)

- Read-only ALARM/CN probes confirm uwsm, hyprland-guiutils, tree-sitter-cli
  and ttf-jetbrains-mono-nerd. The basic font variant uses the full font fallback.
- Yaru is absent from the probed ALARM repository; a pinned upstream source
  bundle and architecture-independent Meson recipe provide it instead.
- All active reference mise tools are recorded as names/versions only in
  `tool-programs/gold-inventory.json`. pi 1.2.0 is from
  `@earendil-works/pi-coding-agent` / `earendil-works/pi`.
- The gold mise ID `github:ogulcancelik/herdr` redirects upstream (HTTP 301
  verified 2026-10-15) to `herdrdev/herdr`, the release owner pinned in
  the program manifest; herdr 0.9.3 provides aarch64 binaries.
- Nine desktop source bundles and the LazyVim source/plugin snapshot have
  pinned SHA256 manifests. Repository presence and prepared sources do not
  prove build success; see [release validation](../docs/v0.2.9-validation.md).
- CN program sources are npmmirror and this project’s Gitee tools-v0.2.9
  assets. The operator preparation script verifies all asset checksums.

## Earlier package audit (2026-09-27)

Checked 2026-09-27 on Arch Linux ARM aarch64 using the configured pacman sync databases (read-only `pacman -Si`, no database refresh).

- Repository: 149/149 found (112 core, 37 additional full).
- AUR RPC: 12/12 found (4 core, 8 additional full), via https://aur.archlinux.org/rpc/v5/info.
- No missing names; existence does not guarantee a future build succeeds.
- `tensaku` and `omawrite` require source builds with `makepkg --ignorearch`.
- Derived from v4.0.4 `install/omarchy-base.packages`, the port notes, and explicit/foreign reference snapshots; snapshots deleted after verification.
- `omarchy-other.packages` is excluded because it provisions boot, kernels, firmware and host hardware.
- `vi` is unavailable in the reference sync database; `ex-vi-compat` is used instead.
- The earlier core AUR manifest included yay, bootstrapped before live AUR installs.
