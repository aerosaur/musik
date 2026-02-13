import MusicKit
import SwiftNotCurses

@MainActor
public class SongItemPage: DestroyablePage {

    private var state: PageState
    private let plane: Plane

    private let borderPlane: Plane
    private let pageNamePlane: Plane
    private let songRightPlane: Plane
    private let albumRightPlane: Plane
    private let artistRightPlane: Plane

    private let item: Song

    public func getItem() async -> Song { item }

    public enum SongItemPageType {
        case searchPage
        case queuePage
        case artistDetailPage
        case albumDetailPage
        case playlistDetailPage
    }

    private let type: SongItemPageType

    public init?(
        in plane: Plane,
        state: PageState,
        type: SongItemPageType,
        item: Song
    ) {
        self.type = type
        self.state = state
        guard
            let pagePlane = Plane(
                in: plane,
                opts: .init(
                    pageState: state,
                    debugID: "SONG_UI_\(item.id)",
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
                debugID: "SONG_UI_\(item.id)_BORDER"
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
                    width: 4,
                    height: 1
                ),
                debugID: "SONG_UI_\(item.id)_PN"
            )
        else {
            return nil
        }
        self.pageNamePlane = pageNamePlane
        self.pageNamePlane.moveAbove(other: self.borderPlane)

        let contentWidth = max(state.width, 4) - 4
        guard
            let songRightPlane = Plane(
                in: pagePlane,
                state: .init(
                    absX: 2,
                    absY: 1,
                    width: min(UInt32(item.title.count), contentWidth),
                    height: 1
                ),
                debugID: "SONG_UI_\(item.id)_SR"
            )
        else {
            return nil
        }
        self.songRightPlane = songRightPlane
        self.songRightPlane.moveAbove(other: self.pageNamePlane)

        guard
            let artistRightPlane = Plane(
                in: pagePlane,
                state: .init(
                    absX: 2,
                    absY: 2,
                    width: min(UInt32(item.artistName.count), contentWidth),
                    height: 1
                ),
                debugID: "SONG_UI_\(item.id)_ARR"
            )
        else {
            return nil
        }
        self.artistRightPlane = artistRightPlane
        self.artistRightPlane.moveAbove(other: self.songRightPlane)

        guard
            let albumRightPlane = Plane(
                in: pagePlane,
                state: .init(
                    absX: 2,
                    absY: 3,
                    width: min(UInt32(item.albumTitle?.count ?? 1), contentWidth),
                    height: 1
                ),
                debugID: "SONG_UI_\(item.id)_AR"
            )
        else {
            return nil
        }
        self.albumRightPlane = albumRightPlane
        self.albumRightPlane.moveAbove(other: self.artistRightPlane)

        self.item = item

        updateColors()
    }

    public func updateColors() {
        let colorConfig: Theme.SongItem
        switch type {
        case .queuePage: colorConfig = Theme.shared.queue.songItem
        case .searchPage: colorConfig = Theme.shared.search.songItem
        case .artistDetailPage: colorConfig = Theme.shared.artistDetail.songItem
        case .albumDetailPage: colorConfig = Theme.shared.albumDetail.songItem
        case .playlistDetailPage: colorConfig = Theme.shared.playlistDetail.songItem
        }
        plane.setColorPair(colorConfig.page)
        borderPlane.setColorPair(colorConfig.border)
        pageNamePlane.setColorPair(colorConfig.pageName)
        songRightPlane.setColorPair(colorConfig.songRight)
        artistRightPlane.setColorPair(colorConfig.artistRight)
        albumRightPlane.setColorPair(colorConfig.albumRight)

        plane.blank()
        borderPlane.windowBorder(width: state.width, height: state.height)
        pageNamePlane.putString("Song", at: (0, 0))
        songRightPlane.putString(item.title, at: (0, 0))
        artistRightPlane.putString(item.artistName, at: (0, 0))
        albumRightPlane.putString(item.albumTitle ?? " ", at: (0, 0))
    }

    public func destroy() async {
        plane.erase()
        plane.destroy()

        borderPlane.erase()
        borderPlane.destroy()

        pageNamePlane.erase()
        pageNamePlane.destroy()

        songRightPlane.erase()
        songRightPlane.destroy()

        artistRightPlane.erase()
        artistRightPlane.destroy()

        albumRightPlane.erase()
        albumRightPlane.destroy()
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
