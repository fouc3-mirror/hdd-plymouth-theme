# HDD 开机动画 Plymouth 主题

把一段开机动画视频，做成 Arch Linux 的 Plymouth 开机画面。

- **背景**：PNG 帧序列动画（默认 1280×720、20fps）
- **上层**：启动日志浮层（半透明底 + 等宽字体，显示 plymouth 推送的启动消息）
- **退出规则**：动画播完一轮才允许退出；按键 + 系统启动完成可立即退出
- **播完一轮后仍在启动流程中 → 保持最后一帧**（不循环）

仓库自带抽帧、安装/卸载、离线校验工具：换素材或换分辨率，都只需要跑一条命令。

> **开发方式**：本项目使用 **DSH（DeepSeek Harness）** 开发。
> **素材**：示例动画来自 B 站，已获原作者授权，见[素材来源与授权](#素材来源与授权)。

---

## 目录结构

```
hdd-plymouth-theme/
├── install.sh                        # 安装 / 卸载脚本
├── extract-frames.sh                 # mp4 → PNG 帧序列（自动同步 TOTAL_FRAMES）
├── src/                              # 源视频（自备，不进仓库）
├── theme/hdd-boot/                   # 主题本体
│   ├── hdd-boot.plymouth             # 主题配置
│   ├── hdd-boot.script               # 主题脚本（动画 + 日志 + 退出逻辑）
│   └── frames/                       # 帧序列（抽帧生成，不进仓库）
├── optional/                         # 可选：systemd 延迟退出
│   ├── plymouth-quit-wait.conf
│   └── plymouth-quit-wait.sh
├── docs/
│   └── source-authorization.png      # 原素材作者的授权聊天记录
└── ref/checker/                      # 离线校验工具
```

源视频与生成好的帧序列不入库（见 `.gitignore`），`frames/` 保留 `.gitkeep`，克隆后跑一次抽帧即可。

## 快速开始

```bash
git clone https://github.com/fouc3-mirror/hdd-plymouth-theme.git
cd hdd-plymouth-theme

# 1. 准备一个开机动画视频
cp /path/to/你的动画.mp4 src/

# 2. 抽帧（1280x720 / 20fps；脚本会自动把 TOTAL_FRAMES 写成实际帧数）
./extract-frames.sh src/你的动画.mp4 theme/hdd-boot/frames 20 1280x720

# 3. 装到系统
sudo ./install.sh --with-quit-wait
```

## 安装 / 卸载

| 命令 | 作用 |
|---|---|
| `sudo ./install.sh` | 装主题 + 设为默认 + 重建 initramfs |
| `sudo ./install.sh --with-quit-wait` | 额外装 systemd 单元（见[让 plymouth 至少等动画播完一轮](#可选让-plymouth-至少等动画播完一轮)） |
| `sudo ./install.sh --uninstall` | 卸载并恢复原默认主题 |
| `sudo ./install.sh --dry-run` | 只打印将做什么，不改系统（不用 sudo） |
| `sudo ./install.sh --no-rebuild` | 只装主题，不动 initramfs |

脚本会检查环境 → 复制主题到 `/usr/share/plymouth/themes/hdd-boot` → 记下原默认主题 →
`plymouth-set-default-theme hdd-boot -R` → 校验结果。卸载时恢复记下的那个主题。

**前提条件**（脚本会检测并提示，但不会自动改系统配置）：

1. `/etc/mkinitcpio.conf` 的 `HOOKS` 里要有 `plymouth`，放在 `udev` 之后、`block` / `encrypt` 之前，例如：

   ```
   HOOKS=(base udev plymouth autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)
   ```

2. 内核参数要有 `quiet splash`（systemd-boot 改 `/boot/loader/entries/*.conf` 的 options，
   GRUB 改 `/etc/default/grub` 的 `GRUB_CMDLINE_LINUX_DEFAULT` 后重跑 `grub-mkconfig`）。

改完这两处再重建一次 initramfs（`sudo mkinitcpio -P`）。`-R` 会把主题目录（含帧序列）和
`MonospaceFont` 对应的字体一起打进 initramfs，所以不需要额外往 `FILES` 里加东西。

想恢复系统原默认主题：`sudo plymouth-set-default-theme --reset -R`。

## 换帧率 / 分辨率

```bash
./extract-frames.sh <输入mp4> <输出目录> <fps> <宽x高>
./extract-frames.sh src/你的动画.mp4 theme/hdd-boot/frames 15 960x540
```

跑完会**自动把主题脚本里的 `TOTAL_FRAMES` 改成实际帧数**。

帧序列在启动时会全部解码进内存（每像素 4 字节）。以 9.07s 的示例视频为例：

| 分辨率 | 帧率 | 帧数 | 磁盘 | 解码后内存 |
|---|---|---|---|---|
| 1280×720 | 20fps | 181 | ~86MB | ~670MB |
| 1280×720 | 15fps | 136 | ~65MB | ~500MB |
| 960×540 | 20fps | 181 | ~40MB | ~380MB |

视频越长帧数越多，体积按比例增长。机器内存小或 `/boot` 分区紧张时，用 960×540。

## 主题脚本

`theme/hdd-boot/hdd-boot.script` 顶部是配置区：`ANIM_FPS`、`TOTAL_FRAMES`、`SCALE_BG`、
`HOLD_LAST`、`LOG_VISIBLE`、`LOG_MAX_LINES`、`LOG_FONT`、`LOG_BAR_RATIO`。

脚本做的事：

| 功能 | 实现 |
|---|---|
| 背景动画 | 刷新回调里逐帧 `Scale()` 到窗口尺寸，设置给背景 sprite |
| 启动日志浮层 | `SetDisplayMessageFunction` / `SetUpdateStatusFunction` 收到消息 → 滚动缓冲 → `Image.Text()` 渲染成一张文字图 |
| 播完一轮 | 帧用完即置 `done`，停在最后一帧，不再推进 |
| 退出判定 | `done` 或（检测到按键 且 系统启动完成）→ `exit_allowed` |

## 可选：让 plymouth 至少等动画播完一轮

`plymouth-quit.service` 通常在启动收尾时才退出 splash，所以动画一般能播完。若某次启动比动画还快，
可以装这个单元，让 `plymouth quit` 等到动画播完一轮（默认 9.5s，可用环境变量 `PLYMOUTH_WAIT_SECONDS` 调整）：

```bash
sudo ./install.sh --with-quit-wait          # 装主题时一起装，推荐
```

它只推迟 `plymouth quit`，不影响系统启动本身：脚本按 plymouthd 的启动时间算出还差多久，只补足不足的部分。

## 调试

```bash
# 主题脚本能否被 plymouth 解析、逻辑是否正确（离线，不需要 root，也不需要装 plymouth）
./ref/checker/check theme/hdd-boot/hdd-boot.script
./ref/checker/run ref/checker/stub.script theme/hdd-boot/hdd-boot.script 2
#   场景: 1=未播完+quit  2=播完一轮  3=按键+启动完成  4=日志滚动

# 重新编译校验器（会自动 sparse clone plymouth 源码）
./ref/checker/build.sh

# 真机调试日志（含脚本语法错误、图片加载失败）
sudo plymouthd --debug --debug-file=/tmp/plymouth-debug.log --no-daemon --mode=boot
# 另一个终端：sudo plymouth show-splash / sudo plymouth quit
```

常见问题：

- **黑屏但能进系统**：多半是帧没打进 initramfs 或路径不对。`ls /usr/share/plymouth/themes/hdd-boot/frames | wc -l`
  应为 182（帧数 + `black.png`）。
- **动画不动，只有一帧**：脚本有报错，看 debug log。
- **日志文字不显示**：initramfs 里字体没被识别。换个系统里 `fc-match` 能解析到的字体名写进
  `MonospaceFont` 和脚本的 `LOG_FONT`。

## 素材来源与授权

本仓库的主题素材（用于抽帧的动画视频）不是原创，来源与授权如下：

| 项 | 内容 |
|---|---|
| 原视频 | [《我把绝区零HDD开屏动画做进了Windows开机！》](https://www.bilibili.com/video/BV1f7tC6oEm7)（BV1f7tC6oEm7） |
| 原作者 | B 站 UP 主 **露露luki_yo** —— [个人空间](https://space.bilibili.com/3537104783018790) |
| 授权凭证 | [`docs/source-authorization.png`](docs/source-authorization.png)（2026-09-08 与作者的聊天记录） |

据聊天记录，作者同意把该动画做成 Arch Linux 的开机画面并发布分享，也同意转成图片序列等修改，
条件是**注明原作者并附上原视频链接**。因此：

- 本仓库不分发原始视频，也不包含转换后的帧序列（见 `.gitignore`），使用者需自备素材。
- 再分发时请保留本节署名与原视频链接，并自行确认授权范围。
- 游戏素材的相关权利归原权利方，本项目以非营利方式分享；如权利人提出异议会移除相关内容。

代码部分（主题脚本、抽帧/安装脚本、校验器）为原创，可自由取用；仓库暂未附 LICENSE 文件。
