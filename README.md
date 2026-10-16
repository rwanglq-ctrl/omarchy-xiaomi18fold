# omarchy-xiaomi18fold

**Omarchy 桌面环境，运行在 Arch Linux ARM (aarch64) 的 systemd-nspawn 容器中，
通过 seatd 在宿主 Debian 13 桌面上显示。**

适用于 Android 16 的 Linux Terminal（AVF 虚拟机）环境。

**测试设备**：Xiaomi 18 Fold（Android 16 Linux Terminal，Debian 13 aarch64 + Arch nspawn）。

本仓库由 [omarchy-xiaomipad9pm](https://github.com/rwanglq-ctrl/omarchy-xiaomipad9pm)（v0.2.11）适配而来，
针对折叠屏 AVF 热插拔显示、触控坐标、无 Super 键的 Android 键盘、以及中文输入热键冲突做了专用补丁。
版本从 **0.1.0** 起算（折叠机产品线）；安装栈与 Pad 相同。

> 问题根因与修复历程见 [CHANGELOG](CHANGELOG.md) / GitHub·Gitee Release notes，不放在本 README。

---

## 系统要求

- **设备**: 支持 Android 16 Linux Terminal 的 aarch64 设备（已在 Xiaomi 18 Fold 上测试）
- **宿主系统**: Debian 13 (trixie) aarch64
- **虚拟化**: Android 16 Linux Terminal（AVF）
- **磁盘**: 建议 ≥ 20 GB 可用空间
- **网络**: 需要互联网连接

## 从零开始：在 Xiaomi 18 Fold 上安装

1. **打开开发者选项**：设置 → 我的设备 → 全部参数与信息，连续点击「OS 版本」7 次。
2. **打开 Linux 开发环境**：设置 → 更多设置 → 开发者选项 → 「Linux 开发环境」。
3. **初始化 Debian**：打开「终端」应用，首次启动会下载 Debian 13 镜像。
4. **扩大磁盘**：终端菜单 → 设置 → 调整磁盘大小，调到 **≥ 24 GB**。
5. **运行一键安装**（见下一节）。
6. **切换到 Omarchy 桌面**：`hypr-switch arch`，再点终端顶部「显示」按钮。
   回到 Debian 图形会话：`hypr-switch debian`。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/rwanglq-ctrl/omarchy-xiaomi18fold/main/install.sh | OMARCHY_ALARM_REF=main bash
```

安装会进入 `omarchy-fold-install` tmux 会话（与 Pad 的 `omarchy-install` 分开，可同机并存）。
终端待机或 SSH 断线后，在 Debian 宿主运行：

```bash
tmux attach -t omarchy-fold-install
# 或查看日志：
tail -f ~/.local/state/omarchy-alarm/install.log
```

### 国内网络安装（Gitee）

```bash
curl -fsSL https://gitee.com/zenbardofsuhe/omarchy-xiaomi18fold/raw/main/install.sh | MIRROR=cn OMARCHY_ALARM_REPO=https://gitee.com/zenbardofsuhe/omarchy-xiaomi18fold OMARCHY_ALARM_REF=main bash -s -- --profile core
```

或先克隆再安装：

```bash
git clone --branch main --depth 1 https://gitee.com/zenbardofsuhe/omarchy-xiaomi18fold.git && cd omarchy-xiaomi18fold
MIRROR=cn bash ./install.sh --profile core
```

失败后重跑同一命令可复用容器与 rootfs 缓存。

## 安装后：折叠机要点

### 键盘与快捷键

- Android 软键盘 **没有 Super/Caps**：本仓库用 `fold_modifier` 把几乎所有 **Super+…** 绑定镜像到 **Alt+…**（例如 Alt+1 切工作区）。
- 物理/蓝牙键盘仍可用 Caps Lock = Super（`caps:super`）。
- **不要用 Alt/Super+Space 切输入法**（与 Omarchy 菜单冲突）。中英文切换默认：
  - **Ctrl+Space**（首选）
  - **Ctrl+Shift+Space**（备用）
  - **单独点一下 Shift**（仅当键盘会发出真正的 Shift 键事件时；多数 Android 软键盘发不出，请用 Ctrl+Space）
- 屏幕键盘（wvkbd）**默认关闭**，优先用 Android 输入法。需要时：Alt+Shift+K，或 `omarchy-osk-toggle start`。自启：`touch ~/.config/omarchy-osk-autostart`。

### 触控与显示

安装器会在 Debian 宿主装上：

| 服务 | 作用 |
|------|------|
| `fold-touch-sync` | 折叠/展开后把触控坐标范围对齐当前显示分辨率 |
| `fold-touch-flushd` | 补发 Android 吞掉的抬起，避免菜单弹出后点按失灵 |
| `fold-clip-bridge` | Arch 模式下打通 Android ↔ Omarchy 剪贴板 |

容器内还有 `fold-display-guard`（热插拔黑屏自愈）、底栏 dock、四指手势等。卡住时可在宿主运行：`fold-rescue`。

### 剪贴板

- **Android → Omarchy**：在 Android 里复制后切回 Linux Terminal，再在桌面粘贴。
- **Omarchy → Android**：在桌面复制后切到其他 Android 应用。

## 配置文件与工具位置

- Hyprland 叠加：`config/hypr/`（含 `fold_modifier.lua`、`touch.lua`）
- 宿主工具：`host/fold/bin/` + `host/fold/systemd/`
- 容器工具：`container/bin/fold-*`、`omarchy-osk-toggle`

## 许可

MIT（与上游 omarchy-alarm-nspawn / Pad 仓库相同）。保留原 LICENSE 与贡献者归属。

---

# English

**Omarchy** on Arch Linux ARM (aarch64) in systemd-nspawn, shown on Debian 13 via seatd — for Android 16 Linux Terminal (AVF).

**Tested on**: Xiaomi 18 Fold.

Adapted from [omarchy-xiaomipad9pm](https://github.com/rwanglq-ctrl/omarchy-xiaomipad9pm) v0.2.11. Fold line starts at **0.1.0**. Issue history lives in Release notes / CHANGELOG, not here.

### Install

```bash
curl -fsSL https://raw.githubusercontent.com/rwanglq-ctrl/omarchy-xiaomi18fold/main/install.sh | OMARCHY_ALARM_REF=main bash
```

CN (Gitee):

```bash
curl -fsSL https://gitee.com/zenbardofsuhe/omarchy-xiaomi18fold/raw/main/install.sh | MIRROR=cn OMARCHY_ALARM_REPO=https://gitee.com/zenbardofsuhe/omarchy-xiaomi18fold OMARCHY_ALARM_REF=main bash -s -- --profile core
```

tmux session: `omarchy-fold-install` (does not collide with Pad’s `omarchy-install`).

### Fold notes

- Super bindings mirrored to Alt for Android keyboards without Super/Caps.
- IME: **Ctrl+Space** (not Alt/Super+Space — menu conflict). Shift alone works only if the keyboard emits a real Shift event.
- OSK (wvkbd) off by default; prefer Android IME.
- Host services: touch range sync, touch unstick, clipboard bridge.
