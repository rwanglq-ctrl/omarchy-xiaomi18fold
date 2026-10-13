# Install network audit and mainland China policy (0.2.0)

Scope: every tracked entry point in `install.sh`, `host/`, `container/`,
`tools/`, `packages/`, `patches/`, `config/`, plus code invoked from pinned
Omarchy v4.0.4. Audit date: 2026-10-13. See
[validation and measured reachability](china-validation.md) for test results.

## Root causes

The documented pipe bootstrap requires GitHub raw before the script can
select a mirror. Its next fetch clones GitHub (or downloads an archive that
redirects to codeload). Host apt uses Debian's existing overseas sources;
rootfs originally comes from overseas ALARM HTTP, then pacman uses its
bundled mirrorlist. Container provisioning clones GitHub again and AUR
recipes download arbitrary upstream sources. Setting only a pacman mirror
cannot fix any of those earlier or later dependencies. Missing deadlines
also turn blocked endpoints into long apparent hangs.

## Every direct fetch and invoked network operation

| Location / stage | Original destination or operation | CN behavior |
| --- | --- | --- |
| README / install.sh pipe entry | `raw.githubusercontent.com/rwanglq-ctrl/omarchy-xiaomipad9pm/main/install.sh` | Cannot rewrite an already blocked bootstrap URL. Transfer the complete checkout, or use a trusted reachable repository mirror. No public CN bootstrap is claimed. |
| install.sh bootstrap | `git clone --depth 1 --branch REF https://github.com/rwanglq-ctrl/omarchy-xiaomipad9pm`; configurable `OMARCHY_ALARM_REPO` / `OMARCHY_ALARM_REF` | Requires local checkout or explicitly configured trusted reachable mirror in CN mode; otherwise fails immediately with instructions. Clone deadline 120 seconds. |
| install.sh archive fallback without git | `REPO/archive/REF.tar.gz`, normally GitHub → `codeload.github.com` | Same explicit mirror requirement; curl connect 5s / total 300s / 2 retries. Archive is downloaded data, then the selected repo's install.sh executes. |
| lib/network.sh auto mode | HEAD `https://github.com` | 2s connect / 4s total probe, failure selects CN; dry runs do not probe. This is an optional detection probe, not an install dependency. Explicit CN never probes GitHub. |
| host/install.sh apt | Existing `/etc/apt/sources.list{,.d/*}`; Debian defaults `deb.debian.org/debian`, `/debian-security`, `security.debian.org/debian-security`; `apt-get update/install` | Rewrite only known official archive prefixes, preserving suites/components/signed-by; save originals. TUNA, USTC, Aliyun selection checks trixie and trixie-security Release with 3s connect / 8s total. Apt uses 15s timeouts and 2 retries; failed metadata updates advance through all three mirrors, with update errors treated as failures. Custom sources remain user controlled. |
| host/install.sh rootfs | `http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz`, same URL plus `.md5` and `.sig`; `OMARCHY_ALARM_TARBALL_URL` override | HTTPS TUNA → USTC → BFSU → SJTU, bounded probes; download+MD5 pair from one mirror, with full artifact fallback. Override is honored without guessing adjacent mirror paths. |
| host/install.sh signature key | Previously GPG HKPS `keyserver.ubuntu.com`, `OMARCHY_ALARM_KEYSERVER` override | Local vendored public key; no keyserver fetch. Existing fingerprint checked against VALIDSIG; BADSIG is fatal. Missing GPG/signature retains the preexisting warning policy. MD5 alone is not publisher authentication. |
| host/install.sh rootfs setup | `pacman -Syu base-devel git sudo` against bundled ALARM `/etc/pacman.d/mirrorlist`, generally `mirror.archlinuxarm.org` | Replace mirrorlist before the first sync, including reused rootfs. TUNA/USTC/BFSU/SJTU, `$arch/$repo`; pacman handles per-file mirror fallback. `pacman-key --init/--populate` uses installed local keys, not a network keyserver. |
| container/install.sh repository packages | `pacman -Syu` for packages/repo-core.txt and additive repo-full.txt; dependencies and fonts from ALARM sync DBs | Same four mainland mirrors before syncing, original mirrorlist backed up. Global mode retains existing sources. |
| container/install.sh yay bootstrap | `git clone https://aur.archlinux.org/yay.git`; makepkg sync dependencies, source archives, Go modules; build/install yay | CN skips all AUR builds explicitly; stock Rime retained. Global behavior unchanged. |
| container/install.sh AUR | yay RPC and recipe Git at `aur.archlinux.org`; `yay -S`; tensaku/omawrite cloned directly and makepkg `--ignorearch` | CN skips all 12 manifest entries (full includes core). AUR mirrors only mirror recipes, not their source downloads; no false promise of full AUR availability. |
| container/install.sh Omarchy | `git clone --branch v4.0.4 --depth 1 https://github.com/basecamp/omarchy.git` | Restore exact vendored Git objects/tag/shallow boundary, checksum all four parts, verify patches/BASE; apply patches with local git am. No GitHub fetch. Global still clones (120s deadline). |
| container/install.sh optional mise | `curl https://mise.run` then execute downloaded installer; installer fetches platform release assets from GitHub | Explicit opt-in full profile only globally; CN skips even when opt-in requested. Curl deadline/retries added. |
| invoked Omarchy provision-user | install/user/all.sh → theme, chromium, git, xcompose, mise-work, hardware, keyring, mise; refresh-applications / xdg defaults | Theme/assets/config local. New CN patch skips both mise leaves even if mise was already installed. Other invoked leaves do not fetch. |
| invoked upstream mise-work | With mise present, Node `mise use -g node@latest`; upstream uses nodejs.org and/or tool release backends; missing bundled x64 archive in provision-owner triggers network fallback | CN returns before this code. Globally original ARM patch skips it if mise is absent. |
| invoked upstream mise | Tool stubs/backend installs for codex, claude, crush, gemini, gh, copilot, opencode, playwright, pi, oh-my-pi, grok, cursor-agent, ghui, hunk, Hermes, Muse (`api.meta.ai`) | CN returns before any tool setup. Most commands create deferred wrappers; actual tool download occurs when launched. Global preserves upstream behavior. |
| container/extras/build-hyprland-0562-fix.sh | Optional `git clone --recursive --shallow-submodules` GitHub `hyprwm/Hyprland` v0.56.2; Git submodules and CMake/meson build dependency paths | Not invoked by install.sh or container/install.sh. Manual source-build helper requires reachable upstream or prepopulated sources; CN base install uses pacman Hyprland. |

## Ecosystems, fonts and data

- Repository fonts in repo-core/repo-full use pacman, not fonts.googleapis.com.
  AUR fonts `ttf-ia-writer`, `ttf-lxgw-wenkai`, and Rime `rime-ice-git` are
  upstream source fetches and are skipped in CN. `fc-cache -f` is local.
- There is no direct npm install, pip install, cargo install, go install or
  rustup in this repository's base installer. AUR PKGBUILDs and optional
  upstream tool installers can invoke those ecosystems; CN excludes them.
- CN exports npm registry `https://registry.npmmirror.com`, pip index
  `https://pypi.tuna.tsinghua.edu.cn/simple`, Go proxy `https://goproxy.cn`,
  Rustup distribution/update servers `https://rsproxy.cn` and `/rustup`,
  and a Cargo sparse registry index. These process settings do not guarantee
  arbitrary Cargo source replacement or mirror arbitrary Git dependencies;
  no language-tool build is needed for CN installation.
- Overseas ecosystem defaults include registry.npmjs.org, pypi.org,
  files.pythonhosted.org, proxy.golang.org, sum.golang.org,
  static.rust-lang.org, index.crates.io and static.crates.io. None is a hard
  dependency in CN mode. Language settings apply to this install process,
  not a permanent overwrite of user configuration.
- `tools/` contains only privacy scan/selftest/allowlist, with no fetch.
  `packages/` contains package manifests and verification docs, no executable
  fetches. `config/` contains local config, including a kitty documentation
  URL (not downloaded); `patches/` contains local git am inputs and runtime
  URLs such as Discord invite/OpenClaw localhost, not installation fetches.
- No global third-party GitHub proxy is enabled. No secrets, mirror auth
  tokens, disabled TLS verification or disabled package signature checks are added.

## Tests and development-only fetches

`tests/run.sh` clones Omarchy for patch validation, queries pacman databases,
and uses AUR HTTPS RPC for all names. `tests/ci.sh` downloads ALARM tarball and
MD5, imports Docker image, uses pacman, and downloads ShellCheck v0.11.0 from
GitHub releases (redirects can involve objects.githubusercontent.com or
release-assets.githubusercontent.com). `tests/full.sh` fetches ALARM rootfs
and MD5 and runs a full core/no-AUR install in native ARM isolation.
These are not invoked during normal installation. The new CN simulation
uses Debian arm64 Docker acquisition before blocking, then mainland sources
inside the container; see tests/china-downloads*.sh.

## Bootstrap and scope limits

For a complete transferred checkout, including vendor, the one-line command is:

```bash
MIRROR=cn bash ./install.sh --profile core
```

`--mirror cn` is equivalent. `global` is the default; `auto` measures GitHub
reachability, not location or all possible filtering rules. A reachable
GitHub page does not prove its raw/releases/CDN are reachable: use explicit
CN where needed. A full CN profile installs repository extras and skips
AUR extras. A public domestic bootstrap needs separate publication; a local
commit does not create one. Source mirrors and URL overrides are trust inputs.

## AUR recipe source audit

The live AUR recipes were cloned read-only on 2026-10-13 (recipes and lockfile
versions can change independently of this project). All are disabled in CN.
Go/Cargo dependency graphs are dynamic upstream inputs; their individual
module/crate URLs are not fixed by this repository.

| Manifest package | Recipe source fetches and build fetches |
| --- | --- |
| rime-ice-git | Git `https://github.com/iDvel/rime-ice.git` |
| ttf-ia-writer | 16 TTF files under `https://github.com/iaolo/iA-Fonts/raw/` at the recipe-pinned commit: Mono, Quattro, Duo, Duospace × Bold/BoldItalic/Italic/Regular; redirects to raw.githubusercontent.com |
| yaru-icon-theme | AUR RPC reports the package, but the Git clone returned an empty repository (`warning: You appear to have cloned an empty repository.`); the cgit PKGBUILD endpoint also returned HTTP 404, so its current recipe sources could not be confirmed. This is a separate global-install availability risk. CN does not require it. |
| yay | `https://github.com/Jguer/yay/archive/vVERSION.tar.gz`; Go dependency modules during make build, default proxy.golang.org/checksum service |
| aether | `https://github.com/omacom/aether/archive/refs/tags/vVERSION.tar.gz` and `/releases/download/vVERSION/aether-linux-arm64` (amd64 variant for x86_64) |
| cliamp | `https://github.com/bjarneo/cliamp/archive/refs/tags/vVERSION.tar.gz`; `go build` module fetches |
| feishu-bin | `https://sf3-cn.feishucdn.com/obj/ee-appcenter/HASH/Feishu-linux_arm64-VERSION.deb` (x64 variant also listed); mainland binary source still requires AUR recipe availability |
| goldendict-ng | `https://github.com/xiaoyifang/goldendict-ng/archive/refs/tags/vVERSION.tar.gz`; CMake build with pacman-provided dependencies |
| omawrite | `https://github.com/omacom-io/omawrite/archive/refs/tags/vVERSION.tar.gz`; qmake/make, fonts bundled in source |
| tensaku | `https://github.com/jondkinney/tensaku/archive/refs/tags/vVERSION.tar.gz`; `cargo fetch --locked`, then frozen build; Rustup can fetch stable toolchain if not already present |
| ttf-lxgw-wenkai | `https://github.com/lxgw/LxgwWenKai/releases/download/vVERSION/lxgw-wenkai-vVERSION.tar.gz` |
| wechat-bin | `https://dldir1v6.qq.com/weixin/Universal/Linux/WeChatLinux_arm64.deb` (x86_64/LoongArch variants also listed) |

GitHub archives redirect to codeload; release downloads can redirect to
objects/release-assets/github-releases.githubusercontent.com. Dependencies
selected by yay may introduce additional recipes; those are not pinned.
No npm/pip fetch appears in these directly audited PKGBUILDs. That does not
cover arbitrary later recipe changes or post-install tool use.

Delegation: the audit was initially sent to `pi` with
`zai-coding-cn/glm-5.3`. It produced no output or edits for over ten minutes;
it was terminated by SIGTERM, exit 143, with no error text. The audit and all
implementation/verification were completed directly afterward.
