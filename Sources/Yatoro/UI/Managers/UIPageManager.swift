import SwiftNotCurses

@MainActor
public struct UIPageManager {

    static var configReload: Bool = false

    var layoutRows: UInt32
    var layoutColumns: UInt32

    // Row-based layout: layout[rowIndex] = [pages side-by-side in that row]
    var layout: [[Page]]

    var commandPage: CommandPage
    var windowTooSmallPage: WindowTooSmallPage

    private static var currentWidth: UInt32 = 0
    private static var currentHeight: UInt32 = 0
    private static var searchActive: Bool = false
    private static var queueActive: Bool = false

    public init?(
        uiConfig: Config.UIConfig,
        stdPlane: Plane
    ) async {
        self.layout = []
        let layoutConfig = uiConfig.layout
        self.layoutRows = layoutConfig.rows
        self.layoutColumns = layoutConfig.cols

        for _ in 0..<layoutRows {
            layout.append([])
        }

        // Fill pages left-to-right, top-to-bottom
        var index = 0
        for row in 0..<Int(layoutRows) {
            for _ in 0..<Int(layoutColumns) {
                if index >= layoutConfig.pages.count {
                    continue
                }

                let pageType = layoutConfig.pages[index]
                index += 1

                switch pageType {

                case .nowPlaying:
                    guard
                        let nowPlayingPage = NowPlayingPage(
                            stdPlane: stdPlane,
                            state: PageState(
                                absX: 0,
                                absY: 0,
                                width: 28,
                                height: 13
                            )
                        )
                    else {
                        logger?.critical("Failed to initiate Player Page.")
                        return nil
                    }
                    layout[row].append(nowPlayingPage)

                case .queue:
                    guard
                        let queuePage = QueuePage(
                            stdPlane: stdPlane,
                            state: PageState(
                                absX: 0,
                                absY: 0,
                                width: 28,
                                height: 13
                            )
                        )
                    else {
                        logger?.critical("Failed to initiate Queue Page.")
                        return nil
                    }
                    layout[row].append(queuePage)

                case .search:
                    guard
                        let searchPage = SearchPage(
                            stdPlane: stdPlane,
                            state: PageState(
                                absX: 0,
                                absY: 0,
                                width: 28,
                                height: 13
                            )
                        )
                    else {
                        logger?.critical("Failed to initiate Search Page.")
                        return nil
                    }
                    layout[row].append(searchPage)

                }
            }
        }
        guard
            let commandPage = CommandPage(stdPlane: stdPlane)
        else {
            fatalError("Failed to initiate Command Page.")
        }

        guard
            let windowTooSmallPage = WindowTooSmallPage(
                stdPlane: stdPlane
            )
        else {
            fatalError("Failed to initiate Window Too Small Page.")
        }
        self.commandPage = commandPage
        self.windowTooSmallPage = windowTooSmallPage
        await setMinimumRequiredDiminsions()
        return
    }

    public func forEachPage(
        _ action: @MainActor @escaping (_ page: Page, _ row: UInt32, _ col: UInt32) async -> Void
    ) async {
        for (rowIndex, row) in layout.enumerated() {
            for (colIndex, page) in row.enumerated() {
                await action(page, UInt32(rowIndex), UInt32(colIndex))
            }
        }
    }

    public func renderPages() async {
        // Detect search/queue state changes and trigger layout resize
        let hasSearch = SearchManager.shared.lastSearchResult != nil
        let hasQueue = Player.shared.queue.count > 1
        let needsResize = (hasSearch != UIPageManager.searchActive) || (hasQueue != UIPageManager.queueActive)
        if needsResize {
            UIPageManager.searchActive = hasSearch
            UIPageManager.queueActive = hasQueue
            if UIPageManager.currentWidth > 0 && UIPageManager.currentHeight > 0 {
                await resizePages(UIPageManager.currentWidth, UIPageManager.currentHeight)
            }
        }

        if UIPageManager.configReload {
            await forEachPage { page, _, _ in
                page.updateColors()
            }
            UIPageManager.configReload = false
            // Force full re-render so existing text picks up new colors
            if UIPageManager.currentWidth > 0 && UIPageManager.currentHeight > 0 {
                await resizePages(UIPageManager.currentWidth, UIPageManager.currentHeight)
            }
        }
        if windowTooSmallPage.windowTooSmall() {
            await windowTooSmallPage.render()
            return
        }
        await forEachPage { page, _, _ in
            await page.render()
        }
        await commandPage.render()
    }

    public func resizePages(
        _ newWidth: UInt32,
        _ newHeight: UInt32
    ) async {
        UIPageManager.currentWidth = newWidth
        UIPageManager.currentHeight = newHeight

        let commandPageHeight: UInt32 = 2
        let availableHeight = newHeight - commandPageHeight

        let numRows = UInt32(layout.count)
        if numRows == 0 {
            return
        }

        // Determine which rows are visible (hide search row when inactive)
        var rowVisible: [Bool] = []
        for row in layout {
            let isSearchRow = row.contains(where: { $0 is SearchPage })
            rowVisible.append(!isSearchRow || UIPageManager.searchActive)
        }

        let visibleRowCount = UInt32(rowVisible.filter { $0 }.count)
        guard visibleRowCount > 0 else { return }

        let baseRowHeight = availableHeight / visibleRowCount
        let extraHeight = availableHeight % visibleRowCount

        var currentY: UInt32 = 0
        var visibleIndex: UInt32 = 0

        for (rowIndex, row) in layout.enumerated() {
            if !rowVisible[rowIndex] {
                // Hide pages in this row (move off-screen with minimal size)
                for page in row {
                    await page.onResize(newPageState: PageState(
                        absX: 0,
                        absY: Int32(newHeight),
                        width: 1,
                        height: 1
                    ))
                }
                continue
            }

            let rowHeight = baseRowHeight + (visibleIndex < extraHeight ? 1 : 0)

            // Determine visible columns in this row (hide queue when empty)
            var visiblePages: [(Int, Page)] = []
            for (colIndex, page) in row.enumerated() {
                let isQueuePage = page is QueuePage
                if isQueuePage && !UIPageManager.queueActive {
                    // Hide this page
                    await page.onResize(newPageState: PageState(
                        absX: Int32(newWidth),
                        absY: Int32(newHeight),
                        width: 1,
                        height: 1
                    ))
                } else {
                    visiblePages.append((colIndex, page))
                }
            }

            let numVisibleCols = UInt32(visiblePages.count)
            if numVisibleCols == 0 {
                currentY += rowHeight
                visibleIndex += 1
                continue
            }

            let baseColWidth = newWidth / numVisibleCols
            let extraWidth = newWidth % numVisibleCols

            var currentX: UInt32 = 0

            for (visColIndex, (_, page)) in visiblePages.enumerated() {
                let pageWidth = baseColWidth + (UInt32(visColIndex) < extraWidth ? 1 : 0)

                let newPageState = PageState(
                    absX: Int32(currentX),
                    absY: Int32(currentY),
                    width: pageWidth,
                    height: rowHeight
                )

                await page.onResize(newPageState: newPageState)
                await page.render()

                currentX += pageWidth
            }
            currentY += rowHeight
            visibleIndex += 1
        }
        await commandPage.onResize(
            newPageState: .init(
                absX: 0,
                absY: Int32(newHeight) - 2,
                width: newWidth,
                height: 2
            )
        )
        await windowTooSmallPage.onResize(
            newPageState: .init(
                absX: 0,
                absY: 0,
                width: newWidth,
                height: newHeight
            )
        )
    }

    public func onQuit() async {
        await forEachPage { page, _, _ in
            if let page = page as? DestroyablePage {
                await page.destroy()
            }
        }
    }

    private func setMinimumRequiredDiminsions() async {
        var minWidth: UInt32 = 0
        var minHeight: UInt32 = 0

        for row in layout {
            var rowMinWidth: UInt32 = 0
            var rowMinHeight: UInt32 = 0

            for page in row {
                let minDim = await page.getMinDimensions()
                rowMinWidth += minDim.width
                rowMinHeight = max(rowMinHeight, minDim.height)
            }

            minWidth = max(minWidth, rowMinWidth)
            minHeight += rowMinHeight
        }

        await windowTooSmallPage.setMinRequiredDim((minWidth, minHeight))
    }

}
