import Foundation
import MusicKit
import SwiftNotCurses

@MainActor
public class SearchPage: DestroyablePage {

    private let stdPlane: Plane

    private let plane: Plane
    private let pageNamePlane: Plane
    private let borderPlane: Plane
    private let searchPhrasePlane: Plane
    private let itemIndicesPlane: Plane

    public static var searchPageQueue: SearchPageQueue?
    /// Set by close command when an inline (nil-page) queue node is popped.
    /// The next render frame will clear cached content and recreate from scratch.
    public static var needsInlineRefresh = false

    private var state: PageState

    private var lastSearchTime: Date
    private var searchCache: [Page]

    private var maxItemsDisplayed: Int {
        (Int(self.state.height) - 7) / 5
    }

    public func onResize(newPageState: PageState) async {
        self.state = newPageState
        plane.updateByPageState(state)

        // If too small to display (hidden), just erase everything
        guard state.height >= 5 else {
            plane.erase()
            borderPlane.erase()
            pageNamePlane.erase()
            searchPhrasePlane.erase()
            itemIndicesPlane.erase()
            for case let item as DestroyablePage in searchCache {
                await item.destroy()
            }
            self.searchCache = []
            await destroyMultiSearchPlanes()
            await destroyDualPlaylistPlanes()
            return
        }

        borderPlane.updateByPageState(
            .init(
                absX: 0,
                absY: 0,
                width: state.width,
                height: state.height
            )
        )
        borderPlane.erase()
        borderPlane.windowBorder(width: state.width, height: state.height)

        pageNamePlane.updateByPageState(.init(absX: 2, absY: 0, width: 13, height: 1))

        itemIndicesPlane.erase()
        itemIndicesPlane.updateByPageState(.init(absX: 1, absY: 1, width: 1, height: state.height - 2))

        for case let item as DestroyablePage in searchCache {
            await item.destroy()
        }
        self.searchCache = []
        await destroyMultiSearchPlanes()
        await destroyDualPlaylistPlanes()
    }

    public func getPageState() async -> PageState { self.state }

    public func getMaxDimensions() async -> (width: UInt32, height: UInt32)? { nil }

    public func getMinDimensions() async -> (width: UInt32, height: UInt32) { (23, 17) }

    public init?(stdPlane: Plane, state: PageState) {
        self.stdPlane = stdPlane
        self.state = state
        guard
            let plane = Plane(
                in: stdPlane,
                opts: .init(
                    x: 30,
                    y: 0,
                    width: state.width,
                    height: state.height - 3,
                    debugID: "SEARCH_PAGE"
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
                debugID: "SEARCH_BORDER"
            )
        else {
            return nil
        }
        self.borderPlane = borderPlane

        guard
            let searchPhrasePlane = Plane(
                in: plane,
                state: .init(absX: 2, absY: 0, width: 1, height: 1),
                debugID: "SEARCH_SP"
            )
        else {
            return nil
        }
        self.searchPhrasePlane = searchPhrasePlane

        guard
            let pageNamePlane = Plane(
                in: plane,
                state: .init(
                    absX: 2,
                    absY: 0,
                    width: 6,
                    height: 1
                ),
                debugID: "SEARCH_PAGE_NAME"
            )
        else {
            return nil
        }
        self.pageNamePlane = pageNamePlane

        guard
            let itemIndicesPlane = Plane(
                in: plane,
                state: .init(
                    absX: 1,
                    absY: 1,
                    width: 1,
                    height: state.height - 2
                ),
                debugID: "SEARCH_II"
            )
        else {
            return nil
        }
        self.itemIndicesPlane = itemIndicesPlane

        self.searchCache = []
        self.lastSearchTime = .now

        updateColors()
    }

    public func updateColors() {
        let colorConfig = Theme.shared.search
        plane.setColorPair(colorConfig.page)
        borderPlane.setColorPair(colorConfig.border)
        searchPhrasePlane.setColorPair(colorConfig.searchPhrase)
        pageNamePlane.setColorPair(colorConfig.pageName)
        itemIndicesPlane.setColorPair(colorConfig.itemIndices)

        // Skip drawing when hidden (dimensions too small for border)
        guard state.width >= 3 && state.height >= 3 else { return }

        plane.blank()
        borderPlane.windowBorder(width: state.width, height: state.height)

        for item in searchCache {
            item.updateColors()
        }
        for col in multiColumns { for item in col.cache { item.updateColors() } }
        for col in dualColumns { for item in col.cache { item.updateColors() } }

        var node = SearchPage.searchPageQueue
        while node != nil {
            node?.page?.updateColors()
            node = node?.previous
        }
    }

    private var lastSelectedIndex: Int = -1
    private var lastSelectedColumn: Int = -1
    private var searchScrollOffset: Int = 0

    private class ColumnState {
        var headerPlane: Plane?
        var indicesPlane: Plane?
        var cache: [Page] = []
        var scrollOffset: Int = 0
        let headerText: String

        init(_ headerText: String) {
            self.headerText = headerText
        }
    }

    // Multi-search columns (0=artists, 1=albums, 2=songs)
    private var multiColumns: [ColumnState] = [
        ColumnState("Artists"), ColumnState("Albums"), ColumnState("Songs")
    ]
    private var isMultiSearchRendered: Bool = false
    private var currentMultiResult: MultiSearchResult?

    // Dual playlist columns (0=library, 1=catalog)
    private var dualColumns: [ColumnState] = [
        ColumnState("My Playlists"), ColumnState("Playlists")
    ]
    private var isDualPlaylistRendered: Bool = false
    private var currentDualPlaylistResult: DualPlaylistSearchResult?

    private var multiMaxItems: Int {
        (Int(self.state.height) - 4) / 5
    }

    private func updateSelectionIndicator() -> Bool {
        let selectedIndex = SearchManager.shared.selectedIndex
        var scrollChanged = false

        let maxItems = maxItemsDisplayed + 1
        if selectedIndex >= searchScrollOffset + maxItems {
            searchScrollOffset = selectedIndex - maxItems + 1
            scrollChanged = true
        } else if selectedIndex < searchScrollOffset {
            searchScrollOffset = selectedIndex
            scrollChanged = true
        }

        guard selectedIndex != lastSelectedIndex || scrollChanged else { return scrollChanged }
        lastSelectedIndex = selectedIndex
        let itemCount = searchCache.count
        guard itemCount > 0 else { return scrollChanged }
        itemIndicesPlane.erase()
        for i in 0..<itemCount {
            let realIndex = i + searchScrollOffset
            let marker = realIndex == selectedIndex ? ">" : " "
            itemIndicesPlane.putString("\(marker)\(realIndex)", at: (x: 0, y: 2 + Int32(i) * 5))
        }
        return scrollChanged
    }

    private func updateColumnsSelectionIndicator(
        columns: [ColumnState],
        rerenderColumn: (Int) async -> Void
    ) async {
        let selectedIndex = SearchManager.shared.selectedIndex
        let selectedColumn = SearchManager.shared.selectedColumn
        guard selectedIndex != lastSelectedIndex || selectedColumn != lastSelectedColumn else { return }
        lastSelectedIndex = selectedIndex
        lastSelectedColumn = selectedColumn

        let colType = SearchManager.shared.multiSearchColumnType()
        let maxItems = multiMaxItems

        // Calculate needed scroll offset for the active column
        let col = columns[colType]
        var offset = col.scrollOffset
        if selectedIndex >= offset + maxItems {
            offset = selectedIndex - maxItems + 1
        } else if selectedIndex < offset {
            offset = selectedIndex
        }

        // If scroll offset changed, re-render that column
        if offset != col.scrollOffset {
            col.scrollOffset = offset
            await rerenderColumn(colType)
        }

        // Dim inactive column headers, brighten active + update indices
        let colorConfig = Theme.shared.search
        let activeColor = colorConfig.pageName
        let dimColor = colorConfig.itemIndices
        for (i, col) in columns.enumerated() {
            col.headerPlane?.erase()
            col.headerPlane?.setColorPair(i == colType ? activeColor : dimColor)
            col.headerPlane?.putString(col.headerText, at: (0, 0))

            col.indicesPlane?.erase()
            for j in 0..<col.cache.count {
                let realIndex = j + col.scrollOffset
                let marker = (i == colType && realIndex == selectedIndex) ? ">" : " "
                col.indicesPlane?.putString("\(marker)\(realIndex)", at: (x: 0, y: 2 + Int32(j) * 5))
            }
        }
    }

    private func rerenderMultiColumn(_ colType: Int, multiResult: MultiSearchResult) async {
        let colWidth = state.width / 3
        let maxItems = multiMaxItems
        let col = multiColumns[colType]
        let offset = col.scrollOffset
        for case let item as DestroyablePage in col.cache { await item.destroy() }
        col.cache = []

        switch colType {
        case 0:  // Artists
            if let artists = multiResult.artists, !artists.isEmpty {
                let colX: Int32 = 1
                let end = min(artists.count, offset + maxItems)
                for i in offset..<end {
                    let slot = i - offset
                    if let item = await ArtistItemPage(
                        in: borderPlane,
                        state: .init(
                            absX: colX + 3,
                            absY: 3 + Int32(slot) * 5,
                            width: colWidth - 5,
                            height: 5
                        ),
                        item: artists[i],
                        type: .searchPage
                    ) {
                        col.cache.append(item)
                    }
                }
            }
        case 1:  // Albums
            if let albums = multiResult.albums, !albums.isEmpty {
                let colX: Int32 = Int32(colWidth)
                let end = min(albums.count, offset + maxItems)
                for i in offset..<end {
                    let slot = i - offset
                    if let item = AlbumItemPage(
                        in: borderPlane,
                        state: .init(
                            absX: colX + 3,
                            absY: 3 + Int32(slot) * 5,
                            width: colWidth - 5,
                            height: 5
                        ),
                        item: albums[i],
                        type: .searchPage
                    ) {
                        col.cache.append(item)
                    }
                }
            }
        case 2:  // Songs
            if let songs = multiResult.songs, !songs.isEmpty {
                let colX: Int32 = Int32(colWidth * 2)
                let end = min(songs.count, offset + maxItems)
                for i in offset..<end {
                    let slot = i - offset
                    if let item = SongItemPage(
                        in: borderPlane,
                        state: .init(
                            absX: colX + 3,
                            absY: 3 + Int32(slot) * 5,
                            width: colWidth - 4,
                            height: 5
                        ),
                        type: .searchPage,
                        item: songs[i]
                    ) {
                        col.cache.append(item)
                    }
                }
            }
        default: break
        }
    }

    private func destroyColumns(_ columns: [ColumnState]) async {
        for col in columns {
            for case let item as DestroyablePage in col.cache { await item.destroy() }
            col.cache = []
            col.indicesPlane?.erase()
            col.indicesPlane?.destroy()
            col.indicesPlane = nil
            col.headerPlane?.erase()
            col.headerPlane?.destroy()
            col.headerPlane = nil
            col.scrollOffset = 0
        }
    }

    private func destroyMultiSearchPlanes() async {
        await destroyColumns(multiColumns)
        isMultiSearchRendered = false
        currentMultiResult = nil
    }

    private func destroyDualPlaylistPlanes() async {
        await destroyColumns(dualColumns)
        isDualPlaylistRendered = false
        currentDualPlaylistResult = nil
    }

    private func ensureColumnPlanes(
        _ col: ColumnState,
        colX: Int32,
        contentHeight: UInt32,
        colorConfig: Theme.Search,
        debugPrefix: String,
        colIndex: Int
    ) {
        if col.headerPlane == nil {
            col.headerPlane = Plane(
                in: borderPlane,
                state: .init(absX: colX + 1, absY: 1, width: UInt32(col.headerText.count), height: 1),
                debugID: "\(debugPrefix)_H\(colIndex)"
            )
            col.headerPlane?.setColorPair(colorConfig.pageName)
            col.headerPlane?.putString(col.headerText, at: (0, 0))
        }
        if col.indicesPlane == nil {
            col.indicesPlane = Plane(
                in: borderPlane,
                state: .init(absX: colX, absY: 3, width: 3, height: contentHeight - 3),
                debugID: "\(debugPrefix)_I\(colIndex)"
            )
            col.indicesPlane?.setColorPair(colorConfig.itemIndices)
        }
    }

    private func renderDualPlaylistColumns(_ dualResult: DualPlaylistSearchResult) async {
        for col in dualColumns {
            for case let item as DestroyablePage in col.cache { await item.destroy() }
            col.cache = []
        }

        let colorConfig = Theme.shared.search
        let colWidth = state.width / 2
        let contentHeight = state.height - 2
        let maxItems = multiMaxItems
        let playlistSets: [MusicItemCollection<Playlist>?] = [dualResult.libraryPlaylists, dualResult.catalogPlaylists]

        for (colIndex, playlists) in playlistSets.enumerated() {
            guard let playlists, !playlists.isEmpty else { continue }
            let col = dualColumns[colIndex]
            let colX: Int32 = colIndex == 0 ? 1 : Int32(colWidth)
            let trailingPad: UInt32 = colIndex == 0 ? 5 : 4

            ensureColumnPlanes(col, colX: colX, contentHeight: contentHeight, colorConfig: colorConfig, debugPrefix: "DP", colIndex: colIndex)

            let offset = col.scrollOffset
            let end = min(playlists.count, offset + maxItems)
            for i in offset..<end {
                let slot = i - offset
                col.indicesPlane?.putString(" \(i)", at: (x: 0, y: 2 + Int32(slot) * 5))
                if let item = PlaylistItemPage(
                    in: borderPlane,
                    state: .init(
                        absX: colX + 3,
                        absY: 3 + Int32(slot) * 5,
                        width: colWidth - trailingPad,
                        height: 5
                    ),
                    item: playlists[i],
                    type: .searchPage
                ) {
                    col.cache.append(item)
                }
            }
        }
    }

    private func rerenderDualPlaylistColumn(_ colType: Int, dualResult: DualPlaylistSearchResult) async {
        let colWidth = state.width / 2
        let maxItems = multiMaxItems
        let col = dualColumns[colType]
        let offset = col.scrollOffset
        for case let item as DestroyablePage in col.cache { await item.destroy() }
        col.cache = []

        let playlistSets: [MusicItemCollection<Playlist>?] = [dualResult.libraryPlaylists, dualResult.catalogPlaylists]
        guard let playlists = playlistSets[colType], !playlists.isEmpty else { return }
        let colX: Int32 = colType == 0 ? 1 : Int32(colWidth)
        let trailingPad: UInt32 = colType == 0 ? 5 : 4
        let end = min(playlists.count, offset + maxItems)
        for i in offset..<end {
            let slot = i - offset
            if let item = PlaylistItemPage(
                in: borderPlane,
                state: .init(
                    absX: colX + 3,
                    absY: 3 + Int32(slot) * 5,
                    width: colWidth - trailingPad,
                    height: 5
                ),
                item: playlists[i],
                type: .searchPage
            ) {
                col.cache.append(item)
            }
        }
    }

    public func render() async {

        // Handle pending inline content refresh (set by close/selectLeft commands)
        if SearchPage.needsInlineRefresh {
            SearchPage.needsInlineRefresh = false
            await refreshInlineContent()
        }

        // Sync queue with result chain (safety net for edge cases)
        await syncQueueWithResults()

        // Render current top overlay page (if any)
        await SearchPage.searchPageQueue?.page?.render()

        // Track whether an overlay is covering the background —
        // when true, skip updating the background selection indicator
        // so arrow keys don't visually move both overlay and background.
        let hasOverlay = SearchPage.searchPageQueue?.page != nil

        guard let result = SearchManager.shared.lastSearchResult?.result else {
            for case let item as DestroyablePage in searchCache {
                await item.destroy()
            }
            searchCache = []
            await destroyMultiSearchPlanes()
            await destroyDualPlaylistPlanes()
            lastSelectedIndex = -1
            lastSelectedColumn = -1
            pageNamePlane.erase()
            pageNamePlane.width = 6
            pageNamePlane.putString("Search", at: (0, 0))
            searchPhrasePlane.updateByPageState(.init(absX: 2, absY: 0, width: 1, height: 1))
            searchPhrasePlane.erase()
            itemIndicesPlane.erase()
            while SearchPage.searchPageQueue.size() > 0 {
                await SearchPage.searchPageQueue?.page?.destroy()
                SearchPage.searchPageQueue = SearchPage.searchPageQueue?.previous
            }
            return
        }

        // Update selection indicator — skip when overlay covers the background
        if !hasOverlay {
            if case .multiSearchResult(_) = result {
                await updateColumnsSelectionIndicator(columns: multiColumns) { colType in
                    if let msr = self.currentMultiResult {
                        await self.rerenderMultiColumn(colType, multiResult: msr)
                    }
                }
            } else if case .dualPlaylistSearchResult(_) = result {
                await updateColumnsSelectionIndicator(columns: dualColumns) { colType in
                    if let dpr = self.currentDualPlaylistResult {
                        await self.rerenderDualPlaylistColumn(colType, dualResult: dpr)
                    }
                }
            } else {
                let scrollChanged = updateSelectionIndicator()
                if scrollChanged, case .searchResult(let sr) = result {
                    for case let item as DestroyablePage in searchCache { await item.destroy() }
                    searchCache = []
                    itemIndicesPlane.erase()
                    await update(result: sr)
                    return
                }
            }
        }

        // Re-sync: a close command may have run during selection update
        await syncQueueWithResults()

        guard SearchPage.searchPageQueue.size() < SearchManager.shared.lastSearchResult.size() else {
            return
        }

        switch result {

        case .multiSearchResult(let multiResult):
            guard !isMultiSearchRendered else { return }

            // Clear single-search state
            for case let item as DestroyablePage in searchCache { await item.destroy() }
            searchCache = []
            itemIndicesPlane.erase()
            await destroyDualPlaylistPlanes()

            while SearchPage.searchPageQueue?.page != nil {
                await SearchPage.searchPageQueue?.page?.destroy()
                SearchPage.searchPageQueue = SearchPage.searchPageQueue?.previous
            }

            let searchPhrase = multiResult.searchPhrase
            pageNamePlane.erase()
            pageNamePlane.width = 7
            pageNamePlane.putString("Search:", at: (0, 0))
            let searchPhrasePlaneWidth = min(
                UInt32(searchPhrase.count),
                self.state.width - pageNamePlane.width - 4
            )
            searchPhrasePlane.updateByPageState(
                .init(
                    absX: Int32(pageNamePlane.width) + 3,
                    absY: 0,
                    width: searchPhrasePlaneWidth,
                    height: 1
                )
            )
            searchPhrasePlane.putString(searchPhrase, at: (0, 0))

            currentMultiResult = multiResult
            await renderMultiColumns(multiResult)
            isMultiSearchRendered = true

            SearchPage.searchPageQueue = .init(SearchPage.searchPageQueue, page: nil, type: result)
            return

        case .dualPlaylistSearchResult(let dualResult):
            guard !isDualPlaylistRendered else { return }

            // Clear single-search and multi-search state
            for case let item as DestroyablePage in searchCache { await item.destroy() }
            searchCache = []
            itemIndicesPlane.erase()
            await destroyMultiSearchPlanes()

            while SearchPage.searchPageQueue?.page != nil {
                await SearchPage.searchPageQueue?.page?.destroy()
                SearchPage.searchPageQueue = SearchPage.searchPageQueue?.previous
            }

            let searchPhrase = dualResult.searchPhrase
            pageNamePlane.erase()
            pageNamePlane.width = 10
            pageNamePlane.putString("Playlists:", at: (0, 0))
            let searchPhrasePlaneWidth = min(
                UInt32(searchPhrase.count),
                self.state.width - pageNamePlane.width - 4
            )
            searchPhrasePlane.updateByPageState(
                .init(
                    absX: Int32(pageNamePlane.width) + 3,
                    absY: 0,
                    width: searchPhrasePlaneWidth,
                    height: 1
                )
            )
            searchPhrasePlane.putString(searchPhrase, at: (0, 0))

            currentDualPlaylistResult = dualResult
            await renderDualPlaylistColumns(dualResult)
            isDualPlaylistRendered = true

            SearchPage.searchPageQueue = .init(SearchPage.searchPageQueue, page: nil, type: result)
            return

        case .searchResult(let searchResult):
            // Reset scroll for new results
            searchScrollOffset = 0

            // Clear multi-search state if transitioning
            if isMultiSearchRendered {
                await destroyMultiSearchPlanes()
            }
            if isDualPlaylistRendered {
                await destroyDualPlaylistPlanes()
            }

            // Close other pages if they are opened at the moment
            while SearchPage.searchPageQueue?.page != nil {
                await SearchPage.searchPageQueue?.page?.destroy()
                SearchPage.searchPageQueue = SearchPage.searchPageQueue?.previous
            }

            switch searchResult.searchType {

            case .recentlyPlayed:

                pageNamePlane.erase()
                pageNamePlane.width = 15
                pageNamePlane.putString("Recently Played", at: (0, 0))
                searchPhrasePlane.updateByPageState(.init(absX: 2, absY: 0, width: 1, height: 1))
                searchPhrasePlane.erase()

                await update(result: searchResult)
            case .recommended:
                pageNamePlane.erase()
                pageNamePlane.width = 11
                pageNamePlane.putString("Recommended", at: (0, 0))
                searchPhrasePlane.updateByPageState(.init(absX: 2, absY: 0, width: 1, height: 1))
                searchPhrasePlane.erase()

                await update(result: searchResult)

            case .catalogSearch:
                guard let searchPhrase = searchResult.searchPhrase else {
                    return
                }
                pageNamePlane.erase()
                switch searchResult.itemType {
                case .song:
                    pageNamePlane.width = 14
                    pageNamePlane.putString("Catalog songs:", at: (0, 0))
                case .album:
                    pageNamePlane.width = 15
                    pageNamePlane.putString("Catalog albums:", at: (0, 0))
                case .artist:
                    pageNamePlane.width = 16
                    pageNamePlane.putString("Catalog artists:", at: (0, 0))
                case .playlist:
                    pageNamePlane.width = 18
                    pageNamePlane.putString("Catalog playlists:", at: (0, 0))
                case .station:
                    pageNamePlane.width = 17
                    pageNamePlane.putString("Catalog stations:", at: (0, 0))
                }
                let searchPhrasePlaneWidth = min(
                    UInt32(searchPhrase.count),
                    self.state.width - pageNamePlane.width - 4
                )
                searchPhrasePlane.updateByPageState(
                    .init(
                        absX: Int32(pageNamePlane.width) + 3,
                        absY: 0,
                        width: searchPhrasePlaneWidth,
                        height: 1
                    )
                )
                searchPhrasePlane.putString(searchPhrase, at: (0, 0))

                await update(result: searchResult)

            case .librarySearch:
                guard let searchPhrase = searchResult.searchPhrase else {
                    return
                }
                pageNamePlane.erase()
                switch searchResult.itemType {
                case .song:
                    pageNamePlane.width = 14
                    pageNamePlane.putString("Library songs:", at: (0, 0))
                case .album:
                    pageNamePlane.width = 15
                    pageNamePlane.putString("Library albums:", at: (0, 0))
                case .artist:
                    pageNamePlane.width = 16
                    pageNamePlane.putString("Library artists:", at: (0, 0))
                case .playlist:
                    pageNamePlane.width = 18
                    pageNamePlane.putString("Library playlists:", at: (0, 0))
                case .station:
                    pageNamePlane.width = 17
                    pageNamePlane.putString("Library stations:", at: (0, 0))
                }
                searchPhrasePlane.updateByPageState(
                    .init(
                        absX: Int32(pageNamePlane.width) + 3,
                        absY: 0,
                        width: UInt32(searchPhrase.count),
                        height: 1
                    )
                )
                searchPhrasePlane.putString(searchPhrase, at: (0, 0))

                await update(result: searchResult)
            }
            SearchPage.searchPageQueue = .init(SearchPage.searchPageQueue, page: nil, type: result)

        case .albumDescription(let albumDescription):
            let albumDetailPage = AlbumDetailPage(
                in: stdPlane,
                state: .init(
                    absX: 5,
                    absY: 2,
                    width: stdPlane.width - 10,
                    height: stdPlane.height - 6
                ),
                albumDescription: albumDescription
            )
            SearchPage.searchPageQueue = .init(SearchPage.searchPageQueue, page: albumDetailPage, type: result)

        case .artistDescription(let artistDescription):
            let artistDetailPage = ArtistDetailPage(
                in: stdPlane,
                state: .init(
                    absX: 5,
                    absY: 2,
                    width: stdPlane.width - 10,
                    height: stdPlane.height - 6
                ),
                artistDescription: artistDescription
            )
            SearchPage.searchPageQueue = .init(SearchPage.searchPageQueue, page: artistDetailPage, type: result)

        case .playlistDescription(let playlistDescription):
            if SearchManager.shared.lastSearchResult?.inPlace ?? false {
                // Close all active pages
                while SearchPage.searchPageQueue?.page != nil {
                    await SearchPage.searchPageQueue?.page?.destroy()
                    SearchPage.searchPageQueue = SearchPage.searchPageQueue?.previous
                }

                // Open Playlist in-place
                let name = playlistDescription.playlist.name
                pageNamePlane.erase()
                pageNamePlane.width = UInt32(name.count)
                pageNamePlane.putString(name, at: (0, 0))
                searchPhrasePlane.updateByPageState(.init(absX: 2, absY: 0, width: 1, height: 1))
                searchPhrasePlane.erase()

                SearchPage.searchPageQueue = .init(SearchPage.searchPageQueue, page: nil, type: result)

                let searchResult = SearchResult(
                    timestamp: .now,
                    searchType: .catalogSearch,
                    itemType: .song,
                    searchPhrase: nil,
                    result: playlistDescription.songs
                )

                await update(result: searchResult)
                break
            }
            let playlistDetailPage = PlaylistDetailPage(
                in: stdPlane,
                state: .init(
                    absX: 5,
                    absY: 2,
                    width: stdPlane.width - 10,
                    height: stdPlane.height - 6
                ),
                playlistDescription: playlistDescription
            )
            SearchPage.searchPageQueue = .init(SearchPage.searchPageQueue, page: playlistDetailPage, type: result)

        case .songDescription(let songDescription):
            let songDetailPage = SongDetailPage(
                in: stdPlane,
                state: .init(
                    absX: 5,
                    absY: 2,
                    width: stdPlane.width - 10,
                    height: stdPlane.height - 6
                ),
                songDescription: songDescription
            )
            SearchPage.searchPageQueue = .init(SearchPage.searchPageQueue, page: songDetailPage, type: result)

        case .recommendationDescription(let recommendationDescription):
            let recommendationDetailPage = RecommendationDetailPage(
                in: stdPlane,
                state: .init(
                    absX: 5,
                    absY: 2,
                    width: stdPlane.width - 10,
                    height: stdPlane.height - 6
                ),
                recommendationDescription: recommendationDescription
            )
            SearchPage.searchPageQueue = .init(SearchPage.searchPageQueue, page: recommendationDetailPage, type: result)

        case .help:
            let helpPage = HelpPage(
                stdPlane: stdPlane,
                state: .init(
                    absX: 5,
                    absY: 2,
                    width: stdPlane.width - 10,
                    height: stdPlane.height - 6
                )
            )
            SearchPage.searchPageQueue = .init(SearchPage.searchPageQueue, page: helpPage, type: result)

        }

    }

    private func renderMultiColumns(_ multiResult: MultiSearchResult) async {
        for col in multiColumns {
            for case let item as DestroyablePage in col.cache { await item.destroy() }
            col.cache = []
        }

        let colorConfig = Theme.shared.search
        let colWidth = state.width / 3
        let contentHeight = state.height - 2
        let maxItems = multiMaxItems

        // Column 0: Artists
        if let artists = multiResult.artists, !artists.isEmpty {
            let col = multiColumns[0]
            let colX: Int32 = 1
            ensureColumnPlanes(col, colX: colX, contentHeight: contentHeight, colorConfig: colorConfig, debugPrefix: "MS", colIndex: 0)

            let offset = col.scrollOffset
            let end = min(artists.count, offset + maxItems)
            for i in offset..<end {
                let slot = i - offset
                col.indicesPlane?.putString(" \(i)", at: (x: 0, y: 2 + Int32(slot) * 5))
                if let item = await ArtistItemPage(
                    in: borderPlane,
                    state: .init(
                        absX: colX + 3,
                        absY: 3 + Int32(slot) * 5,
                        width: colWidth - 5,
                        height: 5
                    ),
                    item: artists[i],
                    type: .searchPage
                ) {
                    col.cache.append(item)
                }
            }
        }

        // Column 1: Albums
        if let albums = multiResult.albums, !albums.isEmpty {
            let col = multiColumns[1]
            let colX: Int32 = Int32(colWidth)
            ensureColumnPlanes(col, colX: colX, contentHeight: contentHeight, colorConfig: colorConfig, debugPrefix: "MS", colIndex: 1)

            let offset = col.scrollOffset
            let end = min(albums.count, offset + maxItems)
            for i in offset..<end {
                let slot = i - offset
                col.indicesPlane?.putString(" \(i)", at: (x: 0, y: 2 + Int32(slot) * 5))
                if let item = AlbumItemPage(
                    in: borderPlane,
                    state: .init(
                        absX: colX + 3,
                        absY: 3 + Int32(slot) * 5,
                        width: colWidth - 5,
                        height: 5
                    ),
                    item: albums[i],
                    type: .searchPage
                ) {
                    col.cache.append(item)
                }
            }
        }

        // Column 2: Songs
        if let songs = multiResult.songs, !songs.isEmpty {
            let col = multiColumns[2]
            let colX: Int32 = Int32(colWidth * 2)
            ensureColumnPlanes(col, colX: colX, contentHeight: contentHeight, colorConfig: colorConfig, debugPrefix: "MS", colIndex: 2)

            let offset = col.scrollOffset
            let end = min(songs.count, offset + maxItems)
            for i in offset..<end {
                let slot = i - offset
                col.indicesPlane?.putString(" \(i)", at: (x: 0, y: 2 + Int32(slot) * 5))
                if let item = SongItemPage(
                    in: borderPlane,
                    state: .init(
                        absX: colX + 3,
                        absY: 3 + Int32(slot) * 5,
                        width: colWidth - 4,
                        height: 5
                    ),
                    type: .searchPage,
                    item: songs[i]
                ) {
                    col.cache.append(item)
                }
            }
        }
    }

    private func update(result: SearchResult) async {
        guard searchCache.isEmpty || lastSearchTime != result.timestamp else {
            return
        }
        logger?.debug("Search UI update.")

        itemIndicesPlane.erase()
        for case let item as DestroyablePage in searchCache {
            await item.destroy()
        }

        searchCache = []
        lastSearchTime = result.timestamp
        let items = result.result
        switch items {
        case let songs as MusicItemCollection<Song>:
            songItems(songs: songs)
        case let albums as MusicItemCollection<Album>:
            albumItems(albums: albums)
        case let artists as MusicItemCollection<Artist>:
            await artistItems(artists: artists)
        case let playlists as MusicItemCollection<Playlist>:
            playlistItems(playlists: playlists)
        case let stations as MusicItemCollection<Station>:
            stationItems(stations: stations)
        case let recentlyPlayedItems as MusicItemCollection<RecentlyPlayedMusicItem>:
            let maxItems = maxItemsDisplayed + 1
            let end = min(recentlyPlayedItems.count, searchScrollOffset + maxItems)
            var slot = 0
            for itemIndex in searchScrollOffset..<end {
                switch recentlyPlayedItems[itemIndex] {
                case .album(let album):
                    albumItem(album: album, realIndex: itemIndex, displaySlot: slot)
                case .station(let station):
                    stationItem(station: station, realIndex: itemIndex, displaySlot: slot)
                case .playlist(let playlist):
                    playlistItem(playlist: playlist, realIndex: itemIndex, displaySlot: slot)
                @unknown default: break
                }
                slot += 1
            }
        case let recommendedItems as MusicItemCollection<MusicPersonalRecommendation>:
            recommendationItems(recommendations: recommendedItems)
        default: break
        }
    }

    private func songItems(songs: MusicItemCollection<Song>) {
        let maxItems = maxItemsDisplayed + 1
        let end = min(songs.count, searchScrollOffset + maxItems)
        for i in searchScrollOffset..<end {
            let slot = i - searchScrollOffset
            itemIndicesPlane.putString("\(i)", at: (x: 0, y: 2 + Int32(slot) * 5))
            guard
                let item = SongItemPage(
                    in: borderPlane,
                    state: .init(
                        absX: 2,
                        absY: 1 + Int32(slot) * 5,
                        width: state.width - 3,
                        height: 5
                    ),
                    type: .searchPage,
                    item: songs[i]
                )
            else { return }
            self.searchCache.append(item)
        }
    }

    private func albumItems(albums: MusicItemCollection<Album>) {
        let maxItems = maxItemsDisplayed + 1
        let end = min(albums.count, searchScrollOffset + maxItems)
        for i in searchScrollOffset..<end {
            let slot = i - searchScrollOffset
            albumItem(album: albums[i], realIndex: i, displaySlot: slot)
        }
    }

    private func albumItem(album: Album, realIndex: Int, displaySlot: Int) {
        itemIndicesPlane.putString("\(realIndex)", at: (x: 0, y: 2 + Int32(displaySlot) * 5))
        guard
            let item = AlbumItemPage(
                in: borderPlane,
                state: .init(
                    absX: 2,
                    absY: 1 + Int32(displaySlot) * 5,
                    width: state.width - 3,
                    height: 5
                ),
                item: album,
                type: .searchPage
            )
        else { return }
        self.searchCache.append(item)
    }

    private func artistItems(artists: MusicItemCollection<Artist>) async {
        let maxItems = maxItemsDisplayed + 1
        let end = min(artists.count, searchScrollOffset + maxItems)
        for i in searchScrollOffset..<end {
            let slot = i - searchScrollOffset
            await artistItem(artist: artists[i], realIndex: i, displaySlot: slot)
        }
    }

    private func artistItem(artist: Artist, realIndex: Int, displaySlot: Int) async {
        itemIndicesPlane.putString("\(realIndex)", at: (x: 0, y: 2 + Int32(displaySlot) * 5))
        guard
            let item = await ArtistItemPage(
                in: borderPlane,
                state: .init(
                    absX: 2,
                    absY: 1 + Int32(displaySlot) * 5,
                    width: state.width - 3,
                    height: 5
                ),
                item: artist,
                type: .searchPage
            )
        else { return }
        self.searchCache.append(item)
    }

    private func playlistItems(playlists: MusicItemCollection<Playlist>) {
        let maxItems = maxItemsDisplayed + 1
        let end = min(playlists.count, searchScrollOffset + maxItems)
        for i in searchScrollOffset..<end {
            let slot = i - searchScrollOffset
            playlistItem(playlist: playlists[i], realIndex: i, displaySlot: slot)
        }
    }

    private func playlistItem(playlist: Playlist, realIndex: Int, displaySlot: Int) {
        itemIndicesPlane.putString("\(realIndex)", at: (x: 0, y: 2 + Int32(displaySlot) * 5))
        guard
            let item = PlaylistItemPage(
                in: borderPlane,
                state: .init(
                    absX: 2,
                    absY: 1 + Int32(displaySlot) * 5,
                    width: state.width - 3,
                    height: 5
                ),
                item: playlist,
                type: .searchPage
            )
        else { return }
        self.searchCache.append(item)
    }

    private func stationItems(stations: MusicItemCollection<Station>) {
        let maxItems = maxItemsDisplayed + 1
        let end = min(stations.count, searchScrollOffset + maxItems)
        for i in searchScrollOffset..<end {
            let slot = i - searchScrollOffset
            stationItem(station: stations[i], realIndex: i, displaySlot: slot)
        }
    }

    private func stationItem(station: Station, realIndex: Int, displaySlot: Int) {
        itemIndicesPlane.putString("\(realIndex)", at: (x: 0, y: 2 + Int32(displaySlot) * 5))
        guard
            let item = StationItemPage(
                in: borderPlane,
                state: .init(
                    absX: 2,
                    absY: 1 + Int32(displaySlot) * 5,
                    width: state.width - 3,
                    height: 5
                ),
                item: station,
                type: .searchPage
            )
        else { return }
        self.searchCache.append(item)
    }

    private func recommendationItems(recommendations: MusicItemCollection<MusicPersonalRecommendation>) {
        let maxItems = maxItemsDisplayed + 1
        let end = min(recommendations.count, searchScrollOffset + maxItems)
        for i in searchScrollOffset..<end {
            let slot = i - searchScrollOffset
            recommendationItem(recommendation: recommendations[i], realIndex: i, displaySlot: slot)
        }
    }

    private func recommendationItem(recommendation: MusicPersonalRecommendation, realIndex: Int, displaySlot: Int) {
        itemIndicesPlane.putString("\(realIndex)", at: (x: 0, y: 2 + Int32(displaySlot) * 5))
        guard
            let item = RecommendationItemPage(
                in: borderPlane,
                state: .init(
                    absX: 2,
                    absY: 1 + Int32(displaySlot) * 5,
                    width: state.width - 3,
                    height: 5
                ),
                item: recommendation
            )
        else { return }
        self.searchCache.append(item)
    }

    public func destroy() async {
        self.plane.erase()
        self.plane.destroy()

        self.borderPlane.erase()
        self.borderPlane.destroy()

        self.itemIndicesPlane.erase()
        self.itemIndicesPlane.destroy()

        self.pageNamePlane.erase()
        self.pageNamePlane.destroy()

        for case let page as DestroyablePage in searchCache {
            await page.destroy()
        }

        await destroyMultiSearchPlanes()
        await destroyDualPlaylistPlanes()

        var queue = SearchPage.searchPageQueue
        while queue != nil {
            await queue?.page?.destroy()
            queue = queue?.previous
        }
    }

    /// Clears all inline (shared-plane) cached content and pops the current
    /// inline queue node so the switch at the end of render() recreates it.
    private func refreshInlineContent() async {
        for case let item as DestroyablePage in searchCache { await item.destroy() }
        searchCache = []
        itemIndicesPlane.erase()
        searchScrollOffset = 0
        lastSelectedIndex = -1
        lastSelectedColumn = -1
        if isMultiSearchRendered { await destroyMultiSearchPlanes() }
        if isDualPlaylistRendered { await destroyDualPlaylistPlanes() }
        // Pop the current inline node so the switch recreates fresh content
        if SearchPage.searchPageQueue?.page == nil {
            SearchPage.searchPageQueue = SearchPage.searchPageQueue?.previous
        }
    }

    /// Safety net: pops excess queue nodes until queue.size() matches result.size().
    private func syncQueueWithResults() async {
        var poppedInline = false
        while SearchPage.searchPageQueue.size() > SearchManager.shared.lastSearchResult.size() {
            if SearchPage.searchPageQueue?.page == nil { poppedInline = true }
            await SearchPage.searchPageQueue?.page?.destroy()
            SearchPage.searchPageQueue = SearchPage.searchPageQueue?.previous
        }
        if poppedInline {
            await refreshInlineContent()
        }
    }

}

public class SearchPageQueue {
    let previous: SearchPageQueue?
    let page: DestroyablePage?
    let type: OpenedResult
    let timestamp: Date

    init(_ previous: SearchPageQueue? = nil, page: DestroyablePage?, type: OpenedResult) {
        self.previous = previous
        self.page = page
        self.type = type
        self.timestamp = Date.now
    }
}

extension Optional where Wrapped == SearchPageQueue {
    func size() -> Int {
        guard let queue = self else {
            return 0
        }
        return 1 + queue.previous.size()
    }

    /// Amount of pages opened excluding the in-place searches and pages
    var amountOfPagesOpened: Int {
        guard let queue = self else {
            return 0
        }
        if queue.page == nil {
            return queue.previous.amountOfPagesOpened
        } else {
            return queue.previous.amountOfPagesOpened + 1
        }
    }
}

extension Optional where Wrapped == ResultNode {
    func size() -> Int {
        guard let queue = self else {
            return 0
        }
        return 1 + queue.previous.size()
    }
}
