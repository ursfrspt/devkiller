@testable import DevKillerCore
import XCTest

final class LsofParserTests: XCTestCase {
    func testParsesStructuredLsofRecords() {
        let output = """
        p12345
        cnode
        Ligyeongjun
        n*:5173
        n127.0.0.1:24678
        p99
        cPython
        Lroot
        n127.0.0.1:8000
        """

        let records = LsofParser.parseListeningProcesses(output)

        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records[0].pid, 12345)
        XCTAssertEqual(records[0].command, "node")
        XCTAssertEqual(records[0].user, "igyeongjun")
        XCTAssertEqual(records[0].port, 5173)
        XCTAssertEqual(records[1].port, 24678)
        XCTAssertEqual(records[2].pid, 99)
        XCTAssertEqual(records[2].command, "Python")
        XCTAssertEqual(records[2].port, 8000)
    }

    func testIgnoresRecordsWithoutPort() {
        let output = """
        p12345
        cnode
        nlocalhost
        """

        XCTAssertTrue(LsofParser.parseListeningProcesses(output).isEmpty)
    }
}
