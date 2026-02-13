import MusicKit
import SwiftNotCurses

@MainActor
public class RecommendationItemPage: DestroyablePage {

    private var state: PageState
    private let plane: Plane

    private let borderPlane: Plane
    private let pageNamePlane: Plane
    private let refreshDateRightPlane: Plane?
    private let titleRightPlane: Plane?
    private let typesRightPlane: Plane

    private let item: MusicPersonalRecommendation

    public func getItem() async -> MusicPersonalRecommendation { item }

    public init?(
        in plane: Plane,
        state: PageState,
        item: MusicPersonalRecommendation
    ) {
        self.state = state
        guard
            let pagePlane = Plane(
                in: plane,
                opts: .init(
                    pageState: state,
                    debugID: "RECOMMENDATION_UI_\(item.id)",
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
                debugID: "RECOMMENDATION_UI_\(item.id)_BORDER"
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
                    width: 14,
                    height: 1
                ),
                debugID: "RECOMMENDATION_UI_\(item.id)_PN"
            )
        else {
            return nil
        }
        self.pageNamePlane = pageNamePlane
        self.pageNamePlane.moveAbove(other: self.borderPlane)

        let contentWidth = max(state.width, 4) - 4

        // Title - row 1, primary
        if let title = item.title {
            guard
                let titleRightPlane = Plane(
                    in: pagePlane,
                    state: .init(
                        absX: 2,
                        absY: 1,
                        width: min(UInt32(title.count), contentWidth),
                        height: 1
                    ),
                    debugID: "RECOMMENDATION_UI_\(item.id)_GR"
                )
            else {
                return nil
            }
            self.titleRightPlane = titleRightPlane
            self.titleRightPlane?.moveAbove(other: self.pageNamePlane)
        } else {
            self.titleRightPlane = nil
        }

        // Refresh date - row 2, secondary
        if let refreshDate = item.nextRefreshDate?.formatted() {
            guard
                let refreshDateRightPlane = Plane(
                    in: pagePlane,
                    state: .init(
                        absX: 2,
                        absY: 2,
                        width: min(UInt32(refreshDate.count), contentWidth),
                        height: 1
                    ),
                    debugID: "RECOMMENDATION_UI_\(item.id)_ARR"
                )
            else {
                return nil
            }
            self.refreshDateRightPlane = refreshDateRightPlane
            self.refreshDateRightPlane?.moveAbove(other: self.titleRightPlane ?? self.pageNamePlane)
        } else {
            self.refreshDateRightPlane = nil
        }

        // Types - row 3, tertiary
        var typesStr = ""
        for type in item.types {
            typesStr.append("\(type), ")
        }
        if typesStr.count >= 2 {
            typesStr.removeLast(2)
        }
        guard
            let typesRightPlane = Plane(
                in: pagePlane,
                state: .init(
                    absX: 2,
                    absY: 3,
                    width: min(UInt32(typesStr.count), contentWidth),
                    height: 1
                ),
                debugID: "RECOMMENDATION_UI_\(item.id)_ALR"
            )
        else {
            return nil
        }
        self.typesRightPlane = typesRightPlane
        self.typesRightPlane.moveAbove(other: self.refreshDateRightPlane ?? self.titleRightPlane ?? self.pageNamePlane)

        self.item = item

        updateColors()

    }

    public func updateColors() {
        let colorConfig = Theme.shared.search.recommendationItem
        plane.setColorPair(colorConfig.page)
        borderPlane.setColorPair(colorConfig.border)
        pageNamePlane.setColorPair(colorConfig.pageName)
        titleRightPlane?.setColorPair(colorConfig.titleRight)
        typesRightPlane.setColorPair(colorConfig.typesRight)
        refreshDateRightPlane?.setColorPair(colorConfig.refreshDateRight)

        plane.blank()
        pageNamePlane.putString("Recommendation", at: (0, 0))
        if let title = item.title {
            titleRightPlane?.putString(title, at: (0, 0))
        }
        if let refreshDate = item.nextRefreshDate?.formatted() {
            refreshDateRightPlane?.putString(refreshDate, at: (0, 0))
        }
        var typesStr = ""
        for type in item.types {
            typesStr.append("\(type), ")
        }
        if typesStr.count >= 2 {
            typesStr.removeLast(2)
        }
        typesRightPlane.putString(typesStr, at: (0, 0))
        borderPlane.windowBorder(width: state.width, height: state.height)
    }

    public func destroy() async {
        plane.erase()
        plane.destroy()

        borderPlane.erase()
        borderPlane.destroy()

        pageNamePlane.erase()
        pageNamePlane.destroy()

        refreshDateRightPlane?.erase()
        refreshDateRightPlane?.destroy()

        titleRightPlane?.erase()
        titleRightPlane?.destroy()

        typesRightPlane.erase()
        typesRightPlane.destroy()
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
