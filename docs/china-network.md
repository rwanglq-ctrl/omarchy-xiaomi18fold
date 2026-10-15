# Install network audit and mainland China policy (updated for 0.2.9)

Scope: every tracked entry point in `install.sh`, `host/`, `container/`,
`tools/`, `packages/`, `patches/`, `config/`, plus code invoked from pinned
Omarchy v4.0.4. Initial audit: 2026-10-13; bootstrap re-audit: 2026-10-14. See
[validation and measured reachability](china-validation.md) for test results.

## Original network failures (before 0.2.0)

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
| README / install.sh pipe entry | GitHub raw `/main/install.sh` | CN commands fetch `https://gitee.com/zenbardofsuhe/omarchy-xiaomipad9pm/raw/main/install.sh`; no GitHub access required. Check the resolved commit printed by bootstrap. |
| install.sh bootstrap | `git clone --no-checkout --branch REF` (main for a SHA), then verified commit checkout; `OMARCHY_ALARM_REPO` / `OMARCHY_ALARM_REF` | CN defaults to Gitee; `OMARCHY_ALARM_REPO=gitee` is also accepted. Explicit trusted repository overrides are honored. Branches, tags and full commit SHA supported; bounded 300s clone, fail clearly on error. |
| install.sh Git prerequisite | Debian apt installs `git ca-certificates` when Git is missing | CN uses temporary signed HTTP mainland apt sources for bootstrap, then normal host setup selects HTTPS. No source archive fallback or archive override. |
| install.sh / lib/network.sh auto mode | HEAD probes of both `https://github.com` and `https://raw.githubusercontent.com` | Both must succeed for global; otherwise CN. Bounded probes, offline dry runs. Bootstrap selects before fetching the checkout. |
| host/install.sh apt | Existing `/etc/apt/sources.list{,.d/*}`; Debian defaults `deb.debian.org/debian`, `/debian-security`, `security.debian.org/debian-security`; `apt-get update/install` | Rewrite only known official archive prefixes, preserving suites/components/signed-by; save originals. TUNA, USTC, Aliyun selection checks trixie and trixie-security Release with 3s connect / 8s total. Apt uses 15s timeouts and 2 retries; failed metadata updates advance through all three mirrors, with update errors treated as failures. Custom sources remain user controlled. |
| host/install.sh rootfs | `http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz`, same URL plus `.md5` and `.sig`; `OMARCHY_ALARM_TARBALL_URL` override | HTTPS TUNA → USTC → BFSU → SJTU, bounded probes; download+MD5 pair from one mirror, with full artifact fallback. Override is honored without guessing adjacent mirror paths. |
| host/install.sh signature key | Previously GPG HKPS `keyserver.ubuntu.com`, `OMARCHY_ALARM_KEYSERVER` override | Local vendored public key; no keyserver fetch. Existing fingerprint checked against VALIDSIG; Downloaded but unverifiable signatures are fatal. Unavailable verification emits an explicit UNVERIFIED warning. MD5 alone is not publisher authentication. |
| host/install.sh rootfs setup | `pacman -Syu base-devel git sudo` against bundled ALARM `/etc/pacman.d/mirrorlist`, generally `mirror.archlinuxarm.org` | Replace mirrorlist before the first sync, including reused rootfs. TUNA/USTC/BFSU/SJTU, `$arch/$repo`; pacman handles per-file mirror fallback. `pacman-key --init/--populate` uses installed local keys, not a network keyserver. |
| container/install.sh repository packages | `pacman -Syu` for packages/repo-core.txt and additive repo-full.txt; dependencies and fonts from ALARM sync DBs | Same four mainland mirrors before syncing, original mirrorlist backed up. Global mode retains existing sources. |
| container/install.sh yay/bootstrap and requested desktop builds | Pinned PKGBUILDs and upstream source archives; makepkg builds as the desktop user | Verified source bundles from this project’s Gitee tools-v0.2.9 release. Repository build dependencies use ALARM mirrors; Cargo and Go dependencies use rsproxy.cn and goproxy.cn. No live AUR recipe or GitHub source fetch. |
| container/install.sh remaining full-profile AUR | yay RPC and recipe Git at `aur.archlinux.org`; `yay -S` | Extra packages without pinned source bundles remain global-only. The requested v0.2.9 core desktop set uses the verified bundle route above. `--no-aur` explicitly skips source builds. |
| container/install.sh Omarchy | `git clone --branch v4.0.4 --depth 1 https://github.com/basecamp/omarchy.git` | Restore exact vendored Git objects/tag/shallow boundary, checksum all four parts, verify patches/BASE; apply patches with local git am. No GitHub fetch. Global still clones (120s deadline). |
| container/install.sh tool programs / lib/tool-programs.py | Pinned npm native tarballs, pi locked dependencies, release assets (Cursor and omp global-only) | In CN, both profiles use npm via npmmirror; other included release binaries via operator-owned Gitee tools-v0.2.9 assets with pinned SHA256. Each HTTPS redirect is checked before following; no GitHub or third-party proxy fallback. mise only links verified local prefixes. |
| invoked Omarchy provision-user | User finalization and desktop theme | Both modes suppress upstream mise provisioning, AI skill links and pi theme activation. Existing AI configs are preserved; no AI defaults are seeded. Desktop leaves remain local. |
| container/extras/build-hyprland-0562-fix.sh | Optional `git clone --recursive --shallow-submodules` GitHub `hyprwm/Hyprland` v0.56.2; Git submodules and CMake/meson build dependency paths | Not invoked by install.sh or container/install.sh. Manual source-build helper requires reachable upstream or prepopulated sources; CN base install uses pacman Hyprland. |

## Ecosystems, fonts and data

- Repository fonts use pacman. `ttf-ia-writer` uses a verified Gitee source
  bundle. Extra full-profile font/Rime recipes without bundles remain
  replaced by a pinned rime-ice source bundle in both modes; existing IME preferences are preserved. `fc-cache -f` is local.
- The base installer verifies every locked pi dependency tarball itself, then
  uses `npm cache add --offline` and `npm ci --offline --ignore-scripts`. npm
  cannot fetch registry metadata, follow redirects or execute lifecycle hooks.
  Native npm tool archives are extracted without running their installers.
  Requested desktop source builds use Cargo/Go CN registries; no rustup
  bootstrap or pip installation is needed.
- CN exports npm registry `https://registry.npmmirror.com`, pip index
  `https://pypi.tuna.tsinghua.edu.cn/simple`, Go proxy `https://goproxy.cn`,
  Rustup distribution/update servers `https://rsproxy.cn` and `/rustup`,
  and a Cargo sparse registry index. These process settings do not guarantee
  arbitrary Cargo source replacement or mirror arbitrary Git dependencies;
  the pinned desktop recipes are separately checked for Git dependencies.
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
- CN release binaries and LazyVim/plugin snapshots use operator-owned Gitee
  assets. Third-party GitHub proxies are prohibited. No global Git proxy,
  mirror tokens, disabled TLS verification or disabled package signature
  checks are added. LazyVim is installed only when its config is absent,
  with automatic plugin/parser/LSP downloads disabled. See
  [the program manifest and boundary](packages.md) and [v0.2.9 evidence](v0.2.9-validation.md).

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
CN where needed. Both CN profiles install the verified v0.2.9 desktop-source
bundles; full additionally installs repository extras and skips only the
remaining AUR extras without verified bundles. Every release is pushed to origin first, then the operator synchronizes
Gitee main and the release tag. Use README's Gitee command for CN Pad installs.
Check the bootstrap SHA; the mirror may lag during that publication handoff.
Source mirrors and URL overrides are trust inputs.

## AUR recipe source audit

This table records upstream sources from the original 2026-10-13 audit.
For v0.2.9, the requested desktop packages use fixed recipes and verified
Gitee source bundles, with locked Go/Cargo dependencies obtained from CN
registries. Remaining live AUR recipes are global-only and can change
independently of this repository.

| Manifest package | Recipe source fetches and build fetches |
| --- | --- |
| rime-ice-git | Git `https://github.com/iDvel/rime-ice.git` |
| ttf-ia-writer | 16 TTF files under `https://github.com/iaolo/iA-Fonts/raw/` at the recipe-pinned commit: Mono, Quattro, Duo, Duospace × Bold/BoldItalic/Italic/Regular; redirects to raw.githubusercontent.com |
| yaru-icon-theme | v0.2.9 uses the upstream `ubuntu/yaru` 26.10.3 source archive, fixed SHA256, and a local icons-only Meson recipe; source archive bundled on Gitee. |
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

Historical audit process (2026-10-13, separate from the mandatory v0.2.9 reviews): the audit was initially sent to `pi` with
`zai-coding-cn/glm-5.3`. It produced no output or edits for over ten minutes;
it was terminated by SIGTERM, exit 143, with no error text. The audit and all
implementation/verification were completed directly afterward.

CN omp and cursor-agent are explicitly skipped under operator Option C (Gitee quota); global installation remains available. ghui ARM64 and rime-ice use checksum-pinned Gitee bundles. Each asset/part may specify its reviewed operator-owned `cn_base_url`; no GitHub/proxy fallback.
