# 贡献指南

感谢参与。所有提交需通过发布前敏感信息扫描。

## 开发流程

```bash
git clone https://github.com/AkikoEra/gnome-shell-rounded-blur-fix.git
cd gnome-shell-rounded-blur-fix

# 改动脚本后，用可覆盖的扩展目录做测试（不动真实扩展）
EXT_DIR=/tmp/fake-ext ./scripts/install.sh

# 发布前必跑
bash scripts/pre-commit-check.sh
```

## 提交规范

使用 Conventional Commits：

```
<type>: <简述>

type ∈ feat | fix | docs | style | refactor | perf | test | build | ci | chore
```

示例：

- `feat: 支持监听 surface 容器的多级 child-added`
- `fix: 还原逻辑改用反向补丁，摆脱备份时间戳依赖`
- `docs: 排障手册补充 WM_CLASS 获取方法`

## PR 要求

| 检查项 | 说明 |
|---|---|
| 补丁上下文 | 修改 `patches/*.patch` 时，必须基于 rounded-window-corners **v51.0** 原始文件生成 diff |
| 语法校验 | `node --check` 通过（临时复制为 `.mjs`） |
| 实测 | 说明在哪个 GNOME Shell 版本 + 会话类型下验证过 |
| 隐私 | 不得包含真实 IP / 主机名 / 用户名 / 代号（跑 `pre-commit-check.sh`） |
| 双语 | README 改动需同步 `README.md` 与 `README_en.md` |

## 补丁文件的生成方式

```bash
# 基于原始文件与修改后文件生成（a/ b/ 前缀，供 patch -p1 使用）
diff -u --label a/lib/windowTracker.js --label b/lib/windowTracker.js \
  windowTracker.js.orig windowTracker.js > patches/0001-rounded-blur-coexist.patch
```

不要直接编辑 patch 文件——用 `install.sh --dry-run` 验证可应用性。

## 新增排障条目

在 `docs/troubleshooting.md` 按既有格式追加（现象 → 原因 → 解法），
每条给出可复制的命令。

## Issue

- **bug**：附 `./scripts/verify.sh` 输出、`gnome-shell --version`、会话类型、扩展版本
- **上游更新导致补丁失效**：附新版 `lib/windowTracker.js` 全文
- **安全问题**：见 [SECURITY.md](SECURITY.md)，勿公开提 issue

## 行为准则

就事论事，附证据，不臆断。
