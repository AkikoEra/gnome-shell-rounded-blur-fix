# 安全策略

## 适用范围

本仓库分发的内容：一个针对 rounded-window-corners v51.0 的源码补丁 + shell 安装/还原/验收脚本。
**不包含**任何凭证、令牌、网络配置。

## 支持版本

仅最新 `main` 分支。

## 报告漏洞

若你发现以下问题，请**勿**公开提 issue，改用 [GitHub Security Advisories](https://github.com/AkikoEra/gnome-shell-rounded-blur-fix/security/advisories/new) 私下报告：

- 补丁或脚本引入的提权 / 任意代码执行风险
- `install.sh` 在异常路径下破坏用户扩展文件且无法还原
- 脚本从不可信来源拉取并执行内容

报告内容要求：

- 受影响的脚本与行号
- 复现步骤（含 GNOME Shell 版本、会话类型、扩展版本）
- 预期影响与实际影响

## 响应流程

- 收到报告后 **7 天内**确认
- 修复发布后在 advisory 中公开致谢（除非你要求匿名）

## 安全设计说明

- 所有脚本仅操作 `~/.local/share/gnome-shell/extensions/` 下的用户级文件，不使用 sudo
- `install.sh` 修改前强制备份；补丁失败自动还原，不静默破坏
- 脚本不联网、不下载、不执行远端内容；补丁文件随仓库分发、可审计
- 发布前由 `scripts/pre-commit-check.sh` 扫描 IP / 密钥 / 代号 / 邮箱
