#!/usr/bin/env bash
# 发布前敏感信息扫描（IP / 云凭证 / 密钥 / 主机名 / 内部代号 / 邮箱）
# 用法: bash scripts/pre-commit-check.sh
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[i]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
DENYLIST="$REPO_DIR/.name-denylist"

echo ""
echo "  发布前敏感信息扫描"
echo "  ─────────────────────────────────────"
echo ""

FAILS=0

# 1. 真实公网 IP -------------------------------------------------------------
info "扫描真实公网 IP..."
IP_HITS=$(grep -rnE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' \
  --include='*.md' --include='*.sh' --include='*.patch' --include='*.txt' \
  --exclude-dir=.git "$REPO_DIR" 2>/dev/null \
  | grep -vE '\b(127\.0\.0\.1|0\.0\.0\.0|255\.255\.255|192\.168\.|10\.[0-9]+\.|172\.(1[6-9]|2[0-9]|3[01])\.)' \
  || true)
if [[ -n "$IP_HITS" ]]; then
  echo "$IP_HITS"
  err "发现疑似真实公网 IP，请确认是否为示例地址"
  FAILS=$((FAILS+1))
else
  ok "无真实公网 IP"
fi

# 2. 云厂商凭证 -------------------------------------------------------------
info "扫描云厂商凭证..."
CLOUD_HITS=$(grep -rnE '(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|LTAI[0-9A-Za-z]{12,20}|GOOG[0-9A-Za-z]{10,50}|sk-[a-zA-Z0-9]{20,})' \
  --include='*.md' --include='*.sh' --include='*.example' --include='*.txt' \
  --exclude-dir=.git "$REPO_DIR" 2>/dev/null || true)
if [[ -n "$CLOUD_HITS" ]]; then
  echo "$CLOUD_HITS"
  err "发现疑似云厂商 AccessKey / SecretKey / API Key"
  FAILS=$((FAILS+1))
else
  ok "无云厂商凭证"
fi

# 3. 常见密钥格式 -----------------------------------------------------------
info "扫描密钥文件内容..."
KEY_HITS=$(grep -rnE '(BEGIN (RSA|OPENSSH|EC|DSA|PGP) PRIVATE KEY|ssh-(rsa|ed25519|dss) [A-Za-z0-9+/]{40,}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}|xox[baprs]-[A-Za-z0-9-]{10,})' \
  --include='*.md' --include='*.sh' --include='*.txt' --include='*.pem' \
  --exclude-dir=.git "$REPO_DIR" 2>/dev/null || true)
if [[ -n "$KEY_HITS" ]]; then
  echo "$KEY_HITS"
  err "发现疑似私钥 / GitHub Token / Slack Token"
  FAILS=$((FAILS+1))
else
  ok "无密钥/token 内容"
fi

# 4. 内部代号黑名单 ----------------------------------------------------------
if [[ -f "$DENYLIST" ]]; then
  info "扫描内部代号（.name-denylist）..."
  while IFS= read -r name; do
    [[ -z "$name" || "$name" =~ ^[[:space:]]*# ]] && continue
    if grep -rniF "$name" --exclude-dir=.git --exclude='.name-denylist' "$REPO_DIR" > /dev/null 2>&1; then
      echo "$name"
      err "发现内部代号/人名/主机名，来自 .name-denylist"
      FAILS=$((FAILS+1))
    fi
  done < "$DENYLIST"
  [[ $FAILS -eq 0 ]] && ok "内部代号检查通过"
else
  warn "未找到 .name-denylist，跳过内部代号检查"
fi

# 5. 邮箱 --------------------------------------------------------------------
info "扫描邮箱地址..."
EMAIL_HITS=$(grep -rnE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' \
  --include='*.md' --include='*.sh' --include='*.example' \
  --exclude-dir=.git --exclude='LICENSE' "$REPO_DIR" 2>/dev/null \
  | grep -vE '(noreply|example\.com|user@host|<.*>|@ztrahmet\.github\.io|[a-z-]+@([a-z0-9-]+\.)*github\.io)' || true)
if [[ -n "$EMAIL_HITS" ]]; then
  echo "$EMAIL_HITS"
  warn "发现邮箱地址，请人工确认是否可公开"
else
  ok "无可疑邮箱"
fi

# 结论 -----------------------------------------------------------------------
echo ""
if [[ $FAILS -eq 0 ]]; then
  ok "发布前检查通过"
  echo ""
  info "下一步: git add . && git commit -m 'feat: <简述>' && git push"
else
  err "发现 $FAILS 处风险，请处理后再发布"
  echo ""
  exit 1
fi
