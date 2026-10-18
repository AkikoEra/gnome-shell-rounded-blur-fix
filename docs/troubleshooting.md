# 排障手册

按症状查找。每条给出：现象 → 原因 → 解法。

---

## 打完补丁没变化

**现象**：`install.sh` 成功，但窗口化模糊依然消失。

**原因**：GNOME 51 无法热重载扩展模块（ESM 缓存 + `ReloadExtension` 未实现 + `Eval` 锁死）。

**解法**：注销并重新登录（或重启）。这是最常见的"没生效"原因——**必须重新登录**。

验证补丁是否真的加载了：

```bash
./scripts/verify.sh
```

若 verify 显示补丁已应用但行为不对，检查 gnome-shell 是否报扩展加载错误：

```bash
journalctl --user _COMM=gnome-shell -b | grep -i 'rounded-window-corners'
```

出现 JS 语法错误 → 立即 `./scripts/revert.sh` 还原。

---

## install.sh 报"补丁无法应用"

**现象**：`patch: **** hunks failed` 或 `malformed patch`。

**原因**：上游 rounded-window-corners 更新了 `windowTracker.js`，补丁上下文漂移。

**解法**：

1. `install.sh` 已自动还原，扩展处于原始状态，桌面不受影响
2. 确认扩展版本：`cat .../metadata.json | python3 -c "import json,sys; print(json.load(sys.stdin)['version-name'])"`
3. 提 issue，附上你的 `lib/windowTracker.js` 全文

---

## 扩展完全没圆角了

**现象**：打补丁 + 重新登录后，所有窗口变方形。

**原因**：effect 挂载失败（surface 查找失败时上游逻辑会跳过该窗口的圆角）。

**解法**：

```bash
journalctl --user _COMM=gnome-shell -b | grep -iE 'rounded|effect' | tail -20
./scripts/revert.sh
# 重新登录，确认原始版本圆角正常，再提 issue
```

---

## 圆角处露出壁纸色（叠窗口时）

<a id="static-圆角"></a>
**现象**：不透明应用（微信、部分 Electron 应用）叠在深色窗口上时，圆角切角处出现浅色/壁纸色斑块。

**原因**：这是 **static 模式的固有现象，不是本补丁的 bug**。static 模式把壁纸模糊画在窗口后面，
而不是采样真实背景；圆角切掉窗口边角后露出的就是壁纸模糊色。

**解法**（三选一）：

```bash
# 方案 1：切回 dynamic 模式（推荐，效果最真实）
dconf write /org/gnome/shell/extensions/blur-my-shell/applications/static-blur false
gnome-extensions disable blur-my-shell@aunetx && gnome-extensions enable blur-my-shell@aunetx

# 方案 2：把该应用加入 blur-my-shell 黑名单（先看当前黑名单）
dconf read /org/gnome/shell/extensions/blur-my-shell/applications/blacklist
dconf write /org/gnome/shell/extensions/blur-my-shell/applications/blacklist "['原列表各项...', 'wm-class名']"

# 方案 3：对该应用禁用圆角（等上游提供 per-app 设置）
```

获取应用的 WM_CLASS（黑名单匹配键）：

```bash
xprop WM_CLASS | head -1   # 然后点目标窗口
```

---

## 模糊和圆角共存后性能下降

**现象**：窗口化应用多时掉帧。

**原因**：dynamic 模式对每个窗口实时采样背景，窗口多时代价线性增长。

**解法**：切 static 模式（见上），或降低 sigma/亮度：

```bash
dconf write /org/gnome/shell/extensions/blur-my-shell/applications/sigma 5   # 默认 7
```

---

## 重新登录后扩展显示 INACTIVE

**现象**：`gnome-extensions info` 显示 rounded-window-corners INACTIVE。

**原因**：扩展被手动禁用，或加载出错。

**解法**：

```bash
gnome-extensions enable rounded-window-corners@ztrahmet.github.io
gdbus call --session --dest org.gnome.Shell.Extensions \
  --object-path /org/gnome/Shell/Extensions \
  --method org.gnome.Shell.Extensions.GetExtensionErrors \
  'rounded-window-corners@ztrahmet.github.io'
```

errors 非空 → 按提示还原或提 issue。

---

## 微信（XWayland）行为异常

**现象**：打补丁后 X11 应用的圆角/模糊变了。

**预期**：本补丁对 X11 窗口**零行为变化**（只是让 Wayland 走同一条已验证的路径）。

**解法**：这是回归 bug，请 `./scripts/revert.sh` 还原并提 issue，附
`xprop WM_CLASS` 输出与 journalctl 日志。

---

## 彻底重来

任何情况下想回到干净状态：

```bash
./scripts/revert.sh          # 还原源码
# 若仍有异常，直接重装上游扩展（GNOME Extensions 网页 或 AUR）
# 最后重新登录
```
