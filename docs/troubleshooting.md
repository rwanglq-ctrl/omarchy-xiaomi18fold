# 故障排除

## 容器无法启动

桌面容器由 `arch-hyprland` 非 boot 模式启动，机器名是 `arch-desktop`。
不要用 `machinectl start arch` 代替正常启动链。Debian 宿主运行：

```bash
~/.local/bin/arch-diag
journalctl --user -u weston.service -b --no-pager
sudo journalctl -b -u systemd-machined --no-pager
```

每次启动证据保存在 `~/.local/state/omarchy-alarm/arch-session-*.log`。
按 `stage=` 顺序区分 sudo/挂载预检、nspawn 注册、容器入口、start-hyprland、
输出就绪、诊断、清理和回退。容器清理后 `machinectl` 查不到它，不代表从未启动。

独立文本终端/SSH、显示服务停止时可运行 `~/.local/bin/arch-selftest`。
它前台运行一次、无 Weston 回退，打印私有日志路径；已有会话时拒绝执行。
详见 [自检与证据](v0.2.5-validation.md)。

## Hyprland 无法启动

### 症状：黑屏或闪退

v0.2.4 不再固定 Virtual-1；连接器编号可能改变。Debian 宿主运行
`~/.local/bin/arch-output --connected` 查看内核已连接的 card0 输出。
`~/.local/bin/arch-diag` 保存私有原始 monitors all、DRM status 和原始日志尾部；
启动 gate 会在停止 Arch、回退 Weston 前自动收集。若输出有尺寸但仍黑屏，
IPC 就绪不能证明像素已显示，请保留诊断进一步定位。

切换方式：`~/.local/bin/hypr-switch arch`，然后完全关闭 Linux Terminal
应用再重新打开。恢复 Debian 使用 `~/.local/bin/hypr-switch debian` 后同样关闭/重开；
不要在当前图形终端内重启 weston.service。

检查 Hyprland 配置：
```bash
# 在容器内
Hyprland --verify-config
```

常见原因：
- 缺少 seatd socket — 确保宿主的 seatd 已启动；Wayland socket 由 Hyprland 创建
- llvmpipe 问题 — 检查 `LIBGL_ALWAYS_SOFTWARE=1` 是否设置
- 配置语法错误 — 查看 `/run/user/UID/hypr/INSTANCE/hyprland.log`（通过宿主 `arch-output --logs` 自动定位）

### 症状：Hyprland 启动但无显示

确认 seatd socket 是否挂载：
```bash
ls -la /run/seatd.sock
```

如果不存在，检查宿主的 `arch-hyprland` 脚本是否正确传递了 seatd socket。

## 鼠标指针不可见

在 `~/.config/hypr/looknfeel.lua` 中添加：
```lua
hl.config({ cursor = { no_hardware_cursors = true } })
```

## 中文输入法问题

### fcitx5 不启动

运行 `fcitx5-autostart` 手动启动，检查输出：
```bash
~/.local/bin/fcitx5-autostart
```

脚本会等待 Wayland socket 就绪，确认有 Wayland 前端，最多重启 3 次。

### 输入法切换不工作

确认环境变量：
```bash
echo $INPUT_METHOD    # 应为 fcitx
echo $QT_IM_MODULE    # 应为 fcitx
echo $XMODIFIERS      # 应为 @im=fcitx
```

这些变量在 `~/.config/hypr/envs.lua` 中设置。

## 锁屏后无法解锁

**原因**: 用户密码处于锁定状态（`passwd -S` 显示 `L`）。

**解决**: 在解锁前先设置密码：
```bash
passwd
```

然后通过 `Super+Ctrl+I` 或运行 `omarchy toggle idle` 恢复空闲锁屏。

## 通知和托盘图标异常

### 症状：收不到通知

宿主可能已占用 `org.freedesktop.Notifications` 服务名。
容器的通知守护进程无法注册到 D-Bus 总线。

### 症状：托盘图标不显示

宿主可能已占用 `org.kde.StatusNotifierWatcher`。
这是 nspawn 容器共享宿主 D-Bus 总线的固有限制。

## 截图和屏幕共享异常

宿主可能已占用 `org.freedesktop.portal.Desktop`（后端是宿主的 xdg-desktop-portal-hyprland）。
容器中的截图/屏幕共享请求可能被路由到宿主的 portal，而宿主的 Hyprland 不在运行。

## 电源和网络面板无数据

这些面板依赖 NetworkManager、bluez、UPower 的系统总线服务，容器中没有这些服务。
属于已知限制，不影响核心功能。

## Omarchy 更新

**不要运行 `omarchy-update`** — 它会走 Omarchy 自家软件源和 channel 切换，
在容器环境中无法正常工作。

更新方式：在 Debian 宿主按 README 的 `OMARCHY_ALARM_REF=main` 命令重跑安装器。
它验证固定上游基线并按 patch-id 应用缺失补丁，拒绝覆盖上游 checkout 的未提交修改。
不要自行 rebase 到另一个 Omarchy tag：本项目补丁和测试针对固定 v4.0.4。

## 性能问题

参见 [性能调优](performance.md)。

快速检查：
```bash
# CPU 使用率
htop

# 内存使用
free -h

# 渲染相关进程
ps aux | grep -E 'hyprland|quickshell|foot'
```

## `registration-collision` / `registry-unavailable` / `session-busy`

从 SSH 或独立的 Debian 终端检查（不要从将被关闭的图形终端执行）：

```bash
journalctl --user -b -u weston.service --no-pager -n 100
machinectl list
machinectl status arch-desktop
```

`registration-collision` 表示已有容器占用会话；启动器不会终止不属于本次启动的容器。
确认无需保留该 Arch 桌面中的工作后，运行以下恢复步骤；这会结束已有 Arch 会话：

```bash
systemctl --user stop weston.service
sudo machinectl terminate arch-desktop
machinectl list  # 确认 arch-desktop 已消失
hypr-switch debian
```

`registry-unavailable` 表示三次有时限的查询均失败，尚无法确认 DRM 未被占用。
检查 `sudo systemctl status systemd-machined` 与其 journal，修复服务后重试。
`session-busy` 表示另一个启动器持有锁；结束或等待已有 `arch-selftest` / `arch-hyprland`，
不要删除锁文件。以上拒绝发生在启动前，原因写入终端或 user journal。

会话证据保留最近 10 个文件，每个至多 8 MiB；超限保留近期输出并标记截断。
独立 `arch-diag` 保留最近 10 份报告。请在重试多次前复制需要保留的证据。
正常 Weston 回退之后的输出交给 journal；该次 Arch 失败证据仍保留在文件中。
