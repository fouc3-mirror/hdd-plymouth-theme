#!/usr/bin/env bash
# extract-frames.sh — 把 HDD 开机动画 mp4 转成 Plymouth 主题用的 PNG 帧序列
#
# 用法:
#   ./extract-frames.sh [输入mp4] [输出目录] [fps] [宽x高]
# 默认:
#   ./extract-frames.sh src/HDD开机动画1.mp4 theme/hdd-boot/frames 20 1280x720
#
# 说明:
#   - fps 建议 15-30；帧越多 → 启动时 plymouth 解码/占用内存越大
#     (720p@20fps ≈ 182 帧 ≈ 700MB 解码内存；内存吃紧可改 960x540 或 15fps)
#   - 分辨率影响显示清晰度（黑底动画压缩效果好，PNG 体积不大）

set -euo pipefail

SRC="${1:-src/HDD开机动画1.mp4}"
OUT="${2:-theme/hdd-boot/frames}"
FPS="${3:-20}"
RES="${4:-1280x720}"

if [ ! -f "$SRC" ]; then
  echo "错误: 输入文件不存在: $SRC" >&2
  exit 1
fi

mkdir -p "$OUT"
rm -f "$OUT"/frame-*.png

W="${RES%x*}"
H="${RES#*x}"

echo "==> $SRC -> $OUT  ($RES, ${FPS}fps)"
ffmpeg -y -v error -stats -i "$SRC" \
  -vf "fps=${FPS},scale=${W}:${H}:flags=lanczos,format=rgb24" \
  -start_number 1 \
  "$OUT/frame-%04d.png"

COUNT=$(ls "$OUT"/frame-*.png 2>/dev/null | wc -l)
if [ "$COUNT" -eq 0 ]; then
  echo "错误: 没有生成任何帧" >&2
  exit 1
fi

DUR=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$SRC")
echo "完成: $COUNT 帧 (视频 ${DUR}s, ${FPS}fps => ${COUNT}帧)"
echo "磁盘占用: $(du -sh "$OUT" | cut -f1)"

# 同步主题脚本里的 TOTAL_FRAMES，避免换 fps/分辨率后忘记改
SCRIPT="$(dirname "$OUT")/hdd-boot.script"
if [ -f "$SCRIPT" ]; then
  OLD=$(sed -n 's/^TOTAL_FRAMES  *= *\([0-9]*\).*/\1/p' "$SCRIPT" | head -1)
  if [ "$OLD" != "$COUNT" ]; then
    LAST=$(printf '%04d' "$COUNT")
    sed -i "s|^TOTAL_FRAMES  *= *[0-9]*;.*|TOTAL_FRAMES  = ${COUNT};             # frame-0001.png ... frame-${LAST}.png|" "$SCRIPT"
    echo "已同步 $SCRIPT: TOTAL_FRAMES ${OLD} -> ${COUNT}"
  else
    echo "TOTAL_FRAMES 已是 ${COUNT}，无需修改"
  fi
fi
