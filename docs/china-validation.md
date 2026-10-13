# China network validation — 0.2.0

Test environment: x86_64 Linux host, QEMU aarch64 binfmt interpreter,
Debian `trixie` arm64 Docker image, 2026-10-13. No Xiaomi device was attached.
The system Docker socket denied access (`permission denied while trying to
connect to the docker API at unix:///var/run/docker.sock`); `sudo -n` reported
`sudo: a password is required`. An isolated rootless Docker daemon, with
rootlesskit/slirp4netns and a private data directory, was used instead.
The system daemon and host configuration were not changed.

Reproduce with `bash tests/china-downloads.sh`. The script enumerates blocked
hosts and installs each with `--add-host HOST:0.0.0.0`, checks failures, and
runs real mainland apt, rootfs, extraction, pacman database and vendor stages.
No HTTP proxy is passed into the container. Docker image acquisition is
outside the blocked install stage. QEMU was confirmed by `uname -m`: aarch64.

## Reachability probes

Each probe used curl with 5-second connect / 15-second total deadlines. These
results are from this machine, not a measurement from mainland China.

| URL | HTTP | Time (seconds) |
| --- | --- | --- |
| https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm/os/ArchLinuxARM-aarch64-latest.tar.gz.md5 | 200 | 0.217 |
| https://mirrors.ustc.edu.cn/archlinuxarm/os/ArchLinuxARM-aarch64-latest.tar.gz.md5 | 200 | 0.108 |
| https://mirrors.aliyun.com/debian/dists/trixie/Release | 200 | 0.422 |
| https://mirrors.bfsu.edu.cn/archlinuxarm/os/ArchLinuxARM-aarch64-latest.tar.gz.md5 | 200 | 0.089 |
| https://mirror.sjtu.edu.cn/archlinuxarm/os/ArchLinuxARM-aarch64-latest.tar.gz.md5 | 200 | 0.048 |
| https://registry.npmmirror.com | 200 | 0.894 |
| https://pypi.tuna.tsinghua.edu.cn/simple/pip/ | 200 | 0.300 |
| https://goproxy.cn/golang.org/x/text/@v/list | 200 | 1.492 |
| https://rsproxy.cn/rustup/release-stable.toml | 200 | 0.448 |

ALARM pacman layout follows [TUNA's official instructions](https://mirrors.tuna.tsinghua.edu.cn/help/archlinuxarm/).
Language mirror probes verify endpoint reachability, not that every package
or upstream Git source is mirrored. AUR is therefore skipped in CN mode.

## Verification

- All shell scripts and extensionless host/container helpers: bash syntax PASS.
- ShellCheck v0.11.0, downloaded locally because it was absent: PASS.
- `tests/mirrors.sh`: PASS, including timeout-policy selection, failed primary
  mirror, artifact fallback, apt metadata failure fallback, source backups, invalid mode and offline dry run.
- `tests/run.sh --quick`: 10 checks PASS; repository-package check FAIL on the
  host's x86_64 databases (`archlinuxarm-keyring` absent). This is an architecture
  mismatch; ARM database validation is included in the simulation script.
- Blocked-host Docker + QEMU Debian arm64 simulation: PASS. Apt package install,
  HTTPS apt metadata update after CA bootstrap, complete 790 MiB rootfs download/MD5/extraction, core/extra/alarm sync DBs,
  `pacman -Si` for all 149 repository packages inside the extracted ARM root,
  vendored checkout/checksums, all ARM patches, and install dry run succeeded.
- Vendored checkout checksum, exact pinned base and ARM patch application: PASS.
- Minimal Debian image CA bootstrap uses HTTP TUNA with normal Debian signed
  metadata/package hashes; after ca-certificates is installed, production
  mirror policy selects HTTPS. An earlier test mounting the host CA bundle
  failed TLS verification; no TLS validation was disabled to resolve it.
- `tests/full.sh --probe-only`: stopped with `Full tests require native aarch64`.
  Full integration needs native ARM, noninteractive sudo and nested isolation.

## Off-device limits

No full desktop install, seatd, weston/display handoff, Android DRM/input,
Xiaomi llvmpipe/dmabuf, audio, actual nspawn boot, or second-run desktop
idempotence was tested. The simulation exercises install download stages,
not an Android VM kernel or mainland routing/filtering behavior. A real CN
bootstrap URL remains unavailable until the complete source is published to
a trusted reachable mirror; use a transferred complete checkout meanwhile.
