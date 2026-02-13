<div align="center">

# Musik
**Apple Music Player for the Terminal**

</div>


## Overview

Musik is a VIM-like Apple Music player written in Swift for the terminal. Forked from [Yatoro](https://github.com/jayadamsmorgan/Yatoro) with enhanced search, recently played, and a custom Dieter Rams-inspired theme.

### Build from source

```
swift build --disable-sandbox -Xcc -DNCURSES_UNCTRL_H_incl
cp .build/debug/musik /opt/homebrew/bin/musik
```

### Requirements

- Active Apple Music subscription
- macOS Sonoma or higher
- Terminal of your preference

### Note

- **Important:** Add both your Terminal and the Musik binary in `System Settings -> Privacy & Security -> Media & Apple Music`

## Feature status

The player is still early in the development, so the features are quite limited for now.


| Feature             | Status  | Comments                                        |
| ------------------- | ------- | ----------------------------------------------- |
| Playing music       | Working |                                                 |
| Player controls     | Working |                                                 |
| Now playing artwork | Working |                                                 |
| Status line         | Working |                                                 |
| Command line        | Working |                                                 |
| Searching music     | Working | Only with `:search` command                     |
| Player queue        | Working | Only adding to queue with `:addToQueue` command |
| Coloring the UI     | Working | Check [THEMING](THEMING.md)                     |
| Mouse controls      |   TBD   |                                                 |
| Arrow navigation    |   TBD   |                                                 |

Feel free to suggest new features through issues!


## Usage

### Configuring

Some of the options might be configured with command line arguments. Check `musik -h`.

Another way to configure everything is configuration file. Check [CONFIGURATION](CONFIGURATION.md).

Command line arguments will overwrite the options set in configuration file.

### Default Controls

| Action                                  | Modifier | Button |
|-----------------------------------------| -------- | ------ |
| Play/Pause Toggle                       |          |  `p`   |
| Play                                    |  `SHIFT` |  `p`   |
| Pause                                   |  `CTRL`  |  `p`   |
| Stop                                    |          |  `c`   |
| Clear queue                             |          |  `x`   |
| Close last search result or detail page |          | `ESC`  |
| Play next                               |          |  `f`   |
| Play previous                           |          |  `b`   |
| Start seeking forward                   |  `CTRL`  |  `f`   |
| Start seeking backward                  |  `CTRL`  |  `b`   |
| Stop seeking                            |          |  `g`   |
| Restart song                            |          |  `r`   |
| Start searching                         |          |  `s`   |
| Station from current entry              |  `CTRL`  |  `s`   |
| Open command line                       |  `SHIFT` |  `:`   |
| Quit application                        |          |  `q`   |
| Quit application (2)                    |  `CTRL`  |  `c`   |

### Commands

Musik has a VIM-like command line. Check full command description in [COMMANDS](COMMANDS.md).


## Contributing

Check [CONTRIBUTING](CONTRIBUTING.md) and [CODE_OF_CONDUCT](CODE_OF_CONDUCT.md).


[upstream]: https://github.com/jayadamsmorgan/Yatoro
