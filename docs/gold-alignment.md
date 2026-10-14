# v0.2.6 working-Pad alignment

The operator collected read-only evidence from working Omarchy on the same Pad:
`/tmp/v026-evidence/pad-arch-reference.txt` and `pad-arch-reference-2.txt`.
Earlier authentication failures are historical; gold evidence is now available.
MIMO compared actual process environment/libraries, not just `pacman -Q`, in
`/tmp/mimo-logs/v026-gold-diff.log`. Raw evidence stays local because it includes
account names, device identifiers and application logs.

| Component | Working Pad reference | v0.2.6 |
| --- | --- | --- |
| Compositor | Custom `/opt/hyprland-0.55`, own watchdog and libraries | Distro Hyprland by default; explicit trusted prefix uses its own watchdog/libs/hyprctl |
| Mesa | Debian 25.0.7, LLVM 19.1.7 under `/opt/debian-mesa` | Installer stages Debian 13 host apt libraries at that prefix; VM has the same versions |
| Renderer environment | No AQ/LIBGL/GALLIUM overrides; llvmpipe fallback | Same defaults; explicit diagnostic knobs retained |
| Seat and devices | seatd; numeric device/socket GIDs in supplementary groups | Already matched by installer; VM confirms mapped groups and access |
| Parent display | No WAYLAND_DISPLAY, unused old Weston socket | No WAYLAND_DISPLAY; private mask of host idle wayland-0 |
| Runtime | UID-owned 0700 tmpfs at `/run/user/1000` | Host user runtime bound at same path for D-Bus/audio/host clients; private socket mask only |
| Monitor | Catch-all preferred,auto,1; Virtual-2 on this session | Catch-all; sysfs preference plus any usable monitor accepted |
| Instances | Abandoned event-only directory, then healthy command socket | Repeated discovery, live PID/UID check, explicit signature, bounded per-instance probes |

The gold's `No CRTC 0`, page-flip-pending messages and initial card0 EGL failure
coexist with working output. They do not alone establish the cause of a black
screen. The earlier VM parent-Wayland deadlock is confirmed; Mesa/version
necessity on the physical Pad remains an inference pending its next test.
The optional reference `blit/` directory has unknown contents and purpose; it
is omitted. The VM works without it.

The two directories are consistent with recovery through the watchdog, but
the exact reason for the first instance's exit is not proven by these excerpts.
Both distro and custom launch paths use `start-hyprland`; the gate tolerates a
restart by that supervisor without caching the first instance. It does not
implement a new forced restart of a wedged compositor: the known idle-parent
wedge is prevented, and other startup failures still time out to Weston.

## Debian Mesa provenance and rollback

`lib/debian-mesa.py` copies the host's apt-installed `libEGL_mesa`, `libgbm`,
`libgallium`, LLVM 19, libedit, libxml2 and libz3 compatibility libraries plus
Debian's **actual** `gbm/dri_gbm.so`. It generates the EGL vendor JSON and records
resolved source paths, binary/source package versions and SHA256 for each file
in `/opt/debian-mesa/manifest.json`. No graphics binaries are distributed in
this repository, and no pacman-owned file is replaced. Apt retains existing
CN mirror routing; the staging step performs no downloads.

Staging happens before an atomic symlink switch to a content-keyed directory.
Older managed copies remain available; existing unmanaged `/opt/debian-mesa`
directories are preserved with a notice. Missing host libraries fail before
activation. Reproduce a copy from the recorded Debian package versions and
verify its recorded hashes; this is package provenance, not a claim that the
upstream compiler output is bit-for-bit reproducible. Host apt updates can
change versions on the next installer run, and the new manifest records that.
`touch ~/.config/arch-use-arch-mesa` selects Arch Mesa on the next launch;
remove that file to restore Debian Mesa. Desktop child processes inherit the
selected Mesa environment, as on the gold reference.

## Hyprland 0.55 build/package decision

Do not copy the reference's unknown `/opt/hyprland-0.55` or `0.56.2-fix` binaries.
The 0.55 instance hash is known, but the evidence does not include dependency
commits, local patches, compiler flags or a complete build manifest. A plain
0.55 package would not necessarily reproduce that custom library stack.

If the Pad still fails with distro Hyprland plus the aligned Mesa/environment,
choose a **pinned source build into an isolated prefix**, with pinned dependency
commits/submodules, compiler/build packages, patches, logs, installed hashes and
RPATH. Build the matching watchdog and hyprctl too. The upstream
[v0.55.0 build configuration](https://github.com/hyprwm/Hyprland/blob/v0.55.0/CMakeLists.txt)
requires CMake 3.30, C++26 and Lua 5.5, plus several Hypr libraries; pinning only
the Hyprland tag is insufficient. This release does not claim to have built or
validated a reproducible 0.55 stack.

An old ALARM package is an alternative only with a verified aarch64 artifact,
ALARM signature, checksum and compatible dependency set. The ordinary
[Arch Linux Archive](https://wiki.archlinux.org/title/Arch_Linux_Archive) is not
proof of an available matching ALARM package; no verified 0.55 ALARM archive set
was established here. Reject an unverified archive URL or a single-package
partial downgrade. Any future CN build must accept local pinned sources or
verified Gitee mirrors without silently fetching GitHub.

The arm64 VM runs distro Hyprland 0.56.2 successfully with Debian Mesa 25.0.7,
so a custom build has **not been shown necessary**. Physical Pad/kernel behavior
is still a release limitation, clearly separated from VM evidence.
