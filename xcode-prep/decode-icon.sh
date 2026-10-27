#!/bin/sh
# 把 base64 文本还原成 AppIcon 1024 PNG（GitHub MCP 不能直接推二进制，所以用这个办法）
set -e
cd "$(dirname "$0")"
base64 -d -i GaoQian/Assets.xcassets/AppIcon.appiconset/icon-1024.png.b64 -o GaoQian/Assets.xcassets/AppIcon.appiconset/icon-1024.png
echo "icon restored: GaoQian/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
