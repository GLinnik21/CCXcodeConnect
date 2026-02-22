import XCTest
@testable import IDEAdapterCore

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
}
