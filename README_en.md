<div align="center">

# gnome-shell-rounded-blur-fix

**Make blur-my-shell's application blur coexist with rounded-window-corners' window corners on GNOME Wayland**

A 64-line upstream patch + zero-dependency installer. No fork, no recompile — re-login and it works.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![GNOME Shell: 51](https://img.shields.io/badge/GNOME%20Shell-51-4A86CF.svg)](docs/installation.md)
[![Target: Wayland](https://img.shields.io/badge/Session-Wayland-FF6B00.svg)](docs/architecture.md)
[![Patched: rounded-window-corners v51.0](https://img.shields.io/badge/Patched-rounded--window--corners%20v51.0-lightgrey.svg)](patches/0001-rounded-blur-coexist.patch)

[English](#features) | [中文](README.md) · [Quick Start](#quick-start) · [How It Works](#how-it-works) · [FAQ](#faq) · [Docs](#docs)

</div>

---

## Features

**The problem**: With both [blur-my-shell](https://github.com/aunetx/blur-my-shell) (application blur) and [rounded-window-corners](https://github.com/ztrahmet/rounded-window-corners) (window corners) enabled on a GNOME Wayland session, application blur disappears entirely for floating (non-maximized) windows and only comes back when maximized or fullscreen. X11 windows are unaffected.

**Symptom** (from a real reproduction):

| Window | Session type | Blur (floating) | Blur (maximized) |
|---|---|---|---|
| kitty / clash-verge / Hermes (Electron) | Wayland native | ❌ gone | ✅ works |
| WeChat | XWayland | ✅ works | ✅ works |

**The fix**: move the corner shader effect's attachment point from the window actor to the surface child actor — the same thing upstream already does for X11 windows. After patching, floating-window blur and rounded corners work at the same time, with no trade-off between the two.

## Quick Start

```bash
git clone https://github.com/AkikoEra/gnome-shell-rounded-blur-fix.git
cd gnome-shell-rounded-blur-fix

# Apply the patch (original file is backed up automatically)
./scripts/install.sh

# Verify
./scripts/verify.sh

# Want it gone? One-command revert
./scripts/revert.sh
```

> **You must re-login after patching** — GNOME Shell cannot hot-reload extension modules on Wayland. Details in [docs/installation.md](docs/installation.md).

## How It Works

<details>
<summary><b>In one sentence: the corner effect is attached to the wrong actor, dragging the blur widget into offscreen rendering too</b> (click for full analysis)</summary>

### The architecture facts

blur-my-shell's application blur inserts a child actor named `bms-application-blurred-widget` into the window actor and uses a **BACKGROUND-mode** blur effect — which needs to sample the real framebuffer content *behind* the window.

rounded-window-corners implements corners via `RoundedCornersEffect` (a `Clutter.ShaderEffect` subclass). A ShaderEffect redirects the entire target actor into an **offscreen buffer** for shading.

### The conflict

Upstream `lib/windowTracker.js` uses different attachment points for the two window types:

```js
// Upstream v51.0
_effectTarget(actor, state) {
    if (actor.metaWindow.get_client_type() !== Meta.WindowClientType.X11)
        return actor;          // ← Wayland: attach to the window actor itself
    const surface = findSurface(actor);  // X11: attach to the surface child
    ...
}
```

- **X11 windows**: effect on the `MetaSurfaceActor` child → offscreen redirect wraps only the texture; the blur widget, a sibling node, is untouched ✅
- **Wayland windows**: effect on the `MetaWindowActor` itself → the whole actor, blur widget included, gets pulled into the offscreen buffer → BACKGROUND-mode sampling has nothing to sample, blur dies ❌

This precisely explains why the symptom only appears for Wayland windows, and only while the window is floating (upstream only applies corners to non-maximized windows; the effect is removed when maximized).

### Verified against mutter 51 sources

`src/compositor/meta-window-actor-wayland.c` confirms Wayland windows **do have a surface child actor** — `MetaSurfaceActorWayland` lives inside a `MetaSurfaceContainerActorWayland` container (a grandchild of the window actor), added via `clutter_actor_insert_child_at_index(container, ...)`. Upstream's implicit assumption that "Wayland has no surface child" is wrong, but reaching it requires recursive lookup + listening on the container's `child-added` signal.

### What the patch changes

1. `_effectTarget()`: drop the Wayland special-case; attach to the surface child for both X11 and Wayland
2. Wait logic: while the surface hasn't committed yet, listen on both the window actor **and** the `MetaSurfaceContainerActor` for `child-added`

Upstream issue corroboration: [blur-my-shell#634](https://github.com/aunetx/blur-my-shell/issues/634) — "the dynamic blur effect used by blur-my-shell is entirely incompatible with any other effect, including the ones used by the rounded windows corner extension".

</details>

## Compatibility

| Component | Tested version | Notes |
|---|---|---|
| GNOME Shell | 51 | Other versions untested; patch context is based on v51.0 sources |
| rounded-window-corners | v51.0 (ztrahmet) | Patch target; `install.sh` checks the version |
| blur-my-shell | v74+ (aunetx) | Compatible with both dynamic and static blur |
| Session type | Wayland | X11 behavior is unchanged (already correct upstream); patch is a no-op there |

## Docs

| Doc | Contents |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Deep root-cause analysis: effect attachment, offscreen redirect, mutter sources |
| [docs/installation.md](docs/installation.md) | Install, re-login, static/dynamic mode switch, revert |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Symptom-indexed troubleshooting |
| [docs/evidence.md](docs/evidence.md) | Full field notes from the original investigation |

## Project Layout

```
gnome-shell-rounded-blur-fix/
├── README.md                    ← you are here
├── README_en.md
├── LICENSE                      MIT
├── CONTRIBUTING.md
├── SECURITY.md
├── docs/
│   ├── architecture.md          root-cause analysis
│   ├── installation.md          install guide
│   ├── troubleshooting.md       troubleshooting
│   └── evidence.md              field notes
├── patches/
│   └── 0001-rounded-blur-coexist.patch   the patch (64 lines)
└── scripts/
    ├── install.sh               backup + apply + check
    ├── revert.sh                one-command revert
    ├── verify.sh                end-to-end verification
    └── pre-commit-check.sh      pre-publish sensitive-data scan
```

## FAQ

<details>
<summary>Does patching require sudo?</summary>

No. It only touches user-level extension files under `~/.local/share/gnome-shell/extensions/`.

</details>

<details>
<summary>Why does nothing change after patching?</summary>

GNOME 45+ caches extension modules as ES modules, and on GNOME 51 the `ReloadExtension` D-Bus method is unimplemented while the Shell's `Eval` interface is locked down — **you must re-login (or reboot) for source changes to load**. Verified by experiment, see [docs/evidence.md](docs/evidence.md).

</details>

<details>
<summary>Will a upstream extension update invalidate the patch?</summary>

Yes. If upstream rewrites `windowTracker.js`, the patch may no longer apply (`install.sh` fails loudly rather than corrupting silently). Re-run `./scripts/install.sh`; if the context has drifted, open an issue with the new file attached.

</details>

<details>
<summary>Rounded-corner edges of opaque apps show wallpaper color when overlapping other windows — is that a bug?</summary>

No. That's inherent to **static blur mode**: it blurs the wallpaper behind the window instead of sampling real content. The corner cut-outs reveal wallpaper color. Two fixes:

1. Switch back to dynamic mode: `dconf write /org/gnome/shell/extensions/blur-my-shell/applications/static-blur false` (then disable/re-enable blur-my-shell)
2. Add the app to blur-my-shell's blacklist: `dconf write /org/gnome/shell/extensions/blur-my-shell/applications/blacklist "['original entries...', 'wm-class']"`

</details>

<details>
<summary>Can this be a standalone installable extension?</summary>

No. The patch fixes internal logic of rounded-window-corners and must live inside that extension. This repo only distributes the patch and scripts, never upstream source.

</details>

<details>
<summary>What about licensing?</summary>

Scripts and docs in this repo are [MIT](LICENSE). The patched `windowTracker.js` is a derivative of upstream GPL-3.0 code — for local use only, do not redistribute the modified file.

</details>

## Star History

[![Star History Chart](https://star-history.com/#AkikoEra/gnome-shell-rounded-blur-fix&Date)](https://star-history.com/#AkikoEra/gnome-shell-rounded-blur-fix&Date)

## Disclaimer

- Not affiliated with blur-my-shell, rounded-window-corners, or GNOME.
- The patch targets rounded-window-corners **v51.0**; behavior on other versions is not guaranteed and `install.sh` warns on version mismatch.
- Modifying GNOME Shell extensions carries a theoretical risk of rendering issues. `install.sh` backs up automatically and `revert.sh` restores in one command. Use at your own risk.

## Contributing

Issues and PRs welcome: [CONTRIBUTING.md](CONTRIBUTING.md)

## License

[MIT](LICENSE) © AkikoEra
