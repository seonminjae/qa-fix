import XCTest
@testable import QAFixMac

final class StreamJSONParserTests: XCTestCase {
    func testAssistantText() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Hello"}]}}"#
        let event = StreamJSONParser.parseLine(line)
        if case let .assistantText(text) = event {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected assistantText, got \(event)")
        }
    }

    func testToolUse() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"path":"a.swift"}}]}}"#
        let event = StreamJSONParser.parseLine(line)
        if case let .toolUse(name, input) = event {
            XCTAssertEqual(name, "Read")
            XCTAssertTrue(input.contains("a.swift"))
        } else {
            XCTFail("Expected toolUse, got \(event)")
        }
    }

    func testResultWithTotalCost() {
        let line = #"{"type":"result","subtype":"success","total_cost_usd":0.0123,"duration_ms":1500,"usage":{"input_tokens":100,"output_tokens":200}}"#
        let event = StreamJSONParser.parseLine(line)
        if case let .result(usage, _) = event {
            XCTAssertEqual(usage.totalCostUSD, 0.0123)
            XCTAssertEqual(usage.inputTokens, 100)
            XCTAssertEqual(usage.outputTokens, 200)
            XCTAssertEqual(usage.durationMS, 1500)
        } else {
            XCTFail("Expected result, got \(event)")
        }
    }

    func testUnknownFallsThrough() {
        let line = #"{"type":"mystery_event","foo":"bar"}"#
        let event = StreamJSONParser.parseLine(line)
        if case let .unknown(raw) = event {
            XCTAssertEqual(raw, line)
        } else {
            XCTFail("Expected unknown, got \(event)")
        }
    }

    func testMalformedJSON() {
        let line = "not a json"
        let event = StreamJSONParser.parseLine(line)
        if case .unknown = event {} else {
            XCTFail("Expected unknown on malformed json")
        }
    }
}
