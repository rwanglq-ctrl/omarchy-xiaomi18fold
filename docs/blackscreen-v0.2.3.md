# Android Terminal black screen investigation (v0.2.3)

## Evidence and confidence

Reported Pad environment: Xiaomi 18 Fold, Android 16 Linux Terminal,
Debian host user UID 1000, ALARM nspawn `arch-desktop`, Hyprland 0.56.2.
The compositor and watchdog launcher remain alive, and wayland-0 exists,
but the display window is black. Aquamarine enumerates virtio_gpu card0,
16 CRTCs, Virtual-1 connected and the other connectors disconnected.
There are repeated `getCurrentCRTC: No CRTC 0` messages; the supplied log
excerpt has no renderer/output initialization messages. Weston works.
No direct Pad access or complete live log was available during this release.

**Confirmed repository defects (high confidence):** the launcher described
llvmpipe but did not force software rendering; the session wrapper waited
synchronously for the launcher and only recovered after an early exit.
An alive compositor with no usable output therefore bypassed recovery forever.
`hypr-switch --now` restarted weston.service, which owns the Android display
and can close the Terminal UI. The host installer did not add its launchers
to interactive bash PATH.

**Device-specific cause (medium confidence, not proven):** compositor startup
is stalled or incomplete along the virtio_gpu DRM/EGL/GBM initialization path.
The missing renderer/output messages favor this over an ordinary blank
wallpaper, but a partial log is insufficient to distinguish Mesa buffer export,
modifiers, seat activation, or atomic modesetting failure. A Wayland socket
and process liveness do not establish successful scanout. Optional Debian Mesa
absence is supported and is not itself a fault.

Hyprland [v0.56.2 Compositor.cpp](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/Compositor.cpp)
requests headless plus DRM and a Wayland fallback backend. The development host ABI
uses Aquamarine 0.15.0; the emulated fresh ALARM installation used 0.15.1. Aquamarine
[v0.15.0 DRM.cpp](https://github.com/hyprwm/aquamarine/blob/v0.15.0/src/backend/drm/DRM.cpp)
returns null when the current connector CRTC_ID is zero; connector init still
returns true, and `recheckCRTCs` subsequently allocates an available CRTC.
Thus the quoted message alone does **not** prove CRTC allocation failed.
The runtime ALARM Aquamarine package version should be checked separately;
this investigation does not assume the Pad package exactly matches the local ABI.

The [Aquamarine environment reference](https://github.com/hyprwm/aquamarine/blob/v0.15.0/docs/env.md)
defines AQ_NO_MODIFIERS and AQ_NO_ATOMIC. Upstream
[warns against legacy DRM](https://github.com/hyprwm/aquamarine/pull/80).
Atomic remains enabled by default. Mesa's
[environment reference](https://docs.mesa3d.org/envvars.html)
documents software rendering and GALLIUM_DRIVER. These flags are set before
Hyprland starts, rather than relying on late Lua environment changes.

## Mitigation and recovery

The default launcher forces llvmpipe, disables modifiers and uses software
cursors. An explicit Lua monitor rule enables Virtual-1 at its preferred mode.
Fixed host marker files provide opt-outs and an opt-in legacy modesetting probe;
no user file is sourced as shell code under sudo.

Session startup polls a bounded namespace-local `hyprctl -j monitors` query
for up to 30 seconds. It excludes the previous container leader so a leftover healthy desktop cannot
satisfy the new session startup gate. It selects live Hyprland instances with matching UID and
executable in the container PID namespace, rejects stale runtime instances,
and requires Virtual-1 with numeric positive dimensions, DPMS on, not disabled
and not marked as a fallback output.
It collects private diagnostics, terminates the container with a bounded
SIGTERM/SIGKILL cleanup, then execs the known-working Weston recovery command.
If cleanup cannot release the machine, it refuses a competing compositor.
Service-stop signals do not initiate recovery. Monitoring is a startup gate;
a later output loss or black pixels despite an active IPC output still requires
manual diagnostics/recovery. Diagnostic collection and cleanup add several
seconds normally, or about 40 seconds on timeout paths, after the startup deadline.

`arch-diag` queries only the existing desktop, writes a mode-0600 file, bounds
command waits, and does not restart services or dump process environments.
Monitor diagnostics omit workspace names and compositor logs omit lines
mentioning windows, titles and clients. Journal logs can still contain application
commands and user paths;
inspect the file before sharing. It prints only the saved path.

All `hypr-switch --now` requests are deferred, including shells without
DISPLAY/WAYLAND_DISPLAY: Android display membership cannot be detected reliably
from those variables. Reopen the display after selecting a mode; use independent
SSH if an explicit service restart is necessary.

## Reproduction and validation limits

Development host: x86_64 with Hyprland 0.56.2 and Aquamarine 0.15.0.
There is no qemu-system-aarch64 executable or Android virtio_gpu device here;
QEMU user-mode ALARM tests do not emulate DRM scanout.

A real Hyprland launch was attempted under bubblewrap with private PID/network
namespaces, an isolated runtime directory, a minimal Lua config and software
rendering; /dev was replaced to prevent access to the active host compositor's
DRM devices. With neither DRM nor a parent Wayland compositor available,
Hyprland aborted at `CBackend::create() failed!` (exit 134). This demonstrates
that this build cannot provide the requested pure-headless reproduction; it
**does not reproduce** the Pad's alive-but-black state. The real 0.56.2
`--verify-config` accepted the new monitor/cursor Lua settings.

Separately, a read-only query of the existing development-host compositor
returned only a 1920x1080 `FALLBACK` monitor with DPMS off; the readiness
predicate rejected that real JSON. This confirms that real 0.56.2 can remain alive without an active
output. That host uses NVIDIA, so this observation does not
reproduce the Pad's virtio_gpu black pixels.

Offline regressions reproduce the session wrapper's alive/no-output behavior
using mocked hardware/IPC, and exercise stale instance filtering, malformed
and inactive monitor reports, IPC timeout, early exit, successful startup,
service-stop signals, failed cleanup, renderer arguments/opt-outs, deferred
switching, private diagnostics and shell PATH. Full ALARM integration verifies
installation, configuration and rerun idempotence separately. Display scanout
and the choice of GPU mitigation remain to be validated on the Pad.

MIMO analysis, patch drafting and final review prompts and outputs are saved at
`/tmp/mimo-logs/blackscreen-analysis.log`, `blackscreen-drafting.log` and
`blackscreen-review.log` on the release workstation. Findings were checked
against source and behavioral tests, rather than accepted without verification.


## v0.2.4 follow-up — 2026-10-14

Pad Weston diagnostics showed Virtual-1 disconnected and Virtual-2 connected,
with preferred 846x1012@60 on virtio_gpu. These are Weston/kernel observations,
not proof that Arch Hyprland had DPMS on or displayed frames. The v0.2.3 gate
required the exact IPC name Virtual-1 and would reject a usable Virtual-2.
This is a confirmed logic defect with high confidence; it does not establish
why the Pad displayed black pixels. The existing Lua catch-all already matched
other outputs, so removing the redundant named rule alone is not proof of a fix.

v0.2.4 retains only the preferred/auto/1 catch-all. Readiness accepts any named,
positive-size, DPMS-on, enabled non-fallback output, excluding synthetic
HEADLESS/FALLBACK outputs. Kernel card0 connected names are discovered and
preferred in reports, never required to equal Aquamarine names. Software GL,
llvmpipe, disabled modifiers, software cursors and atomic DRM remain defaults.
Single-output touchscreen mapping stays automatic; no connector is pinned.

Before cleanup, the gate gives arch-diag a bounded 20-second collection window.
The private 0600 report now includes raw monitors all (including workspace names
and possible device identifiers), raw DRM statuses, and filtered runtime log
and journal tails. Unlike v0.2.3's summary-only report, raw monitor data is
intentionally retained for diagnosis; inspect before sharing. Logs can be stale
or host-shared because the UID runtime is bind-mounted; paths and modification
timestamps identify each of the newest four 128KiB tails. Live monitor IPC still
requires the container PID/UID/executable validation. Device visible-frame and
touchscreen verification remain outstanding.
