import Foundation
import MusicKit
import SwiftNotCurses

@MainActor
public class AlbumItemPage: DestroyablePage {

    private var state: PageState
    private let plane: Plane

    private let borderPlane: Plane
    private let pageNamePlane: Plane
    private let genreRightPlane: Plane
    private let albumRightPlane: Plane
    private let artistRightPlane: Plane

    // Release date display (used in artist detail page instead of genre)
    private var releasedRightPlane: Plane?

    private var artworkPlane: Plane?
    private var artworkVisual: Visual?
    private var isDestroyed: Bool = false

    private let item: Album
    private let releaseDateStr: String

    public enum AlbumItemPageType {
        case searchPage
        case songDetailPage
        case artistDetailPage
        case recommendationDetailPage
    }

    private let type: AlbumItemPageType

    public func getItem() async -> Album { item }

    public init?(
        in plane: Plane,
        state: PageState,
        item: Album,
        type: AlbumItemPageType
    ) {
        self.type = type
        self.state = state
        guard
            let pagePlane = Plane(
                in: plane,
                opts: .init(
                    pageState: state,
                    debugID: "ALBUM_UI_\(item.id)",
                    flags: []
                )
            )
        else {
            return nil
        }
        self.plane = pagePlane
        self.plane.moveAbove(other: plane)

        guard
            let borderPlane = Plane(
                in: pagePlane,
                state: .init(
                    absX: 0,
                    absY: 0,
                    width: state.width,
                    height: state.height
                ),
                debugID: "ALBUM_UI_\(item.id)_BORDER"
            )
        else {
            return nil
        }
        self.borderPlane = borderPlane
        self.borderPlane.moveAbove(other: self.plane)

        guard
            let pageNamePlane = Plane(
                in: pagePlane,
                state: .init(
                    absX: 3,
                    absY: 0,
                    width: 5,
                    height: 1
                ),
                debugID: "ALBUM_UI_\(item.id)_PN"
            )
        else {
            return nil
        }
        self.pageNamePlane = pageNamePlane
        self.pageNamePlane.moveAbove(other: self.borderPlane)

        let contentWidth = max(state.width, 4) - 4

        // Album title - row 1, primary
        guard
            let albumRightPlane = Plane(
                in: pagePlane,
                state: .init(
                    absX: 2,
                    absY: 1,
                    width: min(UInt32(item.title.count), contentWidth),
                    height: 1
                ),
                debugID: "ALBUM_UI_\(item.id)_AR"
            )
        else {
            return nil
        }
        self.albumRightPlane = albumRightPlane
        self.albumRightPlane.moveAbove(other: self.pageNamePlane)

        // Artist - row 2, secondary
        guard
            let artistRightPlane = Plane(
                in: pagePlane,
                state: .init(
                    absX: 2,
                    absY: 2,
                    width: min(UInt32(item.artistName.count), contentWidth),
                    height: 1
                ),
                debugID: "ALBUM_UI_\(item.id)_ARR"
            )
        else {
            return nil
        }
        self.artistRightPlane = artistRightPlane
        self.artistRightPlane.moveAbove(other: self.albumRightPlane)

        // Genre string
        var genreStr = ""
        for genre in item.genreNames {
            if genre == "Music" {
                continue
            }
            genreStr.append("\(genre), ")
        }
        if genreStr.count >= 2 {
            genreStr.removeLast(2)
        }

        // Genre - row 3, tertiary
        guard
            let genreRightPlane = Plane(
                in: pagePlane,
                state: .init(
                    absX: 2,
                    absY: 3,
                    width: min(UInt32(genreStr.count), contentWidth),
                    height: 1
                ),
                debugID: "ALBUM_UI_\(item.id)_GR"
            )
        else {
            return nil
        }
        self.genreRightPlane = genreRightPlane
        self.genreRightPlane.moveAbove(other: self.artistRightPlane)

        self.item = item

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"
        self.releaseDateStr = item.releaseDate.map { dateFormatter.string(from: $0) } ?? "Unknown"

        // For artist detail page, create release date plane (shown instead of genre)
        if type == .artistDetailPage {
            self.releasedRightPlane = Plane(
                in: pagePlane,
                state: .init(
                    absX: 2,
                    absY: 3,
                    width: min(UInt32(releaseDateStr.count), contentWidth),
                    height: 1
                ),
                debugID: "ALBUM_UI_\(item.id)_RR"
            )
        }

        updateColors()
        loadArtwork()
    }

    private func loadArtwork() {
        guard state.width > 15 else { return }
        if let url = item.artwork?.url(width: 50, height: 50) {
            downloadImageAndConvertToRGBA(url: url, width: 50, heigth: 50) { pixelArray in
                if let pixelArray = pixelArray {
                    Task { @MainActor in
                        self.handleArtwork(pixelArray: pixelArray)
                    }
                }
            }
        }
    }

    private func handleArtwork(pixelArray: [UInt8]) {
        guard !isDestroyed, state.width > 15, let notcurses = UI.notcurses else { return }
        let artWidth: UInt32 = 6
        let artHeight: UInt32 = 3
        artworkPlane = Plane(
            in: plane,
            state: .init(
                absX: Int32(state.width) - Int32(artWidth) - 1,
                absY: 1,
                width: artWidth,
                height: artHeight
            ),
            debugID: "ALBUM_ART_\(item.id)"
        )
        guard let artworkPlane else { return }
        artworkPlane.moveAbove(other: borderPlane)
        artworkVisual = Visual(
            in: notcurses,
            width: 50,
            height: 50,
            from: pixelArray,
            for: artworkPlane,
            blit: .braille
        )
        artworkVisual?.render()
    }

    public func updateColors() {
        let colorConfig: Theme.AlbumItem
        switch self.type {
        case .searchPage:
            colorConfig = Theme.shared.search.albumItem
        case .songDetailPage:
            colorConfig = Theme.shared.songDetail.albumItem
        case .artistDetailPage:
            colorConfig = Theme.shared.artistDetail.albumItem
        case .recommendationDetailPage:
            colorConfig = Theme.shared.recommendationDetail.albumItem
        }
        plane.setColorPair(colorConfig.page)
        borderPlane.setColorPair(colorConfig.border)
        pageNamePlane.setColorPair(colorConfig.pageName)
        artistRightPlane.setColorPair(colorConfig.artistRight)
        albumRightPlane.setColorPair(colorConfig.albumRight)
        genreRightPlane.setColorPair(colorConfig.genreRight)

        plane.blank()
        borderPlane.windowBorder(width: state.width, height: state.height)
        pageNamePlane.putString("Album", at: (0, 0))
        albumRightPlane.putString(item.title, at: (0, 0))
        artistRightPlane.putString(item.artistName, at: (0, 0))

        var genreStr = ""
        for genre in item.genreNames {
            if genre == "Music" {
                continue
            }
            genreStr.append("\(genre), ")
        }
        if genreStr.count >= 2 {
            genreStr.removeLast(2)
        }
        if type == .artistDetailPage {
            // Hide genre, show release date instead
            genreRightPlane.erase()

            releasedRightPlane?.setColorPair(colorConfig.genreRight)
            releasedRightPlane?.putString(releaseDateStr, at: (0, 0))
        } else {
            genreRightPlane.putString(genreStr, at: (0, 0))
        }
    }

    public func destroy() async {
        isDestroyed = true
        artworkVisual?.destroy()
        artworkPlane?.erase()
        artworkPlane?.destroy()

        plane.erase()
        plane.destroy()

        borderPlane.erase()
        borderPlane.destroy()

        pageNamePlane.erase()
        pageNamePlane.destroy()

        albumRightPlane.erase()
        albumRightPlane.destroy()

        genreRightPlane.erase()
        genreRightPlane.destroy()

        artistRightPlane.erase()
        artistRightPlane.destroy()

        releasedRightPlane?.erase()
        releasedRightPlane?.destroy()
    }

    public func render() async {

    }

    public func onResize(newPageState: PageState) async {
        self.state = newPageState
        plane.updateByPageState(state)
        plane.blank()

        borderPlane.updateByPageState(state)
        borderPlane.erase()
        borderPlane.windowBorder(width: state.width, height: state.height)
    }

    public func getPageState() async -> PageState { state }

    public func getMinDimensions() async -> (width: UInt32, height: UInt32) { (12, state.height) }

    public func getMaxDimensions() async -> (width: UInt32, height: UInt32)? { nil }

}
