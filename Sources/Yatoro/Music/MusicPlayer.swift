import AVFoundation
import Logging
import MediaPlayer
@preconcurrency import MusicKit

public typealias Player = AudioPlayerManager

public typealias LibraryTopResult = MusicLibrarySearchResponse.TopResult
public typealias CatalogTopResult = MusicCatalogSearchResponse.TopResult

extension CatalogTopResult: @retroactive MusicCatalogSearchable {}
extension LibraryTopResult: @retroactive MusicLibrarySearchable {}

public final class AudioPlayerManager: Sendable {

    @MainActor static let shared = AudioPlayerManager()

    public let player = ApplicationMusicPlayer.shared

    public var queue: ApplicationMusicPlayer.Queue.Entries {
        guard let currentEntry = player.queue.currentEntry else {
            return player.queue.entries
        }

        guard
            let currentPosition = player.queue.entries.firstIndex(
                where: { currentEntry.id == $0.id }
            )
        else {
            return player.queue.entries
        }

        let entries = ApplicationMusicPlayer.Queue.Entries(
            player.queue.entries[currentPosition...]
        )
        return entries

    }

    var nowPlaying: Song? {
        switch player.queue.currentEntry?.item {
        case .song(let song): return song
        default: return nil
        }
    }

    var upNext: Song? {
        guard let currentEntry = player.queue.currentEntry,
              let currentIndex = player.queue.entries.firstIndex(of: currentEntry)
        else { return nil }
        let nextIndex = player.queue.entries.index(after: currentIndex)
        guard nextIndex < player.queue.entries.endIndex else { return nil }
        switch player.queue.entries[nextIndex].item {
        case .song(let song): return song
        default: return nil
        }
    }

    public var status: ApplicationMusicPlayer.PlaybackStatus {
        player.state.playbackStatus
    }
}

// STARTUP
public extension AudioPlayerManager {

    func authorize() async {
        await logger?.trace("Sending music authorization request...")
        let authorizationStatus = await MusicAuthorization.request()
        guard authorizationStatus == .authorized else {
            await logger?.debug(
                "Music authorization not granted. Status: \(authorizationStatus.description)"
            )
            fatalError("Cannot authorize Apple Music request.")
        }
        await logger?.debug("Music authorization granted.")
    }

}

// PLAYBACK
public extension AudioPlayerManager {

    private func _play() async throws {
        await logger?.trace("Trying to play...")
        let playerStatus = player.state.playbackStatus
        await logger?.trace("Player status: \(playerStatus)")
        switch player.state.playbackStatus {
        case .paused:
            await logger?.trace("Trying to continue playing...")
            try await player.play()
            await logger?.trace("Player playing.")
            return
        case .playing:
            await logger?.debug("Player is already playing.")
            return
        case .stopped:
            try await player.play()
        case .interrupted:
            await logger?.critical("Something went wrong: Player status interrupted.")
            return
        case .seekingForward, .seekingBackward:
            await logger?.trace("Trying to stop seeking...")
            player.endSeeking()
            return
        @unknown default:
            await logger?.error("Unknown player status \(playerStatus).")
            return
        }
    }

    func play() async {
        do {
            try await _play()
        } catch {
            await logger?.error(
                "Error playing: \(error.localizedDescription) \(type(of: error))"
            )
        }
    }

    func pause() async {
        await logger?.trace("Trying to pause...")
        let playerStatus = player.state.playbackStatus
        await logger?.trace("Player status: \(playerStatus)")
        switch player.state.playbackStatus {
        case .paused:
            await logger?.debug("Player is already paused.")
            return
        case .playing:
            player.pause()
            await logger?.trace("Player paused.")
            return
        case .stopped:
            await logger?.error("Trying to pause stopped player.")
            return
        case .interrupted:
            await logger?.critical("Something went wrong: Player status interrupted.")
            return
        case .seekingForward, .seekingBackward:
            await logger?.trace("Trying to stop seeking...")
            player.endSeeking()
            player.pause()
            await logger?.trace("Player stopped seeking and paused.")
            return
        @unknown default:
            await logger?.error("Unknown player status \(playerStatus).")
            return
        }
    }

    func playPauseToggle() async {
        switch player.state.playbackStatus {
        case .paused:
            await self.play()
        case .playing:
            await self.pause()
        case .stopped:
            await self.play()
        default:
            return
        }
    }

    func restartSong() async {
        player.restartCurrentEntry()
    }

    func playNext() async {
        do {
            try await player.skipToNextEntry()
        } catch {
            await logger?.error("Failed to play next: \(error.localizedDescription)")
        }
    }

    func playPrevious() async {
        do {
            try await player.skipToPreviousEntry()
        } catch {
            await logger?.error(
                "Failed to play previous: \(error.localizedDescription)"
            )
        }
    }

    func clearQueue() async {
        player.stop()
        player.queue.entries = []
    }

    func addItemsToQueue<T>(
        items: MusicItemCollection<T>,
        at position: ApplicationMusicPlayer.Queue.EntryInsertionPosition
    ) async
    where T: PlayableMusicItem {
        do {
            if player.queue.entries.isEmpty {
                player.queue = .init(for: items)
            } else {
                try await player.queue.insert(items, position: position)
            }
        } catch {
            await logger?.error(
                "Unable to add songs to player queue: \(error.localizedDescription)"
            )
            return
        }
        do {
            if !player.isPreparedToPlay {
                await logger?.trace("Preparing player...")
                try await player.prepareToPlay()
            }
        } catch {
            await logger?.critical("Unable to prepare player: \(error.localizedDescription)")
        }
    }

    func addPlaylistToQueue(
        playlist: Playlist,
        at position: ApplicationMusicPlayer.Queue.EntryInsertionPosition
    ) async {
        do {
            if player.queue.entries.isEmpty {
                player.queue = .init(for: [playlist])
            } else {
                try await player.queue.insert(playlist, position: position)
            }
        } catch {
            await logger?.error(
                "Unable to add playlist to player queue: \(error.localizedDescription)"
            )
            return
        }
        do {
            if !player.isPreparedToPlay {
                await logger?.trace("Preparing player...")
                try await player.prepareToPlay()
            }
        } catch {
            await logger?.critical("Unable to prepare player: \(error.localizedDescription)")
        }
    }

    func setTime(
        seconds: Int,
        relative: Bool
    ) async {
        guard let nowPlaying else {
            await logger?.debug("Unable to set time for current song: Not playing")
            return
        }
        guard let nowPlayingDuration = nowPlaying.duration else {
            await logger?.debug(
                "Unable to set time for current song: Undefined duration"
            )
            return
        }
        if relative {
            if player.playbackTime + Double(seconds) < 0 {
                player.playbackTime = 0
            } else if player.playbackTime + Double(seconds) > nowPlayingDuration {
                player.playbackTime = nowPlayingDuration
            } else {
                player.playbackTime = player.playbackTime + Double(seconds)
            }
            await logger?.trace("Set time for current song: \(player.playbackTime)")
            return
        }
        guard seconds >= 0 else {
            await logger?.debug(
                "Unable to set time for current song: Negative seconds."
            )
            return
        }
        guard Double(seconds) <= nowPlayingDuration else {
            await logger?.debug(
                "Unable to set time for current song: seconds greater than song duration."
            )
            return
        }
        player.playbackTime = Double(seconds)
        await logger?.trace("Set time for current song: \(player.playbackTime)")
    }

    func volumeUp() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "set volume output volume ((output volume of (get volume settings)) + 10)"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            await logger?.error("Failed to increase volume: \(error.localizedDescription)")
        }
    }

    func volumeDown() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "set volume output volume ((output volume of (get volume settings)) - 10)"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            await logger?.error("Failed to decrease volume: \(error.localizedDescription)")
        }
    }

    func removeFromQueue(at visibleIndex: Int) async {
        guard let currentEntry = player.queue.currentEntry,
              let currentPosition = player.queue.entries.firstIndex(where: { currentEntry.id == $0.id })
        else {
            await logger?.debug("removeFromQueue: No current entry")
            return
        }
        let actualIndex = player.queue.entries.index(currentPosition, offsetBy: visibleIndex)
        guard player.queue.entries.indices.contains(actualIndex) else {
            await logger?.debug("removeFromQueue: Index out of range")
            return
        }
        player.queue.entries.remove(at: actualIndex)
        await logger?.debug("removeFromQueue: Removed entry at visible index \(visibleIndex)")
    }

    func playStationFromCurrentSong() async {
        await logger?.trace("Trying to play station from currently playing song...")
        guard var nowPlaying else {
            await logger?.debug("Unable to play station from currently playing song: Now playing is nil.")
            return
        }
        do {
            nowPlaying = try await nowPlaying.with([.station])
        } catch {
            await logger?.error("Unable to play station from currently playing song: \(error.localizedDescription)")
            return
        }
        guard let station = nowPlaying.station else {
            await logger?.debug("Unable to play station from currently playing song: Song has no stations.")
            return
        }
        do {
            try await player.queue.insert(station, position: .afterCurrentEntry)
        } catch {
            await logger?.error("Unable to play station from currently playing song: \(error.localizedDescription)")
            return
        }
        await logger?.debug("Playing station \(station)...")
        await play()
    }

}

public protocol AnyPlayableMusicItemCollection {}
extension MusicItemCollection: AnyPlayableMusicItemCollection
where Element: PlayableMusicItem {}
