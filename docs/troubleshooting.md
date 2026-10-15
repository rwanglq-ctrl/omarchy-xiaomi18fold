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

在 Linux Terminal 的文本标签页（或独立 SSH）直接运行 `~/.local/bin/arch-selftest`。
它先停止 weston.socket 和 weston.service，关闭当前图形应用；有界等待锁/seat，前台测试并打印私有日志路径。
完成、失败或收到可处理信号后重启 socket/service 恢复显示，无需手动停止服务；仍有活跃拥有者时报告 PID/命令并拒绝。
使用命令最后打印的确切路径，不要用 `ls -t` 选择最新文件：恢复服务会另建日志。
v0.2.7 的 `launcher-status` 保留原始退出码；旧版 `registration-failed` 仅表示启动器已退出、Leader 从未被轮询观测到，不是 machined 错误。
`stage=arch-hyprland` 记录实际启动选择，`auto` 表示未设置覆盖变量；旧 v0.2.6 本来就不打印该配置行。
`history:` 是历史 journal；诊断块中的日志快照也可能早于本次启动。详见 [自检与证据](v0.2.7-validation.md)。

## Hyprland 无法启动

### 症状：约 1 秒后退出，`Couldn't waitpid for hyprland: No child processes`

这表示 Hyprland 在初始化完成前被信号杀死；随后的 `Hyprland exit cleanly.` 并不是正常退出。
SIGBUS/SIGKILL 不会生成崩溃报告，hyprland.log 末尾也会丢失。v0.2.6 在实机 Pad 上的原因是
`/opt/debian-mesa` 中被截断的 `libLLVM.so.19.1`（加载即 SIGBUS）。v0.2.8 起每次启动校验暂存的
Debian Mesa；损坏时记录 `stage=debian-mesa-damaged` 并改用 Arch Mesa。重新运行安装器即可修复缓存副本。
`arch-diag` 开头的 `hyprland-signal-death` 与 `staged Debian Mesa integrity` 两行给出这一判断。详见 [v0.2.8 实机证据](v0.2.8-validation.md)。

### 症状：黑屏或闪退

v0.2.4 不再固定 Virtual-1；连接器编号可能改变。Debian 宿主运行
`~/.local/bin/arch-output --connected` 查看内核已连接的 card0 输出。
`~/.local/bin/arch-diag` 保存私有原始 monitors all、DRM status 和原始日志尾部；
启动 gate 会在停止 Arch、回退 Weston 前自动收集。若输出有尺寸但仍黑屏，
IPC 就绪不能证明像素已显示，请保留诊断进一步定位。
v0.2.6 的日志优先记录容器命名空间、runtime 挂载、UID/权限、socket 列表和真正的 hyprland.log。
VM 回溯已确认一种启动阻塞：Aquamarine 连接 weston.socket 的 wayland-0，等待无人响应的 Wayland 握手，
尚未建立自己的命令 socket。直接 DRM 启动现在清除父 WAYLAND_DISPLAY/WAYLAND_SOCKET，并仅在容器内屏蔽宿主的 wayland-0 socket，
使该可选连接立即失败；Hyprland 随后为客户端设置自己的有效 socket。不要把 /dev/null 加到客户端或全局环境。
`ipc-wait` 的 socket absent 表示尚未建立命令 socket；存在 socket 但 probe 超时仍需日志判断启动进度，不能仅凭此断言 DRM hang。
`(EE) could not connect to wayland server` 出现在清理阶段时可能是 Xwayland 的退出消息，不等于原始故障点。
用户服务无法杀死 root nspawn 的 cgroup（EPERM）时，由拥有者限定的 sudo machinectl 清理；以 cleanup-complete 和注册消失为准。

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
systemctl --user stop weston.socket weston.service
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

## 可选启动配置

以下文件位于 **Debian 宿主**的 `~/.config/` 中。修改后完全关闭 Linux Terminal
再重新打开显示，使配置生效。默认使用发行版 Hyprland 和已配置的 Debian Mesa，
由 Mesa/DRM 自动选择驱动；`auto` 表示没有显式设置对应环境变量。

| 文件 | 用法 |
| --- | --- |
| `arch-software-rendering` | 存在时强制 llvmpipe：`LIBGL_ALWAYS_SOFTWARE=1`、`GALLIUM_DRIVER=llvmpipe`。 |
| `arch-no-modifiers` | 存在时设置 `AQ_NO_MODIFIERS=1`。 |
| `arch-no-atomic` | 存在时设置 `AQ_NO_ATOMIC=1`，使用 legacy DRM；默认保留 atomic。 |
| `arch-use-arch-mesa` | 存在时跳过 `/opt/debian-mesa`，使用 Arch Mesa。 |
| `arch-hyprland-prefix` | 文件内容为容器内已有可信构建的绝对安装前缀，如 `/opt/hyprland-custom`；使用该前缀的 Hyprland、start-hyprland、hyprctl 和库。必须包含可执行的 Hyprland 和 start-hyprland。 |

布尔开关用 `touch ~/.config/文件名` 启用，删除该文件撤销。
自定义前缀不会下载任何二进制；删除 `arch-hyprland-prefix` 后恢复发行版启动器。
旧 `arch-hardware-rendering` / `arch-enable-modifiers` 已无作用。
`stage=arch-hyprland` 中的 `launch=` 是 watchdog 命令；`parent_mask=wayland-0`
表示仅在容器内屏蔽宿主监听 socket，空值表示无需屏蔽。
