#!/bin/sh
# =====================================================================
#  plymouth-quit-wait.sh — 让 plymouth 至少等到动画播完一轮再退出
#
#  由 /etc/systemd/system/plymouth-quit.service.d/plymouth-quit-wait.conf
#  在 ExecStartPre 里调用。只推迟 "plymouth quit"，不推迟系统启动本身。
#
#  原理: plymouthd 启动时写 /run/plymouth/pid，算出距其启动已过多少秒，
#        只补足不足 WANT 的部分 —— 快启动才真正等待，慢启动（HDD）不白等。
#        可用环境变量 PLYMOUTH_WAIT_SECONDS 覆盖等待时长（默认 9.5）。
#
#  安装: sudo ./install.sh --with-quit-wait   （见项目根目录 install.sh）
# =====================================================================

WANT="${PLYMOUTH_WAIT_SECONDS:-9.5}"
PIDFILE="/run/plymouth/pid"

# plymouthd 没跑（没启用 splash）就不用等
[ -f "$PIDFILE" ] || exit 0

start=$(stat -c %Y "$PIDFILE" 2>/dev/null) || exit 0
now=$(date +%s)

left=$(awk -v w="$WANT" -v s="$start" -v n="$now" \
        'BEGIN { d = w - (n - s); if (d < 0) d = 0; printf "%.1f", d }')

# 只补足不足的那部分
[ "${left%.*}" -gt 0 ] && sleep "$left"

exit 0
