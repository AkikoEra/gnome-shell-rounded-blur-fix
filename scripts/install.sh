#!/usr/bin/env bash
# 把 rounded-blur 共存补丁应用到已安装的 rounded-window-corners 扩展
# 用法: ./scripts/install.sh [--dry-run]
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
MARKER='MetaSurfaceContainerActor'   # 仅存在于补丁后的代码中

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

echo ""
echo "  gnome-shell-rounded-blur-fix 安装器"
echo "  ─────────────────────────────────────"
echo ""

# 1. 前置检查 ---------------------------------------------------------------
[[ -f "$PATCH_FILE" ]] || { err "找不到补丁文件: $PATCH_FILE"; exit 1; }
[[ -f "$TARGET_FILE" ]] || {
  err "找不到目标扩展: $TARGET_FILE"
  info "请先安装 rounded-window-corners 扩展（GNOME Extensions / AUR / GitHub Releases）"
  exit 1
}
ok "扩展目录已找到"

# 2. 版本检查 ---------------------------------------------------------------
VERSION=$(python3 -c "import json;print(json.load(open('$EXT_DIR/metadata.json')).get('version-name',''))" 2>/dev/null || echo "")
if [[ "$VERSION" == "51.0" ]]; then
  ok "扩展版本: v51.0（补丁目标版本）"
elif [[ -n "$VERSION" ]]; then
  warn "扩展版本 v$VERSION，补丁针对 v51.0 制作。可以继续，但上下文可能不匹配。"
else
  warn "无法读取扩展版本，继续（patch 可能失败）"
fi

# 3. 幂等检查 ---------------------------------------------------------------
if grep -q "$MARKER" "$TARGET_FILE"; then
  ok "补丁已应用过，无需重复操作。"
  info "如需重装: ./scripts/revert.sh 后再运行本脚本"
  exit 0
fi

# 4. 备份 -------------------------------------------------------------------
TS=$(date +%Y%m%d-%H%M%S)
BACKUP="$TARGET_FILE.bak-$TS"

if [[ $DRY_RUN -eq 1 ]]; then
  info "[dry-run] 将备份到: $BACKUP"
  if patch -p1 -d "$EXT_DIR" --dry-run < "$PATCH_FILE" > /dev/null 2>&1; then
    ok "[dry-run] 补丁可以干净地应用"
  else
    err "[dry-run] 补丁无法应用（上游文件可能已变化）"
    patch -p1 -d "$EXT_DIR" --dry-run < "$PATCH_FILE" 2>&1 | head -5
    exit 1
  fi
  exit 0
fi

cp "$TARGET_FILE" "$BACKUP" || { err "备份失败，中止"; exit 1; }
ok "已备份原文件 → $(basename "$BACKUP")"

# 5. 应用补丁 ---------------------------------------------------------------
if patch -p1 -d "$EXT_DIR" --forward < "$PATCH_FILE"; then
  ok "补丁已应用"
else
  err "补丁应用失败，还原备份"
  cp "$BACKUP" "$TARGET_FILE"
  info "请提交 issue 并附上你的 lib/windowTracker.js"
  exit 1
fi

# 6. 语法校验（可选） --------------------------------------------------------
if command -v node > /dev/null 2>&1; then
  TMP=$(mktemp --suffix=.mjs)
  cp "$TARGET_FILE" "$TMP"
  if node --check "$TMP" > /dev/null 2>&1; then
    ok "语法校验通过（node --check）"
  else
    err "语法校验失败，还原备份"
    cp "$BACKUP" "$TARGET_FILE"
    rm -f "$TMP"
    exit 1
  fi
  rm -f "$TMP"
else
  info "未安装 node，跳过语法校验（可手动用 gjs 验证）"
fi

# 7. 收尾提醒 ---------------------------------------------------------------
echo ""
ok "安装完成。"
echo ""
warn "必须重新登录（或重启机器）补丁才会生效 —— GNOME 51 无法热重载扩展模块。"
info "验收: ./scripts/verify.sh"
info "还原: ./scripts/revert.sh"
echo ""
