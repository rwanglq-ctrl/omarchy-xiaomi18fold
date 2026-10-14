# omarchy-xiaomipad9pm

**Omarchy v4.0.4 桌面环境，运行在 Arch Linux ARM (aarch64) 的 systemd-nspawn 容器中，
通过 seatd 在宿主 Debian 13 桌面上显示。**

适用于 Android 16 的 Linux Terminal（AVF 虚拟机）环境。

**测试设备**：Xiaomi Pad 9 Pro Max（Android 16 Linux Terminal，Debian 13 aarch64）。

---

## 层级结构

```
┌─────────────────────────────────────────────────────────────────┐
│  Android 16 Linux Terminal（AVF 虚拟机）                        │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Debian 13 (宿主操作系统)                                  │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │  systemd-nspawn 容器 (Arch Linux ARM aarch64)       │  │  │
│  │  │  ┌───────────────────────────────────────────────┐  │  │  │
│  │  │  │  Omarchy v4.0.4 + ARM 移植补丁                │  │  │  │
│  │  │  │  Hyprland (llvmpipe 软件渲染)                  │  │  │  │
│  │  │  │  quickshell 外壳                               │  │  │  │
│  │  │  │  fcitx5 + 雾凇拼音 (中文输入)                  │  │  │  │
│  │  │  └───────────────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  │  seatd ── 把容器 Hyprland 画面转发到宿主显示               │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## 系统要求

- **设备**: 支持 Android 16 Linux Terminal 的 aarch64 设备（已在 Xiaomi Pad 9 Pro Max 上测试）
- **宿主系统**: Debian 13 (trixie) aarch64
- **虚拟化**: Android 16 Linux Terminal（AVF）
- **磁盘**: ≥ 10 GB 可用空间（`core` 档装完约 7.5 GB，含软件包缓存）
- **网络**: 需要互联网连接（下载 Arch Linux ARM 根文件系统和软件包）

## 从零开始：在 Xiaomi Pad 9 Pro Max 上安装

> 以下菜单名称以 HyperOS（Android 16）为准，不同系统版本的叫法可能略有差异。

1. **打开开发者选项**：进入「设置 → 我的设备 → 全部参数与信息」，连续点击「OS 版本」7 次，
   按提示验证锁屏密码，看到「您已处于开发者模式」即可。
2. **打开 Linux 开发环境**：进入「设置 → 更多设置 → 开发者选项」，打开
   「Linux 开发环境」（Linux development environment），桌面上会出现「终端」（Terminal）应用。
3. **初始化 Debian**：打开「终端」应用，首次启动会下载并安装 Debian 13 镜像
   （几百 MB，建议连接 Wi-Fi），完成后进入命令行。
4. **扩大磁盘**：在终端右上角菜单进入「设置 → 调整磁盘大小」，调到 **≥ 16 GB**
   （`core` 档装完约 7.5 GB，留出空间给软件包缓存和个人文件）。
5. **运行一键安装**（见下一节）。脚本会先配置 Debian 宿主，再下载并配置 Arch Linux ARM 容器，
   整个过程需要下载数 GB 的软件包，耗时取决于网速。
6. **切换到 Omarchy 桌面**：运行 `hypr-switch arch`，然后点击终端顶部的
   「显示」按钮（显示器图标）打开图形界面，就会进入 Arch 容器里的 Hyprland / Omarchy。
   以后想回到 Debian 图形会话，运行 `hypr-switch debian`。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/rwanglq-ctrl/omarchy-xiaomipad9pm/main/install.sh | OMARCHY_ALARM_REF=main bash
```

### 国内网络安装

发布版本：`0.2.6`。每次发布先推送 GitHub，再由维护者同步 Gitee 的 `main` 和版本标签。以下命令使用 Gitee 源码和国内软件包镜像，无需访问 GitHub；请核对安装器打印的源码 SHA。

```bash
curl -fsSL https://gitee.com/zenbardofsuhe/omarchy-xiaomipad9pm/raw/main/install.sh | MIRROR=cn OMARCHY_ALARM_REPO=https://gitee.com/zenbardofsuhe/omarchy-xiaomipad9pm OMARCHY_ALARM_REF=main bash -s -- --profile core
```

**Resume on Pad（失败后继续）**：在 Debian 宿主终端重新运行以下命令。安装器会复用现有 Arch 容器和校验通过的 rootfs 缓存，保留未完成下载的 `.part` 文件；先修复容器 DNS 再继续 pacman。使用相同的用户和 `--rootfs` 参数（如曾指定）。

```bash
curl -fsSL https://gitee.com/zenbardofsuhe/omarchy-xiaomipad9pm/raw/main/install.sh | MIRROR=cn OMARCHY_ALARM_REPO=https://gitee.com/zenbardofsuhe/omarchy-xiaomipad9pm OMARCHY_ALARM_REF=main bash -s -- --profile core
```

Pad 切换网络后若容器 DNS 再次失败，重跑相同安装命令可刷新宿主上游 DNS。

或先克隆再安装：

```bash
git clone --branch main --depth 1 https://gitee.com/zenbardofsuhe/omarchy-xiaomipad9pm.git && cd omarchy-xiaomipad9pm
MIRROR=cn bash ./install.sh --profile core
```

也可使用 `--mirror cn`；`--mirror auto` 短探测 github.com 与 raw.githubusercontent.com
（两者都可达才选 `global`），并打印所选模式；`--dry-run` 不探测、按 `global` 预览。
默认 `global` 保持海外安装方式。国内模式使用阿里云/清华/中科大 Debian 源，
清华/中科大/北外/交大 ALARM rootfs 和 pacman 源；原有软件源会备份。
Omarchy v4.0.4 已随源码附带，取得本项目源码后无需另行从 GitHub 下载上游。
国内模式跳过 AUR/yay 和可选 mise，保留仓库字体及默认 Rime 中文输入；
full 中的 AUR 应用也会跳过。`MIRROR=cn` 要放在管道右侧的 `bash` 前面，放在 curl 左侧无效。

`MIRROR=cn` 默认从 Gitee 拉取本项目源码并选择国内软件包源；`global` 默认从 GitHub 拉取。
也可设置 `OMARCHY_ALARM_REPO` 指向你自己信任的 Git 镜像。
引导器缺少 Git 时先通过 Debian apt 安装 `git` 和 CA 证书；克隆后再检出 `OMARCHY_ALARM_REF`，支持分支、标签和完整提交 SHA（SHA 先克隆 `main` 及完整历史再检出）。
Git 获取失败会明确退出，不请求 Gitee archive，也不再支持 `OMARCHY_ALARM_ARCHIVE_URL`。
第三方 GitHub 代理不作为默认依赖。完整审计及测试限制见 [国内网络审计](docs/china-network.md)。


或者克隆仓库后手动运行：

```bash
git clone https://github.com/rwanglq-ctrl/omarchy-xiaomipad9pm.git
cd omarchy-xiaomipad9pm
./install.sh
```

安装脚本支持以下选项：

```
./install.sh [--dry-run] [--user NAME] [--profile core|full] [--yes]
```

- `--dry-run` — 仅打印操作，不做任何修改
- `--user NAME` — 指定用户名（默认当前用户）
- `--profile core` — 最小安装：Omarchy 桌面 + 中文输入
- `--profile full` — 完整安装：core + 额外的 aarch64 可用应用

## 安装配置文件

| 配置 | 说明 |
|------|------|
| `core` | Omarchy 桌面环境 + fcitx5 中文输入法 + 雾凇拼音 |
| `full` | core + 额外应用（如 qalculate-gtk 等 aarch64 可用的工具） |

## 切换会话

安装完成后，默认会话为 Debian 桌面。切换到 Arch 容器的 Hyprland：

```bash
hypr-switch arch
```

切回 Debian：

```bash
hypr-switch debian
```

### v0.2.6 启动诊断 / Safe Pad update

在 **Debian 宿主**的普通终端运行上面的 `main` 国内 Resume 命令。
无需删除容器或 rootfs 缓存；已有配置会由安装器更新。安装器不会重启显示服务。
当前 shell 立即补上 PATH：`export PATH="$HOME/.local/bin:$PATH"`；后续 bash 会话自动生效。

安全测试：`~/.local/bin/hypr-switch arch`，完全关闭 Linux Terminal 应用再重新打开。
不要在正在使用的图形终端内手动重启 weston.service。`--now` 现仅保存选择并提示延后；
任何 shell 都不会因此重启服务，因为 Android 的 shell 无法可靠判定是否属于显示窗口。
没有启用且尺寸为正的非 fallback 输出时，启动探测 30 秒后会保存诊断、停止 Arch 容器并回到 Weston
（启动器提前退出会立即收集；诊断和清理有独立超时）。IPC 有活动输出不代表像素已正确显示；若仍黑屏，使用独立的
Debian 文本终端运行 `~/.local/bin/arch-diag`，然后 `~/.local/bin/hypr-switch debian`，
完全关闭 Linux Terminal 应用再重新打开。仅在独立 SSH 连接里、接受显示及应用关闭时，才手动运行
`systemctl --user restart weston.service` 进行恢复。

`arch-diag` 是只读命令，打印私有日志路径 `~/.local/state/omarchy-alarm/arch-diag-*.log`，
不启动容器、不重启服务、不转储环境变量。每次启动的 stdout/stderr、阶段时间、原始 monitors all、真实运行时 Hyprland 日志、shell 日志及 journal
会在清理前保存到同目录的 `arch-session-*.log`，退出容器后仍可查看。
日志不再过滤 `Window` 行，可能含窗口标题、工作区名称和设备标识；目录 0700、文件 0600，分享前请检查。
`arch-output` 只查询运行中的 arch-desktop，成功时输出监视器 JSON；失败返回非零。

v0.2.6 按同一 Pad 的工作参考安装 Debian 13 宿主 Mesa 到容器 `/opt/debian-mesa`，
保留 pacman 的 Mesa。`manifest.json` 记录包版本、源码版本和文件 SHA256。
默认由 Mesa/DRM 自动选择驱动，不再强制 `LIBGL_ALWAYS_SOFTWARE`、`GALLIUM_DRIVER` 或 `AQ_*`；
参考设备仍使用 llvmpipe。Lua 使用通用 preferred,auto,1 显示规则并关闭硬件光标。
启动时清除 `WAYLAND_DISPLAY`/`WAYLAND_SOCKET`，并仅在容器内屏蔽宿主的空闲 wayland-0 监听 socket。
以下文件在宿主的 `~/.config/` 中生效，修改后需重新打开显示：

- `arch-no-atomic`：可选 legacy DRM 诊断；默认保留 atomic。
- `arch-software-rendering`：显式强制 llvmpipe 软件渲染。
- `arch-no-modifiers`：显式禁用 DRM modifiers。
- `arch-use-arch-mesa`：跳过 Debian Mesa，使用 Arch Mesa 做对照测试。
- `arch-hyprland-prefix`：内容为已有可信构建的绝对安装前缀；使用其中的 Hyprland、start-hyprland、hyprctl 和库。
  不会自动下载或复制参考设备的未知二进制。默认仍为发行版 Hyprland。

创建开关用 `touch ~/.config/文件名`，撤销用 `rm ~/.config/文件名`。
旧 `arch-hardware-rendering` / `arch-enable-modifiers` 已无作用（现在默认自动选择）。
工作参考的自定义 Hyprland 0.55 尚无完整构建来源；版本差异、构建方案及验证限制见
[v0.2.6 validation](docs/v0.2.6-validation.md)。

v0.2.4 修复已确认的连接器假设：一次 Pad Weston 诊断中 Virtual-2 已连接、Virtual-1 未连接（编号可能变化）；
启动 gate 接受任何可用输出，arch-output 自动读取 card0 的 connected 状态。
回退前保存 monitors all、Arch Hyprland 日志尾部和 DRM status。单显示器触屏使用默认自动映射。
v0.2.6 在独立 arm64 VM 中复现并修复空闲 Weston socket 引起的启动阻塞，
并验证 Debian Mesa 启动、IPC、自检及显示恢复。实体 Pad 的新版本仍待验证，详见
[v0.2.6 evidence](docs/v0.2.6-validation.md)。

一次性自检：在 Linux Terminal 的**文本标签页**（或独立 SSH）运行：

```bash
~/.local/bin/arch-selftest
```

命令会关闭显示及当前图形应用：先停止 weston.socket，再停止 weston.service，
有界等待会话锁和 DRM seat 释放；完成、失败或收到可处理信号后重启 socket/service，恢复所选桌面。
无需预先手动停止服务。仍有其他活跃拥有者时会报告 PID/命令并拒绝竞争，不删除内核锁文件。
自检完成后打印私有日志路径；退出 0 表示输出 IPC 就绪且已清理，不等于可见像素已通过验证。
失败时分享该日志，勿只拍最后几行。v0.2.6 优先在容器挂载命名空间内保存真实 Hyprland 日志、socket 权限和挂载信息，
并记录显式 instance signature 的探测进度。详见 [v0.2.6 evidence](docs/v0.2.6-validation.md)。
VM 已复现启动阻塞：Aquamarine 把仍监听的 weston.socket 当成父 Wayland compositor，
等待无人响应的握手，因而未建立 Hyprland 命令 socket。v0.2.6 的直接 DRM 启动禁用这个父连接；
Hyprland 启动后仍为客户端设置自己的显示 socket。实体 Pad 和已知正常安装的对照验证尚待完成。

根因证据和复现范围见 [display investigation](docs/blackscreen-v0.2.3.md)。

## 已知限制

- **没有 GPU 硬件虚拟化支持**: 当前 Android 16 Linux Terminal 不提供 GPU 硬件加速，图形界面由 CPU 软件绘制（Mesa llvmpipe）。
  已关闭动画、模糊、阴影等特效，日常使用（终端、浏览器、办公）性能流畅；3D 游戏、视频剪辑等重度图形任务不适合。
- **暂不支持声音输入输出**: 扬声器、耳机和麦克风在容器桌面里暂时都不可用。
- **无 systemd --user**: 容器内没有用户级 systemd。原本由 systemd 用户服务管理的进程改为 Hyprland 启动时直接拉起。
- **宿主总线服务名冲突**: 宿主可能已占用 `org.freedesktop.Notifications`、`org.kde.StatusNotifierWatcher` 等服务名，可能导致通知、托盘图标异常。
- **锁屏密码警告**: 如果用户密码处于锁定状态，锁屏后将无法解锁。请先设置密码再使用锁屏功能。
- **x86-only 应用跳过**: 1Password、Spotify、Signal、Steam 等仅提供 x86 版本的应用不会安装。

## 卸载

在独立的文本终端或 SSH 中操作；这会关闭图形桌面及应用。

```bash
# 停止并删除容器（桌面运行时注册的机器名是 arch-desktop）
systemctl --user stop weston.socket weston.service
sudo machinectl terminate arch-desktop 2>/dev/null || true
sudo rm -rf /var/lib/machines/arch

# 删除宿主启动器
rm ~/.local/bin/{arch-hyprland,archbox,archsh,hypr-switch,hypr-session,arch-output,arch-diag,arch-selftest,arch-machine-id,arch-log}

# 删除 systemd drop-in（如已安装）
rm ~/.config/systemd/user/weston.service.d/hyprland.conf
systemctl --user daemon-reload

# 不再需要诊断证据时，删除私有日志及会话状态
rm -rf ~/.local/state/omarchy-alarm
```

## 架构文档

详细技术文档见 `docs/` 目录：

- [架构设计](docs/architecture.md) — uwsm/systemd-user 替代方案
- [软件包清单](docs/packages.md) — 跳过的包及原因
- [性能调优](docs/performance.md) — llvmpipe 优化和 udmabuf
- [故障排除](docs/troubleshooting.md) — 常见问题及解决方法

## 许可证

本项目基于 [MIT 许可证](LICENSE) 发布。

## 致谢

- [Omarchy](https://github.com/basecamp/omarchy) by Basecamp — 框架本身，MIT 许可证
- [Arch Linux ARM](https://archlinuxarm.org/) — aarch64 发行版
- [Hyprland](https://hyprland.org/) — Wayland 合成器
- [fcitx5](https://fcitx5.org/) + [Rime](https://rime.im/) + 雾凇拼音 — 中文输入方案
- [Xiaomi Pad 9 Pro Max](https://www.mi.com/prod/xiaomi-pad-9-pro-max) — 本项目的测试设备，采用 Xiaomi XRING O3 最新旗舰 AI 处理器
- **安装配置**：使用 [Claude Code](https://claude.com/claude-code) agent + [Claude Opus 5.5](https://www.anthropic.com/claude-opus-5-5) 模型完成
- **GitHub 发布**：使用 [Orca](https://www.onorca.dev/) ADE（[GitHub](https://github.com/stablyai/orca)）协调多个 agent 并行完成——
  [Claude Code](https://claude.com/claude-code)、[Codex](https://github.com/openai/codex)、[Pi](https://pi.dev)、
  [MiMo Code](https://mimo.xiaomi.com/coder)，以及 [MiMo-V2.6-Pro-UltraSpeed](https://mimo.mi.com/models/en-US/mimo-v2.6-pro-ultraspeed) 模型

---

## English

**Omarchy v4.0.4 on Arch Linux ARM (aarch64), running in a systemd-nspawn container on the
Debian 13 VM of Android 16's Linux Terminal, and shown on its display through seatd.**

**Tested device**: [Xiaomi Pad 9 Pro Max](https://www.mi.com/prod/xiaomi-pad-9-pro-max), powered by Xiaomi's latest flagship AI processor, the XRING O3 (Android 16 Linux Terminal, Debian 13 aarch64).

### Requirements

- An aarch64 device with Android 16's Linux Terminal (tested on Xiaomi Pad 9 Pro Max)
- The Terminal's Debian 13 (trixie) aarch64 VM
- ≥ 10 GB free disk space (the `core` profile takes about 7.5 GB, package cache included)
- An internet connection

### From scratch on Xiaomi Pad 9 Pro Max

Menu names follow HyperOS (Android 16) and may differ slightly between versions.

1. **Enable developer options**: *Settings → My device → All specs*, tap *OS version* 7 times
   and confirm with your lock-screen password.
2. **Enable the Linux development environment**: *Settings → Additional settings → Developer options*,
   turn on *Linux development environment*. A *Terminal* app appears.
3. **Set up Debian**: open *Terminal*. The first launch downloads and installs the Debian 13 image
   (a few hundred MB, Wi-Fi recommended) and drops you into a shell.
4. **Grow the disk**: *Terminal menu → Settings → Resize disk*, set it to **≥ 16 GB**.
5. **Run the one-command installer** below. It prepares the Debian host, then downloads and configures
   the Arch Linux ARM container; expect several GB of downloads.
6. **Switch to the Omarchy desktop**: run `hypr-switch arch`, then tap the Terminal's *Display* button
   (monitor icon). To go back to Debian's session later: `hypr-switch debian`.

### One-command install

```bash
curl -fsSL https://raw.githubusercontent.com/rwanglq-ctrl/omarchy-xiaomipad9pm/main/install.sh | OMARCHY_ALARM_REF=main bash
```

Or clone and run it:

```bash
git clone https://github.com/rwanglq-ctrl/omarchy-xiaomipad9pm.git
cd omarchy-xiaomipad9pm
./install.sh [--dry-run] [--user NAME] [--profile core|full] [--yes]
```

- `core`: the Omarchy desktop plus Chinese input (fcitx5 + Rime / rime-ice)
- `full`: core plus extra apps that exist for aarch64

### Known limitations

- **No GPU hardware virtualization**: Android 16's Linux Terminal offers no GPU acceleration yet, so the
  GUI is drawn by the CPU (Mesa llvmpipe). With animations, blur and shadows turned off, everyday use
  (terminals, browser, office apps) runs smoothly; 3D games and video editing are not a good fit.
- **No audio input or output yet**: speakers, headphones and the microphone don't work in the container desktop.
- **No systemd --user in the container**: services Omarchy runs as user units are started by Hyprland instead.
- **Host D-Bus name conflicts**: the host may already own notification and tray service names, so
  notifications or tray icons can misbehave.
- **Lock screen**: if your password is locked or unset you cannot unlock the lock screen. Set a password first.
- **x86-only apps are skipped** (1Password, Spotify, Signal, Steam, ...).

### Tests

v0.2.6 reproduces and fixes a startup deadlock against an idle Weston activation
socket in a Debian arm64 VM. The aligned Debian Mesa stack passes startup, monitor
IPC, shell IPC and selftest/restoration there. Physical Pad confirmation remains
outstanding. See [validation evidence and limits](docs/v0.2.6-validation.md).

`tests/run.sh --quick` (syntax, ShellCheck, privacy scan, patches, package names, dry-runs, Lua, hygiene)
runs on every push; `tests/run.sh --full` installs the `core` profile into a fresh Arch Linux ARM rootfs
and checks that a second run changes nothing (run it from the *Actions* tab).

Details: [docs/](docs/) (in Chinese). License: [MIT](LICENSE). Built on
[Omarchy](https://github.com/basecamp/omarchy) by Basecamp.
Thanks to the [Xiaomi Pad 9 Pro Max](https://www.mi.com/prod/xiaomi-pad-9-pro-max) with Xiaomi's latest flagship AI processor, the XRING O3, the device this project was built and tested on.
The installation and configuration were done with the [Claude Code](https://claude.com/claude-code) agent and
the [Claude Opus 5.5](https://www.anthropic.com/claude-opus-5-5) model. The GitHub release was built with the
[Orca](https://www.onorca.dev/) ADE ([GitHub](https://github.com/stablyai/orca)) coordinating
[Claude Code](https://claude.com/claude-code), [Codex](https://github.com/openai/codex), [Pi](https://pi.dev) and
[MiMo Code](https://mimo.xiaomi.com/coder) in parallel, together with the
[MiMo-V2.6-Pro-UltraSpeed](https://mimo.mi.com/models/en-US/mimo-v2.6-pro-ultraspeed) model.
