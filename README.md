# Vitrail

Lightweight macOS window layout manager. Define layouts in TOML, switch with global hotkeys.

No tiling tree, no automatic rearrangement — just precise window positioning with percentages.

## Features

- **TOML config** — define layouts with window positions as percentages
- **Global hotkeys** — switch layouts with `alt+1`, `alt+2`, etc.
- **Menu bar icon** — click to apply layouts, edit config, or quit
- **Window matching** — match by app name + optional title filter (supports Chrome profiles)
- **Spacing** — configurable gaps between windows (% or px)
- **Hide others** — automatically hide apps not in the active layout
- **Multi-screen** — assign windows to specific screens
- **Launch at login** — toggle from the menu bar

## Install

### Homebrew (recommended)

```bash
brew tap 0xtlt/tap
brew install vitrail
```

### Download DMG

Grab the latest DMG from [Releases](https://github.com/0xtlt/vitrail/releases) — signed and notarized.

### From source

```bash
git clone https://github.com/0xtlt/vitrail.git
cd vitrail
swift build -c release
cp .build/release/Vitrail /usr/local/bin/vitrail
```

## Setup

Create your config at `~/.config/vitrail/config.toml` (or click **Edit Config...** in the menu bar):

```toml
spacing = "1%"
hide_others = true

[[layout]]
name = "dev"
hotkey = "alt+1"

  [[layout.window]]
  app = "Terminal"
  x = 0
  y = 0
  width = 40
  height = 100

  [[layout.window]]
  app = "Google Chrome"
  x = 40
  y = 0
  width = 60
  height = 100

[[layout]]
name = "work"
hotkey = "alt+2"

  [[layout.window]]
  app = "Slack"
  x = 0
  y = 0
  width = 40
  height = 100

  [[layout.window]]
  app = "Google Chrome"
  title = "Work"
  x = 40
  y = 0
  width = 60
  height = 100
```

## Config reference

### Global settings

| Key | Default | Description |
|-----|---------|-------------|
| `spacing` | `"1%"` | Gap between windows. `"1%"`, `"10px"`, or `"10"` |
| `hide_others` | `true` | Hide apps not in the active layout |

### Layout

| Key | Description |
|-----|-------------|
| `name` | Layout name (shown in menu bar) |
| `hotkey` | Global shortcut. Modifiers: `alt`, `cmd`, `ctrl`, `shift`. Example: `"alt+1"`, `"ctrl+shift+a"` |

### Window

| Key | Required | Description |
|-----|----------|-------------|
| `app` | yes | App name (as shown in Activity Monitor) |
| `title` | no | Window title filter (substring match). Useful for Chrome profiles |
| `screen` | no | Screen index (1 = primary, 2 = secondary). Default: `1` |
| `x` | yes | X position as % of screen (0-100) |
| `y` | yes | Y position as % of screen (0-100) |
| `width` | yes | Width as % of screen (0-100) |
| `height` | yes | Height as % of screen (0-100) |

## Usage

```bash
# Run with default config (~/.config/vitrail/config.toml)
vitrail

# Run with custom config
vitrail /path/to/config.toml
```

## Permissions

Vitrail needs **Accessibility** permission to move and resize windows.

On first launch, macOS will prompt you to grant access in **System Settings > Privacy & Security > Accessibility**.

## Requirements

- macOS 13+
- Swift 5.9+

## License

MIT
