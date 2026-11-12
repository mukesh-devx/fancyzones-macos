# FancyZones for macOS (Hammerspoon)

A window manager in the spirit of Windows PowerToys FancyZones, written in Lua for [Hammerspoon](https://www.hammerspoon.org).

- **`⌥Z`** opens a visual zone editor: draw, move, resize and delete rectangular zones.
- **Hold `⇧` while dragging a window** to show the zones. The zone under the cursor lights up. Release the mouse to snap the window into it.
- Multiple named **layouts**, saved as JSON, assigned **per display**. Zones are stored as fractions of the screen, so one layout works on any resolution.
- Multi-monitor aware (mixed resolutions, displays left of or above the primary one).

Built on `hs.canvas` (overlays), `hs.eventtap` (input) and `hs.window` (positioning).

## Requirements

- A macOS version supported by your Hammerspoon release
- Hammerspoon 1.0 or newer (developed against 1.1.1): `brew install --cask hammerspoon`

## Install

```sh
./install.sh
```

The script:

1. symlinks `fancyzones/` to `~/.hammerspoon/fancyzones`,
2. appends a marked block to `~/.hammerspoon/init.lua` (after saving a timestamped backup),
3. is safe to run again, and `./install.sh --uninstall` reverses it (your layouts are kept).

Options: `--copy` copies the files instead of symlinking. `HS_DIR=/some/dir ./install.sh` targets another config directory.

Then **reload Hammerspoon** (menu bar icon → *Reload Config*).

### Manual install

```sh
ln -s "$(pwd)/fancyzones" ~/.hammerspoon/fancyzones
```

and add to `~/.hammerspoon/init.lua`:

```lua
require("fancyzones").start()
```

## Grant Accessibility permission

Hammerspoon needs **Accessibility** access to watch mouse/keyboard events and to move other apps' windows. FancyZones checks this at startup:

1. If it is missing, macOS shows its prompt and FancyZones shows an on-screen hint.
2. Open **System Settings → Privacy & Security → Accessibility** and enable **Hammerspoon**.
3. FancyZones notices the change within about 1.5 seconds and starts; no reload is normally needed.

If the drag listener still does not start after granting access, quit and reopen Hammerspoon once. The menu bar item shows `⚠︎ Grant Accessibility access…` while the permission is missing.

## Using it

### Snapping windows

1. Start dragging a window by its title bar.
2. Hold **Shift** (before or during the drag). Zones appear on every display.
3. Move over a zone; it highlights. Release the mouse to snap.
4. Release **Shift** before the mouse to cancel the snap and keep the window where it is.

Shift-dragging that does not move a window (selecting text, scrollbars, resizing a window edge) is detected and ignored.

### Editing zones (`⌥Z`)

The editor dims the desktop on every display. Each display shows the layout assigned to it. `⌥Z` again (or Esc) closes it.

| Action | How |
| --- | --- |
| Draw a zone | Drag on empty space. Hold **⇧** to draw on top of an existing zone. |
| Move a zone | Drag its body. |
| Resize | Select a zone, then drag a handle or any edge. Edges shared with neighbouring zones move together, like a splitter. |
| Detach / free-hand | Hold **⌥** while dragging: no edge snapping, shared edges stay put. |
| Delete a zone | Select it, press **⌫**, or click the red **×** on the zone. |
| Nudge | Arrow keys move the selected zone 4 pt (**⇧** for 20 pt). |
| Select | Click a zone; **Tab** / **⇧Tab** cycle; click empty space to deselect. |
| Add a zone | **+ Zone** button or **N**. |
| Undo | **⌘Z** (every edit, including layout changes). |
| Save | **⏎** or the **Save** button. |
| Cancel | **Esc** or the **Cancel** button. With unsaved changes, Esc asks first and a second Esc discards. |

Edges snap to other zones, the screen edges and the centre line; guide lines show what you snapped to.

Toolbar (top of each display):

- **‹ name ›** switches this display to the previous/next layout. Click the name to rename it inline.
- **Templates** applies a starting point (full, 2/3 columns, priority, rows, 2×2 grid, main + side) to the current layout.
- **New layout** adds a blank layout; **Delete layout** removes the current one (at least one must remain).
- **Gap − / +** sets the space between snapped windows (and to the screen edges) in 2 pt steps, 0 to 48. The dashed outline inside each zone shows where the window will actually sit. The gap is part of Save/Cancel/undo like any other edit, and it applies to all layouts and displays.

Nothing is written until you press Save, and Save refuses layouts that have no zones.

### Menu bar

The `▦` item opens the editor, toggles snapping (remembered across restarts), switches the layout per display, opens the layouts folder and reloads the config.

## Configuration

Pass overrides to `start`. Only the keys you set change.

```lua
require("fancyzones").start{
  hotkey        = { mods = { "alt" }, key = "z" },
  snapModifiers = { "shift" },        -- try { "shift", "alt" } or { "ctrl" }
  spacing       = 12,                 -- default gap in points (the editor's Gap control overrides it once used)
  animationDuration = 0.14,           -- 0 = instant snap
  excludedApps  = { "com.apple.finder" },
  theme         = { accent = "#30D158" },
}
```

| Option | Default | Meaning |
| --- | --- | --- |
| `hotkey` | `{mods={"alt"}, key="z"}` | Opens/closes the editor. `nil` disables it. |
| `snapModifiers` | `{"shift"}` | Modifier(s) held while dragging. Accepts `shift`, `alt`/`option`, `ctrl`/`control`, `cmd`/`command`. Extra modifiers are tolerated. |
| `spacing` | `8` | Starting gap in points: full gap at screen edges, shared between neighbours. A gap saved from the editor is remembered and wins over this value. |
| `animationDuration` | `0.14` | Seconds for the window to glide into place. |
| `fadeIn` / `fadeOut` | `0.10` / `0.12` | Overlay fade times. |
| `dragThreshold` | `4` | Pointer travel (pt) before a drag is classified. |
| `showZoneNumbers` | `true` | Numbers on snap-overlay zones. |
| `menubar` | `true` | Show the menu bar item. |
| `excludedApps` | `{}` | Bundle IDs never snapped. |
| `dataDir` | `~/.hammerspoon/fancyzones-data` | Where `layouts.json` lives. |
| `editor.edgeSnapPx` | `10` | Magnetism distance in the editor (0 disables). |
| `editor.minZonePx` | `56` | Smallest zone the editor allows. |
| `editor.nudgePx` | `4` | Arrow-key step. |
| `theme.accent` / `danger` / `panel` | `#0A84FF` / `#FF453A` / `#1C1C1E` | Colours (`#RRGGBB`). |
| `theme.overlayDim` / `editorDim` | `0.10` / `0.55` | Backdrop opacity. |
| `theme.cornerRadius`, `theme.font` | `10`, system font | |
| `logLevel` | `"info"` | `"debug"` for troubleshooting. |

Invalid values produce an on-screen warning and fall back to the default; they never stop FancyZones from starting.

### Lua API

```lua
local fz = require("fancyzones")
fz.start(cfg) ; fz.stop()
fz.openEditor() ; fz.closeEditor() ; fz.toggleEditor()
fz.setSnappingEnabled(true) ; fz.isSnappingEnabled()
fz.setLayout("priority")                 -- display under the pointer
fz.setLayout("grid-2x2", hs.screen.primaryScreen())
fz.layouts.list()                        -- the layout store
```

## Layout file

`~/.hammerspoon/fancyzones-data/layouts.json`, written atomically. Safe to edit by hand while Hammerspoon is not running (or reload afterwards).

```json
{
  "version": 1,
  "layouts": [
    {
      "id": "main-side",
      "name": "Main + side",
      "zones": [
        { "x": 0.0,    "y": 0.0, "w": 0.6667, "h": 1.0 },
        { "x": 0.6667, "y": 0.0, "w": 0.3333, "h": 0.5 },
        { "x": 0.6667, "y": 0.5, "w": 0.3333, "h": 0.5 }
      ]
    }
  ],
  "assignments": { "<display UUID>": "main-side" }
}
```

- `x, y, w, h` are fractions (0–1) of the display's **usable area** (without menu bar and Dock).
- Displays are identified by UUID, so a layout assignment follows the physical monitor.
- Invalid zones are clamped or dropped on load. A file that cannot be parsed is renamed to `layouts.json.corrupt-<timestamp>` and defaults are restored, so your data is never silently overwritten.

## How it is organised

```
fancyzones/
  init.lua        public API: start / stop / openEditor / ...
  config.lua      defaults, deep merge, validation
  theme.lua       colour palette
  layouts.lua     JSON store, validation, templates, per-display assignment
  geometry.lua    pure maths: normalized zones <-> screen rects, hit tests, spacing
  screens.lua     multi-monitor helpers (global coordinates, UUIDs)
  windows.lua     find the dragged window, move it (with a verify-and-retry pass)
  overlay.lua     snap overlay: one click-through canvas per display, animated highlight
  snapper.lua     drag detection state machine on hs.eventtap
  editor.lua      editor controller: input, undo, layouts, lifecycle
  editor_ops.lua  pure gesture maths: draw / move / resize / snapping / linked edges
  editor_view.lua pure renderer: editor state -> canvas elements + clickable regions
  permissions.lua Accessibility check, prompt, wait-for-grant, tap verification
  menubar.lua     menu bar item
  util.lua, log.lua
```

`geometry`, `editor_ops` and `editor_view` are plain Lua with no Hammerspoon calls, so the interaction maths and the editor's rendering can be checked outside Hammerspoon.

## macOS limitations and how they are handled

- **No "window is being dragged" event.** macOS does not tell apps that a window drag is in progress. While the snap modifier is held, FancyZones samples the window under the pointer twice; if it moved along with the pointer and kept its size, it is a move. Pure Shift-clicks and text selections never trigger it, and nothing expensive runs unless the modifier is held. Some very laggy apps may be classified late; release and press Shift again to retry.
- **Event tap health.** macOS disables taps that block or after sleep. A watchdog restarts the tap every 5 s if needed, and a guard hides the overlay if a mouse-up is ever missed.
- **Spaces and full screen.** Hammerspoon only sees windows on the current Space, and native full-screen windows are skipped. Overlays are shown on every Space.
- **Secure input.** While a password field has focus, macOS withholds keyboard events from every tap. The editor warns about this; the on-screen buttons and the mouse still work.
- **Minimum sizes.** Windows with a minimum size larger than the zone overflow it (top-left aligned). A rejected move is retried once without animation, which fixes most cross-display "sticky edge" cases.
- **Built-in macOS tiling.** On macOS 15+, *Desktop & Dock → Tile by dragging windows to screen edges* can compete with edge snapping. Turn it off if windows jump unexpectedly.
- **Rendering.** `hs.canvas` cannot blur what is behind it, so the polish comes from translucency, rounded corners, shadows and eased highlight transitions instead of acrylic.
- **Dock and menu bar.** Zones are fractions of the usable area. Changing the Dock size or position changes the pixel size of zones, not their proportions.
- **Zones cannot span displays**; each display has its own zone set.
- **Hotkey.** `⌥Z` produces `Ω` on some keyboard layouts when typed into apps; Hammerspoon intercepts it first. Change `hotkey` if it conflicts.

## Troubleshooting

- **Nothing happens when dragging with Shift**: check the Hammerspoon Console (menu bar icon → Console). Set `logLevel = "debug"`. Confirm Accessibility is enabled and that no other tool (BetterTouchTool, Rectangle…) reacts to the same drag.
- **Overlay appears for window resizes or text selection**: report the app; try raising `dragThreshold`.
- **`FancyZones failed to load`**: confirm `~/.hammerspoon/fancyzones/init.lua` exists (re-run `./install.sh`).
- **Start over**: quit Hammerspoon, delete `~/.hammerspoon/fancyzones-data/layouts.json`, reopen.
- **Uninstall**: `./install.sh --uninstall`.
