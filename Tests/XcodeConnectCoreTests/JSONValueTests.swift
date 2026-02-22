import XCTest
@testable import XcodeConnectCore

final class JSONValueTests: XCTestCase {

    // MARK: - Round-trip for all 7 variants

    func testNullRoundTrip() throws {
        let val: JSONValue = .null
        let data = try JSONEncoder().encode(val)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, .null)
    }

    func testBoolRoundTrip() throws {
        for b in [true, false] {
            let val: JSONValue = .bool(b)
            let data = try JSONEncoder().encode(val)
            let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
            XCTAssertEqual(decoded, .bool(b))
        }
    }

    func testIntRoundTrip() throws {
        let val: JSONValue = .int(42)
        let data = try JSONEncoder().encode(val)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, .int(42))
    }

    func testDoubleRoundTrip() throws {
        let val: JSONValue = .double(3.14)
        let data = try JSONEncoder().encode(val)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, .double(3.14))
    }

    func testStringRoundTrip() throws {
        let val: JSONValue = .string("hello")
        let data = try JSONEncoder().encode(val)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, .string("hello"))
    }

    func testArrayRoundTrip() throws {
        let val: JSONValue = .array([.int(1), .string("two"), .bool(true)])
        let data = try JSONEncoder().encode(val)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, val)
    }

    func testObjectRoundTrip() throws {
        let val: JSONValue = .object(["key": .string("value"), "num": .int(1)])
        let data = try JSONEncoder().encode(val)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, val)
    }

    // MARK: - Nested structures

    func testNestedStructure() throws {
        let val: JSONValue = .object([
            "list": .array([.object(["inner": .bool(true)])]),
            "meta": .null
        ])
        let data = try JSONEncoder().encode(val)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, val)
    }

    // MARK: - Accessors

    func testStringValueAccessor() {
        XCTAssertEqual(JSONValue.string("hi").stringValue, "hi")
        XCTAssertNil(JSONValue.int(1).stringValue)
    }

    func testObjectValueAccessor() {
        let obj: JSONValue = .object(["a": .int(1)])
        XCTAssertNotNil(obj.objectValue)
        XCTAssertNil(JSONValue.string("x").objectValue)
    }

    func testArrayValueAccessor() {
        let arr: JSONValue = .array([.int(1)])
        XCTAssertNotNil(arr.arrayValue)
        XCTAssertNil(JSONValue.string("x").arrayValue)
    }

    func testIntValueAccessor() {
        XCTAssertEqual(JSONValue.int(5).intValue, 5)
        XCTAssertNil(JSONValue.string("5").intValue)
    }

    // MARK: - Subscript

    func testSubscriptOnObject() {
        let val: JSONValue = .object(["key": .string("val")])
        XCTAssertEqual(val["key"], .string("val"))
    }

    func testSubscriptMissingKey() {
        let val: JSONValue = .object(["key": .string("val")])
        XCTAssertNil(val["missing"])
    }

    func testSubscriptOnNonObject() {
        let val: JSONValue = .string("not object")
        XCTAssertNil(val["key"])
    }

    // MARK: - Hashable

    func testEquality() {
        XCTAssertEqual(JSONValue.int(1), JSONValue.int(1))
        XCTAssertNotEqual(JSONValue.int(1), JSONValue.int(2))
    }

    func testSetUsage() {
        var set = Set<JSONValue>()
        set.insert(.string("a"))
        set.insert(.string("a"))
        set.insert(.int(1))
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - Decode from raw JSON

    func testDecodeFromRawJSON() throws {
        let json = #"{"name":"test","count":3,"active":true,"tags":["a","b"]}"#
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded["name"]?.stringValue, "test")
        XCTAssertEqual(decoded["count"]?.intValue, 3)
        XCTAssertEqual(decoded["active"], .bool(true))
        XCTAssertEqual(decoded["tags"]?.arrayValue?.count, 2)
    }
}
