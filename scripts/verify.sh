#!/usr/bin/env bash
# 端到端验收：补丁状态、语法、扩展启用状态、模糊模式
# 用法: ./scripts/verify.sh
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[i]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }

EXT_DIR="${EXT_DIR:-$HOME/.local/share/gnome-shell/extensions/rounded-window-corners@ztrahmet.github.io}"
TARGET_FILE="$EXT_DIR/lib/windowTracker.js"
MARKER='MetaSurfaceContainerActor'
BMS_UUID="blur-my-shell@aunetx"
RWC_UUID="rounded-window-corners@ztrahmet.github.io"

FAILS=0

echo ""
echo "  gnome-shell-rounded-blur-fix 验收"
echo "  ─────────────────────────────────────"
echo ""

# 1. 会话类型 ----------------------------------------------------------------
SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
if [[ "$SESSION_TYPE" == "wayland" ]]; then
  ok "会话类型: Wayland（补丁生效的目标场景）"
elif [[ "$SESSION_TYPE" == "x11" ]]; then
  info "会话类型: X11（上游本就正确，补丁无副作用）"
else
  info "会话类型: 未知（$SESSION_TYPE）"
fi

# 2. 扩展文件与补丁状态 ------------------------------------------------------
if [[ -f "$TARGET_FILE" ]]; then
  ok "扩展目录已找到"
else
  err "找不到 rounded-window-corners 扩展"
  FAILS=$((FAILS+1))
fi

if grep -q "$MARKER" "$TARGET_FILE" 2>/dev/null; then
  ok "补丁已应用（检测到 surface 挂载点代码）"
else
  warn "补丁未应用（可能已还原，或上游更新覆盖）"
fi

# 3. 语法校验 ----------------------------------------------------------------
if command -v node > /dev/null 2>&1 && [[ -f "$TARGET_FILE" ]]; then
  TMP=$(mktemp --suffix=.mjs)
  cp "$TARGET_FILE" "$TMP"
  if node --check "$TMP" > /dev/null 2>&1; then
    ok "语法校验通过"
  else
    err "语法校验失败 —— 扩展可能无法加载，立即运行 ./scripts/revert.sh"
    FAILS=$((FAILS+1))
  fi
  rm -f "$TMP"
fi

# 4. 扩展启用状态 ------------------------------------------------------------
if command -v gnome-extensions > /dev/null 2>&1; then
  for UUID in "$RWC_UUID" "$BMS_UUID"; do
    STATE=$(gnome-extensions info "$UUID" 2>/dev/null | grep -E 'State:' | awk '{print $2}')
    NAME=${UUID%%@*}
    case "$STATE" in
      ACTIVE)    ok "$NAME: ACTIVE" ;;
      INACTIVE)  warn "$NAME: 已安装但未启用（gnome-extensions enable $UUID）" ;;
      "")        warn "$NAME: 未安装" ;;
      *)         info "$NAME: $STATE" ;;
    esac
  done
fi

# 5. blur-my-shell 模糊模式 -------------------------------------------------
STATIC=$(dconf read /org/gnome/shell/extensions/blur-my-shell/applications/static-blur 2>/dev/null | tr -d "'" || echo "")
if [[ "$STATIC" == "true" ]]; then
  warn "blur-my-shell 当前为 static（壁纸）模式 —— 与圆角共存没问题，但叠窗口时圆角处会露壁纸色"
  info "切回 dynamic: dconf write /org/gnome/shell/extensions/blur-my-shell/applications/static-blur false && gnome-extensions disable $BMS_UUID && gnome-extensions enable $BMS_UUID"
elif [[ "$STATIC" == "false" ]]; then
  ok "blur-my-shell 当前为 dynamic（实时采样）模式"
else
  info "blur-my-shell 模糊模式未设置（使用默认值）"
fi

# 6. 收尾 --------------------------------------------------------------------
echo ""
if [[ $FAILS -eq 0 ]]; then
  ok "验收通过。若刚打完补丁，请确认已重新登录。"
  echo ""
  info "最终验证（手动）: 打开任意 Wayland 应用窗口化放置，应同时看到圆角与模糊"
else
  err "验收有 $FAILS 项失败，参见 docs/troubleshooting.md"
  echo ""
  exit 1
fi
