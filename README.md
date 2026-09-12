# HDD 开机动画 Plymouth 主题

把一段开机动画 mp4（示例：9.07s / 2560×1440 / 30fps）转成 PNG 帧序列，做成一个 Plymouth 主题：

- **背景**：帧序列动画（1280×720，20fps，181 帧）
- **上层**：启动日志浮层
- **退出规则**：动画播完一轮才允许退出；按键 + 系统启动完成可立即退出
- **播完一轮后仍在中途启动 → 保持最后一帧**（不循环）

> **开发方式**：本项目全程使用 **DSH（DeepSeek Harness）** AI Agent 开发 —— 包括 plymouth 26 script API 的源码核对、帧序列生成、主题脚本编写，以及离线校验器（用 plymouth 自带解析器 + stub 运行时验证脚本逻辑）。
>
> **素材来源**：示例动画来自 B 站 UP 主 **露露luki_yo** 的《我把绝区零HDD开屏动画做进了Windows开机！》，**已获作者授权**改编并分享（授权聊天记录见 [`docs/source-authorization.png`](docs/source-authorization.png)，详见第 11 节）。
>
> **仓库不含**源视频和生成好的帧序列（分别是 113MB / 86MB 的素材与生成物，见 `.gitignore`）：
> 你需要自己准备一个 mp4 放进 `src/`，再用 `extract-frames.sh` 生成帧。因此**克隆下来不能直接装**，先看第 2 节。

---

## 1. 目录结构

```
hdd-plymouth-theme/
├── install.sh                        # ★ 安装 / 卸载脚本（见第 3 节）
├── extract-frames.sh                 # 抽帧脚本（参数化，自动同步 TOTAL_FRAMES）
├── src/                              # 源视频（自备，不进仓库）
│   └── HDD开机动画1.mp4               # 示例：9.07s（较短的那个）
├── theme/hdd-boot/                   # ★ 主题本体
│   ├── hdd-boot.plymouth             # 主题配置
│   ├── hdd-boot.script               # 主题脚本（动画 + 日志 + 退出逻辑）
│   └── frames/                       # 帧序列（抽帧生成，不进仓库）
│       └── frame-0001.png ... frame-0181.png + black.png
├── optional/
│   ├── plymouth-quit-wait.conf       # 可选：systemd 延迟退出（见第 7 节）
│   └── plymouth-quit-wait.sh         # 上面的单元调用的脚本（装到 /usr/local/bin）
├── docs/
│   └── source-authorization.png      # 原素材作者的授权聊天记录（见第 11 节）
└── ref/checker/                      # 离线校验工具（plymouth 解析器 + stub 运行时）
```

## 2. 从克隆开始

```bash
git clone https://github.com/fouc3-mirror/hdd-plymouth-theme.git
cd hdd-plymouth-theme

# 1) 放一个开机动画视频进去
cp /path/to/你的动画.mp4 src/

# 2) 抽帧（1280x720 / 20fps；脚本会自动把 TOTAL_FRAMES 写成实际帧数）
./extract-frames.sh src/你的动画.mp4 theme/hdd-boot/frames 20 1280x720

# 3) 装到系统
sudo ./install.sh
```

> 视频时长/帧率不同也能用：`extract-frames.sh` 会按实际时长抽帧并同步主题脚本里的 `TOTAL_FRAMES`。

## 3. 安装到 Arch

```bash
sudo ./install.sh                      # 装主题 + 设为默认 + 重建 initramfs
sudo ./install.sh --with-quit-wait     # 额外装 systemd 单元（见第 7 节）
sudo ./install.sh --uninstall          # 卸载并恢复原默认主题
sudo ./install.sh --dry-run            # 只看会做什么（不用 sudo）
sudo ./install.sh --no-rebuild         # 不重建 initramfs
```

脚本会做的事：检查环境 → 复制主题到 `/usr/share/plymouth/themes/hdd-boot` → 记下原来的默认主题 →
`plymouth-set-default-theme hdd-boot -R` → 校验结果。卸载时把默认主题恢复成记下的那个。

**前提条件（脚本会自动检测并提示，但不会替你改系统配置）**：

1. `/etc/mkinitcpio.conf` 的 `HOOKS` 里要有 `plymouth`（放在 `udev` 之后、`block`/`encrypt` 之前）。
   本机当前是：
   `HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)`
   —— **没有 plymouth，需要加上**，例如：
   `HOOKS=(base udev plymouth autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)`
2. 内核参数要有 `quiet splash`。本机当前 cmdline 没有 `splash`，需要在引导器里加
   （systemd-boot 改 `/boot/loader/entries/*.conf` 的 options，GRUB 改 `/etc/default/grub` 的 `GRUB_CMDLINE_LINUX_DEFAULT`）。
3. 改完这两处再 `sudo mkinitcpio -P`（`install.sh` 已带 `-R`，改 HOOKS 后需再跑一次重建）。

> `plymouth-set-default-theme -R` 会把主题目录（含 `frames/`，约 86MB）和 `MonospaceFont` 对应的字体文件一起打进 initramfs，
> 所以**不需要**额外往 `FILES` 里加东西；代价是 initramfs 会大 ~86MB。
> 本机原默认主题是 `bgrt`，想手动还原：`sudo plymouth-set-default-theme bgrt -R`。

## 4. 换帧率 / 分辨率

```bash
cd ~/Projects/hdd-plymouth-theme
./extract-frames.sh src/HDD开机动画1.mp4 theme/hdd-boot/frames 15 960x540
#                   输入                输出目录                 fps 分辨率
```

脚本跑完会**自动把主题脚本里的 `TOTAL_FRAMES` 改成实际帧数**。

体积/内存参考（帧全部常驻内存，PNG 解码后每帧 4 字节/像素）：

| 分辨率 | 帧率 | 帧数 | 磁盘 | 解码后内存 |
|---|---|---|---|---|
| 1280×720 | 20fps | 181 | ~86MB | ~670MB |
| 1280×720 | 15fps | 136 | ~65MB | ~500MB |
| 960×540 | 20fps | 181 | ~40MB | ~380MB |

本机 16GB 内存用默认的 720p/20fps 没问题；内存紧或想要更短的 initramfs，换 960×540。

## 5. 主题脚本逻辑（`hdd-boot.script`）

| 需求 | 实现位置 |
|---|---|
| 背景播放帧序列 | `on_refresh()`：每 tick 取 `frames[i]`，`Scale()` 到窗口尺寸后 `bg_sprite.SetImage()`；`Plymouth.SetRefreshRate(20)` 控制速度 |
| 动画必须播完一轮才允许退出 | `on_refresh()` 播完 `TOTAL_FRAMES` 后置 `anim.done=1`；`update_exit_allowed()` 里 `anim.done` → 允许退出 |
| 播完仍在中途启动 → 保持最后一帧 | `on_refresh()` 开头 `if (anim.done) return;`，并停在 `TOTAL_FRAMES-1`，不循环、不清屏 |
| 检测按键 + 系统启动完成才允许退出 | `on_key()` 置 `anim.key_pressed`；`on_boot_progress()`（progress≥1.0）和 `on_quit()` 置 `anim.boot_complete`；`update_exit_allowed()` 判定 `key_pressed && boot_complete` |
| 上层显示启动日志 | `on_message()` / `on_status()` 收消息 → `log_push()` 滚动缓冲（8 行）→ `log_render()` 用 `Image.Text()` 渲染到 z=1001 的 sprite，底下压一条 z=1000 的半透明黑条 |

可调项在脚本顶部的「配置」区：`ANIM_FPS`、`TOTAL_FRAMES`、`SCALE_BG`、`LOG_VISIBLE`、`LOG_MAX_LINES`、`LOG_FONT`、`LOG_BAR_RATIO`。

## 6. ⚠️ 两个必须知道的 API 限制（重要）

主题是照需求写的，但 **plymouth 26 的 script 语言能力和需求里假设的 API 不一致**，这里说清楚，避免踩坑：

**6.1 `GetBootLog()` 不存在。**

我核对了本机 `/usr/lib/plymouth/script.so` 导出的全部函数（并对照 plymouth 源码 26.134 与 0.9.5）：script 插件的 `Plymouth` 对象只有
`SetRefreshFunction / SetRefreshRate / SetBootProgressFunction / SetRootMountedFunction / SetKeyboardInputFunction / SetUpdateStatusFunction / SetDisplayNormalFunction / SetDisplayPasswordFunction / SetDisplayQuestionFunction / SetDisplayPromptFunction / SetDisplayHotplugFunction / SetValidateInputFunction / SetDisplayMessageFunction / SetHideMessageFunction / SetQuitFunction / SetSystemUpdateFunction / GetMode / GetCapslockState`
—— **没有任何读取启动日志的接口**，`GetBootLog()` 从来不是 plymouth 的一部分。

日志浮层因此改用 plymouth 实际会推给主题的消息流（`SetDisplayMessageFunction` / `SetUpdateStatusFunction`）渲染。它是 plymouth 层面的启动状态消息；**不是**内核 dmesg / systemd journal 全文。
（真正的全量日志只有 plymouthd 内置的 console viewer 会显示，而它在 v26 里只能由「密码输入时按 ESC」这条路径触发，主题脚本无法打开它。想要全量日志需要改 plymouthd 源码，不在本次范围内。）

**6.2 脚本拦不住 plymouthd 拆除 splash。**

`Plymouth.SetQuitFunction` 注册的回调在 plymouthd 决定退出时被调用，但**调用完脚本状态就被销毁**（`plugin.c: stop_script_animation()` → `script_lib_plymouth_on_quit()` → `script_state_destroy()`）。所以：

- 「动画播完一轮才允许退出」在**脚本内**能保证的是：动画播完前画面一直保持、播完后停在最后一帧、并给出 `anim.exit_allowed` 状态；**不能**真正让 plymouthd 多等。
- 「按键立即退出」在**脚本内**只能记录 `key_pressed` 并参与 `exit_allowed` 判定；script 语言没有 `Plymouth.Quit()`，也不能执行外部命令，所以**按键没法从脚本里直接把 `plymouth quit` 叫起来**。

对你这台机器（机械硬盘）来说这通常不是问题：`plymouth-quit.service` 在 `systemd-user-sessions.service` 之后才跑，HDD 启动到那一步远超 9s，动画早就播完了。
但如果哪次启动比动画还快（SSD），想让「必须播完一轮」真正生效，用下面的可选单元。

## 7. 可选：让 plymouth 至少等动画播完一轮

```bash
sudo ./install.sh --with-quit-wait          # 装主题时一起装（推荐）
# 或者主题已装好，单独装:
sudo install -m 755 optional/plymouth-quit-wait.sh /usr/local/bin/
sudo install -m 644 optional/plymouth-quit-wait.conf /etc/systemd/system/plymouth-quit.service.d/
sudo systemctl daemon-reload
```

它只推迟 `plymouth quit`，**不会**推迟系统启动本身。逻辑是「确保 plymouthd 起来后至少过了 9.5s 再退出」，快启动时才真正等待，慢启动（HDD）不会白等。等待时长可用环境变量 `PLYMOUTH_WAIT_SECONDS` 覆盖。
`install.sh --uninstall` 会一并移除；手动撤掉就是删掉 `.conf` 和 `/usr/local/bin/plymouth-quit-wait.sh` 再 `daemon-reload`。

> ⚠️ **不要在 unit 文件里写内联 shell**：systemd 会把 `%Y`（stat）、`%s`（date）当作
> unit specifier 展开，命令会被静默改写（实测 `stat -c %Y` 变成 `stat -c /usr/lib/systemd/system`，
> 延迟完全失效且不报错）。所以逻辑放在独立脚本里。

> 按键跳过这段等待做不到（见 6.2）：脚本拿不到执行权，systemd 的 `ExecStartPre` 也没法被按键打断。

## 8. 调试

```bash
# 主题脚本能否被 plymouth 解析（离线校验器，不需要 root，也不需要装 plymouth）
./ref/checker/check theme/hdd-boot/hdd-boot.script

# 用 stub 运行时把脚本真正跑一遍，验证退出/保持最后一帧/日志滚动逻辑
./ref/checker/run ref/checker/stub.script theme/hdd-boot/hdd-boot.script 2
#   场景: 1=未播完+quit  2=播完一轮  3=按键+启动完成  4=日志滚动

# 校验器是预编译好的；改了脚本想重新编译：
./ref/checker/build.sh     # 会自动 sparse clone plymouth 源码再编译

# 真机调试：plymouthd 调试日志（含脚本语法错误、图片加载失败）
sudo plymouthd --debug --debug-file=/tmp/plymouth-debug.log --no-daemon --mode=boot
# 另一个终端：
sudo plymouth show-splash
sudo plymouth quit
```

常见问题：

- **花屏/黑屏但能进系统**：多半是帧没打进 initramfs，或 `ImageDir` 路径不对。`ls /usr/share/plymouth/themes/hdd-boot/frames | wc -l` 应为 182（181 帧 + `black.png`）。
- **动画不动，只有一帧**：`Plymouth.SetRefreshRate` 之后没有回调，看 debug log 里脚本是否有报错。
- **日志文字不显示**：initramfs 里字体没被识别。`MonospaceFont=monospace 12` 是给 `Image.Text` 用的字体名，Arch 的 plymouth hook 会按它自动打包字体；仍不显示就换一个系统里 `fc-match` 得到的字体名。
- **退出太早/太晚**：看第 6、7 节。

## 9. 已验证 / 未验证

已验证（离线，用 plymouth 自带解析器 + stub 运行时真实执行了脚本）：

| 场景 | 结果 |
|---|---|
| 语法解析（`script_parse_file`） | PARSE OK（官方 `script.script` 作对照同样 OK） |
| 181 帧加载 + 播完一轮 | `done=1`，停在最后一帧（index 180），允许退出 |
| 播完后再刷新 | index 不再变化（保持最后一帧） |
| 未播完 + quit、无按键 | `exit_allowed=0`（不允许退出） |
| 未播完 + 按键 + 启动未完成 | 不允许退出 |
| 未播完 + 按键 + 启动完成（progress=1.0） | 允许退出 |
| 12 条日志消息 | 缓冲正确滚动，保留最后 8 行并渲染成一张文字图 |

**未验证**：真机启动渲染（GPU/DRM 上的实际画面、动画流畅度、字体渲染）。建议先在真机上按第 8 节跑一次 `plymouthd --debug` 看日志。

## 10. 本机已做的系统改动（2026-09-12）

主题装好后开机仍看不到，是因为缺了 plymouth 的两条启用条件。已在系统上改好：

| 文件 | 改动 | 备份 |
|---|---|---|
| `/etc/mkinitcpio.conf` | `HOOKS` 加 `plymouth`（`base udev` 之后） | `/etc/mkinitcpio.conf.bak-20260912-164108` |
| `/etc/default/grub` | `GRUB_CMDLINE_LINUX_DEFAULT` 追加 `quiet splash` | `/etc/default/grub.bak-20260912-164108` |
| `/boot/grub/grub.cfg` | 重新执行 `grub-mkconfig -o` 生成 | `/boot/grub/grub.cfg.bak-20260912-164108` |
| 两个 initramfs | 重新执行 `mkinitcpio -P` 生成 | — |

重建后校验（`lsinitcpio /boot/initramfs-linux-lts.img`）：

| 内容 | 数量 |
|---|---|
| 主题帧 `hdd-boot/frames/frame-*.png` | 181 ✅ |
| `black.png` / `hdd-boot.script` / `hdd-boot.plymouth` | 1 / 1 / 1 ✅ |
| `plymouth/script.so`、`renderers/drm.so` | 各 1 ✅ |
| `Plymouth-monospace*.ttf`（日志文字用） | 2 ✅ |

体积代价：initramfs 从约 171MB → **257MB**（两个内核各一份，共 +172MB）。
本机 `/boot` 只有 1GB，改完剩 **414MB**。若嫌紧，用第 4 节换成 `960×540` 抽帧（约 −92MB）。

**两个已知取舍**：

- 追加的 `quiet` 会把原来的 `loglevel=5` 覆盖成 4（内核按 cmdline 顺序取最后一个）。
  想保留详细日志：把 `/etc/default/grub` 里的 `quiet` 删掉、只留 `splash`，再 `sudo grub-mkconfig -o /boot/grub/grub.cfg`。
- 本机是 Intel 核显 + NVIDIA 独显（Optimus）。plymouth 走 DRM/KMS，正常应由 Intel 输出；
  万一开机黑屏，先切到别的 TTY 或用快照回滚，再按下面命令撤掉改动。

**回滚**：

```bash
sudo cp /etc/mkinitcpio.conf.bak-20260912-164108 /etc/mkinitcpio.conf
sudo cp /etc/default/grub.bak-20260912-164108 /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo mkinitcpio -P
# 主题本身: sudo ./install.sh --uninstall
```

## 11. 素材来源与授权

本仓库的主题素材（用于抽帧的动画视频）**不是原创**，来源与授权如下：

| 项 | 内容 |
|---|---|
| 原视频 | [《我把绝区零HDD开屏动画做进了Windows开机！》](https://www.bilibili.com/video/BV1f7tC6oEm7)（BV1f7tC6oEm7） |
| 原作者 | B 站 UP 主 **露露luki_yo** —— [个人空间](https://space.bilibili.com/3537104783018790) |
| 授权凭证 | [`docs/source-authorization.png`](docs/source-authorization.png)（2026-09-08 与作者的聊天记录） |

**授权内容**（据聊天记录）：作者同意把该动画做成 Arch Linux 的开机画面，发布到 AUR 与 GitHub 免费分享给其他 Linux 用户；
并同意对动画文件「稍作修改（比如转成图片序列）」以适配 Linux，由改编方自行下载视频转换。
条件是**注明原作者并附上原视频的 B 站链接**。

**因此**：

- 本仓库**不分发**原始视频，也不包含转换后的帧序列（见 `.gitignore`）；使用者需自备素材。
- 任何人基于本仓库再分发时，请保留本节署名与原视频链接，并自行确认授权范围。
- 原视频是把游戏《绝区零》的 HDD 开屏动画做成 Windows 开机动画；游戏素材的相关权利归原权利方，本项目以非营利方式分享。
- 若原作者或相关权利人提出异议，会移除相关内容。

> 代码部分（主题脚本、抽帧/安装脚本、校验器）为原创，可自由取用；仓库暂未附 LICENSE 文件。


