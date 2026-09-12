#!/usr/bin/env bash
# =====================================================================
# install.sh — 安装 / 卸载 hdd-boot Plymouth 主题
#
#  用法:
#     sudo ./install.sh [选项]
#
#  选项:
#     --with-quit-wait   同时安装 systemd 单元，让 plymouth 至少等动画播完
#                        一轮（9.5s）再退出
#     --no-rebuild       不重建 initramfs（默认会重建）
#     --uninstall        卸载：恢复之前的默认主题并删除主题文件
#     --dry-run          只打印将要做的事，不改动系统（可不用 sudo）
#     -h, --help         显示本帮助
#
#  注意: 装完还需确认 /etc/mkinitcpio.conf 的 HOOKS 含 plymouth、
#        内核参数有 splash，脚本会在结尾检查并提示。
# =====================================================================

set -euo pipefail

THEME_NAME="hdd-boot"
PROJECT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
THEME_SRC="$PROJECT_DIR/theme/$THEME_NAME"
THEME_DST="/usr/share/plymouth/themes/$THEME_NAME"
QUIT_WAIT_SRC="$PROJECT_DIR/optional/plymouth-quit-wait.conf"
QUIT_WAIT_DST="/etc/systemd/system/plymouth-quit.service.d/plymouth-quit-wait.conf"
STATE_DIR="/var/lib/hdd-plymouth-theme"
STATE_FILE="$STATE_DIR/previous-theme"
QUIT_WAIT_SCRIPT_SRC="$PROJECT_DIR/optional/plymouth-quit-wait.sh"
QUIT_WAIT_SCRIPT_DST="/usr/local/bin/plymouth-quit-wait.sh"

WITH_QUIT_WAIT=0
NO_REBUILD=0
DO_UNINSTALL=0
DRY_RUN=0

c_ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
c_info() { printf '\033[36m·\033[0m %s\n' "$*"; }
c_warn() { printf '\033[33m!\033[0m %s\n' "$*"; }
c_err()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; }
die()    { c_err "$*"; exit 1; }

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '  [dry-run] %s\n' "$*"
    return 0
  fi
  "$@"
}

usage() {
  sed -n '3,$p' "$0" | sed -n '/^#/!q;p' | sed 's/^# \{0,1\}//' | grep -v '^=\{4,\}$'
}

# ---------------------------- 参数 ----------------------------
ORIG_ARGS=("$@")
while [ $# -gt 0 ]; do
  case "$1" in
    --with-quit-wait) WITH_QUIT_WAIT=1 ;;
    --no-rebuild)     NO_REBUILD=1 ;;
    --uninstall)      DO_UNINSTALL=1 ;;
    --dry-run)        DRY_RUN=1 ;;
    -h|--help)        usage; exit 0 ;;
    *)                c_err "未知参数: $1"; echo; usage; exit 2 ;;
  esac
  shift
done

# ---------------------------- 前置检查 ----------------------------
if [ "$(id -u)" -ne 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  die "需要 root 权限，请用: sudo $0${ORIG_ARGS[*]:+ ${ORIG_ARGS[*]}}"
fi

command -v plymouthd >/dev/null 2>&1 \
  || die "没找到 plymouthd，请先安装 plymouth（pacman -S plymouth）"
command -v plymouth-set-default-theme >/dev/null 2>&1 \
  || die "没找到 plymouth-set-default-theme"

[ -d "$THEME_SRC" ] || die "主题源目录不存在: $THEME_SRC"
[ -f "$THEME_SRC/$THEME_NAME.script" ] || die "缺少主题脚本: $THEME_SRC/$THEME_NAME.script"
[ -f "$THEME_SRC/$THEME_NAME.plymouth" ] || die "缺少主题配置: $THEME_SRC/$THEME_NAME.plymouth"

# 帧数与脚本里的 TOTAL_FRAMES 必须一致，否则动画会缺帧/取到空图
frames_on_disk=$(ls "$THEME_SRC"/frames/frame-*.png 2>/dev/null | wc -l)
script_total=$(sed -n 's/^TOTAL_FRAMES  *= *\([0-9]*\).*/\1/p' "$THEME_SRC/$THEME_NAME.script" | head -1)
[ -n "$script_total" ] || die "读不到 $THEME_NAME.script 里的 TOTAL_FRAMES"
if [ "$frames_on_disk" != "$script_total" ]; then
  die "帧数与 TOTAL_FRAMES 不一致: 磁盘 $frames_on_disk 帧, 脚本写的是 $script_total。
    请先重新抽帧: ./extract-frames.sh src/HDD开机动画1.mp4 theme/$THEME_NAME/frames <fps> <宽x高>"
fi

# 主题配置里的路径必须与实际安装位置一致
if ! grep -q "^ImageDir=$THEME_DST/frames$" "$THEME_SRC/$THEME_NAME.plymouth"; then
  die "$THEME_NAME.plymouth 里的 ImageDir 不是 $THEME_DST/frames，安装路径对不上"
fi
if ! grep -q "^ScriptFile=$THEME_DST/$THEME_NAME.script$" "$THEME_SRC/$THEME_NAME.plymouth"; then
  die "$THEME_NAME.plymouth 里的 ScriptFile 不是 $THEME_DST/$THEME_NAME.script，安装路径对不上"
fi

# ---------------------------- 环境提示（只提示，不自动改系统配置） ----------------------------
env_warnings=0

check_environment() {
  env_warnings=0

  if [ -f /etc/mkinitcpio.conf ]; then
    if ! grep -qE '^[[:space:]]*HOOKS=.*plymouth' /etc/mkinitcpio.conf; then
      c_warn "/etc/mkinitcpio.conf 的 HOOKS 里没有 plymouth —— initramfs 阶段不会显示主题"
      echo "     建议改成（plymouth 放在 udev 之后、block/encrypt 之前）:"
      echo "       HOOKS=(base udev plymouth autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)"
      env_warnings=$((env_warnings + 1))
    fi
  fi

  if ! grep -qw splash /proc/cmdline 2>/dev/null; then
    c_warn "当前内核命令行没有 splash —— plymouth 不会启用图形启动画面"
    echo "     需要在引导器内核参数里加上: quiet splash"
    echo "     （systemd-boot: /boot/loader/entries/*.conf 的 options；GRUB: /etc/default/grub 的 GRUB_CMDLINE_LINUX_DEFAULT）"
    env_warnings=$((env_warnings + 1))
  fi

  [ "$env_warnings" -gt 0 ] && echo
  return 0
}

# ---------------------------- 安装 ----------------------------
install_theme() {
  c_info "复制主题: $THEME_SRC -> $THEME_DST  ($(du -sh "$THEME_SRC" | cut -f1))"
  run install -d /usr/share/plymouth/themes
  [ -d "$THEME_DST" ] && run rm -rf "$THEME_DST"
  run cp -r "$THEME_SRC" "$THEME_DST"

  # 记下原来的默认主题，卸载时恢复
  local prev
  prev="$(plymouth-set-default-theme 2>/dev/null || true)"
  if [ ! -f "$STATE_FILE" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      printf '  [dry-run] 记录原默认主题到 %s: %s\n' "$STATE_FILE" "${prev:-<空>}"
    else
      install -d "$STATE_DIR"
      printf '%s\n' "$prev" > "$STATE_FILE"
      c_info "已记录原默认主题: ${prev:-<空>}"
    fi
  fi

  if [ "$NO_REBUILD" -eq 1 ]; then
    c_info "设置默认主题: $THEME_NAME （--no-rebuild，不动 initramfs）"
    run plymouth-set-default-theme "$THEME_NAME"
  else
    c_info "设置默认主题并重建 initramfs: $THEME_NAME -R"
    run plymouth-set-default-theme "$THEME_NAME" -R
  fi

  if [ "$WITH_QUIT_WAIT" -eq 1 ]; then
    c_info "安装 systemd 单元（让动画至少播完一轮再退出）"
    [ -f "$QUIT_WAIT_SCRIPT_SRC" ] || die "缺少脚本: $QUIT_WAIT_SCRIPT_SRC"
    run install -d "$(dirname "$QUIT_WAIT_DST")"
    run install -m 755 "$QUIT_WAIT_SCRIPT_SRC" "$QUIT_WAIT_SCRIPT_DST"
    run install -m 644 "$QUIT_WAIT_SRC" "$QUIT_WAIT_DST"
    run systemctl daemon-reload
  fi

  if [ "$DRY_RUN" -eq 0 ]; then
    local now
    now="$(plymouth-set-default-theme 2>/dev/null || true)"
    [ "$now" = "$THEME_NAME" ] && c_ok "当前默认主题: $now" || c_warn "当前默认主题是 $now（预期 $THEME_NAME）"
  fi
}

# ---------------------------- 卸载 ----------------------------
uninstall_theme() {
  local prev=""
  [ -f "$STATE_FILE" ] && prev="$(cat "$STATE_FILE")"

  if [ -n "$prev" ] && [ "$prev" != "$THEME_NAME" ]; then
    if [ "$NO_REBUILD" -eq 1 ]; then
      c_info "恢复默认主题: $prev"
      run plymouth-set-default-theme "$prev"
    else
      c_info "恢复默认主题并重建 initramfs: $prev -R"
      run plymouth-set-default-theme "$prev" -R
    fi
  else
    if [ "$NO_REBUILD" -eq 1 ]; then
      c_info "恢复系统默认主题（plymouthd.defaults）"
      run plymouth-set-default-theme --reset
    else
      c_info "恢复系统默认主题并重建 initramfs"
      run plymouth-set-default-theme --reset -R
    fi
  fi

  c_info "删除主题目录: $THEME_DST"
  run rm -rf "$THEME_DST"

  if [ -f "$QUIT_WAIT_DST" ] || [ -f "$QUIT_WAIT_SCRIPT_DST" ]; then
    c_info "移除 systemd 单元与配套脚本"
    run rm -f "$QUIT_WAIT_DST" "$QUIT_WAIT_SCRIPT_DST"
    if [ "$DRY_RUN" -eq 0 ]; then
      rmdir --ignore-fail-on-non-empty "$(dirname "$QUIT_WAIT_DST")" 2>/dev/null || true
    fi
    run systemctl daemon-reload
  fi

  run rm -rf "$STATE_DIR"
  c_ok "卸载完成"
}

# ---------------------------- 主流程 ----------------------------
if [ "$DO_UNINSTALL" -eq 1 ]; then
  [ "$DRY_RUN" -eq 1 ] && c_info "== 卸载（dry-run）==" || c_info "== 卸载 =="
  uninstall_theme
else
  [ "$DRY_RUN" -eq 1 ] && c_info "== 安装（dry-run）==" || c_info "== 安装 =="
  check_environment
  install_theme
  echo
  c_ok "主题已安装: $THEME_DST"
  if [ "$env_warnings" -gt 0 ]; then
    echo
    c_warn "上面有 $env_warnings 项环境提示需要处理，否则开机看不到主题"
  fi
  echo
  c_info "调试: sudo plymouthd --debug --debug-file=/tmp/plymouth-debug.log --no-daemon --mode=boot"
  c_info "卸载: sudo $0 --uninstall"
fi
