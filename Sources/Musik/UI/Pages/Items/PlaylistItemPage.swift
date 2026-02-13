import MusicKit
import SwiftNotCurses

@MainActor
public class PlaylistItemPage: DestroyablePage {

    private var state: PageState
    private let plane: Plane

    private let borderPlane: Plane
    private let pageNamePlane: Plane
    private let descriptionRightPlane: Plane
    private let curatorRightPlane: Plane
    private let playlistRightPlane: Plane

    private var artworkPlane: Plane?
    private var artworkVisual: Visual?

    private let item: Playlist

    public func getItem() async -> Playlist { item }

    public enum PlaylistItemPageType {
        case searchPage
        case recommendationDetail
    }

    private let type: PlaylistItemPageType

    public init?(
        in plane: Plane,
        state: PageState,
        item: Playlist,
        type: PlaylistItemPageType
    ) {
        self.type = type
        self.state = state
        guard
            let pagePlane = Plane(
                in: plane,
                opts: .init(
                    pageState: state,
                    debugID: "PLAYLIST_UI_\(item.id)",
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
                debugID: "PLAYLIST_UI_\(item.id)_BORDER"
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
                    width: 8,
                    height: 1
                ),
                debugID: "PLAYLIST_UI_\(item.id)_PN"
            )
        else {
            return nil
        }
        self.pageNamePlane = pageNamePlane
        self.pageNamePlane.moveAbove(other: self.borderPlane)

        let contentWidth = max(state.width, 4) - 4

        // Playlist name - row 1, primary
        guard
            let playlistRightPlane = Plane(
                in: pagePlane,
                state: .init(
                    absX: 2,
                    absY: 1,
                    width: min(UInt32(item.name.count), contentWidth),
                    height: 1
                ),
                debugID: "PLAYLIST_UI_\(item.id)_PR"
            )
        else {
            return nil
        }
        self.playlistRightPlane = playlistRightPlane
        self.playlistRightPlane.moveAbove(other: self.pageNamePlane)

        // Curator - row 2, secondary
        guard
            let curatorRightPlane = Plane(
                in: pagePlane,
                state: .init(
                    absX: 2,
                    absY: 2,
                    width: min(UInt32(item.curatorName?.count ?? 1), contentWidth),
                    height: 1
                ),
                debugID: "PLAYLIST_UI_\(item.id)_CR"
            )
        else {
            return nil
        }
        self.curatorRightPlane = curatorRightPlane
        self.curatorRightPlane.moveAbove(other: self.playlistRightPlane)

        // Description - row 3, tertiary
        var descWidth = min(UInt32(item.standardDescription?.count ?? 1), contentWidth)
        if descWidth == 0 { descWidth = 1 }
        guard
            let descriptionRightPlane = Plane(
                in: pagePlane,
                state: .init(
                    absX: 2,
                    absY: 3,
                    width: descWidth,
                    height: 1
                ),
                debugID: "PLAYLIST_UI_\(item.id)_DR"
            )
        else {
            return nil
        }
        self.descriptionRightPlane = descriptionRightPlane
        self.descriptionRightPlane.moveAbove(other: self.curatorRightPlane)

        self.item = item

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
        guard state.width > 15, let notcurses = UI.notcurses else { return }
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
            debugID: "PLAYLIST_ART_\(item.id)"
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
        let colorConfig: Theme.PlaylistItem
        switch self.type {
        case .searchPage:
            colorConfig = Theme.shared.search.playlistItem
        case .recommendationDetail:
            colorConfig = Theme.shared.recommendationDetail.playlistItem
        }
        plane.setColorPair(colorConfig.page)
        borderPlane.setColorPair(colorConfig.border)
        pageNamePlane.setColorPair(colorConfig.pageName)
        playlistRightPlane.setColorPair(colorConfig.playlistRight)
        descriptionRightPlane.setColorPair(colorConfig.descriptionRight)
        curatorRightPlane.setColorPair(colorConfig.curatorRight)

        plane.blank()
        borderPlane.windowBorder(width: state.width, height: state.height)
        pageNamePlane.putString("Playlist", at: (0, 0))
        playlistRightPlane.putString(item.name, at: (0, 0))
        curatorRightPlane.putString(item.curatorName ?? "", at: (0, 0))
        descriptionRightPlane.putString(item.standardDescription ?? "", at: (0, 0))
    }

    public func destroy() async {
        artworkVisual?.destroy()
        artworkPlane?.erase()
        artworkPlane?.destroy()

        plane.erase()
        plane.destroy()

        borderPlane.erase()
        borderPlane.destroy()

        pageNamePlane.erase()
        pageNamePlane.destroy()

        curatorRightPlane.erase()
        curatorRightPlane.destroy()

        descriptionRightPlane.erase()
        descriptionRightPlane.destroy()

        playlistRightPlane.erase()
        playlistRightPlane.destroy()
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
