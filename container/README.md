# Container installation

Run `bash container/install.sh --dry-run --profile full` to review the steps.
Real installation requires a sudo-capable regular user in Arch Linux ARM aarch64;
root must pass `--user NAME`. The default profile is `core`. `full` adds the
applications in the two `*-full.txt` manifests to the corresponding core lists.
`--no-aur` skips yay and all AUR builds, and selects the stock Rime schema instead
of the unavailable rime-ice preset. Release validation is recorded in
[the versioned validation record](../docs/v0.2.9-validation.md).

The installer logs real runs to `~/.cache/omarchy-alarm/install.log`. Repository
installation includes a full system upgrade. The requested desktop packages
use fixed, verified source bundles and run makepkg as the regular user.
Additional global-only AUR packages retain the yay path. Source and build
caches live below `~/.cache`, including Rust temporary files. The two packages
`tensaku` and `omawrite` explicitly use `makepkg --ignorearch` because their AUR
metadata lists x86_64 despite their portable source builds.

An existing Omarchy checkout must be at the pinned commit in `patches/BASE`.
The installer never resets it or discards local edits. Applied patch checksums
are recorded under `~/.local/state/omarchy-alarm`. Repeat runs preserve seeded
upstream defaults, reapply the explicit `config/` overlay, and append the shell
and makepkg blocks only once. The config overlay intentionally replaces its
listed target files; review it before installing onto an existing account.

Upstream `omarchy-provision-user` runs in headless provisioning mode, with Tokyo
Night as the initial theme. Existing provisioned users keep their current theme.
The user's bashrc is retained with a marked block based on the upstream default.
The local GSettings keyfile backend avoids writing through the host dconf service.
`config-share/fcitx5/rime/default.custom.yaml` is the only Rime share overlay;
no learned dictionaries or personal application profiles are included.

Stay-awake defaults to ON on every installer run. A locked or missing password
prints a warning. Set a password before using `omarchy toggle idle` or manually
locking the session. Host services and hardware configuration are not provisioned
here; desktop launch remains the host launcher's job.

Both profiles install pinned mise and AI programs after desktop provisioning.
See [program packages and sources](../docs/packages.md). Verified prefixes are
registered with `mise link`, with commands in `~/.local/bin`; no tool configuration,
authentication, keys or tokens are installed. Upstream mise provisioning is disabled
in both modes, including repeat runs. Existing AI settings are preserved, and new
AI defaults/skills are not seeded. Failures are nonfatal and reported per tool in
`~/.local/state/omarchy-alarm/tool-programs.txt`.

`extras/build-hyprland-0562-fix.sh` is an optional llvmpipe performance backport,
never invoked by the installer. It requires the development tools and libraries
for Hyprland (including CMake, Ninja, Python and a C++ toolchain). Set `JOBS`,
`HYPRLAND_FIX_SOURCE` or `HYPRLAND_FIX_PREFIX` to override its defaults; the prefix
must be a dedicated absolute directory. Select its compositor explicitly in the
host launcher. Once the distro compositor includes the damage-clip fix (expected
in Hyprland 0.57 or newer), use `/usr/bin/Hyprland` and remove the dedicated prefix.
