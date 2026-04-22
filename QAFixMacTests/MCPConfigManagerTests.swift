import XCTest
@testable import QAFixMac

final class MCPConfigManagerTests: XCTestCase {
    func testWritesValidJSON() throws {
        let url = try MCPConfigManager.writeNotionConfig(token: "secret-token-abc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let servers = json?["mcpServers"] as? [String: Any]
        let notion = servers?["notion"] as? [String: Any]
        XCTAssertNotNil(notion)
        XCTAssertEqual(notion?["command"] as? String, "npx")
        let env = notion?["env"] as? [String: Any]
        XCTAssertTrue((env?["OPENAPI_MCP_HEADERS"] as? String ?? "").contains("secret-token-abc"))
    }
}
