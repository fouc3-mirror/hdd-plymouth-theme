#!/usr/bin/env bash
# 重新编译离线校验器（不需要 root，也不需要装 plymouth）
#
#   ./check <theme.script>            语法解析（用 plymouth 自己的 script 解析器）
#   ./run stub.script <theme.script> <场景号>   用 stub 运行时把脚本真正跑一遍
#                                     场景: 1=未播完+quit  2=播完一轮  3=按键+启动完成  4=日志滚动
#
# 原理: 直接编译 plymouth 仓库里的 script 插件解析器/执行器 + 少量 libply。
#       仓库里的 check / run 是预编译好的，一般不用跑这个脚本。

set -euo pipefail
cd "$(dirname "$0")"

SRC=plymouth-src
if [ ! -d "$SRC" ]; then
  echo "==> 拉取 plymouth 源码（sparse，只取需要的目录）"
  git clone --depth 1 --filter=blob:none --sparse \
    https://gitlab.freedesktop.org/plymouth/plymouth.git "$SRC"
  ( cd "$SRC" && git sparse-checkout set src/plugins/splash/script src/libply )
fi

S="$SRC/src/plugins/splash/script"
L="$SRC/src/libply"
CORE="$S/script-parse.c $S/script-scan.c $S/script-object.c $S/script-debug.c $S/script-execute.c $S/script.c"
LIBPLY="$L/ply-list.c $L/ply-hashtable.c $L/ply-bitarray.c $L/ply-logger.c $L/ply-utils.c $L/ply-secure-boot.c"

echo "==> 编译 check"
# shellcheck disable=SC2086
gcc -O2 -D_GNU_SOURCE -I"$S" -I"$L" -o check main.c $CORE $LIBPLY -lm

echo "==> 编译 run"
# shellcheck disable=SC2086
gcc -O2 -D_GNU_SOURCE -I"$S" -I"$L" -o run run.c $CORE $LIBPLY -lm

echo "OK: ./check 和 ./run 已重新编译"
