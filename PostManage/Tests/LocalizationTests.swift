import XCTest
@testable import PostManage

final class LocalizationTests: XCTestCase {
    func testChineseStringsAreBundled() throws {
        let appBundle = Bundle(for: AppStore.self)
        let folder = try XCTUnwrap(appBundle.path(forResource: "zh-Hans", ofType: "lproj"))
        let chinese = try XCTUnwrap(Bundle(path: folder))
        XCTAssertEqual(chinese.localizedString(forKey: "Settings", value: nil, table: nil), "设置")
        XCTAssertEqual(chinese.localizedString(forKey: "Format JSON", value: nil, table: nil), "格式化 JSON")
        XCTAssertEqual(L10n.string("Open Data Folder", language: "zh-Hans", bundle: appBundle), "打开数据目录")
        XCTAssertEqual(L10n.string("Open Data Folder", language: "en", bundle: appBundle), "Open Data Folder")
        XCTAssertEqual(L10n.format("Replace All (%d)", language: "zh-Hans", 3, bundle: appBundle), "全部替换（3）")
        XCTAssertEqual(L10n.string("Expand collection", language: "zh-Hans", bundle: appBundle), "展开集合")
        XCTAssertEqual(L10n.string("Auth password", language: "zh-Hans", bundle: appBundle), "授权密码")
        XCTAssertEqual(L10n.format("Version %@", language: "zh-Hans", "1.0.1", bundle: appBundle), "版本 1.0.1")
        XCTAssertEqual(L10n.format("Replaced %d matches in %@", language: "zh-Hans",
                                    3, "工作区", bundle: appBundle), "已替换 工作区 中的 3 处匹配")
    }

    func testAppBundleHasMarketingAndBuildVersions() {
        let info = Bundle(for: AppStore.self).infoDictionary
        XCTAssertEqual(info?["CFBundleShortVersionString"] as? String, "1.0.1")
        XCTAssertEqual(info?["CFBundleVersion"] as? String, "1")
    }
}
