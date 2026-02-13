import MusicKit
import SwiftNotCurses

@MainActor
public class StationItemPage: DestroyablePage {

    private var state: PageState
    private let plane: Plane

    private let borderPlane: Plane
    private let pageNamePlane: Plane
    private let notesRightPlane: Plane
    private let isLiveRightPlane: Plane
    private let stationRightPlane: Plane

    private let item: Station

    public func getItem() async -> Station { item }

    public enum StationItemPageType {
        case searchPage
        case recommendationDetail
    }

    private let type: StationItemPageType

    public init?(
        in plane: Plane,
        state: PageState,
        item: Station,
        type: StationItemPageType
    ) {
        self.type = type
        self.state = state
        guard
            let pagePlane = Plane(
                in: plane,
                opts: .init(
                    pageState: state,
                    debugID: "STATION_UI_\(item.id)",
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
                debugID: "STATION_UI_\(item.id)_BORDER"
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
                    width: 7,
                    height: 1
                ),
                debugID: "STATION_UI_\(item.id)_PN"
            )
        else {
            return nil
        }
        self.pageNamePlane = pageNamePlane
        self.pageNamePlane.moveAbove(other: self.borderPlane)

        let contentWidth = max(state.width, 4) - 4

        // Station name - row 1, primary
        guard
            let stationRightPlane = Plane(
                in: pagePlane,
                state: .init(
                    absX: 2,
                    absY: 1,
                    width: min(UInt32(item.name.count), contentWidth),
                    height: 1
                ),
                debugID: "STATION_UI_\(item.id)_SR"
            )
        else {
            return nil
        }
        self.stationRightPlane = stationRightPlane
        self.stationRightPlane.moveAbove(other: self.pageNamePlane)

        // IsLive - row 2, secondary
        guard
            let isLiveRightPlane = Plane(
                in: pagePlane,
                state: .init(
                    absX: 2,
                    absY: 2,
                    width: min(UInt32("\(item.isLive)".count), contentWidth),
                    height: 1
                ),
                debugID: "STATION_UI_\(item.id)_CR"
            )
        else {
            return nil
        }
        self.isLiveRightPlane = isLiveRightPlane
        self.isLiveRightPlane.moveAbove(other: self.stationRightPlane)

        // Notes - row 3, tertiary
        var notesWidth = min(UInt32(item.editorialNotes?.standard?.count ?? 1), contentWidth)
        if notesWidth == 0 { notesWidth = 1 }
        guard
            let notesRightPlane = Plane(
                in: pagePlane,
                state: .init(
                    absX: 2,
                    absY: 3,
                    width: notesWidth,
                    height: 1
                ),
                debugID: "STATION_UI_\(item.id)_DR"
            )
        else {
            return nil
        }
        self.notesRightPlane = notesRightPlane
        self.notesRightPlane.moveAbove(other: self.isLiveRightPlane)

        self.item = item

        updateColors()
    }

    public func updateColors() {
        let colorConfig: Theme.StationItem
        switch self.type {
        case .searchPage:
            colorConfig = Theme.shared.search.stationItem
        case .recommendationDetail:
            colorConfig = Theme.shared.recommendationDetail.stationItem
        }
        plane.setColorPair(colorConfig.page)
        borderPlane.setColorPair(colorConfig.border)
        pageNamePlane.setColorPair(colorConfig.pageName)
        stationRightPlane.setColorPair(colorConfig.stationRight)
        notesRightPlane.setColorPair(colorConfig.notesRight)
        isLiveRightPlane.setColorPair(colorConfig.isLiveRight)

        plane.blank()
        borderPlane.windowBorder(width: state.width, height: state.height)
        pageNamePlane.putString("Station", at: (0, 0))
        stationRightPlane.putString(item.name, at: (0, 0))
        isLiveRightPlane.putString("\(item.isLive)", at: (0, 0))
        notesRightPlane.putString(item.editorialNotes?.standard ?? "", at: (0, 0))
    }

    public func destroy() async {
        plane.erase()
        plane.destroy()

        borderPlane.erase()
        borderPlane.destroy()

        pageNamePlane.erase()
        pageNamePlane.destroy()

        isLiveRightPlane.erase()
        isLiveRightPlane.destroy()

        notesRightPlane.erase()
        notesRightPlane.destroy()

        stationRightPlane.erase()
        stationRightPlane.destroy()
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
