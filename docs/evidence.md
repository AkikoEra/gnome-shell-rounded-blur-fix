# 实测记录

> 2026-10-17 排查全过程的原始记录。环境信息已脱敏（用户名/主机名/IP 均为占位）。

## 环境

| 项 | 值 |
|---|---|
| 桌面 | GNOME Shell 51.0 |
| 会话 | Wayland（`loginctl show-session <id> -p Type` → `Type=wayland`） |
| XWayland | `:0 -rootless`（X11 应用经由它） |
| 扩展 | rounded-window-corners v51.0、blur-my-shell v74+，均 ACTIVE |

## 复现

用户报告：kitty / clash-verge / Hermes（三者均为 Wayland 原生窗口）
窗口化时模糊消失、最大化恢复；微信（XWayland）不受影响。

枚举窗口时的关键观察：

```
$ xwininfo -root -tree | grep -E '^\s+0x'
# 只出现 WeChat、ToDesk、awesun 等 X11 客户端
# kitty / clash / hermes 不在 X 树中 → 确认为 Wayland 原生窗口
```

## 排查路径（含死胡同）

### 死胡同 1：GNOME Shell D-Bus Eval

```
$ gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell \
    --method org.gnome.Shell.Eval '1+1'
(false, '')
```

`unsafe-mode` 已为 `true` 仍被拒。GNOME 51 锁死 Eval，无法注入运行时诊断代码。

### 死胡同 2：portal 截图

```
$ gdbus call --session --dest org.freedesktop.portal.Desktop \
    --object-path /org/freedesktop/portal/desktop \
    --method org.freedesktop.portal.Screenshot.Screenshot "" "{'interactive': <false>}"
# 返回 request path，但 Response 信号永远不来
```

journalctl 显示 shell 内部失败：

```
cogl_texture_2d_new_with_size: assertion 'width >= 1' failed
```

且 gdbus 调用方退出即取消请求。常驻 gjs 客户端接信号亦超时。截图路线放弃。

### 死胡同 3：新扩展目录不被发现

```
$ gnome-extensions enable hermes-diag@local
扩展"hermes-diag@local"不存在
```

新建扩展目录不被已运行的 shell 实时扫描。

### 死胡同 4：ReloadExtension 是空接口

```
$ gdbus introspect --session --dest org.gnome.Shell.Extensions ... 
      ReloadExtension(in  s uuid);      ← introspection 里有声明

$ gdbus call ... --method org.gnome.Shell.Extensions.ReloadExtension '...'
错误：...Method ReloadExtension is not implemented   ← 实际未实现
```

### 死胡同 5（决定性实验）：改源码后禁用/启用不重载模块

向扩展 `enable()` 注入**故意的语法错误**后执行 disable + enable：

```
$ gnome-extensions disable rounded-window-corners@ztrahmet.github.io
$ gnome-extensions enable  rounded-window-corners@ztrahmet.github.io

$ gdbus call ... GetExtensionErrors 'rounded-window-corners@ztrahmet.github.io'
(@as [],)                      ← 无任何报错
$ ... GetExtensionInfo ... | grep state
'state': <2.0>                 ← ACTIVE，跑的还是旧缓存代码
```

**结论：GNOME 45+ ESM 模块缓存按 URL 永久缓存，改扩展源码必须重新登录。**
（所有测试性修改均已还原，仅保留最终补丁。）

## 根因定位

读上游 `lib/windowTracker.js` 发现 `_effectTarget()` 的分叉：

```js
if (actor.metaWindow.get_client_type() !== Meta.WindowClientType.X11)
    return actor;                    // Wayland → window actor 本身 ← 元凶
const surface = findSurface(actor);  // X11 → surface 子节点
```

BMS 侧确认模糊 widget 是 window actor 的子节点：

```js
// blur-my-shell applications.js:236
window_actor.set_child_below_sibling(meta_window.blur_actor, null);
// blur widget 名: 'bms-application-blurred-widget'（applications.js:351）
```

上游只对非最大化窗口应用圆角（`_shouldRound()` 跳过 maximized/fullscreen），
解释了"只在窗口化复现"。

## mutter 51 源码验证

拉取 `meta-window-actor-wayland.c`（tag 51.0）：

```c
// init: surface 容器是 window actor 的子节点
self->surface_container = surface_container_new (META_WINDOW_ACTOR (self));
clutter_actor_add_child (CLUTTER_ACTOR (self),
                         CLUTTER_ACTOR (self->surface_container));

// surface 提交时: surface actor 是容器的子节点（即 window actor 的孙节点）
clutter_actor_insert_child_at_index (container, surface_actor, index);
```

GType 名确认：

```
$ strings /usr/lib/libmutter-51.so.0.0.0 | grep -E '^MetaSurface(Container)?Actor' | sort -u
MetaSurfaceActor
MetaSurfaceActorWayland
MetaSurfaceContainerActorWayland
```

**推翻上游隐含假设**：Wayland 有 surface actor，只是嵌套在容器内。

## 修复与验证

补丁两处（64 行 diff）：

1. `_effectTarget()`：删除 Wayland 特判，统一走 `findSurface()`（递归查找可穿过容器）
2. 等待逻辑：同时监听 window actor 与 `MetaSurfaceContainerActor` 的 `child-added`

```bash
# 语法校验
$ cp windowTracker.js /tmp/wt-check.mjs && node --check /tmp/wt-check.mjs && echo SYNTAX-OK
SYNTAX-OK
```

用户重新登录后确认：**窗口化模糊恢复，与圆角共存**。

## 排查中顺手发现

- blur-my-shell 黑名单匹配键是 `WM_CLASS`（`xprop WM_CLASS` 获取，如 `wechat`）
- static 模式下不透明应用叠窗口时圆角处露壁纸色——是 static 的固有特性，非 bug
- 用户机器 `~/.env` 中 `GH_TOKEN` 仅为注释占位符（无真实凭证）

## 经验总结

1. **先查上游代码分叉点**，比逐个禁用扩展猜更快——症状的"会话类型相关性"直接指向 X11/Wayland 分支
2. **注入语法错误做对照实验**是验证"代码有没有被加载"的决定性手段
3. GNOME Shell 运行时诊断的三条路（Eval / 截图 / 新扩展）在 51 上全被封死，**源码审计 > 运行时探测**
4. mutter 源码（GitHub tag 51.0）是验证 actor 树结构的唯一可靠来源
