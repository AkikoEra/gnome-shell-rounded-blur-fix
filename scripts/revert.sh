#!/usr/bin/env bash
# 还原 rounded-window-corners 扩展到打补丁前的原始状态
# 用法: ./scripts/revert.sh
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[i]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PATCH_FILE="$REPO_DIR/patches/0001-rounded-blur-coexist.patch"
EXT_DIR="${EXT_DIR:-$HOME/.local/share/gnome-shell/extensions/rounded-window-corners@ztrahmet.github.io}"
TARGET_FILE="$EXT_DIR/lib/windowTracker.js"
MARKER='MetaSurfaceContainerActor'

echo ""
echo "  gnome-shell-rounded-blur-fix 还原器"
echo "  ─────────────────────────────────────"
echo ""

[[ -f "$TARGET_FILE" ]] || { err "找不到目标扩展: $TARGET_FILE"; exit 1; }

if ! grep -q "$MARKER" "$TARGET_FILE"; then
  ok "当前未应用补丁，无需还原。"
  exit 0
fi

# 优先用反向补丁（不依赖备份时间戳）；失败则回退到最新备份
if patch -p1 -d "$EXT_DIR" -R --dry-run < "$PATCH_FILE" > /dev/null 2>&1; then
  patch -p1 -d "$EXT_DIR" -R < "$PATCH_FILE" > /dev/null && ok "已通过反向补丁还原"
else
  LATEST_BAK=$(ls -t "$TARGET_FILE".bak-* 2>/dev/null | head -1)
  if [[ -n "$LATEST_BAK" ]]; then
    cp "$LATEST_BAK" "$TARGET_FILE" && ok "已从备份还原 → $(basename "$LATEST_BAK")"
  else
    err "反向补丁失败且找不到备份文件。请手动从 GitHub 重装扩展。"
    exit 1
  fi
fi

echo ""
warn "还原同样需要重新登录才会生效。"
echo ""
