<div align="center">

# Musik
**Apple Music Player for the Terminal**

A VIM-like Apple Music client built in Swift. Forked from [Yatoro](https://github.com/jayadamsmorgan/Yatoro) with enhanced search, queue management, and a Dieter Rams-inspired theme.

</div>

## What's Different from Yatoro

- **Multi-column search** — artists, albums, and songs displayed simultaneously in a 3-column layout
- **Natural language search** — type `recent`, `my playlists`, `artist radiohead` and it just works
- **Recently played on startup** — auto-loads your history when you launch
- **Queue management** — select, remove, and jump to items directly with keyboard
- **Dual playlist search** — library and catalog playlists side by side
- **Braun theme** — warm amber accent palette inspired by Dieter Rams

## Installation

### Requirements

- Active Apple Music subscription
- macOS Sonoma or higher
- Terminal emulator (Ghostty, iTerm2, etc.)

### Build from source

```
git clone https://github.com/aerosaur/musik.git
cd musik
swift build --disable-sandbox -Xcc -DNCURSES_UNCTRL_H_incl
cp .build/debug/musik /opt/homebrew/bin/musik
```

### Post-install

Add both your terminal and `musik` in **System Settings > Privacy & Security > Media & Apple Music**.

Config lives at `~/.config/Musik/config.yaml`. Themes go in `~/.config/Musik/themes/`.

## Search

Enter command mode with `:` then use `:search` or just press `s`.

| Command | What it does |
|---------|-------------|
| `:search biffy clyro` | Multi-search across artists, albums, songs |
| `:search -r` | Recently played |
| `:search -s` | Recommended / suggestions |
| `:search -l jazz` | Search your library |
| `:search -t al radiohead` | Filter by type: `so` songs, `al` albums, `ar` artists, `pl` playlists |

**Shortcuts in search input:** typing `recent` converts to `-r`, `recommended` to `-s`, `my playlists` to library playlist search.

## Controls

### Navigation

| Key | Action |
|-----|--------|
| `j` / `k` / `Down` / `Up` | Move down / up |
| `l` / `Enter` | Open / play selected |
| `h` / `Esc` | Go back / close |
| `Left` / `Right` | Navigate search columns |
| `TAB` | Toggle focus between search and queue |
| `0-9` | Jump to queue position |

### Playback

| Key | Action |
|-----|--------|
| `Space` | Play / pause |
| `f` / `b` | Next / previous track |
| `Ctrl+f` / `Ctrl+b` | Seek forward / backward |
| `r` | Restart song |
| `=` / `-` | Volume up / down |

### Queue

| Key | Action |
|-----|--------|
| `a` | Add all results and play |
| `Backspace` | Remove selected from queue |
| `x` | Clear queue |
| `c` | Stop playback |

### General

| Key | Action |
|-----|--------|
| `:` | Open command line |
| `s` | Start search |
| `q` / `Ctrl+c` | Quit |

## Theming

Themes are YAML files in `~/.config/Musik/themes/`. Set the active theme in `config.yaml`:

```yaml
ui:
  theme: braun
```

Included themes: `braun` (default), `default`, `catppuccin-frappe`, `arc-raiders`.

See [THEMING.md](THEMING.md) for the full color reference.

## Credits

Built on [Yatoro](https://github.com/jayadamsmorgan/Yatoro) by [@jayadamsmorgan](https://github.com/jayadamsmorgan). Licensed under MIT.
