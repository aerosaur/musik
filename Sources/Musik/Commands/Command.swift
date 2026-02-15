import ArgumentParser
import Logging
import MusicKit

public struct Command: Sendable {
    public let name: String
    public let shortName: String?
    public var action: CommandAction?

    public init(
        name: String,
        short: String? = nil,
        action: CommandAction?
    ) {
        self.name = name
        self.shortName = short
        self.action = action
    }

    public static let defaultCommands: [Command] = [
        .init(name: "addToQueue", short: "a", action: .addToQueue),
        .init(name: "play", short: "pl", action: .play),
        .init(name: "playPauseToggle", short: "pp", action: .playPauseToggle),
        .init(name: "pause", short: "pa", action: .pause),
        .init(name: "stop", short: "s", action: .stop),
        .init(name: "clearQueue", short: "cq", action: .clearQueue),
        .init(name: "playNext", short: "pn", action: .playNext),
        .init(name: "startSeekingForward", short: "sf", action: .startSeekingForward),
        .init(name: "playPrevious", short: "b", action: .playPrevious),
        .init(name: "startSeekingBackward", short: "sb", action: .startSeekingBackward),
        .init(name: "stopSeeking", short: "ss", action: .stopSeeking),
        .init(name: "restartSong", short: "r", action: .restartSong),
        .init(name: "quitApplication", short: "q", action: .quitApplication),
        .init(name: "search", short: "/", action: .search),
        .init(name: "setSongTime", short: "time", action: .setSongTime),
        .init(name: "stationFromCurrentEntry", short: "sce", action: .stationFromCurrentEntry),
        .init(name: "shuffleMode", short: "shuffle", action: .shuffleMode),
        .init(name: "repeatMode", short: "repeat", action: .repeatMode),
        .init(name: "reloadTheme", short: "rld", action: .reloadTheme),
        .init(name: "open", short: "o", action: .open),
        .init(name: "close", short: "c", action: .close),
        .init(name: "closeAll", short: "ca", action: .closeAll),
        .init(name: "help", short: "h", action: nil), // Help command, handled specially
        .init(name: "selectDown", short: "sd", action: .selectDown),
        .init(name: "selectUp", short: "su", action: .selectUp),
        .init(name: "addSelectedAndPlay", short: "asp", action: .addSelectedAndPlay),
        .init(name: "openSelected", short: "os", action: .openSelected),
        .init(name: "playIndex", short: "pi", action: .playIndex),
        .init(name: "addAllAndPlay", short: "aap", action: .addAllAndPlay),
        .init(name: "volumeUp", short: "vu", action: .volumeUp),
        .init(name: "volumeDown", short: "vd", action: .volumeDown),
        .init(name: "selectLeft", short: "sl", action: .selectLeft),
        .init(name: "selectRight", short: "sr", action: .selectRight),
        .init(name: "toggleQueueFocus", short: "tqf", action: .toggleQueueFocus),
        .init(name: "removeFromQueue", short: "rfq", action: .removeFromQueue),
    ]

    @MainActor
    public static func parseCommand(_ commandString: String) async {
        logger?.warning("PARSE COMMAND: '\(commandString)'")
        let commandParts = Array(commandString.split(separator: " "))
        guard let commandString = commandParts.first else {
            logger?.debug("Empty command entered")
            return
        }
        guard
            let command = defaultCommands.first(where: { cmd in
                if let short = cmd.shortName {
                    return short == commandString || cmd.name == commandString
                }
                return cmd.name == commandString
            })
        else {
            let msg = "Unknown command \"\(commandString)\""
            await CommandInput.shared.setLastCommandOutput(msg)
            logger?.debug(msg)
            return
        }
        let arguments = Array(commandParts.dropFirst().map(String.init))

        // Handle help command specially
        if command.name == "help" {
            SearchManager.shared.showHelp()
            return
        }

        guard let action = command.action else {
            let msg = "Command \"\(command.name)\" doesn't have any action."
            await CommandInput.shared.setLastCommandOutput(msg)
            logger?.debug(msg)
            return
        }
        switch action {

        case .addToQueue: await AddToQueueCommand.execute(arguments: arguments)

        case .playPauseToggle: await Player.shared.playPauseToggle()

        case .play: await Player.shared.play()

        case .pause: await Player.shared.pause()

        case .stop: Player.shared.player.stop()

        case .clearQueue: await Player.shared.clearQueue()

        case .playNext: await Player.shared.playNext()

        case .startSeekingForward: Player.shared.player.beginSeekingForward()

        case .playPrevious: await Player.shared.playPrevious()

        case .startSeekingBackward: Player.shared.player.beginSeekingBackward()

        case .stopSeeking: Player.shared.player.endSeeking()

        case .restartSong: await Player.shared.restartSong()

        case .quitApplication: UI.running = false

        case .search: await SearchCommand.execute(arguments: arguments)

        case .setSongTime: await SetSongTimeCommand.execute(arguments: arguments)

        case .stationFromCurrentEntry: await Player.shared.playStationFromCurrentSong()

        case .repeatMode: await RepeatModeCommand.execute(arguments: arguments)

        case .shuffleMode: await ShuffleModeCommand.execute(arguments: arguments)

        case .reloadTheme:
            ConfigurationParser.loadTheme()
            UIPageManager.configReload = true

        case .open: await OpenCommand.execute(arguments: arguments)

        case .close:
            logger?.warning("CLOSE: queue=\(SearchPage.searchPageQueue.size()) result=\(SearchManager.shared.lastSearchResult.size()) topPage=\(String(describing: SearchPage.searchPageQueue?.page))")
            // Always pop queue node (overlay or inline) alongside the result
            if let top = SearchPage.searchPageQueue {
                await top.page?.destroy()
                SearchPage.searchPageQueue = top.previous
                if top.page == nil {
                    SearchPage.needsInlineRefresh = true
                }
            }
            if let prev = SearchManager.shared.lastSearchResult?.previous {
                SearchManager.shared.lastSearchResult = prev
                SearchManager.shared.resetSelection()
            } else {
                // At root - reload recently played instead of going blank
                SearchPage.needsInlineRefresh = true
                await SearchManager.shared.loadRecentlyPlayed()
            }

        case .closeAll:
            // Destroy all pages (overlay and inline) before reloading
            while SearchPage.searchPageQueue.size() > 0 {
                await SearchPage.searchPageQueue?.page?.destroy()
                SearchPage.searchPageQueue = SearchPage.searchPageQueue?.previous
            }
            SearchPage.needsInlineRefresh = true
            await SearchManager.shared.loadRecentlyPlayed()

        case .selectDown:
            if SearchManager.shared.queueFocused {
                let queueCount = Player.shared.queue.count
                if queueCount > 0 && SearchManager.shared.queueSelectedIndex < queueCount - 1 {
                    SearchManager.shared.queueSelectedIndex += 1
                }
            } else {
                SearchManager.shared.selectNext()
            }

        case .selectUp:
            if SearchManager.shared.queueFocused {
                if SearchManager.shared.queueSelectedIndex > 0 {
                    SearchManager.shared.queueSelectedIndex -= 1
                }
            } else {
                SearchManager.shared.selectPrevious()
            }

        case .addSelectedAndPlay:
            // Capture whether the selected item opens a detail page BEFORE the
            // action changes lastSearchResult (openArtist pushes artistDescription
            // which would make the post-check return false incorrectly).
            var didOpenDetail = false

            if SearchManager.shared.isMultiSearch {
                let index = SearchManager.shared.selectedIndex
                let colType = SearchManager.shared.multiSearchColumnType()
                guard let lastResult = SearchManager.shared.lastSearchResult else { break }

                if case .dualPlaylistSearchResult(let dpr) = lastResult.result {
                    // Dual playlist search: queue selected playlist and play
                    switch colType {
                    case 0:  // Library playlist
                        if let playlists = dpr.libraryPlaylists, index < playlists.count {
                            let name = playlists[index].name
                            await Player.shared.addPlaylistToQueue(playlist: playlists[index], at: .tail)
                            await Player.shared.play()
                            await CommandInput.shared.setLastCommandOutput("Playing: \(name)")
                        }
                    case 1:  // Catalog playlist
                        if let playlists = dpr.catalogPlaylists, index < playlists.count {
                            let name = playlists[index].name
                            await Player.shared.addPlaylistToQueue(playlist: playlists[index], at: .tail)
                            await Player.shared.play()
                            await CommandInput.shared.setLastCommandOutput("Playing: \(name)")
                        }
                    default: break
                    }
                } else {
                    switch colType {
                    case 0:  // Artist - open detail
                        if case .multiSearchResult(let msr) = lastResult.result,
                           let artists = msr.artists, index < artists.count {
                            do {
                                try await OpenCommand.openArtist(artists[index])
                                didOpenDetail = true
                            } catch {
                                await CommandInput.shared.setLastCommandOutput("Failed to open artist")
                            }
                        }
                    case 1:  // Album - queue whole album and play
                        if case .multiSearchResult(let msr) = lastResult.result,
                           let albums = msr.albums, index < albums.count {
                            let title = albums[index].title
                            await Player.shared.addItemsToQueue(items: [albums[index]], at: .tail)
                            await Player.shared.play()
                            await CommandInput.shared.setLastCommandOutput("Playing: \(title)")
                        }
                    case 2:  // Song - queue and play
                        if case .multiSearchResult(let msr) = lastResult.result,
                           let songs = msr.songs, index < songs.count {
                            let title = songs[index].title
                            await Player.shared.addItemsToQueue(items: [songs[index]], at: .tail)
                            await Player.shared.play()
                            await CommandInput.shared.setLastCommandOutput("Playing: \(title)")
                        }
                    default: break
                    }
                }
            } else {
                let arg = SearchManager.shared.selectedItemArgument()
                let shouldOpen = SearchManager.shared.selectedItemShouldOpen()
                if shouldOpen {
                    await OpenCommand.execute(arguments: [arg])
                    didOpenDetail = true
                } else {
                    await AddToQueueCommand.execute(arguments: [arg])
                    await Player.shared.play()
                }
            }
            // Always reset selection so detail pages start at index 0
            // and played items don't leave stale selection state.
            SearchManager.shared.resetSelection()
            // After playing, navigate back to root result (Recently Played).
            // Skip when we opened a detail page (artist, etc.) — ESC will close it.
            // Walk the result chain to root instead of async API call — avoids
            // race conditions where the render recreates overlays during the await.
            if !didOpenDetail {
                while SearchPage.searchPageQueue.size() > 0 {
                    await SearchPage.searchPageQueue?.page?.destroy()
                    SearchPage.searchPageQueue = SearchPage.searchPageQueue?.previous
                }
                while SearchManager.shared.lastSearchResult?.previous != nil {
                    SearchManager.shared.lastSearchResult = SearchManager.shared.lastSearchResult?.previous
                }
                SearchPage.needsInlineRefresh = true
            }

        case .openSelected:
            let arg = SearchManager.shared.selectedItemArgument()
            await OpenCommand.execute(arguments: [arg])

        case .playIndex:
            guard let indexStr = arguments.first, let index = Int(indexStr) else {
                let msg = "playIndex requires a number argument"
                await CommandInput.shared.setLastCommandOutput(msg)
                return
            }
            let count = SearchManager.shared.currentItemCount
            guard index >= 0 && index < count else {
                let msg = "Index out of range"
                await CommandInput.shared.setLastCommandOutput(msg)
                return
            }
            SearchManager.shared.selectedIndex = index
            let arg = SearchManager.shared.argumentForIndex(index)
            let shouldOpen = SearchManager.shared.selectedItemShouldOpen()
            if shouldOpen {
                await OpenCommand.execute(arguments: [arg])
            } else {
                await AddToQueueCommand.execute(arguments: [arg])
                await Player.shared.play()
                SearchManager.shared.resetSelection()
                while SearchPage.searchPageQueue.size() > 0 {
                    await SearchPage.searchPageQueue?.page?.destroy()
                    SearchPage.searchPageQueue = SearchPage.searchPageQueue?.previous
                }
                while SearchManager.shared.lastSearchResult?.previous != nil {
                    SearchManager.shared.lastSearchResult = SearchManager.shared.lastSearchResult?.previous
                }
                SearchPage.needsInlineRefresh = true
            }

        case .addAllAndPlay:
            await AddToQueueCommand.execute(arguments: ["a"])
            await Player.shared.play()
            SearchManager.shared.resetSelection()
            while SearchPage.searchPageQueue.size() > 0 {
                await SearchPage.searchPageQueue?.page?.destroy()
                SearchPage.searchPageQueue = SearchPage.searchPageQueue?.previous
            }
            while SearchManager.shared.lastSearchResult?.previous != nil {
                SearchManager.shared.lastSearchResult = SearchManager.shared.lastSearchResult?.previous
            }
            SearchPage.needsInlineRefresh = true

        case .volumeUp:
            await Player.shared.volumeUp()

        case .volumeDown:
            await Player.shared.volumeDown()

        case .selectLeft:
            if SearchManager.shared.isMultiSearch {
                SearchManager.shared.selectLeft()
            } else {
                // Fall back to close behavior — pop queue and result
                if let top = SearchPage.searchPageQueue {
                    await top.page?.destroy()
                    SearchPage.searchPageQueue = top.previous
                    if top.page == nil {
                        SearchPage.needsInlineRefresh = true
                    }
                }
                if let prev = SearchManager.shared.lastSearchResult?.previous {
                    SearchManager.shared.lastSearchResult = prev
                    SearchManager.shared.resetSelection()
                } else {
                    SearchManager.shared.lastSearchResult = nil
                    SearchManager.shared.resetSelection()
                }
            }

        case .selectRight:
            if SearchManager.shared.isMultiSearch {
                SearchManager.shared.selectRight()
            } else {
                // Fall back to openSelected behavior
                let arg = SearchManager.shared.selectedItemArgument()
                await OpenCommand.execute(arguments: [arg])
            }

        case .toggleQueueFocus:
            SearchManager.shared.queueFocused.toggle()
            if SearchManager.shared.queueFocused {
                // Clamp queue selection to valid range
                let queueCount = Player.shared.queue.count
                if SearchManager.shared.queueSelectedIndex >= queueCount {
                    SearchManager.shared.queueSelectedIndex = max(0, queueCount - 1)
                }
            }

        case .removeFromQueue:
            guard SearchManager.shared.queueFocused else { break }
            let idx = SearchManager.shared.queueSelectedIndex
            // Index 0 is the currently playing song - skip it
            guard idx > 0 else {
                await CommandInput.shared.setLastCommandOutput("Can't remove currently playing song")
                break
            }
            let queueCount = Player.shared.queue.count
            guard idx < queueCount else { break }
            await Player.shared.removeFromQueue(at: idx)
            // Adjust selection if we removed the last item
            let newCount = Player.shared.queue.count
            if SearchManager.shared.queueSelectedIndex >= newCount && newCount > 0 {
                SearchManager.shared.queueSelectedIndex = newCount - 1
            }

        }
        return
    }
}

public enum CommandAction: String, Sendable, Codable {
    case addToQueue
    case playPauseToggle
    case play
    case pause
    case stop
    case clearQueue
    case playNext
    case startSeekingForward
    case playPrevious
    case startSeekingBackward
    case stopSeeking
    case restartSong
    case quitApplication
    case search
    case setSongTime
    case stationFromCurrentEntry
    case repeatMode
    case shuffleMode
    case reloadTheme
    case open
    case close
    case closeAll
    case selectDown
    case selectUp
    case addSelectedAndPlay
    case openSelected
    case playIndex
    case addAllAndPlay
    case volumeUp
    case volumeDown
    case selectLeft
    case selectRight
    case toggleQueueFocus
    case removeFromQueue
}
