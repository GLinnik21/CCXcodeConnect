import XCTest
@testable import XcodeConnectCore

final class TextOffsetConverterTests: XCTestCase {

    func testOffsetZero() {
        let (line, char) = TextOffsetConverter.offsetToLineChar(in: "hello", offset: 0)
        XCTAssertEqual(line, 0)
        XCTAssertEqual(char, 0)
    }

    func testNegativeOffset() {
        let (line, char) = TextOffsetConverter.offsetToLineChar(in: "hello", offset: -5)
        XCTAssertEqual(line, 0)
        XCTAssertEqual(char, 0)
    }

    func testOffset1InHello() {
        let (line, char) = TextOffsetConverter.offsetToLineChar(in: "hello", offset: 1)
        XCTAssertEqual(line, 0)
        XCTAssertEqual(char, 0)
    }

    func testOffset3InHello() {
        let (line, char) = TextOffsetConverter.offsetToLineChar(in: "hello", offset: 3)
        XCTAssertEqual(line, 0)
        XCTAssertEqual(char, 2)
    }

    func testOffset7InMultiline() {
        let (line, char) = TextOffsetConverter.offsetToLineChar(in: "hello\nworld", offset: 7)
        XCTAssertEqual(line, 1)
        XCTAssertEqual(char, 0)
    }

    func testOffset6InMultiline() {
        let (line, char) = TextOffsetConverter.offsetToLineChar(in: "hello\nworld", offset: 6)
        XCTAssertEqual(line, 0)
        XCTAssertEqual(char, 5)
    }

    func testOffset5InThreeLines() {
        let (line, char) = TextOffsetConverter.offsetToLineChar(in: "a\nb\nc\n", offset: 5)
        XCTAssertEqual(line, 2)
        XCTAssertEqual(char, 0)
    }

    func testEmptyString() {
        let (line, char) = TextOffsetConverter.offsetToLineChar(in: "", offset: 0)
        XCTAssertEqual(line, 0)
        XCTAssertEqual(char, 0)
    }

    func testBeyondEnd() {
        let text = "ab"
        let (line, _) = TextOffsetConverter.offsetToLineChar(in: text, offset: 100)
        XCTAssertEqual(line, 0)
    }

    func testTwoOffsets_singleLine() {
        let text = "hello"
        let (r1, r2) = TextOffsetConverter.twoOffsetsToLineChars(in: text, first: 2, second: 4)
        XCTAssertEqual(r1.0, 0); XCTAssertEqual(r1.1, 1)
        XCTAssertEqual(r2.0, 0); XCTAssertEqual(r2.1, 3)
    }

    func testTwoOffsets_equal() {
        let text = "hello\nworld"
        let (r1, r2) = TextOffsetConverter.twoOffsetsToLineChars(in: text, first: 7, second: 7)
        XCTAssertEqual(r1.0, r2.0)
        XCTAssertEqual(r1.1, r2.1)
        XCTAssertEqual(r1.0, 1); XCTAssertEqual(r1.1, 0)
    }

    func testTwoOffsets_acrossNewline() {
        let text = "hello\nworld"
        let (r1, r2) = TextOffsetConverter.twoOffsetsToLineChars(in: text, first: 3, second: 8)
        XCTAssertEqual(r1.0, 0); XCTAssertEqual(r1.1, 2)
        XCTAssertEqual(r2.0, 1); XCTAssertEqual(r2.1, 1)
    }

    func testTwoOffsets_firstZero() {
        let text = "hello\nworld"
        let (r1, r2) = TextOffsetConverter.twoOffsetsToLineChars(in: text, first: 0, second: 7)
        XCTAssertEqual(r1.0, 0); XCTAssertEqual(r1.1, 0)
        XCTAssertEqual(r2.0, 1); XCTAssertEqual(r2.1, 0)
    }

    func testTwoOffsets_matchesIndividualCalls() {
        let text = "abc\ndefg\nhi"
        for first in [1, 3, 5, 9] {
            for second in [first, first + 1, first + 4] where second <= 11 {
                let expected1 = TextOffsetConverter.offsetToLineChar(in: text, offset: first)
                let expected2 = TextOffsetConverter.offsetToLineChar(in: text, offset: second)
                let (got1, got2) = TextOffsetConverter.twoOffsetsToLineChars(in: text, first: first, second: second)
                XCTAssertEqual(got1.0, expected1.line, "first=\(first) second=\(second) line mismatch for r1")
                XCTAssertEqual(got1.1, expected1.character, "first=\(first) second=\(second) char mismatch for r1")
                XCTAssertEqual(got2.0, expected2.line, "first=\(first) second=\(second) line mismatch for r2")
                XCTAssertEqual(got2.1, expected2.character, "first=\(first) second=\(second) char mismatch for r2")
            }
        }
    }
}
