@testable import DevKillerCore
import XCTest

final class ServerClassifierTests: XCTestCase {
    func testHighConfidenceWhenCommandAndPortMatch() {
        let classification = ServerClassifier.classify(command: "node", port: 5173)

        XCTAssertEqual(classification.framework, "Vite dev server")
        XCTAssertEqual(classification.confidence, .high)
        XCTAssertTrue(classification.isLikelyDevelopmentServer)
    }

    func testMediumConfidenceForKnownPortOnly() {
        let classification = ServerClassifier.classify(command: "unknown", port: 3000)

        XCTAssertEqual(classification.confidence, .medium)
        XCTAssertTrue(classification.isLikelyDevelopmentServer)
    }

    func testLowConfidenceForUnrecognizedPrivilegedPort() {
        let classification = ServerClassifier.classify(command: "launchd", port: 80)

        XCTAssertEqual(classification.confidence, .low)
        XCTAssertFalse(classification.isLikelyDevelopmentServer)
    }

    func testKnownMacOSSystemProcessIsLowConfidenceEvenOnCommonDevPort() {
        let classification = ServerClassifier.classify(command: "ControlCenter", port: 5000)

        XCTAssertEqual(classification.confidence, .low)
        XCTAssertFalse(classification.isLikelyDevelopmentServer)
    }

    func testSpecificPortHintSurvivesGenericRuntimeCommand() {
        let classification = ServerClassifier.classify(command: "node", port: 5173)

        XCTAssertEqual(classification.framework, "Vite dev server")
    }

    func testExpoMetroPortIsIdentified() {
        let classification = ServerClassifier.classify(command: "node", port: 8081)

        XCTAssertEqual(classification.framework, "Expo / React Native Metro")
        XCTAssertEqual(classification.confidence, .high)
        XCTAssertTrue(classification.isLikelyDevelopmentServer)
    }

    func testExpoMetroFallbackPortIsIdentified() {
        let classification = ServerClassifier.classify(command: "node", port: 8082)

        XCTAssertEqual(classification.framework, "Expo / React Native Metro")
        XCTAssertEqual(classification.confidence, .high)
        XCTAssertTrue(classification.isLikelyDevelopmentServer)
    }
}
