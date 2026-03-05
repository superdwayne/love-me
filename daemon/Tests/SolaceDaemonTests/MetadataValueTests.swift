import XCTest
@testable import SolaceDaemon

final class MetadataValueTests: XCTestCase {

    func testStringMetadata() {
        let value = MetadataValue.string("test")
        if case .string(let s) = value {
            XCTAssertEqual(s, "test")
        } else {
            XCTFail("Expected string metadata")
        }
    }

    func testIntMetadata() {
        let value = MetadataValue.int(42)
        if case .int(let i) = value {
            XCTAssertEqual(i, 42)
        } else {
            XCTFail("Expected int metadata")
        }
    }

    func testBoolMetadata() {
        let value = MetadataValue.bool(true)
        if case .bool(let b) = value {
            XCTAssertEqual(b, true)
        } else {
            XCTFail("Expected bool metadata")
        }
    }

    func testDoubleMetadata() {
        let value = MetadataValue.double(3.14)
        if case .double(let d) = value {
            XCTAssertEqual(d, 3.14, accuracy: 0.001)
        } else {
            XCTFail("Expected double metadata")
        }
    }

    func testArrayMetadata() {
        let array = MetadataValue.array([
            .string("a"),
            .int(1),
            .bool(true)
        ])
        if case .array(let arr) = array {
            XCTAssertEqual(arr.count, 3)
        } else {
            XCTFail("Expected array metadata")
        }
    }

    func testObjectMetadata() {
        let object = MetadataValue.object([
            "name": .string("Alice"),
            "age": .int(30)
        ])
        if case .object(let dict) = object {
            if case .string(let name) = dict["name"] {
                XCTAssertEqual(name, "Alice")
            } else {
                XCTFail("Expected string value for name")
            }
            if case .int(let age) = dict["age"] {
                XCTAssertEqual(age, 30)
            } else {
                XCTFail("Expected int value for age")
            }
        } else {
            XCTFail("Expected object metadata")
        }
    }

    func testMetadataEncoding() throws {
        let value = MetadataValue.object([
            "text": .string("hello"),
            "number": .int(123)
        ])

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(MetadataValue.self, from: data)

        if case .object(let dict) = decoded {
            if case .string(let text) = dict["text"] {
                XCTAssertEqual(text, "hello")
            }
            if case .int(let num) = dict["number"] {
                XCTAssertEqual(num, 123)
            }
        } else {
            XCTFail("Expected decoded object")
        }
    }

    func testNullMetadata() {
        let value = MetadataValue.null
        if case .null = value {
            // Success
        } else {
            XCTFail("Expected null metadata")
        }
    }
}
