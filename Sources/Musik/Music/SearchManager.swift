import Foundation
import Logging
import MusicKit

public struct SearchResult {

    public let timestamp: Date

    public let searchType: SearchType
    public let itemType: MusicItemType

    public let searchPhrase: String?

    public let result: any AnyMusicItemCollection

}

public struct MultiSearchResult {

    public let timestamp: Date

    public let searchType: SearchType
    public let searchPhrase: String

    public let artists: MusicItemCollection<Artist>?
    public let albums: MusicItemCollection<Album>?
    public let songs: MusicItemCollection<Song>?

}

public struct DualPlaylistSearchResult {

    public let timestamp: Date
    public let searchPhrase: String

    public let libraryPlaylists: MusicItemCollection<Playlist>?
    public let catalogPlaylists: MusicItemCollection<Playlist>?

}

public enum SearchType: Hashable, CaseIterable, Sendable {
    case recentlyPlayed
    case recommended
    case catalogSearch
    case librarySearch
}

public struct SongDescriptionResult {
    public let song: Song
    public let artists: MusicItemCollection<Artist>?  // Prefix "w"
    public let album: Album?  // Prefix "a"
}

public struct ArtistDescriptionResult {
    public let artist: Artist
    public let topSongs: MusicItemCollection<Song>?  // Prefix "t"
    public let lastAlbums: MusicItemCollection<Album>?  // Prefix "a"
}

public struct PlaylistDescriptionResult {
    public let playlist: Playlist
    public let songs: MusicItemCollection<Song>  // No prefix
}

public struct AlbumDescriptionResult {
    public let album: Album
    public let songs: MusicItemCollection<Song>  // Prefix "s"
    public let artists: MusicItemCollection<Artist>?  // Prefix "w"
}

public struct RecommendationDescriptionResult {
    public let recommendation: MusicPersonalRecommendation

    public let albums: MusicItemCollection<Album>?  // Prefix "a"
    public let stations: MusicItemCollection<Station>?  // Prefix "s"
    public let playlists: MusicItemCollection<Playlist>?  // Prefix "p"
}

public enum OpenedResult {
    case songDescription(SongDescriptionResult)
    case albumDescription(AlbumDescriptionResult)
    case artistDescription(ArtistDescriptionResult)
    case playlistDescription(PlaylistDescriptionResult)
    case recommendationDescription(RecommendationDescriptionResult)
    case searchResult(SearchResult)
    case multiSearchResult(MultiSearchResult)
    case dualPlaylistSearchResult(DualPlaylistSearchResult)
    case help
}

public class ResultNode {

    public var previous: ResultNode?
    public var result: OpenedResult
    public var inPlace: Bool

    public init(previous: ResultNode? = nil, _ result: OpenedResult, inPlace: Bool = true) {
        self.previous = previous
        self.result = result
        self.inPlace = inPlace
    }
}

public class SearchManager: @unchecked Sendable {

    public static let shared: SearchManager = .init()

    public var lastSearchResult: ResultNode?

    /// Currently selected item index in search results
    public var selectedIndex: Int = 0

    /// Currently selected column for multi-search (0=artists, 1=albums, 2=songs)
    public var selectedColumn: Int = 0

    /// Whether the queue panel is focused (vs search)
    public var queueFocused: Bool = false

    /// Currently selected item index in the queue
    public var queueSelectedIndex: Int = 0

    /// Whether we're in multi-column search mode
    public var isMultiSearch: Bool {
        guard let lastResult = lastSearchResult else { return false }
        if case .multiSearchResult(_) = lastResult.result { return true }
        if case .dualPlaylistSearchResult(_) = lastResult.result { return true }
        return false
    }

    /// Number of columns in multi-search that have results
    public var multiSearchColumnCount: Int {
        guard let lastResult = lastSearchResult else { return 0 }
        if case .multiSearchResult(let msr) = lastResult.result {
            var count = 0
            if msr.artists != nil && !(msr.artists!.isEmpty) { count += 1 }
            if msr.albums != nil && !(msr.albums!.isEmpty) { count += 1 }
            if msr.songs != nil && !(msr.songs!.isEmpty) { count += 1 }
            return count
        }
        if case .dualPlaylistSearchResult(let dpr) = lastResult.result {
            var count = 0
            if dpr.libraryPlaylists != nil && !(dpr.libraryPlaylists!.isEmpty) { count += 1 }
            if dpr.catalogPlaylists != nil && !(dpr.catalogPlaylists!.isEmpty) { count += 1 }
            return count
        }
        return 0
    }

    /// Maps selectedColumn to the actual column type in multi-search
    /// Returns 0=artists, 1=albums, 2=songs based on which columns have data
    /// For dual playlist: 0=library, 1=catalog
    public func multiSearchColumnType() -> Int {
        guard let lastResult = lastSearchResult else { return 0 }
        if case .multiSearchResult(let msr) = lastResult.result {
            var columns: [Int] = []
            if msr.artists != nil && !(msr.artists!.isEmpty) { columns.append(0) }
            if msr.albums != nil && !(msr.albums!.isEmpty) { columns.append(1) }
            if msr.songs != nil && !(msr.songs!.isEmpty) { columns.append(2) }
            if selectedColumn < columns.count {
                return columns[selectedColumn]
            }
        }
        if case .dualPlaylistSearchResult(let dpr) = lastResult.result {
            var columns: [Int] = []
            if dpr.libraryPlaylists != nil && !(dpr.libraryPlaylists!.isEmpty) { columns.append(0) }
            if dpr.catalogPlaylists != nil && !(dpr.catalogPlaylists!.isEmpty) { columns.append(1) }
            if selectedColumn < columns.count {
                return columns[selectedColumn]
            }
        }
        return 0
    }

    /// Number of navigable items in the current view
    public var currentItemCount: Int {
        guard let lastResult = lastSearchResult else { return 0 }
        switch lastResult.result {
        case .searchResult(let searchResult):
            return searchResult.result.count
        case .multiSearchResult(let msr):
            switch multiSearchColumnType() {
            case 0: return msr.artists?.count ?? 0
            case 1: return msr.albums?.count ?? 0
            case 2: return msr.songs?.count ?? 0
            default: return 0
            }
        case .dualPlaylistSearchResult(let dpr):
            switch multiSearchColumnType() {
            case 0: return dpr.libraryPlaylists?.count ?? 0
            case 1: return dpr.catalogPlaylists?.count ?? 0
            default: return 0
            }
        case .playlistDescription(let pd):
            return pd.songs.count
        case .albumDescription(let ad):
            return ad.songs.count
        case .artistDescription(let ad):
            return ad.lastAlbums?.count ?? 0
        case .recommendationDescription(let rd):
            return (rd.albums?.count ?? 0) + (rd.stations?.count ?? 0) + (rd.playlists?.count ?? 0)
        case .songDescription(_):
            return 1
        case .help:
            return 0
        }
    }

    public func selectNext() {
        let count = currentItemCount
        if count > 0 && selectedIndex < count - 1 {
            selectedIndex += 1
        }
    }

    public func selectPrevious() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    public func selectLeft() {
        if selectedColumn > 0 {
            selectedColumn -= 1
            let count = currentItemCount
            if selectedIndex >= count {
                selectedIndex = max(0, count - 1)
            }
        }
    }

    public func selectRight() {
        let maxCol = multiSearchColumnCount - 1
        if selectedColumn < maxCol {
            selectedColumn += 1
            let count = currentItemCount
            if selectedIndex >= count {
                selectedIndex = max(0, count - 1)
            }
        }
    }

    public func resetSelection() {
        selectedIndex = 0
        selectedColumn = 0
    }

    /// Returns true if the selected item should be opened (drilled into)
    /// rather than added to queue and played.
    public func selectedItemShouldOpen() -> Bool {
        guard let lastResult = lastSearchResult else { return false }
        switch lastResult.result {
        case .searchResult(let searchResult):
            switch searchResult.itemType {
            case .artist:
                return true
            case .song, .station, .album, .playlist:
                return false
            }
        case .multiSearchResult(_):
            // Artists open, albums queue, songs queue
            return multiSearchColumnType() == 0
        case .dualPlaylistSearchResult(_):
            return false
        case .recommendationDescription(_):
            return true
        case .artistDescription(_), .albumDescription(_),
             .playlistDescription(_), .songDescription(_):
            return false
        case .help:
            return false
        }
    }

    /// Converts a flat selectedIndex to the correct prefixed argument string
    /// for the current view context.
    public func argumentForIndex(_ index: Int) -> String {
        guard let lastResult = lastSearchResult else { return "\(index)" }
        switch lastResult.result {
        case .searchResult(_), .playlistDescription(_), .songDescription(_), .help:
            return "\(index)"
        case .multiSearchResult(_), .dualPlaylistSearchResult(_):
            return "\(index)"
        case .albumDescription(_):
            return "s\(index)"
        case .artistDescription(_):
            return "a\(index)"
        case .recommendationDescription(let rd):
            let albumCount = rd.albums?.count ?? 0
            let stationCount = rd.stations?.count ?? 0
            if index < albumCount {
                return "a\(index)"
            } else if index < albumCount + stationCount {
                return "s\(index - albumCount)"
            } else {
                return "p\(index - albumCount - stationCount)"
            }
        }
    }

    /// Returns the argument string for the currently selected item.
    public func selectedItemArgument() -> String {
        return argumentForIndex(selectedIndex)
    }

    private init() {}

    /// Load recently played as the root search result.
    /// This is the "home" state - close always falls back here.
    /// Retries with increasing delays since MusicKit may not be ready at startup.
    @MainActor
    public func loadRecentlyPlayed() async {
        let delays: [UInt64] = [0, 1_000_000_000, 2_000_000_000, 3_000_000_000]
        for (attempt, delay) in delays.enumerated() {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            await newSearch(
                for: nil,
                itemType: .album,
                in: .recentlyPlayed,
                inPlace: true,
                limit: 25
            )
            if lastSearchResult != nil {
                lastSearchResult?.previous = nil
                await logger?.debug("Recently played loaded on attempt \(attempt + 1)")
                return
            }
            await logger?.debug("Recently played attempt \(attempt + 1) failed, retrying...")
        }
    }

    public func newSearch(
        for phrase: String? = nil,
        itemType: MusicItemType,
        in searchType: SearchType,
        inPlace: Bool,
        limit: UInt32
    )
        async
    {
        resetSelection()
        var result: (any AnyMusicItemCollection)?

        let limit = Int(limit)

        switch searchType {

        case .recentlyPlayed:
            result = await getRecentlyPlayed(limit: limit) as MusicItemCollection<RecentlyPlayedMusicItem>?

        case .recommended:
            result = await getUserRecommendedBatch(limit: limit)

        case .catalogSearch:
            guard let phrase else { return }
            switch itemType {
            case .song:
                result = await searchCatalogBatch(for: phrase, limit: limit) as MusicItemCollection<Song>?
            case .album:
                result = await searchCatalogBatch(for: phrase, limit: limit) as MusicItemCollection<Album>?
            case .artist:
                result = await searchCatalogBatch(for: phrase, limit: limit) as MusicItemCollection<Artist>?
            case .playlist:
                result = await searchCatalogBatch(for: phrase, limit: limit) as MusicItemCollection<Playlist>?
            case .station:
                result = await searchCatalogBatch(for: phrase, limit: limit) as MusicItemCollection<Station>?
            }

        case .librarySearch:
            guard let phrase else { return }
            switch itemType {
            case .song:
                result = await searchUserLibraryBatch(for: phrase, limit: limit) as MusicItemCollection<Song>?
            case .album:
                result = await searchUserLibraryBatch(for: phrase, limit: limit) as MusicItemCollection<Album>?
            case .artist:
                result = await searchUserLibraryBatch(for: phrase, limit: limit) as MusicItemCollection<Artist>?
            case .playlist:
                result = await searchUserLibraryBatch(for: phrase, limit: limit) as MusicItemCollection<Playlist>?
            case .station: break  // Should be handled in commands since station is not MusicLibraryRequestable
            }

        }
        guard let result else {
            await logger?.debug("Search Manager: Search result is nil")
            return
        }

        let searchResult: SearchResult = .init(
            timestamp: Date.now,
            searchType: searchType,
            itemType: itemType,
            searchPhrase: phrase,
            result: result
        )
        self.lastSearchResult = ResultNode(previous: lastSearchResult, .searchResult(searchResult), inPlace: inPlace)
    }

    public func newMultiSearch(
        for phrase: String,
        in searchType: SearchType,
        limit: UInt32
    ) async {
        resetSelection()
        let limit = Int(limit)

        var artists: MusicItemCollection<Artist>?
        var albums: MusicItemCollection<Album>?
        var songs: MusicItemCollection<Song>?

        switch searchType {
        case .catalogSearch:
            artists = await searchCatalogBatch(for: phrase, limit: limit) as MusicItemCollection<Artist>?
            albums = await searchCatalogBatch(for: phrase, limit: limit) as MusicItemCollection<Album>?
            songs = await searchCatalogBatch(for: phrase, limit: limit) as MusicItemCollection<Song>?
        case .librarySearch:
            artists = await searchUserLibraryBatch(for: phrase, limit: limit) as MusicItemCollection<Artist>?
            albums = await searchUserLibraryBatch(for: phrase, limit: limit) as MusicItemCollection<Album>?
            songs = await searchUserLibraryBatch(for: phrase, limit: limit) as MusicItemCollection<Song>?
        default:
            return
        }

        let multiResult = MultiSearchResult(
            timestamp: Date.now,
            searchType: searchType,
            searchPhrase: phrase,
            artists: artists,
            albums: albums,
            songs: songs
        )
        self.lastSearchResult = ResultNode(
            previous: lastSearchResult,
            .multiSearchResult(multiResult),
            inPlace: true
        )
    }

    public func newDualPlaylistSearch(
        for phrase: String,
        limit: UInt32
    ) async {
        resetSelection()
        let limit = Int(limit)

        let libraryPlaylists = await searchUserLibraryBatch(for: phrase, limit: limit) as MusicItemCollection<Playlist>?
        let catalogPlaylists = await searchCatalogBatch(for: phrase, limit: limit) as MusicItemCollection<Playlist>?

        let dualResult = DualPlaylistSearchResult(
            timestamp: Date.now,
            searchPhrase: phrase,
            libraryPlaylists: libraryPlaylists,
            catalogPlaylists: catalogPlaylists
        )
        self.lastSearchResult = ResultNode(
            previous: lastSearchResult,
            .dualPlaylistSearchResult(dualResult),
            inPlace: true
        )
    }

    public func showHelp() {
        self.lastSearchResult = ResultNode(previous: lastSearchResult, .help, inPlace: false)
    }

}

// Requesting
public extension SearchManager {

    func getRecentlyPlayed<T>(
        limit: Int
    ) async
        -> MusicItemCollection<T>?
    where T: Decodable, T: MusicRecentlyPlayedRequestable {
        await logger?.trace(
            "Get recently played for \(T.self): Requesting with limit \(limit)..."
        )
        var request = MusicRecentlyPlayedRequest<T>()
        request.limit = limit
        do {
            let response = try await request.response()
            await logger?.debug("Recently played response success: \(response)")
            return response.items
        } catch {
            await logger?.error(
                "Failed to make recently played request: \(error.localizedDescription)"
            )
            return nil
        }
    }

    func getRecentlyPlayedContainer(
        limit: Int
    ) async
        -> MusicItemCollection<RecentlyPlayedMusicItem>?
    {
        await logger?.trace(
            "Get recently played container: Requesting with limit \(limit)..."
        )
        var request = MusicRecentlyPlayedContainerRequest()
        request.limit = limit
        do {
            let response = try await request.response()
            await logger?.debug(
                "Recently played container response success: \(response)"
            )
            return response.items
        } catch {
            await logger?.error(
                "Failed to make recently played container request: \(error.localizedDescription)"
            )
            return nil
        }
    }

    func getUserRecommendedBatch(
        limit: Int
    ) async
        -> MusicItemCollection<MusicPersonalRecommendation>?
    {
        await logger?.trace(
            "Get user recommended batch: Requesting with limit \(limit)..."
        )
        var request = MusicPersonalRecommendationsRequest()
        request.limit = limit
        do {
            let response = try await request.response()
            await logger?.debug("Get user recommended batch: success: \(response)")
            return response.recommendations
        } catch {
            await logger?.error(
                "Failed to get user recommended batch: \(error.localizedDescription)"
            )
            return nil
        }
    }

    func getUserLibraryBatch<T>(
        limit: Int,
        onlyOfflineContent: Bool = false
    ) async
        -> MusicItemCollection<T>?
    where T: MusicLibraryRequestable {
        await logger?.trace(
            "Get user library batch for \(T.self): Requesting with limit: \(limit), onlyOfflineContent: \(onlyOfflineContent)..."
        )
        var request = MusicLibraryRequest<T>()
        request.limit = limit
        request.includeOnlyDownloadedContent = onlyOfflineContent
        do {
            let response = try await request.response()
            await logger?.debug("Get user library batch: success: \(response)")
            return response.items
        } catch {
            await logger?.error(
                "Failed to make user library song request: \(error.localizedDescription)"
            )
            return nil
        }
    }

    func searchCatalogBatch<T>(
        for term: String,
        limit: Int
    ) async
        -> MusicItemCollection<T>?
    where T: MusicCatalogSearchable {
        await logger?.trace(
            "Search catalog batch for \(T.self): Requesting with term \(term), limit \(limit)..."
        )
        var request = MusicCatalogSearchRequest(term: term, types: [T.self])
        if T.self == CatalogTopResult.self {
            await logger?.trace(
                "Search catalog batch for \(T.self): Including top results."
            )
            request.includeTopResults = true
        }
        request.limit = limit
        do {
            let response = try await request.response()
            await logger?.trace(
                "Search catalog batch for \(T.self): Response success \(response)"
            )
            var collection: MusicItemCollection<T>?
            switch T.self {
            case is Album.Type:
                collection = response.albums as? MusicItemCollection<T>
            case is Song.Type:
                collection = response.songs as? MusicItemCollection<T>
            case is Artist.Type:
                collection = response.artists as? MusicItemCollection<T>
            case is Curator.Type:
                collection = response.curators as? MusicItemCollection<T>
            case is Station.Type:
                collection = response.stations as? MusicItemCollection<T>
            case is Playlist.Type:
                collection = response.playlists as? MusicItemCollection<T>
            case is RadioShow.Type:
                collection = response.radioShows as? MusicItemCollection<T>
            case is CatalogTopResult.Type:
                collection = response.topResults as? MusicItemCollection<T>
            case is RecordLabel.Type:
                collection = response.recordLabels as? MusicItemCollection<T>
            case is MusicVideo.Type:
                collection = response.musicVideos as? MusicItemCollection<T>
            default:
                await logger?.error(
                    "Failed to search catalog batch: Type \(T.self) is not supported."
                )
            }
            guard let collection else {
                await logger?.error(
                    "Failed to search catalog batch: Unable to transform \(T.self) as \(T.self)"
                )
                return nil
            }
            await logger?.debug(
                "Search catalog batch for \(T.self): Success: \(collection)"
            )
            return collection
        } catch {
            await logger?.error(
                "Failed to search catalog batch for \(T.self): \(error.localizedDescription)"
            )
            return nil
        }
    }

    func searchUserLibraryBatch<T>(
        for term: String,
        limit: Int
    ) async
        -> MusicItemCollection<T>?
    where T: MusicLibrarySearchable {
        await logger?.trace(
            "Search user library batch for \(T.self): Requesting with term \(term), limit \(limit)..."
        )
        var request = MusicLibrarySearchRequest(term: term, types: [T.self])
        if T.self == LibraryTopResult.self {
            await logger?.trace(
                "Search user library batch for \(T.self): Including top results."
            )
            request.includeTopResults = true
        }
        request.limit = limit
        do {
            let response = try await request.response()
            var collection: MusicItemCollection<T>?
            switch T.self {
            case is Song.Type:
                collection = response.songs as? MusicItemCollection<T>
            case is LibraryTopResult.Type:
                collection = response.topResults as? MusicItemCollection<T>
            case is Playlist.Type:
                collection = response.playlists as? MusicItemCollection<T>
            case is Album.Type:
                collection = response.albums as? MusicItemCollection<T>
            case is Artist.Type:
                collection = response.artists as? MusicItemCollection<T>
            case is MusicVideo.Type:
                collection = response.musicVideos as? MusicItemCollection<T>
            default:
                await logger?.error(
                    "Search user library failed: Unsupported type \(T.self)."
                )
                return nil
            }
            guard let collection else {
                await logger?.error(
                    "Search user library failed: Unable to transform \(T.self) type as \(T.self) type."
                )
                return nil
            }
            await logger?.debug(
                "Searching user library for \(T.self): success: \(collection)"
            )
            return collection
        } catch {
            await logger?.error(
                "Failed to search user library: Request error: \(error.localizedDescription)"
            )
            return nil
        }
    }

    func getAllCatalogCharts(
        limit: Int
    ) async
        -> MusicCatalogChartsResponse?
    {
        await logger?.trace("Get all catalog charts: Requesting...")
        var request = MusicCatalogChartsRequest(types: [
            Song.self, Playlist.self, Album.self, MusicVideo.self,
        ])
        request.limit = limit
        do {
            let response = try await request.response()
            await logger?.trace("Get all catalog charts: success: \(response)")
            return response
        } catch {
            await logger?.error(
                "Failed to get all catalog charts: \(error.localizedDescription)"
            )
            return nil
        }
    }

    func getSpecificCatalogCharts<T>(
        limit: Int
    ) async
        -> [MusicCatalogChart<T>]? where T: MusicCatalogChartRequestable
    {
        await logger?.trace("Get catalog charts for type \(T.self): Requesting...")
        var request = MusicCatalogChartsRequest(types: [T.self])
        request.limit = limit
        do {
            let response = try await request.response()
            var result: [MusicCatalogChart<T>]?
            switch T.self {
            case is Song.Type:
                result = response.songCharts as? [MusicCatalogChart<T>]
            case is Playlist.Type:
                result = response.playlistCharts as? [MusicCatalogChart<T>]
            case is Album.Type:
                result = response.albumCharts as? [MusicCatalogChart<T>]
            case is MusicVideo.Type:
                result = response.musicVideoCharts as? [MusicCatalogChart<T>]
            default:
                await logger?.error(
                    "Failed to get catalog charts for type \(T.self): Unsupported type."
                )
                return nil
            }
            guard let result else {
                await logger?.error(
                    "Failed to get catalog charts: Unable to transform \(T.self) as \(T.self)."
                )
                return nil
            }
            return result
        } catch {
            await logger?.error(
                "Failed to get catalog charts for type \(T.self): \(error.localizedDescription)"
            )
            return nil
        }
    }

    func nextMusicItemsBatch<T>(
        for previousBatch: MusicItemCollection<T>,
        limit: Int
    ) async
        -> MusicItemCollection<T>?
    {
        guard previousBatch.hasNextBatch else {
            await logger?.trace(
                "Previous batch does not have next batch."
            )
            return nil
        }
        do {
            let response = try await previousBatch.nextBatch(limit: limit)
            guard let response else {
                await logger?.debug("Next batch is nil, should not happen.")
                return nil
            }
            await logger?.trace("Next batch success: \(response)")
            return response
        } catch {
            await logger?.error(
                "Failed to load next batch for previous batch \(previousBatch): \(error.localizedDescription)"
            )
            return nil
        }
    }

    func getUserLibrarySectioned<T, V>(
        for term: String? = nil,
        limit: Int,
        onlyOfflineContent: Bool = false
    ) async
        -> MusicLibrarySectionedResponse<T, V>?
    where T: MusicLibrarySectionRequestable, V: MusicLibraryRequestable {
        await logger?.trace(
            "Get user library sectioned for section \(T.self) items \(V.self):"
                + " Requesting with term \(term ?? "'nil'"), limit \(limit), onlyOfflineContent: \(onlyOfflineContent)"
        )
        var request = MusicLibrarySectionedRequest<T, V>()
        request.limit = limit
        if let term {
            request.filterItems(text: term)
        }
        request.includeOnlyDownloadedContent = onlyOfflineContent
        // Items here could also be filtered by more complicated filters and sorted, probably not needed for now
        do {
            let response = try await request.response()
            await logger?.debug(
                "Get user library sectioned for section \(T.self) items \(V.self): success: \(response)"
            )
            return response
        } catch {
            await logger?.error(
                "Get user library sectioned for section \(T.self) items \(V.self): \(error.localizedDescription)"
            )
            return nil
        }
    }

    // TODO: Search suggestions requests
    // Though I am not sure it is needed
    // As I don't know how to make use of it in UI yet
}
