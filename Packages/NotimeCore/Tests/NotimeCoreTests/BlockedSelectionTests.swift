#if !os(iOS)
import NotimeCore
import XCTest

final class BlockedSelectionTests: XCTestCase {
    func testFiftyAppsAndSitesFitButFiftyOneDoNot() {
        let apps = Set((0..<30).map { ApplicationToken("app\($0)") })
        let sites = Set((0..<20).map { WebDomainToken("site\($0)") })
        var selection = BlockedSelection(applicationTokens: apps, webDomainTokens: sites)
        XCTAssertFalse(selection.exceedsShieldLimit)

        selection.webDomainTokens.insert(WebDomainToken("one-more"))
        XCTAssertTrue(selection.exceedsShieldLimit)
    }

    func testCategoriesDoNotCountTowardTheLimit() {
        let categories = Set((0..<100).map { ActivityCategoryToken("category\($0)") })
        XCTAssertFalse(BlockedSelection(categoryTokens: categories).exceedsShieldLimit)
    }
}
#endif
