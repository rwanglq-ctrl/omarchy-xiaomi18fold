# 软件包清单

## 概述

Omarchy v4 的软件包分四类：
1. **官方源包** — 从 Arch Linux ARM (ALARM) 官方仓库安装
2. **AUR 包** — 固定源码包通过 makepkg 编译；其他 global 项目通过 yay
3. **固定版本工具程序** — 已校验的 aarch64 发布物，通过 mise 管理
4. **跳过的包** — 因架构限制或环境约束无法安装

完整的跳过清单及原因见 `packages/skip.txt`。

## 官方源包

Omarchy 的 `omarchy-base.packages` 中列出的包，凡在 ALARM 官方源可用且不在跳过名单中的，
均会安装（以 `packages/repo-core.txt` 和 `repo-full.txt` 为准）。

额外补装的包：

| 包 | 用途 |
|----|------|
| `neovim` | 替代 nvim（ALARM 中包名不同） |
| `ex-vi-compat` | 基础编辑器兼容命令 |
| `fcitx5-rime` | Rime 输入法引擎 |
| `fcitx5-configtool` | fcitx5 配置工具 |
| `qt6-5compat` | Qt6 兼容层 |
| `qt6-svg` | SVG 支持 |
| `qt6-wayland` | Qt6 Wayland 集成 |
| `pipewire-pulse` | PulseAudio 兼容层（仅客户端） |
| `qalculate-gtk` | 计算器（替代 omacalc） |
| `jq` | JSON 处理工具 |

## AUR 包

v0.2.9 的 core 和 full 都尝试安装 `yay`、`tensaku`、`omawrite`、`aether`、
`cliamp`、`ttfx`、`ttf-ia-writer` 和 `yaru-icon-theme`（ALARM 缺包时）。安装器使用仓库固定的 PKGBUILD 与已校验的
源文件包，经 `makepkg` 在桌面用户身份下构建/打包；aether 使用其官方 ARM64
预编译程序，不在 CN 模式实时抓取 AUR/GitHub。
`tree-sitter-cli` 已在 ALARM extra 提供 aarch64 0.26.9，直接使用仓库包。

CN 源文件包来自本项目 Gitee `tools-v0.2.9` release；Cargo/Go 依赖使用
rsproxy.cn / goproxy.cn。测试 Pad 的 CN ALARM 元数据确认 Go 1.27.2、
Rust 1.99.0；Go 满足 cliamp 的 1.26.6 和 yay 的 1.26 要求，不需要下载额外
工具链。`--no-aur` 明确跳过这些源码构建。每个包单独记录成功或
`FAILED (nonfatal)`，不能把“列入清单”当成“已编译成功”；真实 Pad 结果见
[v0.2.9 验证记录](v0.2.9-validation.md)。本版本发布前仍须完成该验证。

其余 full profile 的 AUR 项目继续使用原有 global 路径；没有固定 CN 源文件包
的额外项目在 CN 跳过。构建工作目录位于用户缓存，避免占满 `/tmp`。

## core / full 的工具程序（v0.2.9）

两种 profile 都安装下列程序。版本来自参考 Pad 的只读工具清单；未复制其文件。
安装清单和完整校验值见 `packages/tool-programs/manifest.json`，pi 的全部传递依赖
固定在 `packages/tool-programs/pi/package-lock.json`。Node.js 和 npm 已移入 core
仓库包，提供 pi 的运行时和离线包安装器。

| 命令 | 版本 | 发布物 / CN 来源 |
| --- | --- | --- |
| `mise` | 2026.10.0 | 官方 `@jdxcode/mise-linux-arm64` npm 二进制包 / npmmirror |
| `claude` | 2.1.296 | 官方 `@anthropic-ai/claude-code-linux-arm64` / npmmirror |
| `codex` | 0.162.1 | 官方 `@openai/codex` 的 linux-arm64 发布包 / npmmirror |
| `pi` | 1.2.0 | `@earendil-works/pi-coding-agent` 和锁定依赖 / npmmirror |
| `opencode` | 1.19.0 | 官方 `opencode-linux-arm64` / npmmirror |
| `herdr` | 0.9.3 | herdrdev/herdr 的 `herdr-linux-aarch64` 预编译程序 / 本项目 Gitee tools-v0.2.9 资产 |
| `crush` | 0.97.1 | charmbracelet/crush 的 Linux arm64 tar 包 / 本项目 Gitee tools-v0.2.9 资产 |
| `cursor-agent` | 2026.10.14-0f9edde | 仅 global：Cursor 官方 linux/arm64 包；CN 明确跳过（运营者配额决定） |
| `omp`（oh-my-pi） | 18.10.3 | 仅 global：can1357/oh-my-pi 的 `omp-linux-arm64`；CN 明确跳过（附件配额，Option C） |
| `gh` | 2.102.0 | cli/cli 的 Linux arm64 tar 包 / 本项目 Gitee tools-v0.2.9 资产 |

**herdr 已提供 aarch64 预编译发行版，无需 Zig/LLVM 源码构建。** `mise-bin`
这个 Arch 包仍不安装，但 mise 程序本身使用官方 ARM64 npm 发布物。

程序存于 `~/.local/share/omarchy-tools/`，通过 `mise link http:NAME@VERSION`
注册已验证的前缀，并在 `~/.local/bin/` 提供命令。注册目录见
`~/.local/share/mise/installs/`，安装结果见 `tool-programs.txt`；
不运行 `mise use`，不创建 mise 全局配置，不启用自动后端安装。已有同名用户命令
保留为 `.pre-omarchy-TIMESTAMP`，已由本安装器管理的命令幂等更新。
`mise link` 的 `http:` 是本地安装记录的后端标识，本步骤不让 mise 发起 HTTP 下载。

仅安装程序及其随包运行库、许可证和包元数据，不安装或复制用户 AI 配置、密钥、
令牌或登录文件，不导入参考 Pad 的技能、插件或主题。安装器跳过上游 AI 默认
配置、技能链接和 pi 主题初始化，保留已经存在的用户文件。用户首次运行、登录
或自行修改主题属于用户操作，工具可能自行创建配置。Omarchy 后续运行时的
主题切换也可能向已有 AI 配置目录写入主题文件；安装器的 headless 流程不会运行
这些主题钩子。旧程序前缀和用户命令备份保留，确认新版本正常后可自行清理。

CN 模式的 npm 包仅从 `https://registry.npmmirror.com` 获取；每个下载及其跳转
均校验允许的 HTTPS 主机。Gitee 仅允许本项目 release/attachment 路径及官方
`foruda.gitee.com/attach_file/` CDN 跳转，内容仍须通过固定摘要校验。发布物从本项目 Gitee `tools-v0.2.9` release 读取，校验仓库固定的
上游 SHA256；没有回退到 GitHub。npm 发布物验证固定 SHA512/SRI，pi 的所有
传递依赖先按同样策略下载校验，再以 `npm cache add --offline` 和
`npm ci --offline --ignore-scripts` 安装。Cursor 包 SHA256 固定在清单中，来自
官方 HTTPS 发布物的实测摘要。global 模式使用清单中的上游 URL。
维护者运行 `scripts/mirror-tool-assets.sh` 准备已校验的文件，再上传到本项目
Gitee `tools-v0.2.9` release；终端用户无需令牌。两个较大发布物拆成最多 90 MiB
的分片上传，每片及重组后的原文件均验证固定 SHA256；完整上传清单共 25 个文件（含新增 rime-ice 与 ghui，排除 omp 与 cursor-agent）。安装器不使用第三方 GitHub
代理，也不会从 Gitee 回退到 GitHub。

所有工具失败均明确记录为 `FAILED (nonfatal)`，桌面继续安装。最终安装摘要再次列出
每个失败项目（包括辅助进程异常），明确提示缺失/未完成，不能把桌面成功视作全部工具成功。查看
`~/.local/state/omarchy-alarm/tool-programs.txt` 和安装日志；网络恢复后重跑即可。
下载缓存重用前仍验证摘要；损坏缓存重新下载，摘要不匹配不执行。

### 完整参考清单

v0.2.9 的范围包括参考 Pad 的全部 mise 程序：除上述工具外，还有
antigravity-cli、copilot、hunk、coding_agent_session_search（cass）、
MiMo-Code（mimocode）、OpenRouter ori、basecamp-cli、hey-cli、cf、ghui、
playwright、pnpm、node 和 sing-box。仅安装程序，不复制配置、不启用网络服务，
Playwright 不自动下载浏览器。具体版本和校验值以固定清单为准。

### 用户目录与桌面补全

安装器创建 `~/Work` 及 Desktop、Documents、Downloads、Music、Pictures、Public、
Templates、Videos。已有文件、链接、XDG 目录偏好均保留；`user-dirs.dirs`
仅在不存在时写入标准默认值，不创建 `Work/.mise.toml`。

ALARM/CN 仓库实测提供 `uwsm` 0.27.0-1、`hyprland-guiutils` 0.2.2-4、
`ttf-jetbrains-mono-nerd` 3.5.1-2，已纳入 core。`yaru-icon-theme` 和
`ttf-jetbrains-mono-nerd-basic` 的 `pacman -Si` 返回 package not found；
Yaru 因此改用固定 Gitee 源文件包和 Meson 构建（26.10.3，架构无关），
字体使用完整 Nerd 字体。uwsm 包可用不代表容器启用
systemd 用户会话；现有桌面启动方式保持有效。

LazyVim 初始配置仅在 `~/.config/nvim` 完全不存在时安装；已有目录、文件或
符号链接均保留。初始配置和插件属于用户明确要求的编辑器配置，不适用
AI 工具的 programs-only 边界。CN 安装使用固定且校验过的 Gitee starter/插件快照。自动插件更新、tree-sitter
解析器下载和 Mason/LSP 下载关闭；保留 Neovim 自带解析器。新增语言服务器、
额外解析器和 Playwright 浏览器需用户另行安装，不在自动网络安装范围内。

## 跳过的包

### 系统服务 / 引导 / 登录管理器 / 固件驱动

在 nspawn 容器中无法工作的系统级包：

- **网络**: avahi, nss-mdns, networkmanager
- **蓝牙**: bluez, bluez-tools, bluez-utils
- **打印**: cups, cups-filters, cups-pk-helper, system-config-printer
- **容器**: docker, docker-buildx, docker-compose, lazydocker
- **防火墙**: ufw, ufw-docker
- **电源**: power-profiles-daemon
- **引导**: plymouth, limine, mkinitcpio 相关钩子
- **登录**: sddm（uwsm 已加入 core，但容器仍使用现有启动方式）
- **固件**: linux-firmware, wireless-regdb, kernel-modules-hook
- **GPU**: nvidia 驱动, gpu-screen-recorder（需要 GPU 编码）
- **其他**: bolt, ddcutil（显示器硬件控制）, udiskie（需要 udisks2）, tzupdate

Omarchy 的 `etc/` 目录中的配置文件全部跳过（cups, docker, limine, mkinitcpio,
NetworkManager, plymouth, sddm, systemd, sudoers, sysctl 等）。

### 仅 x86 或无 aarch64 编译源

| 包 | 处理方式 | 原因 |
|----|---------|------|
| `mise-bin` | 使用上面的官方 aarch64 发布物 | 不依赖此 Arch 包 |
| `obsidian` | 不在容器内安装 | Electron 二进制仅 x86；可通过 host-run 在宿主上运行 |
| `obs-studio` | 跳过 | ALARM 无此包 |
| `pinta` | 跳过 | 依赖 dotnet |
| `dotnet-runtime` | 跳过 | — |
| `qemu-user-static-binfmt` | 跳过 | — |
| `localsend` | 跳过 | 需要 flutter/fvm 工具链（fvm 仅 x86_64） |

### Omarchy 自家源包（不可公开获取）

| 包 | 替代方案 |
|----|---------|
| `omacalc` | 使用 `qalculate-gtk`，快捷键重新绑定 |
| `omacut` | 跳过（已安装 kdenlive） |
| `omarchy-nvim` | 使用 LazyVim 官方 starter 配置 |
| `hyprland-preview-share-picker` | 使用 xdph 自带的 `hyprland-share-picker` |
| `tobi-try` | 跳过 |
| `asdcontrol` | 跳过 |

### 字体替代

| 原包 | 替代 |
|------|------|
| `ttf-jetbrains-mono-nerd-basic` | 官方源的 `ttf-jetbrains-mono-nerd` |

## 编译注意事项

对于 PKGBUILD 中仅标记 `x86_64` 但实际是源码编译的包（如 tensaku、omawrite），
使用 `makepkg --ignorearch` 强制编译。这些包使用 Rust 或 C++ 编写，源码本身支持 aarch64。

## v0.2.9 平板通用默认值

- 触控板轻点点击；`crosvm-virtio-mouse-0` 滚动系数 0.01；通配输出 scale 1；光标 28。
- llvmpipe 关闭阴影、模糊、动画、透明、圆角和色彩管理；后台 5 FPS，启用 FIFO workaround。不设置 `LP_NUM_THREADS`（参考 Pad 实测设置后帧率从 107 降至 54）。
- `GSETTINGS_BACKEND=keyfile`、用户目录下的 `TMUX_TMPDIR`、fcitx 环境变量和 `chi_sim+eng` OCR；CJK SC 字体优先；截图分享使用 `hyprland-share-picker`。
- fcitx5、Rime 和固定提交 `da1fbe602e38f26db846fa10120ee64c2b0324c0` 的公共 rime-ice 数据通过校验后的 Gitee 源文件包安装。输入法配置仅在不存在时创建，Shift 切换中英文；已有设置和用户词库不覆盖。缺少可选 rime-ice 时新配置保留简体朙月拼音；后续安装成功仅自动升级字节完全匹配的安装器备用配置，优先 rime_ice 并保留 luna_pinyin_simp。安装器执行 rime_deployer 构建，失败会在最终汇总中醒目报告。
- 键盘默认使用 `kb_options = "caps:super,compose:ralt"`（Caps Lock = Super，右 Alt = Compose），避免上游 `shift:both_capslock_cancel` 吞掉 fcitx5 Shift 切换。重复安装仅更新未修改的安装器/上游默认 input.lua；用户编辑和符号链接保留，新默认另存 `~/.local/state/omarchy-alarm/input.lua.dist` 供人工合并。
- 桌面通过 `dbus-run-session` 使用独立会话总线，避免宿主总线缺失或 portal 名称冲突；`host-run` 明确连接宿主总线（宿主需运行用户总线）。
- 会话启动 portal 与锁屏输入法复位助手；btop/About 窗口 1200×800、LocalSend 浮动规则；计算器 qalculate；Super+Ctrl+Enter 启动 herdr（下载失败时需先重试工具安装）。
- 不复制个人键盘配置、代理、主题、应用或路径。远程访问、wayvnc 和 upgrade-all 不安装为自动启动项，必须由用户自行选择启用。
- **已知未包含**：Hyprland 0.55 / 0.56.2 damage-clip 自编译补丁尚无本项目可验证的 ARM64 发布物及回归证据；本版使用仓库 Hyprland，不能声称解决该特定打字延迟。后续在完成构建与 Pad A/B 测试后再集成。

与 README 中的模式说明一致：CN 模式不安装 omp 和 cursor-agent，也不会删除此前已有的副本。新装 CN 系统运行 README 中这两个 `--version` 命令会提示找不到命令。安装摘要明确标记此政策性跳过。
在 global/海外网络可单独安装：

```sh
MIRROR=global python3 /opt/omarchy-alarm-nspawn/lib/tool-programs.py --only omp --only cursor-agent
```

ghui 0.9.1 的 ARM64 npm 发布物在 npmmirror 返回 404；故采用同版本官方
原生 tar 包，先验证 npm SHA512，再固定 SHA256 镜像到 Gitee，CN 无上游回退。
AUR/LazyVim 固定源文件包在两种网络模式均使用 Gitee；其他程序 global 使用上游。
每个资产/分片的 `cn_base_url` 可在审核清单后单独指定同一运营者的 Gitee release，
跳转校验限制到对应仓库；当前全部使用本项目仓库，不需要第二仓库。
