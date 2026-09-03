import XCTest
@testable import LinguaFlowCore

final class CommittedSentenceBufferTests: XCTestCase {
    func testBuildsASentenceFromCommittedChunks() {
        var buffer = CommittedSentenceBuffer(maxCharacters: 120)

        XCTAssertEqual(buffer.append("我今天"), .init(text: "我今天", revision: 1, isFinal: false))
        XCTAssertEqual(buffer.append("想去公园"), .init(text: "我今天想去公园", revision: 2, isFinal: false))
    }

    func testFinalPunctuationFinishesCurrentSentenceAndStartsANewOne() {
        var buffer = CommittedSentenceBuffer(maxCharacters: 120)

        _ = buffer.append("我今天想去公园")
        XCTAssertEqual(
            buffer.append("。"),
            .init(text: "我今天想去公园。", revision: 2, isFinal: true)
        )
        XCTAssertEqual(
            buffer.append("明天"),
            .init(text: "明天", revision: 3, isFinal: false)
        )
    }

    func testDeleteTracksHostBackspaceWithoutConsumingTheHostEvent() {
        var buffer = CommittedSentenceBuffer(maxCharacters: 120)
        _ = buffer.append("你好呀")

        XCTAssertEqual(buffer.removeLastCharacter(), .init(text: "你好", revision: 2, isFinal: false))
    }

    func testCapsContextByCharactersInsteadOfUtf8Bytes() {
        var buffer = CommittedSentenceBuffer(maxCharacters: 4)

        XCTAssertEqual(buffer.append("甲乙丙丁戊"), .init(text: "乙丙丁戊", revision: 1, isFinal: false))
    }

    func testWhitespaceOnlyCommitDoesNotCreateARequest() {
        var buffer = CommittedSentenceBuffer(maxCharacters: 120)

        XCTAssertNil(buffer.append("   \n"))
        XCTAssertEqual(buffer.revision, 0)
    }

    func testResetDropsDocumentContextAndAdvancesRevision() {
        var buffer = CommittedSentenceBuffer(maxCharacters: 120)
        _ = buffer.append("不能带到下一个应用")

        buffer.reset()

        XCTAssertEqual(buffer.revision, 2)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertNil(buffer.currentSnapshot)
    }
}
