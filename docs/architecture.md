# 架构分析：为什么圆角会杀死模糊

> 本文是 2026-10-17 实际排查的沉淀。结论经过 mutter 51 源码与运行时行为双重验证。

## TL;DR

rounded-window-corners 对 Wayland 窗口把 shader effect 挂在 **window actor 本身**，
导致整个 actor（含 blur-my-shell 的模糊 widget）被重定向进离屏 buffer。
BACKGROUND 模式的模糊效果因此采样不到真实背景 → 窗口化时模糊消失。

## 两个扩展各自做什么

### blur-my-shell（应用模糊）

在 window actor 内部插入一个名为 `bms-application-blurred-widget` 的子 actor：

```
MetaWindowActor (Wayland)
├── bms-application-blurred-widget   ← BMS 插入，垫在最底层
│     └── Shell.BlurEffect (mode = BACKGROUND)
├── surface_container
│     └── MetaSurfaceActorWayland    ← 窗口真实贴图
└── ...
```

BACKGROUND 模式的关键性质：**采样 actor 背后的 framebuffer 内容**。
它要求自己正常地位于合成管线中、背后有真实画面可采样。

### rounded-window-corners（窗口圆角）

用 `RoundedCornersEffect`（`Clutter.ShaderEffect` 子类）给窗口做圆角 + 描边 + 投影。
ShaderEffect 的固有行为：把目标 actor **整体重定向到离屏 buffer**，对纹理着色后再合成回屏幕。

## 冲突的精确位置

上游 `lib/windowTracker.js` 的 `_effectTarget()`（v51.0 原始代码）：

```js
_effectTarget(actor, state) {
    if (actor.metaWindow.get_client_type() !== Meta.WindowClientType.X11)
        return actor;                        // Wayland → window actor 本身
    const surface = findSurface(actor);      // X11 → surface 子节点
    ...
}
```

| 窗口类型 | effect 挂载点 | 离屏重定向范围 | BMS 模糊 widget | 结果 |
|---|---|---|---|---|
| X11 | `MetaSurfaceActor` 子节点 | 只包住贴图 | 兄弟节点，不受影响 | ✅ 共存 |
| Wayland | `MetaWindowActor` 本身 | 整棵子树 | 被卷进离屏 buffer | ❌ 模糊失效 |

BACKGROUND 模式在离屏 buffer 内没有"背后的真实画面"可采样（buffer 里只有窗口自己），
模糊效果等同于对空内容操作 → 视觉上完全消失。

## 为什么只在窗口化时复现

上游 `_shouldRound()` 只对**非最大化/非全屏**窗口应用圆角：

```js
return !(win.maximizedHorizontally || win.maximizedVertically || win.fullscreen);
```

最大化时 effect 被移除 → window actor 恢复正常合成 → 模糊恢复。
这与实测症状（"全屏正常、窗口化不加载"）完全吻合，也反过来印证了根因。

## 为什么 X11 窗口（微信）没事

微信是 XWayland 窗口，走的是上游 X11 分支：effect 挂 `MetaSurfaceActor` 子节点，
离屏重定向只包住贴图，模糊 widget 作为兄弟节点毫发无损。

## mutter 51 的关键事实

上游隐含假设"Wayland 窗口没有 surface 子节点"——这是错的。
`src/compositor/meta-window-actor-wayland.c`（mutter 51.0）：

```c
// window actor 的 init 中：
self->surface_container = surface_container_new (META_WINDOW_ACTOR (self));
clutter_actor_add_child (CLUTTER_ACTOR (self),
                         CLUTTER_ACTOR (self->surface_container));

// surface 提交时：
clutter_actor_insert_child_at_index (container, surface_actor, index);
```

Wayland 的 surface actor 存在，只是**多嵌套了一层** `MetaSurfaceContainerActorWayland`：

```
MetaWindowActorWayland
└── MetaSurfaceContainerActorWayland   ← 孙节点的父容器
    └── MetaSurfaceActorWayland        ← 真正该挂 effect 的目标
```

上游的 `findSurface()` 本身是递归的、能穿过容器找到它，但：
1. Wayland 特判在 `findSurface` 之前就 return 了，永远走不到递归查找
2. surface 尚未提交时容器是空的，原"等待 surface 出现"逻辑只监听 window actor 的 `child-added`，
   而 Wayland 的 surface 是加到**容器**里的，这个监听永远不会触发

## 补丁做了什么

**改动 1 — 统一挂载点**（`_effectTarget`）：

删除 Wayland 特判，两类窗口都走 `findSurface()`。递归查找自动穿过 surface 容器。

**改动 2 — 监听容器**（等待 surface 出现的逻辑）：

surface 未提交时，同时监听 window actor 和 `MetaSurfaceContainerActor` 的 `child-added`，
任一触发即重新同步。

完整 diff 见 [`patches/0001-rounded-blur-coexist.patch`](../patches/0001-rounded-blur-coexist.patch)（64 行）。

## 为什么必须重新登录

实测确认（详见 [evidence.md](evidence.md)）：

- GNOME 45+ 扩展是 ESM 模块，import 缓存按 URL 永久缓存于进程内
- GNOME 51 的 `org.gnome.Shell.Extensions.ReloadExtension` D-Bus 方法**已声明但未实现**
- Shell 的 `org.gnome.Shell.Eval` 被锁死（unsafe-mode 开启也拒绝）
- 新扩展目录不被已运行的 shell 实时发现

结论：Wayland 会话下改扩展源码 = 重新登录（或重启机器）才生效。
Alt+F2 → r 仅限 X11 会话。

## 上游佐证

- [blur-my-shell#634](https://github.com/aunetx/blur-my-shell/issues/634)：
  "the dynamic blur effect used by blur-my-shell is entirely incompatible with any other effect,
  including the ones used by the rounded windows corner extension"

  —— 该 issue 描述的是同类冲突。本补丁从挂载点侧给出了针对 Wayland 的具体解法。

## 兼容性与边界

- **X11 会话**：上游本来就正确，补丁走同一条 surface 路径，行为不变
- **多个 surface（subsurface）**：`findSurface` 返回第一个匹配项（通常是主 surface），
  与上游 X11 行为一致
- **上游更新**：`windowTracker.js` 变动大时补丁无法干净应用，`install.sh` 会失败而非静默破坏
