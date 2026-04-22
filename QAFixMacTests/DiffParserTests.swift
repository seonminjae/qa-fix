import XCTest
@testable import QAFixMac

final class DiffParserTests: XCTestCase {
    func testSingleFileParsing() {
        let diff = """
        diff --git a/Foo.swift b/Foo.swift
        index 1..2 100644
        --- a/Foo.swift
        +++ b/Foo.swift
        @@ -1,3 +1,3 @@
         line1
        -old
        +new
        """
        let files = DiffParser.parse(diff)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.path, "Foo.swift")
        XCTAssertEqual(files.first?.additions, 1)
        XCTAssertEqual(files.first?.deletions, 1)
    }

    func testMultipleFiles() {
        let diff = """
        diff --git a/A.swift b/A.swift
        --- a/A.swift
        +++ b/A.swift
        @@ -1 +1 @@
        -a
        +a!
        diff --git a/B.swift b/B.swift
        --- a/B.swift
        +++ b/B.swift
        @@ -1 +1 @@
        -b
        +b!
        """
        let files = DiffParser.parse(diff)
        XCTAssertEqual(files.count, 2)
    }
}
