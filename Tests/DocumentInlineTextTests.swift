import XCTest
@testable import Pawster

final class DocumentInlineTextTests: XCTestCase {
    private func linkedText(_ value: AttributedString) -> [String] {
        value.runs.compactMap { run in run.link == nil ? nil : String(value[run.range].characters) }
    }
    func testChineseTextAfterAURLIsNotPartOfTheLink() {
        let source = "项目：https://github.com/GotTal/Pawster。项目代码许可：GPL-3.0-or-later；请阅读声明。"
        let result = DocumentInlineText.render(source)
        XCTAssertEqual(String(result.characters), source)
        XCTAssertEqual(linkedText(result), ["https://github.com/GotTal/Pawster"])
        XCTAssertEqual(result.runs.compactMap(\.link).map(\.absoluteString), ["https://github.com/GotTal/Pawster"])
    }
    func testScreenshotExamplesKeepCommitAndExplanationOutsideLinks() {
        let source = "来源：https://github.com/Mak5er/AirCard-iOS，固定提交 40640c4d。另引用 https://github.com/rooootdev/neospring。本项目保留署名，加入会话控制。"
        let result = DocumentInlineText.render(source)
        XCTAssertEqual(String(result.characters), source)
        XCTAssertEqual(linkedText(result), ["https://github.com/Mak5er/AirCard-iOS", "https://github.com/rooootdev/neospring"])
    }
    func testEnglishPunctuationAndBalancedURLParentheses() {
        let source = "See (https://example.com/docs_(cat)). Next: https://example.com/help?x=1&y=2#topic, then continue."
        let result = DocumentInlineText.render(source)
        XCTAssertEqual(String(result.characters), source)
        XCTAssertEqual(linkedText(result), ["https://example.com/docs_(cat)", "https://example.com/help?x=1&y=2#topic"])
    }
    func testExplicitMarkdownLinksAndCodeSpansAreNotRewritten() {
        let source = "[项目主页](https://github.com/GotTal/Pawster) 和 `https://example.com/code`，以及 <https://example.com/help>。"
        XCTAssertEqual(DocumentInlineText.boundedMarkdown(source), source)
        let result = DocumentInlineText.render(source)
        XCTAssertEqual(linkedText(result), ["项目主页", "https://example.com/help"])
        XCTAssertTrue(String(result.characters).contains("https://example.com/code"))
    }
    func testEmailBoundariesAndEmphasisRemainIntact() {
        let source = "联系 xkstudio@icloud.com。**保存其他工作**，正文不是邮箱链接。"
        let result = DocumentInlineText.render(source)
        XCTAssertEqual(linkedText(result), ["xkstudio@icloud.com"])
        XCTAssertEqual(result.runs.compactMap(\.link).map(\.absoluteString), ["mailto:xkstudio@icloud.com"])
        XCTAssertTrue(result.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        XCTAssertTrue(String(result.characters).contains("。保存其他工作，正文不是邮箱链接。"))
    }
    func testNormalizationDoesNotGrowWhenAppliedAgain() {
        let source = "https://github.com/GotTal/Pawster。邮箱：xkstudio@icloud.com。"
        let normalized = DocumentInlineText.boundedMarkdown(source)
        XCTAssertEqual(DocumentInlineText.boundedMarkdown(normalized), normalized)
        XCTAssertEqual(normalized, "<https://github.com/GotTal/Pawster>。邮箱：<xkstudio@icloud.com>。")
    }
}
