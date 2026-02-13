import SwiftNotCurses

@MainActor
public class ArtistDetailPage: DestroyablePage {

    private var state: PageState

    private let artistDescription: ArtistDescriptionResult

    private var plane: Plane

    private var borderPlane: Plane

    private var artworkPlane: Plane
    private var artworkVisual: Visual?

    private var artistTitlePlane: Plane  // Name of the artist

    private var albumsTitlePlane: Plane?  // "Albums:"
    private var albumsIndicesPlane: Plane?  // Indices of albums
    private var albumItemPages: [AlbumItemPage?]

    private var lastSelectedIndex: Int = -1
    private var scrollOffset: Int = 0

    private var maxAmountOfItemsDisplayed: Int {
        Int(state.height - 8) / 5
    }

    public init?(
        in stdPlane: Plane,
        state: PageState,
        artistDescription: ArtistDescriptionResult
    ) {
        self.state = state
        self.artistDescription = artistDescription

        guard
            let plane = Plane(
                in: stdPlane,
                state: state,
                debugID: "ARDP"
            )
        else {
            return nil
        }
        self.plane = plane

        guard
            let artworkPlane = Plane(
                in: plane,
                state: .init(
                    absX: 0,
                    absY: 0,
                    width: 1,
                    height: 1
                ),
                debugID: "ARDPAP"
            )
        else {
            return nil
        }
        self.artworkPlane = artworkPlane

        guard
            let borderPlane = Plane(
                in: plane,
                state: .init(
                    absX: 0,
                    absY: 0,
                    width: state.width,
                    height: state.height
                ),
                debugID: "ARDBP"
            )
        else {
            return nil
        }
        self.borderPlane = borderPlane

        let artistName = artistDescription.artist.name
        guard
            let artistTitlePlane = Plane(
                in: plane,
                state: .init(
                    absX: 4,
                    absY: 2,
                    width: UInt32(artistName.count),
                    height: 1
                ),
                debugID: "ARDPTP"
            )
        else {
            return nil
        }
        self.artistTitlePlane = artistTitlePlane

        self.albumItemPages = []

        loadAlbums()

        loadArtwork()

        updateColors()

    }

    private func loadAlbums() {
        loadAlbumsFromOffset(0)
    }

    private func loadAlbumsFromOffset(_ offset: Int) {
        guard let albums = artistDescription.lastAlbums, !albums.isEmpty else {
            return
        }
        let oneThirdWidth = Int32(state.width) / 3

        if self.albumsTitlePlane == nil {
            self.albumsTitlePlane = Plane(
                in: plane,
                state: .init(
                    absX: oneThirdWidth + 2,
                    absY: 2,
                    width: 7,
                    height: 1
                ),
                debugID: "ARDPAT"
            )
        }
        if self.albumsIndicesPlane == nil {
            self.albumsIndicesPlane = Plane(
                in: plane,
                state: .init(
                    absX: oneThirdWidth + 2,
                    absY: 4,
                    width: 3,
                    height: UInt32(maxAmountOfItemsDisplayed + 1) * 5
                ),
                debugID: "ARDPAI"
            )
        }

        // Destroy existing album item pages
        for page in albumItemPages {
            Task { await page?.destroy() }
        }
        albumItemPages = []

        let albumItemWidth = state.width - UInt32(oneThirdWidth) - 7
        let maxItems = maxAmountOfItemsDisplayed + 1
        let end = min(albums.count, offset + maxItems)
        for i in offset..<end {
            let slot = i - offset
            let albumItem = AlbumItemPage(
                in: borderPlane,
                state: .init(
                    absX: oneThirdWidth + 5,
                    absY: 4 + Int32(slot * 5),
                    width: albumItemWidth,
                    height: 5
                ),
                item: albums[i],
                type: .artistDetailPage
            )
            self.albumItemPages.append(albumItem)
        }
    }

    private func loadArtwork() {
        Task {
            if let url = artistDescription.artist.artwork?.url(
                width: Int(Config.shared.ui.artwork.width),
                height: Int(Config.shared.ui.artwork.height)
            ) {
                downloadImageAndConvertToRGBA(
                    url: url,
                    width: Int(Config.shared.ui.artwork.width),
                    heigth: Int(Config.shared.ui.artwork.height)
                ) { pixelArray in
                    if let pixelArray = pixelArray {
                        await logger?.debug(
                            "ArtistDetailPage: Successfully obtained artwork RGBA byte array with count: \(pixelArray.count)"
                        )
                        Task { @MainActor in
                            self.handleArtwork(pixelArray: pixelArray)
                        }
                    } else {
                        await logger?.error("ArtistDetailPage: Failed to get artwork RGBA byte array.")
                    }
                }
            }
        }
    }

    func handleArtwork(pixelArray: [UInt8]) {
        let artworkPlaneWidth = state.width / 3 - 5
        let artworkPlaneHeight = artworkPlaneWidth / 2 - 1
        if artworkPlaneHeight > self.state.height - 12 {  // TODO: fix
            self.artworkVisual?.destroy()
            self.artworkPlane.updateByPageState(
                .init(
                    absX: 0,
                    absY: 0,
                    width: 1,
                    height: 1
                )
            )
            return
        }
        self.artworkPlane.updateByPageState(
            .init(
                absX: 4,
                absY: 6,
                width: artworkPlaneWidth,
                height: artworkPlaneHeight
            )
        )
        self.artworkVisual?.destroy()
        self.artworkVisual = Visual(
            in: UI.notcurses!,
            width: Int32(Config.shared.ui.artwork.width),
            height: Int32(Config.shared.ui.artwork.height),
            from: pixelArray,
            for: self.artworkPlane,
            blit: Config.shared.ui.artwork.blit
        )
        self.artworkVisual?.render()
    }

    public func destroy() async {
        self.plane.erase()
        self.plane.destroy()

        self.borderPlane.erase()
        self.borderPlane.destroy()

        self.artworkVisual?.destroy()
        self.artworkPlane.erase()
        self.artworkPlane.destroy()

        self.artistTitlePlane.erase()
        self.artistTitlePlane.destroy()

        self.albumsTitlePlane?.erase()
        self.albumsTitlePlane?.destroy()

        self.albumsIndicesPlane?.erase()
        self.albumsIndicesPlane?.destroy()

        for page in self.albumItemPages {
            await page?.destroy()
        }
    }

    public func render() async {
        let selectedIndex = SearchManager.shared.selectedIndex
        guard selectedIndex != lastSelectedIndex else { return }
        lastSelectedIndex = selectedIndex

        guard let albums = artistDescription.lastAlbums, !albums.isEmpty else { return }

        let maxItems = maxAmountOfItemsDisplayed + 1

        // Calculate needed scroll offset
        var newOffset = scrollOffset
        if selectedIndex >= scrollOffset + maxItems {
            newOffset = selectedIndex - maxItems + 1
        } else if selectedIndex < scrollOffset {
            newOffset = selectedIndex
        }

        // Re-render albums if scroll offset changed
        if newOffset != scrollOffset {
            scrollOffset = newOffset
            loadAlbumsFromOffset(scrollOffset)
            // Re-apply colors to new album items
            for page in albumItemPages {
                page?.updateColors()
            }
        }

        // Update selection indicators
        albumsIndicesPlane?.erase()
        let end = min(albums.count, scrollOffset + maxItems)
        for i in scrollOffset..<end {
            let slot = i - scrollOffset
            let marker = selectedIndex == i ? ">" : " "
            albumsIndicesPlane?.putString("\(marker)\(i)", at: (0, 2 + Int32(slot * 5)))
        }
    }

    public func updateColors() {
        let colorConfig = Theme.shared.artistDetail

        self.plane.setColorPair(colorConfig.page)
        self.plane.blank()

        self.borderPlane.setColorPair(colorConfig.border)
        self.borderPlane.windowBorder(width: state.width, height: state.height)

        self.artistTitlePlane.setColorPair(colorConfig.artistTitle)
        self.artistTitlePlane.putString(self.artistDescription.artist.name, at: (0, 0))

        self.albumsTitlePlane?.setColorPair(colorConfig.albumsText)
        self.albumsTitlePlane?.putString("Albums:", at: (0, 0))

        self.albumsIndicesPlane?.setColorPair(colorConfig.albumIndices)
        if let albums = artistDescription.lastAlbums, !albums.isEmpty {
            let maxItems = maxAmountOfItemsDisplayed + 1
            let end = min(albums.count, scrollOffset + maxItems)
            for i in scrollOffset..<end {
                let slot = i - scrollOffset
                self.albumsIndicesPlane?.putString(" \(i)", at: (0, 2 + Int32(slot * 5)))
            }
        }

        for page in albumItemPages {
            page?.updateColors()
        }
    }

    public func onResize(newPageState: PageState) async {
        self.state = newPageState

        plane.updateByPageState(state)

        borderPlane.updateByPageState(.init(absX: 0, absY: 0, width: state.width, height: state.height))
        borderPlane.erase()
        borderPlane.windowBorder(width: state.width, height: state.height)
    }

    public func getPageState() async -> PageState { state }

    public func getMinDimensions() async -> (width: UInt32, height: UInt32) { (23, 23) }

    public func getMaxDimensions() async -> (width: UInt32, height: UInt32)? { nil }

}
