import Foundation
import MusicKit
import SwiftNotCurses

@MainActor
public class QueuePage: Page {

    private let plane: Plane
    private let borderPlane: Plane
    private let pageNamePlane: Plane

    private let shufflePlane: Plane
    private let repeatPlane: Plane

    private var state: PageState

    private var currentQueue: ApplicationMusicPlayer.Queue.Entries?
    private var cache: [Page]
    private var queueIndicesPlane: Plane?
    private var lastQueueSelectedIndex: Int = -1
    private var lastQueueFocused: Bool = false
    private var scrollOffset: Int = 0

    private var maxItemsDisplayed: Int {
        (Int(self.state.height) - 7) / 5
    }

    public func onResize(newPageState: PageState) async {
        self.state = newPageState

        plane.updateByPageState(state)

        // If too small to display (hidden), just erase everything
        guard state.height >= 5 && state.width >= 5 else {
            plane.erase()
            borderPlane.erase()
            pageNamePlane.erase()
            shufflePlane.erase()
            repeatPlane.erase()
            queueIndicesPlane?.erase()
            for case let item as SongItemPage in cache {
                await item.destroy()
            }
            cache = []
            queueIndicesPlane?.erase()
            queueIndicesPlane?.destroy()
            queueIndicesPlane = nil
            self.currentQueue = nil
            return
        }

        plane.blank()

        borderPlane.updateByPageState(.init(absX: 0, absY: 0, width: state.width, height: state.height))
        borderPlane.erase()
        borderPlane.windowBorder(width: state.width, height: state.height)

        shufflePlane.updateByPageState(
            .init(
                absX: Int32(state.width) - 24,
                absY: Int32(state.height) - 1,
                width: 11,
                height: 1
            )
        )
        repeatPlane.updateByPageState(
            .init(
                absX: Int32(state.width) - 12,
                absY: Int32(state.height) - 1,
                width: 11,
                height: 1
            )
        )

        self.currentQueue = nil
    }

    public func getPageState() async -> PageState { self.state }

    public func getMaxDimensions() async -> (width: UInt32, height: UInt32)? { nil }

    public func getMinDimensions() async -> (width: UInt32, height: UInt32) { (23, 17) }

    public init?(
        stdPlane: Plane,
        state: PageState
    ) {
        self.state = state
        guard
            let plane = Plane(
                in: stdPlane,
                opts: .init(
                    x: 30,
                    y: 0,
                    width: state.width,
                    height: state.height - 3,
                    debugID: "QUEUE_PAGE",
                    flags: [.fixed]
                )
            )
        else {
            return nil
        }
        self.plane = plane

        guard
            let borderPlane = Plane(
                in: plane,
                state: .init(
                    absX: 0,
                    absY: 0,
                    width: state.width,
                    height: state.height
                ),
                debugID: "QUEUE_BORDER"
            )
        else {
            return nil
        }
        self.borderPlane = borderPlane

        guard
            let pageNamePlane = Plane(
                in: plane,
                state: .init(
                    absX: 2,
                    absY: 0,
                    width: 7,
                    height: 1
                ),
                debugID: "QUEUE_PAGE_NAME"
            )
        else {
            return nil
        }
        self.pageNamePlane = pageNamePlane

        guard
            let shufflePlane = Plane(
                in: plane,
                state: .init(
                    absX: Int32(state.width) - 12,
                    absY: Int32(state.height) - 2,
                    width: 11,
                    height: 1
                ),
                debugID: "QUEUE_PAGE_SH"
            )
        else {
            return nil
        }
        self.shufflePlane = shufflePlane

        guard
            let repeatPlane = Plane(
                in: plane,
                state: .init(
                    absX: Int32(state.width) - 12,
                    absY: Int32(state.height) - 2,
                    width: 10,
                    height: 1
                ),
                debugID: "QUEUE_PAGE_RE"
            )
        else {
            return nil
        }
        self.repeatPlane = repeatPlane

        self.cache = []
        self.currentQueue = nil

        updateColors()
    }

    public func updateColors() {
        let colorConfig = Theme.shared.queue
        plane.setColorPair(colorConfig.page)
        borderPlane.setColorPair(colorConfig.border)
        pageNamePlane.setColorPair(colorConfig.pageName)
        shufflePlane.setColorPair(colorConfig.shuffleMode)
        repeatPlane.setColorPair(colorConfig.repeatMode)

        guard state.width >= 5 && state.height >= 5 else { return }

        plane.blank()
        borderPlane.windowBorder(width: state.width, height: state.height)
        pageNamePlane.putString("Up Next", at: (0, 0))

        for item in cache {
            item.updateColors()
        }
    }

    public func render() async {

        // Hidden state - don't render
        guard state.height >= 5 && state.width >= 5 else { return }

        switch Player.shared.player.state.repeatMode {
        case Optional.none, .some(.none):
            repeatPlane.width = 10
            repeatPlane.putString("Repeat:Off", at: (0, 0))
        case .one:
            repeatPlane.width = 10
            repeatPlane.putString("Repeat:One", at: (0, 0))
        case .all:
            repeatPlane.width = 10
            repeatPlane.putString("Repeat:All", at: (0, 0))
        @unknown default:
            logger?.error("QueuePage: Unhandled repeat mode.")
        }

        switch Player.shared.player.state.shuffleMode {
        case Optional.none, .off:
            shufflePlane.width = 11
            shufflePlane.putString("Shuffle:Off", at: (0, 0))
        case .songs:
            shufflePlane.width = 10
            shufflePlane.putString("Shuffle:On", at: (0, 0))
        @unknown default:
            logger?.error("QueuePage: Unhandled shuffle mode.")
        }

        let queueFocused = SearchManager.shared.queueFocused

        // Clamp selection to valid range every frame (queue shifts during playback)
        let queueCount = Player.shared.queue.count
        if queueCount == 0 {
            SearchManager.shared.queueSelectedIndex = 0
        } else if SearchManager.shared.queueSelectedIndex >= queueCount {
            SearchManager.shared.queueSelectedIndex = queueCount - 1
        }

        let queueSelectedIndex = SearchManager.shared.queueSelectedIndex

        // Handle scroll offset when queue is focused
        if queueFocused {
            let maxItems = maxItemsDisplayed + 1
            if queueSelectedIndex >= scrollOffset + maxItems {
                scrollOffset = queueSelectedIndex - maxItems + 1
                currentQueue = nil  // Force re-render
            } else if queueSelectedIndex < scrollOffset {
                scrollOffset = queueSelectedIndex
                currentQueue = nil  // Force re-render
            }
        } else if scrollOffset != 0 {
            scrollOffset = 0
            currentQueue = nil  // Force re-render
        }

        // Update selection indicator
        if queueFocused != lastQueueFocused || queueSelectedIndex != lastQueueSelectedIndex {
            lastQueueFocused = queueFocused
            lastQueueSelectedIndex = queueSelectedIndex
            let colorConfig = Theme.shared.queue
            let accentColor = colorConfig.pageName
            let dimColor = colorConfig.border
            if queueFocused && !cache.isEmpty {
                queueIndicesPlane?.erase()
                for i in 0..<cache.count {
                    let realIndex = i + scrollOffset
                    if realIndex == 0 {
                        queueIndicesPlane?.setColorPair(accentColor)
                        queueIndicesPlane?.putString("▶", at: (x: 0, y: 1 + Int32(i) * 5))
                    } else if realIndex == queueSelectedIndex {
                        queueIndicesPlane?.setColorPair(accentColor)
                        queueIndicesPlane?.putString(">", at: (x: 0, y: 1 + Int32(i) * 5))
                    } else {
                        queueIndicesPlane?.setColorPair(dimColor)
                        queueIndicesPlane?.putString(" ", at: (x: 0, y: 1 + Int32(i) * 5))
                    }
                }
                queueIndicesPlane?.setColorPair(dimColor)
            } else {
                // Still show now-playing marker even when not focused
                queueIndicesPlane?.erase()
                if !cache.isEmpty && scrollOffset == 0 {
                    queueIndicesPlane?.setColorPair(accentColor)
                    queueIndicesPlane?.putString("▶", at: (x: 0, y: 1))
                    queueIndicesPlane?.setColorPair(dimColor)
                }
            }
        }

        guard currentQueue != Player.shared.queue else {
            return
        }
        logger?.debug("Queue UI update")
        for case let item as SongItemPage in cache {
            await item.destroy()
        }
        cache = []
        queueIndicesPlane?.erase()
        queueIndicesPlane?.destroy()
        queueIndicesPlane = nil

        currentQueue = Player.shared.queue
        guard let currentQueue = currentQueue else { return }

        // Create indices plane
        queueIndicesPlane = Plane(
            in: borderPlane,
            state: .init(
                absX: 0,
                absY: 0,
                width: 1,
                height: state.height - 2
            ),
            debugID: "QUEUE_IDX"
        )
        let colorConfig = Theme.shared.queue
        queueIndicesPlane?.setColorPair(colorConfig.border)

        let maxItems = maxItemsDisplayed + 1
        var i = 0
        let entries = Array(currentQueue)
        let end = min(entries.count, scrollOffset + maxItems)
        for itemIndex in scrollOffset..<end {
            switch entries[itemIndex].item {
            case .song(let song):
                guard
                    let page = SongItemPage(
                        in: self.borderPlane,
                        state: .init(
                            absX: 2,
                            absY: 1 + Int32(i) * 5,
                            width: state.width - 3,
                            height: 5
                        ),
                        type: .queuePage,
                        item: song
                    )
                else {
                    continue
                }
                i += 1
                self.cache.append(page)
            default: break
            }
        }

        // Draw indicators
        for i in 0..<cache.count {
            let realIndex = i + scrollOffset
            if realIndex == 0 {
                queueIndicesPlane?.setColorPair(colorConfig.pageName)
                queueIndicesPlane?.putString("▶", at: (x: 0, y: 1 + Int32(i) * 5))
            } else if queueFocused && realIndex == queueSelectedIndex {
                queueIndicesPlane?.setColorPair(colorConfig.pageName)
                queueIndicesPlane?.putString(">", at: (x: 0, y: 1 + Int32(i) * 5))
            } else {
                queueIndicesPlane?.setColorPair(colorConfig.border)
                queueIndicesPlane?.putString(" ", at: (x: 0, y: 1 + Int32(i) * 5))
            }
        }
        queueIndicesPlane?.setColorPair(colorConfig.border)

    }

}
