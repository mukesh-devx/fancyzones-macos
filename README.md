<div align="center">

# 🪟 FancyZones for macOS

**A customizable, physical-feeling grid and zone window manager for macOS, inspired by Microsoft PowerToys FancyZones.**

Built natively in Lua on top of [Hammerspoon](https://www.hammerspoon.org).

[![macOS](https://img.shields.io/badge/macOS-12.0+-blue?style=flat-square&logo=apple&logoColor=white)](https://apple.com/macos)
[![Hammerspoon](https://img.shields.io/badge/Hammerspoon-1.0+-orange?style=flat-square&logo=lua&logoColor=white)](https://www.hammerspoon.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square)](https://github.com/mukesh-devx/fancyzones-macos)

[Features](#-key-features) • [Installation](#-installation) • [Usage](#-how-to-use) • [Editor Guide](#-visual-zone-editor) • [Configuration](#-configuration) • [Architecture](#-codebase-architecture)

---

</div>

## ✨ Key Features

- **⚡️ Intuitive Snap-on-Drag**: Hold <kbd>⇧ Shift</kbd> while dragging any window by its title bar to reveal your zones. Hover over a zone and release the mouse to snap the window smoothly into place.
- **🎨 Interactive Visual Zone Editor (<kbd>⌥ Option</kbd> + <kbd>Z</kbd>)**: Draw, nudge, resize, and delete zones directly on screen with magnetic edge snapping, guide lines, and full undo/redo (<kbd>⌘ Cmd</kbd> + <kbd>Z</kbd>).
- **🖥️ True Multi-Monitor Support**: Independent layouts assigned per display UUID. Supports mixed resolutions, displays placed in any orientation, and dynamic connect/disconnect detection.
- **🌌 Seamless macOS Spaces & Mission Control Integration**: Canvases use `canJoinAllSpaces`, `stationary`, and `fullScreenAuxiliary` collection behaviors alongside dynamic Space watchers so zones never disappear or flicker when switching virtual desktops.
- **📐 Resolution-Independent Layouts**: Zones are stored as proportional fractions (`0.0`–`1.0`) of the screen's usable frame, ensuring your layouts scale cleanly if your resolution changes.
- **🕹️ Native Menu Bar Utility**: Quick layout switcher, snapping toggle, layout directory shortcut, and configuration reloader.
- **🛡️ Smart Drag Classification**: Differentiates between window moves and text selection/resizes, ignoring non-move events with zero system lag.

---

## 📋 Requirements

- **macOS 12.0 (Monterey)** or higher
- **Hammerspoon 1.0+** (tested and verified on 1.1.x)
  ```sh
  brew install --cask hammerspoon
  ```

---

## 🚀 Installation

### Automated Install (Recommended)

Clone the repository and run the automated installer:

```sh
git clone https://github.com/mukesh-devx/fancyzones-macos.git
cd fancyzones-macos
./install.sh
```

The script automatically:
1. Symlinks `fancyzones/` into your `~/.hammerspoon/` directory.
2. Creates a timestamped backup of your current `init.lua`.
3. Safely adds the FancyZones loader block to `~/.hammerspoon/init.lua`.

After installation, reload Hammerspoon from the menu bar:
**Hammerspoon icon → Reload Config**

### Manual Installation

If you prefer to configure Hammerspoon manually:

```sh
# 1. Symlink the module
ln -s "$(pwd)/fancyzones" ~/.hammerspoon/fancyzones
```

Then add the following snippet to your `~/.hammerspoon/init.lua`:

```lua
local ok, fz = pcall(require, "fancyzones")
if ok then
  fz.start()
else
  hs.alert.show("FancyZones failed to load: " .. tostring(fz), 5)
end
```

---

## 🔐 Grant Accessibility Permissions

macOS requires **Accessibility** permissions for Hammerspoon to detect window dragging and reposition windows:

1. On launch, if permission is missing, FancyZones displays an on-screen prompt.
2. Go to **System Settings → Privacy & Security → Accessibility**.
3. Toggle **Hammerspoon** to **ON**.
4. FancyZones will automatically detect the permission grant and start listening without requiring a restart.

> [!TIP]
> If dragging still doesn't snap after granting permission, simply restart Hammerspoon once.

---

## 🎯 How to Use

### 1. Snapping Windows

```
┌────────────────────────────────────────────────────────┐
│  1. Grab window by title bar                           │
│  2. Hold [ Shift ]                                     │
│  3. Drag into zone (zone glows with accent color)       │
│  4. Release mouse to snap!                             │
└────────────────────────────────────────────────────────┘
```

- **Snap to Zone**: Hold <kbd>⇧ Shift</kbd> (before or during the drag), move over any zone, and release the mouse.
- **Cancel Snap**: Release <kbd>⇧ Shift</kbd> *before* releasing the mouse to drop the window without snapping.
- **Smart Filtering**: Pure Shift-clicks, text selections, and scrollbar drags are detected and ignored automatically.

---

## 🎨 Visual Zone Editor

Press **<kbd>⌥ Option</kbd> + <kbd>Z</kbd>** (or select **Edit Zones** from the menu bar) to open the interactive canvas editor across all connected displays.

```
+--------------------------------------------------------------+
| [‹ Layout Name ›]  [Templates ▼]  [New]  [Delete]  Gap: [- 8 +] |
+--------------------------------------------------------------+
|                                                              |
|   +-----------------------+    +-------------------------+   |
|   |                       |    |                         |   |
|   |        Zone 1         |    |         Zone 2          |   |
|   |                       |    |                         |   |
|   +-----------------------+    +-------------------------+   |
|                                                              |
|                  [ Save ]       [ Cancel ]                   |
+--------------------------------------------------------------+
```

### Keyboard & Mouse Shortcuts

| Action | Control / Keybinding |
| :--- | :--- |
| **Draw new zone** | Click and drag on empty canvas space (Hold <kbd>⇧ Shift</kbd> to draw over an existing zone) |
| **Move zone** | Click & drag any zone body |
| **Resize zone** | Select a zone, then drag any edge or corner handle. Shared edges move together like splitters! |
| **Free-hand / Detach** | Hold <kbd>⌥ Option</kbd> while dragging to bypass magnetic edge snapping |
| **Nudge** | Arrow keys (<kbd>←</kbd> <kbd>→</kbd> <kbd>↑</kbd> <kbd>↓</kbd>) move selected zone by 4 pt (Hold <kbd>⇧ Shift</kbd> for 20 pt) |
| **Cycle selection** | <kbd>Tab</kbd> / <kbd>⇧ Shift</kbd> + <kbd>Tab</kbd> |
| **Delete zone** | Select zone and press <kbd>⌫ Backspace</kbd>, or click the red <kbd>×</kbd> handle |
| **Undo** | <kbd>⌘ Cmd</kbd> + <kbd>Z</kbd> (undoes zone edits, template switches, gap adjustments) |
| **Save & Apply** | Press <kbd>Return ⏎</kbd> or click **Save** |
| **Discard & Exit** | Press <kbd>Esc</kbd> or click **Cancel** |

### Toolbar Features

- **`< Layout Name >`**: Click arrows to switch layouts on the current monitor. Click the name directly to rename it inline.
- **Templates**: Apply pre-built layouts: *Full Screen, 2 Columns, 3 Columns, Priority (1-2-1), 2 Rows, 2×2 Grid, and Main + Side*.
- **Gap Control (`-` / `+`)**: Adjust margin spacing between windows (0 to 48 pt). The inner dashed outline shows the exact snapped window boundaries.

---

## ⚙️ Configuration

FancyZones works out of the box with zero setup, but every aspect can be customized. Pass an override table to `fz.start()` in your `~/.hammerspoon/init.lua`:

```lua
local fz = require("fancyzones")

fz.start({
  -- Hotkey to toggle the visual zone editor
  hotkey = { mods = { "alt" }, key = "z" },

  -- Key(s) required while dragging: "shift", "alt", "ctrl", "cmd"
  snapModifiers = { "shift" },

  -- Window glide duration in seconds (0 = instant snap)
  animationDuration = 0.14,

  -- Default window gap in points (editor setting overrides this once saved)
  spacing = 8,

  -- Exclude specific applications from being snapped
  excludedApps = {
    "com.apple.finder",
  },

  -- Custom theme colors
  theme = {
    accent = "#0A84FF",       -- Highlight glow color
    danger = "#FF453A",       -- Delete handle color
    cornerRadius = 10,        -- Zone corner radius
    overlayDim = 0.12,        -- Backdrop dim while dragging
  },

  logLevel = "info",          -- "debug" for troubleshooting
})
```

### Full Configuration Reference

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `hotkey` | `table` or `nil` | `{mods={"alt"}, key="z"}` | Global hotkey to toggle zone editor. Set `nil` to disable. |
| `snapModifiers` | `table` | `{"shift"}` | Modifiers held while dragging. Any of `shift`, `alt`, `ctrl`, `cmd`. |
| `spacing` | `number` | `8` | Default gap between zones and screen edges (in points). |
| `animationDuration`| `number` | `0.14` | Seconds for window glide animation. Set `0` for instant snap. |
| `fadeIn` / `fadeOut`| `number` | `0.10` / `0.12` | Overlay fade transition speeds. |
| `dragThreshold` | `number` | `4` | Pointer travel (points) before classifying a drag. |
| `showZoneNumbers` | `boolean` | `true` | Show zone index numbers on the overlay tiles. |
| `menubar` | `boolean` | `true` | Show status menu bar icon. |
| `excludedApps` | `table` | `{}` | List of macOS Bundle IDs to ignore. |
| `theme.accent` | `string` | `"#0A84FF"` | Active zone glow color (`#RRGGBB`). |
| `theme.panel` | `string` | `"#1C1C1E"` | Toolbar and editor UI background. |
| `theme.cornerRadius`| `number` | `10` | Corner roundness for tiles and editor handles. |

---

## 🛠️ Lua API

FancyZones exposes a clean programmatic API for scripting and external triggers:

```lua
local fz = require("fancyzones")

-- Lifecycle
fz.start(customConfig)
fz.stop()
fz.isRunning()

-- Editor
fz.openEditor()
fz.closeEditor()
fz.toggleEditor()

-- Snapping state
fz.setSnappingEnabled(true)
fz.isSnappingEnabled()

-- Layouts
fz.setLayout("priority")                      -- Applies to display under pointer
fz.setLayout("columns-3", hs.screen.mainScreen()) -- Applies to specific screen
local allLayouts = fz.layouts.list()          -- Layout store
```

---

## 📁 Layout Storage

Layouts are persisted in human-readable JSON at `~/.hammerspoon/fancyzones-data/layouts.json`:

```json
{
  "version": 1,
  "layouts": [
    {
      "id": "main-side",
      "name": "Main + Side",
      "zones": [
        { "x": 0.0, "y": 0.0, "w": 0.6667, "h": 1.0 },
        { "x": 0.6667, "y": 0.0, "w": 0.3333, "h": 0.5 },
        { "x": 0.6667, "y": 0.5, "w": 0.3333, "h": 0.5 }
      ]
    }
  ],
  "assignments": {
    "A615F0F4-D419-41EF-B3C2-155DC0719752": "main-side"
  }
}
```

- Writes are atomic (`.tmp` file + atomic rename) to eliminate corruption risks.
- Invalid data is clamped cleanly, and unreadable files are automatically backed up (`.corrupt-<timestamp>`) rather than overwritten.

---

## 🏗️ Codebase Architecture

The project is structured with strict separation of pure mathematical logic and macOS APIs:

```
fancyzones-hammerspoon/
├── fancyzones/
│   ├── init.lua          # Public API facade, lifecycle, watcher management
│   ├── snapper.lua       # Mouse eventtap state machine for drag classification
│   ├── overlay.lua       # Overlay rendering, highlight ease timer, Spaces sync
│   ├── editor.lua        # Editor controller, input events, session management
│   ├── editor_view.lua   # Pure rendering: converts state to hs.canvas primitives
│   ├── editor_ops.lua    # Pure geometry: zone dragging, resizing, magnetic edges
│   ├── geometry.lua      # Pure math: coordinate normalization, hit testing, gaps
│   ├── screens.lua       # Multi-monitor detection, global coordinates, UUID hashing
│   ├── windows.lua       # Frontmost window detection & smooth setFrame positioning
│   ├── layouts.lua       # Layout persistence (JSON), validation, and templates
│   ├── permissions.lua   # Accessibility permission verification and prompt
│   ├── menubar.lua       # Dynamic SVG-template menu bar icon & actions
│   ├── config.lua        # Option merging, defaults, and type validation
│   ├── theme.lua         # Color conversions, hex parsing, color lerping
│   ├── util.lua          # Timer and table helpers
│   └── log.lua           # Scoped logging with level filtering
├── install.sh            # One-click symlink/copy installer & uninstaller
├── LICENSE               # MIT License
└── README.md
```

> **Developer Note**: Modules like `geometry.lua`, `editor_ops.lua`, and `editor_view.lua` have zero dependencies on Hammerspoon (`hs.*`), enabling automated unit testing with standard Lua 5.4.

---

## ❓ Frequently Asked Questions

<details>
<summary><b>Why do zones not appear when I drag with Shift?</b></summary>
<br>
1. Check that Accessibility is granted in <b>System Settings → Privacy & Security → Accessibility</b>.<br>
2. Check the Hammerspoon Console (Menu bar icon → <i>Console</i>) for any errors.<br>
3. Ensure no competing window management utilities (like Rectangle or BetterTouchTool) are consuming the drag event.
</details>

<details>
<summary><b>Does FancyZones interfere with macOS 15+ (Sequoia) window tiling?</b></summary>
<br>
No, FancyZones operates exclusively when you hold your designated modifier (<kbd>⇧ Shift</kbd>). If you find macOS Sequoia's screen-edge snapping competing when you release near display borders, you can disable macOS's built-in tiling in <i>System Settings → Desktop & Dock → Tile by dragging windows to screen edges</i>.
</details>

<details>
<summary><b>Can zones span across two separate physical monitors?</b></summary>
<br>
No. In macOS, displays operate in separate viewports. Zones are contained within individual physical displays to ensure proper rendering and DPI scaling.
</details>

---

## 🤝 Contributing

Contributions, feature suggestions, and bug reports are warmly welcome!

1. **Fork** the repository
2. Create a feature branch: `git checkout -b feature/awesome-addition`
3. Commit your changes: `git commit -m 'Add awesome feature'`
4. Push to branch: `git push origin feature/awesome-addition`
5. Open a **Pull Request**

---

## 📄 License

This project is open-source software licensed under the **[MIT License](LICENSE)**.
Feel free to use, modify, and distribute it freely.
