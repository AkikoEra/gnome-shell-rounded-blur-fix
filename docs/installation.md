# 安装指南

## 前置条件

| 组件 | 要求 | 检查命令 |
|---|---|---|
| GNOME Shell | 51（其他版本未实测） | `gnome-shell --version` |
| rounded-window-corners | v51.0（[ztrahmet](https://github.com/ztrahmet/rounded-window-corners)） | 见下方 |
| blur-my-shell | v74+（[aunetx](https://github.com/aunetx/blur-my-shell)） | GNOME Extensions |
| 会话类型 | Wayland（X11 下无副作用但也无必要） | `echo $XDG_SESSION_TYPE` |

检查扩展版本：

```bash
cat ~/.local/share/gnome-shell/extensions/rounded-window-corners@ztrahmet.github.io/metadata.json \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('version-name'))"
```

> rounded-window-corners 没有偏好设置界面（"No preferences"），
> 若未安装请从 [GNOME Extensions](https://extensions.gnome.org/extension/7098/) 或 GitHub Releases 获取。

## 安装

```bash
git clone https://github.com/AkikoEra/gnome-shell-rounded-blur-fix.git
cd gnome-shell-rounded-blur-fix

# 1. 先看看会不会成功（不改任何文件）
./scripts/install.sh --dry-run

# 2. 正式安装（自动备份原文件为 windowTracker.js.bak-<时间戳>）
./scripts/install.sh

# 3. 验收
./scripts/verify.sh
```

全程**不需要 sudo**——只改 `~/.local/share/gnome-shell/extensions/` 下的用户级文件。

### 自定义扩展安装路径

如果你的扩展不在默认位置：

```bash
EXT_DIR=/path/to/rounded-window-corners@ztrahmet.github.io ./scripts/install.sh
```

## 重新登录（必做）

**打完补丁必须注销并重新登录**（或重启机器）。

GNOME 45+ 把扩展作为 ES 模块加载并永久缓存于 shell 进程内；GNOME 51 的
`ReloadExtension` D-Bus 接口未实现、`Eval` 接口被锁死，因此没有热重载途径。
Alt+F2 → `r` 仅在 X11 会话有效，Wayland 下 gnome-shell 就是合成器本身，重启即杀会话。

> ⚠️ 重新登录前请保存所有工作。已实测确认：禁用/启用扩展、`ReloadExtension`、
> 修改后 touch 目录，均**不会**加载新代码。

## 验证修复

重新登录后：

1. 运行 `./scripts/verify.sh`，应显示补丁已应用 + 两个扩展 ACTIVE
2. 打开任意 Wayland 应用（kitty、GNOME Terminal、Electron 应用均可），**窗口化**放置
3. 应同时看到：圆角生效 + 窗口内有模糊
4. 对比测试：`xeyes` 或微信（XWayland）行为应与打补丁前完全一致

## blur-my-shell 的模糊模式

本补丁与 static / dynamic 两种模式均兼容：

| 模式 | 模糊内容 | 适用 |
|---|---|---|
| `dynamic`（推荐） | 窗口后面的**实时画面** | 窗口叠窗口时效果真实 |
| `static` | **壁纸**的模糊 | 性能敏感场景 |

切换命令：

```bash
# 切到 static
dconf write /org/gnome/shell/extensions/blur-my-shell/applications/static-blur true
# 切回 dynamic
dconf write /org/gnome/shell/extensions/blur-my-shell/applications/static-blur false

# 切换后需要重启扩展（这个可以热操作）
gnome-extensions disable blur-my-shell@aunetx && gnome-extensions enable blur-my-shell@aunetx
```

> **static 模式的一个固有现象**（非 bug）：不透明应用（如微信、部分 Electron 应用）
> 叠在深色窗口上时，圆角切角处会露出壁纸模糊色。因为 static 模式画的是壁纸而非真实背景。
> 解法见 [troubleshooting.md](troubleshooting.md#static-圆角)。

## 还原

```bash
./scripts/revert.sh
# 然后重新登录
```

还原优先使用反向补丁（不依赖备份时间戳），失败时自动回退到最新的
`windowTracker.js.bak-*` 备份。若备份也丢失，从 GitHub 重装 rounded-window-corners 即可。

## 上游更新之后

rounded-window-corners 发布新版后，重装扩展会覆盖补丁。重新执行：

```bash
./scripts/install.sh
```

- 上下文匹配 → 直接打上
- 上下文漂移 → `install.sh` 报错并还原，不会静默破坏。此时提 issue 附上新版 `windowTracker.js`
