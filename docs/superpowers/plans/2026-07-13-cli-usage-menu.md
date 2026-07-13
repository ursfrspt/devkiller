# CLI Usage in Menu Bar — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the official Claude Code and Codex 5-hour and weekly usage limits (percent used + reset info) in the DevKiller menu bar.

**Architecture:** All parsing/provider logic lives in `DevKillerCore` as pure functions behind injected protocols (mirroring the existing `LsofRunning`/`SystemLsofRunner` pattern). Claude data comes from a live `claude -p "/usage"` call; Codex data comes from the newest local `rollout-*.jsonl` `rate_limits` snapshot. `DevKillerBar` renders a Usage section and refreshes on menu-open + a manual button.

**Tech Stack:** Swift 5.9, SwiftPM, SwiftUI `MenuBarExtra`, XCTest, `Foundation.Process`.

## Global Constraints

- Platform: macOS 13+ (`swift-tools-version: 5.9`).
- Keep discovery/parsing logic in `DevKillerCore`; keep `DevKillerBar` UI thin (per `AGENTS.md`).
- Inject process execution and file access via protocols so parsers are pure and unit-testable (mirror `LsofRunning`).
- No auth token handling. Never read Keychain or `~/.codex/auth.json`.
- No background polling of the Claude CLI. Refresh on menu-open + manual only.
- All public Core types are `Sendable`.
- Verification per `AGENTS.md`: `swift test` and `swift build` must pass; `swift run devkillerctl usage` is the manual smoke test.
- Tunable constants: Claude CLI timeout `20s`; Codex stale threshold `24h`; severity thresholds green `<70`, amber `70...90`, red `>90`.

**Model note (refinement of spec):** the spec listed `UsageWindow.resetsAt: Date?`. Because Claude's `/usage` prints a human, year-less reset string that cannot be reliably parsed to a `Date`, the model carries two optional fields: `resetsAt: Date?` (machine time — Codex fills this from `resets_at` epoch) and `resetText: String?` (human text — Claude fills this verbatim). At most one is set per window.

---

### Task 1: Usage data model + pure helpers

**Files:**
- Create: `Sources/DevKillerCore/UsageModels.swift`
- Test: `Tests/DevKillerCoreTests/UsageModelsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum UsageTool: String, Sendable { case claudeCode, codex }`
  - `enum WindowKind: Sendable, Equatable { case fiveHour, weekly }`
  - `enum UsageSeverity: Sendable, Equatable { case normal, warning, critical }`
  - `struct UsageWindow: Sendable, Equatable { kind, label, usedPercent, resetsAt, resetText; var severity: UsageSeverity }`
  - `enum ToolUsageState: Sendable, Equatable { case available(windows: [UsageWindow], asOf: Date?); case notInstalled; case unavailable(reason: String) }`
  - `struct ToolUsage: Sendable, Equatable { tool: UsageTool; state: ToolUsageState }`
  - `func usageSeverity(_ percent: Double) -> UsageSeverity`
  - `func isUsageStale(asOf: Date, now: Date, threshold: TimeInterval = 24 * 3600) -> Bool`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/DevKillerCoreTests/UsageModelsTests.swift
@testable import DevKillerCore
import XCTest

final class UsageModelsTests: XCTestCase {
    func testSeverityThresholds() {
        XCTAssertEqual(usageSeverity(0), .normal)
        XCTAssertEqual(usageSeverity(69.9), .normal)
        XCTAssertEqual(usageSeverity(70), .warning)
        XCTAssertEqual(usageSeverity(90), .warning)
        XCTAssertEqual(usageSeverity(90.1), .critical)
        XCTAssertEqual(usageSeverity(100), .critical)
    }

    func testWindowSeverityMatchesHelper() {
        let window = UsageWindow(kind: .weekly, label: "Week", usedPercent: 95, resetsAt: nil, resetText: nil)
        XCTAssertEqual(window.severity, .critical)
    }

    func testStaleDetection() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(isUsageStale(asOf: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(isUsageStale(asOf: now.addingTimeInterval(-25 * 3600), now: now))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UsageModelsTests`
Expected: FAIL — `usageSeverity`, `UsageWindow`, etc. not defined (compile error).

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/DevKillerCore/UsageModels.swift
import Foundation

public enum UsageTool: String, Sendable {
    case claudeCode
    case codex
}

public enum WindowKind: Sendable, Equatable {
    case fiveHour
    case weekly
}

public enum UsageSeverity: Sendable, Equatable {
    case normal
    case warning
    case critical
}

public func usageSeverity(_ percent: Double) -> UsageSeverity {
    if percent > 90 { return .critical }
    if percent >= 70 { return .warning }
    return .normal
}

public func isUsageStale(asOf: Date, now: Date, threshold: TimeInterval = 24 * 3600) -> Bool {
    now.timeIntervalSince(asOf) > threshold
}

public struct UsageWindow: Sendable, Equatable {
    public let kind: WindowKind
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public let resetText: String?

    public init(kind: WindowKind, label: String, usedPercent: Double, resetsAt: Date?, resetText: String?) {
        self.kind = kind
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.resetText = resetText
    }

    public var severity: UsageSeverity { usageSeverity(usedPercent) }
}

public enum ToolUsageState: Sendable, Equatable {
    case available(windows: [UsageWindow], asOf: Date?)
    case notInstalled
    case unavailable(reason: String)
}

public struct ToolUsage: Sendable, Equatable {
    public let tool: UsageTool
    public let state: ToolUsageState

    public init(tool: UsageTool, state: ToolUsageState) {
        self.tool = tool
        self.state = state
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter UsageModelsTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DevKillerCore/UsageModels.swift Tests/DevKillerCoreTests/UsageModelsTests.swift
git commit -m "Add usage data model and severity/stale helpers"
```

---

### Task 2: Claude `/usage` text parser

**Files:**
- Create: `Sources/DevKillerCore/ClaudeUsageParser.swift`
- Test: `Tests/DevKillerCoreTests/ClaudeUsageParserTests.swift`

**Interfaces:**
- Consumes: `ToolUsageState`, `UsageWindow`, `WindowKind` (Task 1).
- Produces: `enum ClaudeUsageParser { static func parse(_ output: String) -> ToolUsageState }`

Parsing rules, applied line by line:
- `Current session: N% used · resets <text>` → `UsageWindow(kind: .fiveHour, label: "5h", usedPercent: N, resetsAt: nil, resetText: "<text>")`
- `Current week (all models): N% used · resets <text>` → `UsageWindow(kind: .weekly, label: "Week (all models)", …)`
- `Current week (<name>): N% used · resets <text>` → `UsageWindow(kind: .weekly, label: "Week (<name>)", …)`
- The `· resets <text>` suffix is optional; if absent, `resetText = nil`.
- If no windows are found → `.unavailable(reason: "Could not read Claude usage")`.
- `asOf` is `nil` (Claude data is real time).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/DevKillerCoreTests/ClaudeUsageParserTests.swift
@testable import DevKillerCore
import XCTest

final class ClaudeUsageParserTests: XCTestCase {
    private let sample = """
    You are currently using your subscription to power your Claude Code usage

    Current session: 5% used · resets Jul 14 at 3:49am (Asia/Seoul)
    Current week (all models): 78% used · resets Jul 14 at 1:59am (Asia/Seoul)
    Current week (Fable): 97% used · resets Jul 14 at 1:59am (Asia/Seoul)

    What's contributing to your limits usage?
    Last 24h · 217 requests · 7 sessions
    """

    func testParsesAllWindows() {
        guard case let .available(windows, asOf) = ClaudeUsageParser.parse(sample) else {
            return XCTFail("expected available")
        }
        XCTAssertNil(asOf)
        XCTAssertEqual(windows.count, 3)

        XCTAssertEqual(windows[0].kind, .fiveHour)
        XCTAssertEqual(windows[0].label, "5h")
        XCTAssertEqual(windows[0].usedPercent, 5)
        XCTAssertEqual(windows[0].resetText, "Jul 14 at 3:49am (Asia/Seoul)")
        XCTAssertNil(windows[0].resetsAt)

        XCTAssertEqual(windows[1].kind, .weekly)
        XCTAssertEqual(windows[1].label, "Week (all models)")
        XCTAssertEqual(windows[1].usedPercent, 78)

        XCTAssertEqual(windows[2].label, "Week (Fable)")
        XCTAssertEqual(windows[2].usedPercent, 97)
    }

    func testParsesWindowWithoutResetSuffix() {
        guard case let .available(windows, _) = ClaudeUsageParser.parse("Current session: 12% used") else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].usedPercent, 12)
        XCTAssertNil(windows[0].resetText)
    }

    func testGarbledOutputIsUnavailable() {
        guard case .unavailable = ClaudeUsageParser.parse("error: not logged in") else {
            return XCTFail("expected unavailable")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClaudeUsageParserTests`
Expected: FAIL — `ClaudeUsageParser` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/DevKillerCore/ClaudeUsageParser.swift
import Foundation

public enum ClaudeUsageParser {
    public static func parse(_ output: String) -> ToolUsageState {
        var windows: [UsageWindow] = []

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let window = parseLine(line) else { continue }
            windows.append(window)
        }

        if windows.isEmpty {
            return .unavailable(reason: "Could not read Claude usage")
        }
        return .available(windows: windows, asOf: nil)
    }

    private static func parseLine(_ line: String) -> UsageWindow? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let head = String(line[line.startIndex..<colon])
        let rest = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

        let kind: WindowKind
        let label: String
        if head == "Current session" {
            kind = .fiveHour
            label = "5h"
        } else if head.hasPrefix("Current week") {
            kind = .weekly
            // "Current week (all models)" -> "Week (all models)"
            label = "Week" + head.dropFirst("Current week".count)
        } else {
            return nil
        }

        // rest looks like "5% used · resets Jul 14 at 3:49am (Asia/Seoul)"
        guard let percentEnd = rest.firstIndex(of: "%") else { return nil }
        guard let percent = Double(rest[rest.startIndex..<percentEnd]) else { return nil }

        var resetText: String?
        if let resetsRange = rest.range(of: "resets ") {
            let text = String(rest[resetsRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            resetText = text.isEmpty ? nil : text
        }

        return UsageWindow(kind: kind, label: label, usedPercent: percent, resetsAt: nil, resetText: resetText)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ClaudeUsageParserTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DevKillerCore/ClaudeUsageParser.swift Tests/DevKillerCoreTests/ClaudeUsageParserTests.swift
git commit -m "Add Claude /usage text parser"
```

---

### Task 3: Codex rollout `rate_limits` parser

**Files:**
- Create: `Sources/DevKillerCore/CodexUsageParser.swift`
- Test: `Tests/DevKillerCoreTests/CodexUsageParserTests.swift`

**Interfaces:**
- Consumes: `ToolUsageState`, `UsageWindow`, `WindowKind` (Task 1).
- Produces: `enum CodexUsageParser { static func parse(_ rolloutLine: String) -> ToolUsageState }`

Input is one JSON line from a Codex `rollout-*.jsonl` file whose `payload.rate_limits` is present. Mapping:
- `payload.rate_limits.primary` and `.secondary` each → a `UsageWindow` when non-null.
- `window.window_minutes == 300` → `.fiveHour` (label `"5h"`); otherwise `.weekly` (label `"Week"`).
- `window.used_percent` → `usedPercent`.
- `window.resets_at` (epoch seconds) → `resetsAt = Date(timeIntervalSince1970:)`; `resetText = nil`.
- Top-level `timestamp` (ISO8601) → `asOf`.
- Windows are ordered 5h first, then weekly.
- If the line has no parseable `rate_limits` window → `.unavailable(reason: "No Codex rate limit data")`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/DevKillerCoreTests/CodexUsageParserTests.swift
@testable import DevKillerCore
import XCTest

final class CodexUsageParserTests: XCTestCase {
    // Real rollout shape (weekly-only, secondary null).
    private let weeklyOnly = """
    {"timestamp":"2026-07-13T14:03:08.874Z","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":258400},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":19.0,"window_minutes":10080,"resets_at":1784495024},"secondary":null,"credits":null,"individual_limit":null,"plan_type":"prolite","rate_limit_reached_type":null}}}
    """

    // Synthesized both-window shape.
    private let bothWindows = """
    {"timestamp":"2026-07-13T14:03:08.874Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":42.0,"window_minutes":10080,"resets_at":1784495024},"secondary":{"used_percent":8.5,"window_minutes":300,"resets_at":1784400000}}}}
    """

    func testParsesWeeklyOnly() {
        guard case let .available(windows, asOf) = CodexUsageParser.parse(weeklyOnly) else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].kind, .weekly)
        XCTAssertEqual(windows[0].label, "Week")
        XCTAssertEqual(windows[0].usedPercent, 19.0)
        XCTAssertEqual(windows[0].resetsAt, Date(timeIntervalSince1970: 1784495024))
        XCTAssertNil(windows[0].resetText)
        XCTAssertEqual(asOf, ISO8601DateFormatter().date(from: "2026-07-13T14:03:08.874Z"))
    }

    func testParsesBothWindowsFiveHourFirst() {
        guard case let .available(windows, _) = CodexUsageParser.parse(bothWindows) else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].kind, .fiveHour)
        XCTAssertEqual(windows[0].usedPercent, 8.5)
        XCTAssertEqual(windows[1].kind, .weekly)
        XCTAssertEqual(windows[1].usedPercent, 42.0)
    }

    func testMissingRateLimitsIsUnavailable() {
        let line = "{\"timestamp\":\"2026-07-13T14:03:08.874Z\",\"payload\":{\"type\":\"token_count\"}}"
        guard case .unavailable = CodexUsageParser.parse(line) else {
            return XCTFail("expected unavailable")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CodexUsageParserTests`
Expected: FAIL — `CodexUsageParser` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/DevKillerCore/CodexUsageParser.swift
import Foundation

public enum CodexUsageParser {
    private struct RolloutLine: Decodable {
        let timestamp: String?
        let payload: Payload?
    }

    private struct Payload: Decodable {
        let rate_limits: RateLimits?
    }

    private struct RateLimits: Decodable {
        let primary: Window?
        let secondary: Window?
    }

    private struct Window: Decodable {
        let used_percent: Double?
        let window_minutes: Int?
        let resets_at: Double?
    }

    public static func parse(_ rolloutLine: String) -> ToolUsageState {
        guard let data = rolloutLine.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RolloutLine.self, from: data),
              let limits = decoded.payload?.rate_limits else {
            return .unavailable(reason: "No Codex rate limit data")
        }

        let parsed = [limits.primary, limits.secondary]
            .compactMap { $0 }
            .compactMap(window(from:))
            .sorted { lhs, rhs in kindRank(lhs.kind) < kindRank(rhs.kind) }

        if parsed.isEmpty {
            return .unavailable(reason: "No Codex rate limit data")
        }

        let asOf = decoded.timestamp.flatMap { ISO8601DateFormatter().date(from: $0) }
        return .available(windows: parsed, asOf: asOf)
    }

    private static func window(from window: Window) -> UsageWindow? {
        guard let percent = window.used_percent else { return nil }
        let isFiveHour = window.window_minutes == 300
        let kind: WindowKind = isFiveHour ? .fiveHour : .weekly
        let label = isFiveHour ? "5h" : "Week"
        let resetsAt = window.resets_at.map { Date(timeIntervalSince1970: $0) }
        return UsageWindow(kind: kind, label: label, usedPercent: percent, resetsAt: resetsAt, resetText: nil)
    }

    private static func kindRank(_ kind: WindowKind) -> Int {
        kind == .fiveHour ? 0 : 1
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CodexUsageParserTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DevKillerCore/CodexUsageParser.swift Tests/DevKillerCoreTests/CodexUsageParserTests.swift
git commit -m "Add Codex rollout rate_limits parser"
```

---

### Task 4: Claude binary locator

**Files:**
- Create: `Sources/DevKillerCore/ClaudeBinaryLocator.swift`
- Test: `Tests/DevKillerCoreTests/ClaudeBinaryLocatorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `protocol ClaudeBinaryLocating: Sendable { func locate() -> String? }`
  - `enum ClaudeBinaryDiscovery { static func locate(candidates: [String], fileExists: (String) -> Bool, shellLookup: () -> String?) -> String? }`
  - `static var defaultCandidates: [String]` on `ClaudeBinaryDiscovery` (expanded absolute paths).

Logic: return the first candidate for which `fileExists` is true; if none match, return the trimmed result of `shellLookup` when it is a non-empty existing path; otherwise `nil`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/DevKillerCoreTests/ClaudeBinaryLocatorTests.swift
@testable import DevKillerCore
import XCTest

final class ClaudeBinaryLocatorTests: XCTestCase {
    func testReturnsFirstExistingCandidate() {
        let found = ClaudeBinaryDiscovery.locate(
            candidates: ["/a/claude", "/b/claude"],
            fileExists: { $0 == "/b/claude" },
            shellLookup: { XCTFail("should not reach shell"); return nil }
        )
        XCTAssertEqual(found, "/b/claude")
    }

    func testFallsBackToShellLookup() {
        let found = ClaudeBinaryDiscovery.locate(
            candidates: ["/a/claude"],
            fileExists: { $0 == "/shell/claude" },
            shellLookup: { "/shell/claude\n" }
        )
        XCTAssertEqual(found, "/shell/claude")
    }

    func testReturnsNilWhenNothingFound() {
        let found = ClaudeBinaryDiscovery.locate(
            candidates: ["/a/claude"],
            fileExists: { _ in false },
            shellLookup: { nil }
        )
        XCTAssertNil(found)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClaudeBinaryLocatorTests`
Expected: FAIL — `ClaudeBinaryDiscovery` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/DevKillerCore/ClaudeBinaryLocator.swift
import Foundation

public protocol ClaudeBinaryLocating: Sendable {
    func locate() -> String?
}

public enum ClaudeBinaryDiscovery {
    public static func locate(
        candidates: [String],
        fileExists: (String) -> Bool,
        shellLookup: () -> String?
    ) -> String? {
        for candidate in candidates where fileExists(candidate) {
            return candidate
        }
        if let resolved = shellLookup()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !resolved.isEmpty,
           fileExists(resolved) {
            return resolved
        }
        return nil
    }

    public static var defaultCandidates: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ]
        // nvm-installed node bin dirs
        let nvmVersions = "\(home)/.nvm/versions/node"
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: nvmVersions) {
            paths.append(contentsOf: entries.map { "\(nvmVersions)/\($0)/bin/claude" })
        }
        return paths
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ClaudeBinaryLocatorTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DevKillerCore/ClaudeBinaryLocator.swift Tests/DevKillerCoreTests/ClaudeBinaryLocatorTests.swift
git commit -m "Add Claude binary locator"
```

---

### Task 5: Claude usage provider

**Files:**
- Create: `Sources/DevKillerCore/ClaudeUsageProvider.swift`
- Test: `Tests/DevKillerCoreTests/ClaudeUsageProviderTests.swift`

**Interfaces:**
- Consumes: `ClaudeBinaryLocating` (Task 4), `ClaudeUsageParser` (Task 2), `ToolUsage`/`ToolUsageState` (Task 1).
- Produces:
  - `protocol CommandRunning: Sendable { func run(executable: String, arguments: [String], timeout: Duration) throws -> String }`
  - `struct ClaudeUsageProvider { init(locator:runner:timeout:); func fetch() -> ToolUsage }`

Behavior: if `locator.locate()` is nil → `ToolUsage(tool: .claudeCode, state: .notInstalled)`. Else run `["-p", "/usage", "--output-format", "text"]`; on success parse stdout; on any thrown error → `.unavailable(reason: "Claude usage unavailable")`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/DevKillerCoreTests/ClaudeUsageProviderTests.swift
@testable import DevKillerCore
import XCTest

private struct StubLocator: ClaudeBinaryLocating {
    let path: String?
    func locate() -> String? { path }
}

private struct StubRunner: CommandRunning {
    let result: Result<String, Error>
    func run(executable: String, arguments: [String], timeout: Duration) throws -> String {
        try result.get()
    }
}

private struct RunnerError: Error {}

final class ClaudeUsageProviderTests: XCTestCase {
    func testNotInstalledWhenBinaryMissing() {
        let provider = ClaudeUsageProvider(
            locator: StubLocator(path: nil),
            runner: StubRunner(result: .success("")),
            timeout: .seconds(20)
        )
        XCTAssertEqual(provider.fetch(), ToolUsage(tool: .claudeCode, state: .notInstalled))
    }

    func testParsesRunnerOutput() {
        let provider = ClaudeUsageProvider(
            locator: StubLocator(path: "/bin/claude"),
            runner: StubRunner(result: .success("Current session: 5% used")),
            timeout: .seconds(20)
        )
        guard case let .available(windows, _) = provider.fetch().state else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(windows.first?.usedPercent, 5)
    }

    func testUnavailableWhenRunnerThrows() {
        let provider = ClaudeUsageProvider(
            locator: StubLocator(path: "/bin/claude"),
            runner: StubRunner(result: .failure(RunnerError())),
            timeout: .seconds(20)
        )
        guard case .unavailable = provider.fetch().state else {
            return XCTFail("expected unavailable")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClaudeUsageProviderTests`
Expected: FAIL — `CommandRunning` / `ClaudeUsageProvider` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/DevKillerCore/ClaudeUsageProvider.swift
import Foundation

public protocol CommandRunning: Sendable {
    func run(executable: String, arguments: [String], timeout: Duration) throws -> String
}

public struct ClaudeUsageProvider {
    private let locator: ClaudeBinaryLocating
    private let runner: CommandRunning
    private let timeout: Duration

    public init(locator: ClaudeBinaryLocating, runner: CommandRunning, timeout: Duration) {
        self.locator = locator
        self.runner = runner
        self.timeout = timeout
    }

    public func fetch() -> ToolUsage {
        guard let executable = locator.locate() else {
            return ToolUsage(tool: .claudeCode, state: .notInstalled)
        }
        do {
            let output = try runner.run(
                executable: executable,
                arguments: ["-p", "/usage", "--output-format", "text"],
                timeout: timeout
            )
            return ToolUsage(tool: .claudeCode, state: ClaudeUsageParser.parse(output))
        } catch {
            return ToolUsage(tool: .claudeCode, state: .unavailable(reason: "Claude usage unavailable"))
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ClaudeUsageProviderTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DevKillerCore/ClaudeUsageProvider.swift Tests/DevKillerCoreTests/ClaudeUsageProviderTests.swift
git commit -m "Add Claude usage provider"
```

---

### Task 6: Codex usage provider

**Files:**
- Create: `Sources/DevKillerCore/CodexUsageProvider.swift`
- Test: `Tests/DevKillerCoreTests/CodexUsageProviderTests.swift`

**Interfaces:**
- Consumes: `CodexUsageParser` (Task 3), `ToolUsage`/`ToolUsageState` (Task 1).
- Produces:
  - `enum CodexRolloutLookup: Sendable, Equatable { case notInstalled; case noData; case line(String) }`
  - `protocol CodexRolloutLocating: Sendable { func latestRateLimitLine() -> CodexRolloutLookup }`
  - `struct CodexUsageProvider { init(locator:); func fetch() -> ToolUsage }`

Behavior: map `.notInstalled` → `ToolUsage(.codex, .notInstalled)`; `.noData` → `.unavailable(reason: "No recent Codex usage")`; `.line(l)` → `CodexUsageParser.parse(l)`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/DevKillerCoreTests/CodexUsageProviderTests.swift
@testable import DevKillerCore
import XCTest

private struct StubCodexLocator: CodexRolloutLocating {
    let lookup: CodexRolloutLookup
    func latestRateLimitLine() -> CodexRolloutLookup { lookup }
}

final class CodexUsageProviderTests: XCTestCase {
    func testNotInstalled() {
        let provider = CodexUsageProvider(locator: StubCodexLocator(lookup: .notInstalled))
        XCTAssertEqual(provider.fetch(), ToolUsage(tool: .codex, state: .notInstalled))
    }

    func testNoData() {
        let provider = CodexUsageProvider(locator: StubCodexLocator(lookup: .noData))
        guard case .unavailable = provider.fetch().state else {
            return XCTFail("expected unavailable")
        }
    }

    func testParsesLine() {
        let line = "{\"timestamp\":\"2026-07-13T14:03:08.874Z\",\"payload\":{\"rate_limits\":{\"primary\":{\"used_percent\":19.0,\"window_minutes\":10080,\"resets_at\":1784495024},\"secondary\":null}}}"
        let provider = CodexUsageProvider(locator: StubCodexLocator(lookup: .line(line)))
        guard case let .available(windows, _) = provider.fetch().state else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(windows.first?.usedPercent, 19.0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CodexUsageProviderTests`
Expected: FAIL — `CodexRolloutLocating` / `CodexUsageProvider` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/DevKillerCore/CodexUsageProvider.swift
import Foundation

public enum CodexRolloutLookup: Sendable, Equatable {
    case notInstalled
    case noData
    case line(String)
}

public protocol CodexRolloutLocating: Sendable {
    func latestRateLimitLine() -> CodexRolloutLookup
}

public struct CodexUsageProvider {
    private let locator: CodexRolloutLocating

    public init(locator: CodexRolloutLocating) {
        self.locator = locator
    }

    public func fetch() -> ToolUsage {
        switch locator.latestRateLimitLine() {
        case .notInstalled:
            return ToolUsage(tool: .codex, state: .notInstalled)
        case .noData:
            return ToolUsage(tool: .codex, state: .unavailable(reason: "No recent Codex usage"))
        case let .line(line):
            return ToolUsage(tool: .codex, state: CodexUsageParser.parse(line))
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CodexUsageProviderTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DevKillerCore/CodexUsageProvider.swift Tests/DevKillerCoreTests/CodexUsageProviderTests.swift
git commit -m "Add Codex usage provider"
```

---

### Task 7: Real adapters + UsageService aggregator

**Files:**
- Create: `Sources/DevKillerCore/UsageService.swift`
- Test: `Tests/DevKillerCoreTests/UsageServiceTests.swift`

**Interfaces:**
- Consumes: `ClaudeUsageProvider` (Task 5), `CodexUsageProvider` (Task 6), `ClaudeBinaryLocating`/`ClaudeBinaryDiscovery` (Task 4), `CommandRunning` (Task 5), `CodexRolloutLocating`/`CodexRolloutLookup` (Task 6).
- Produces:
  - `protocol UsageProviding: Sendable { func fetchAll() -> [ToolUsage] }`
  - `struct SystemClaudeLocator: ClaudeBinaryLocating`
  - `struct SystemCommandRunner: CommandRunning` (spawns `Process`, enforces timeout)
  - `struct SystemCodexRolloutLocator: CodexRolloutLocating` (reads `~/.codex/sessions`)
  - `struct UsageService: UsageProviding` with a default `init()` wiring the system adapters and a testable `init(claudeProvider:codexProvider:)`.

`fetchAll()` returns `[claudeProvider.fetch(), codexProvider.fetch()]` (both entries; the UI hides `.notInstalled`).

The real adapters are thin I/O wrappers excluded from unit tests; they are exercised by the Task 8 smoke test. Only the aggregator is unit-tested here, via injected fake providers. Note: `UsageService` cannot inject `ClaudeUsageProvider`/`CodexUsageProvider` structs directly through `UsageProviding`, so the aggregator holds two closures `() -> ToolUsage`; the fake test supplies closures, the default init supplies `claudeProvider.fetch`/`codexProvider.fetch`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/DevKillerCoreTests/UsageServiceTests.swift
@testable import DevKillerCore
import XCTest

final class UsageServiceTests: XCTestCase {
    func testFetchAllReturnsBothTools() {
        let service = UsageService(
            claude: { ToolUsage(tool: .claudeCode, state: .notInstalled) },
            codex: { ToolUsage(tool: .codex, state: .available(windows: [], asOf: nil)) }
        )
        let all = service.fetchAll()
        XCTAssertEqual(all.map(\.tool), [.claudeCode, .codex])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UsageServiceTests`
Expected: FAIL — `UsageService` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/DevKillerCore/UsageService.swift
import Foundation

public protocol UsageProviding: Sendable {
    func fetchAll() -> [ToolUsage]
}

public struct UsageService: UsageProviding {
    private let claude: @Sendable () -> ToolUsage
    private let codex: @Sendable () -> ToolUsage

    public init(
        claude: @escaping @Sendable () -> ToolUsage,
        codex: @escaping @Sendable () -> ToolUsage
    ) {
        self.claude = claude
        self.codex = codex
    }

    public init(timeout: Duration = .seconds(20)) {
        let claudeProvider = ClaudeUsageProvider(
            locator: SystemClaudeLocator(),
            runner: SystemCommandRunner(),
            timeout: timeout
        )
        let codexProvider = CodexUsageProvider(locator: SystemCodexRolloutLocator())
        self.claude = { claudeProvider.fetch() }
        self.codex = { codexProvider.fetch() }
    }

    public func fetchAll() -> [ToolUsage] {
        [claude(), codex()]
    }
}

public struct SystemClaudeLocator: ClaudeBinaryLocating {
    public init() {}

    public func locate() -> String? {
        ClaudeBinaryDiscovery.locate(
            candidates: ClaudeBinaryDiscovery.defaultCandidates,
            fileExists: { FileManager.default.isExecutableFile(atPath: $0) },
            shellLookup: Self.shellLookup
        )
    }

    private static func shellLookup() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}

public struct SystemCommandRunner: CommandRunning {
    public init() {}

    public func run(executable: String, arguments: [String], timeout: Duration) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()

        let deadline = Date().addingTimeInterval(Double(timeout.components.seconds))
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            throw UsageRunnerError.timedOut
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public enum UsageRunnerError: Error {
    case timedOut
}

public struct SystemCodexRolloutLocator: CodexRolloutLocating {
    public init() {}

    public func latestRateLimitLine() -> CodexRolloutLookup {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sessions = home.appendingPathComponent(".codex/sessions")
        guard FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex").path) else {
            return .notInstalled
        }
        guard let newest = newestRollout(in: sessions),
              let line = lastRateLimitLine(in: newest) else {
            return .noData
        }
        return .line(line)
    }

    private func newestRollout(in root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }

        var newest: URL?
        var newestDate = Date.distantPast
        for case let url as URL in enumerator where url.lastPathComponent.hasPrefix("rollout-") {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if date > newestDate {
                newestDate = date
                newest = url
            }
        }
        return newest
    }

    private func lastRateLimitLine(in file: URL) -> String? {
        guard let contents = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return contents
            .split(whereSeparator: \.isNewline)
            .last { $0.contains("\"rate_limits\"") }
            .map(String.init)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter UsageServiceTests`
Expected: PASS (1 test).

- [ ] **Step 5: Run the full Core suite and build**

Run: `swift test && swift build`
Expected: all tests PASS, build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Sources/DevKillerCore/UsageService.swift Tests/DevKillerCoreTests/UsageServiceTests.swift
git commit -m "Add usage system adapters and aggregator service"
```

---

### Task 8: `devkillerctl usage` smoke command

**Files:**
- Modify: `Sources/devkillerctl/main.swift` (add `case "usage"` in the `switch`, add a `printUsage` helper, extend the usage/help text)

**Interfaces:**
- Consumes: `UsageService` (Task 7), `ToolUsage`/`ToolUsageState` (Task 1).
- Produces: CLI behavior only.

This task has no unit test; it is the manual smoke test for the real adapters.

- [ ] **Step 1: Add the `usage` case**

In `Sources/devkillerctl/main.swift`, inside the `switch command {` block, add before `default:`:

```swift
            case "usage":
                printUsage(UsageService().fetchAll())
```

- [ ] **Step 2: Add the `printUsage` helper**

Add this method inside `enum CLI` (e.g. after `printResults`):

```swift
    private static func printUsage(_ usage: [ToolUsage]) {
        for tool in usage {
            let name = tool.tool == .claudeCode ? "claude-code" : "codex"
            switch tool.state {
            case .notInstalled:
                print("\(name): not installed")
            case let .unavailable(reason):
                print("\(name): unavailable (\(reason))")
            case let .available(windows, asOf):
                let asOfText = asOf.map { " asOf=\($0)" } ?? ""
                print("\(name):\(asOfText)")
                for window in windows {
                    let reset = window.resetsAt.map { " resetsAt=\($0)" }
                        ?? window.resetText.map { " resets=\"\($0)\"" }
                        ?? ""
                    print("  \(window.label): \(window.usedPercent)%\(reset)")
                }
            }
        }
    }
```

- [ ] **Step 3: Extend the help text**

In the `default:` case's `fail("""..."""`), add this line to the usage block:

```
  devkillerctl usage
```

- [ ] **Step 4: Build and smoke test**

Run: `swift build && swift run devkillerctl usage`
Expected: prints `claude-code:` with `5h`/`Week ...` percentages (live) and `codex:` with a `Week`/`5h` line (or `not installed` / `unavailable` if a tool is absent). No crash.

- [ ] **Step 5: Commit**

```bash
git add Sources/devkillerctl/main.swift
git commit -m "Add devkillerctl usage smoke command"
```

---

### Task 9: DevKillerStore usage integration

**Files:**
- Modify: `Sources/DevKillerBar/DevKillerBarApp.swift` (extend `DevKillerStore`)
- Test: `Tests/DevKillerBarTests/DevKillerStoreUsageTests.swift`

**Interfaces:**
- Consumes: `UsageProviding`/`UsageService` (Task 7), `ToolUsage` (Task 1).
- Produces: on `DevKillerStore`:
  - `@Published var usage: [ToolUsage]`
  - `@Published var isUsageLoading: Bool`
  - `func refreshUsage() async`
  - a new injectable `usageProvider: UsageProviding` init parameter (default `UsageService()`).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/DevKillerBarTests/DevKillerStoreUsageTests.swift
@testable import DevKillerBar
import DevKillerCore
import XCTest

private struct StubUsageProvider: UsageProviding {
    let usage: [ToolUsage]
    func fetchAll() -> [ToolUsage] { usage }
}

@MainActor
final class DevKillerStoreUsageTests: XCTestCase {
    func testRefreshUsagePopulatesUsage() async {
        let store = DevKillerStore(
            usesSampleServers: true,
            usageProvider: StubUsageProvider(usage: [
                ToolUsage(tool: .claudeCode, state: .available(windows: [], asOf: nil))
            ])
        )
        await store.refreshUsage()
        XCTAssertEqual(store.usage.map(\.tool), [.claudeCode])
        XCTAssertFalse(store.isUsageLoading)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DevKillerStoreUsageTests`
Expected: FAIL — `usageProvider:` init param and `refreshUsage` not defined.

- [ ] **Step 3: Extend `DevKillerStore`**

Add published properties near the existing `@Published` declarations:

```swift
    @Published var usage: [ToolUsage] = []
    @Published var isUsageLoading = false
```

Add a stored property near `serverProvider`:

```swift
    private let usageProvider: UsageProviding
```

Add `usageProvider` to the initializer signature and body. Change the `init` signature to include:

```swift
        usageProvider: UsageProviding = UsageService(),
```

(place it alongside the other parameters, e.g. after `serverProvider`), and assign inside `init`:

```swift
        self.usageProvider = usageProvider
```

Add the refresh method (e.g. after `refresh()`):

```swift
    func refreshUsage() async {
        guard !isUsageLoading else { return }
        isUsageLoading = true
        defer { isUsageLoading = false }

        let usageProvider = self.usageProvider
        let result = await Task.detached {
            usageProvider.fetchAll()
        }.value
        self.usage = result
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter DevKillerStoreUsageTests`
Expected: PASS (1 test).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: all tests PASS (existing store tests still green).

- [ ] **Step 6: Commit**

```bash
git add Sources/DevKillerBar/DevKillerBarApp.swift Tests/DevKillerBarTests/DevKillerStoreUsageTests.swift
git commit -m "Wire usage provider into DevKillerStore"
```

---

### Task 10: Usage section UI

**Files:**
- Modify: `Sources/DevKillerBar/DevKillerBarApp.swift` (add `UsageSectionView`, `UsageToolBlock`, `UsageBarRow`; render in `DevKillerMenuView`; refresh on appear + manual button)
- Test: `Tests/DevKillerBarTests/UsageSectionViewTests.swift`

**Interfaces:**
- Consumes: `DevKillerStore.usage`/`isUsageLoading`/`refreshUsage()` (Task 9), `UsageWindow`/`UsageSeverity`/`isUsageStale`/`usageSeverity` (Task 1).
- Produces: view types + a pure `usageBarColor(for:) -> Color` helper and `usageResetDisplay(window:) -> String?` helper (both testable).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/DevKillerBarTests/UsageSectionViewTests.swift
@testable import DevKillerBar
import DevKillerCore
import SwiftUI
import XCTest

final class UsageSectionViewTests: XCTestCase {
    func testBarColorBySeverity() {
        XCTAssertEqual(usageBarColor(for: .normal), Color.green)
        XCTAssertEqual(usageBarColor(for: .warning), Color.orange)
        XCTAssertEqual(usageBarColor(for: .critical), Color.red)
    }

    func testResetDisplayPrefersTextThenDate() {
        let textWindow = UsageWindow(kind: .fiveHour, label: "5h", usedPercent: 5, resetsAt: nil, resetText: "Jul 14 at 3:49am")
        XCTAssertEqual(usageResetDisplay(window: textWindow), "resets Jul 14 at 3:49am")

        let dateWindow = UsageWindow(kind: .weekly, label: "Week", usedPercent: 19, resetsAt: Date(timeIntervalSince1970: 1784495024), resetText: nil)
        XCTAssertTrue(usageResetDisplay(window: dateWindow)?.hasPrefix("resets ") == true)

        let noneWindow = UsageWindow(kind: .weekly, label: "Week", usedPercent: 19, resetsAt: nil, resetText: nil)
        XCTAssertNil(usageResetDisplay(window: noneWindow))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter UsageSectionViewTests`
Expected: FAIL — `usageBarColor` / `usageResetDisplay` not defined.

- [ ] **Step 3: Add view helpers and views**

Add to `Sources/DevKillerBar/DevKillerBarApp.swift`:

```swift
func usageBarColor(for severity: UsageSeverity) -> Color {
    switch severity {
    case .normal: return .green
    case .warning: return .orange
    case .critical: return .red
    }
}

func usageResetDisplay(window: UsageWindow) -> String? {
    if let text = window.resetText {
        return "resets \(text)"
    }
    if let date = window.resetsAt {
        return "resets \(date.formatted(date: .abbreviated, time: .shortened))"
    }
    return nil
}

struct UsageSectionView: View {
    let usage: [ToolUsage]
    let isLoading: Bool
    let refresh: () -> Void

    private var visibleTools: [ToolUsage] {
        usage.filter { tool in
            if case .notInstalled = tool.state { return false }
            return true
        }
    }

    var body: some View {
        if !visibleTools.isEmpty || isLoading {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Usage")
                        .font(.caption).bold()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }

                ForEach(visibleTools, id: \.tool.rawValue) { tool in
                    UsageToolBlock(tool: tool)
                }
            }
            Divider()
        }
    }
}

struct UsageToolBlock: View {
    let tool: ToolUsage

    private var title: String {
        tool.tool == .claudeCode ? "Claude Code" : "Codex"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).bold()

            switch tool.state {
            case let .available(windows, asOf):
                ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                    UsageBarRow(window: window)
                }
                if let asOf, isUsageStale(asOf: asOf, now: Date()) {
                    Text("stale · as of \(asOf.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.tertiary)
                } else if let asOf {
                    Text("as of \(asOf.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            case let .unavailable(reason):
                Text(reason).font(.caption2).foregroundStyle(.secondary)
            case .notInstalled:
                EmptyView()
            }
        }
    }
}

struct UsageBarRow: View {
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(window.label)
                    .font(.caption2)
                    .frame(width: 120, alignment: .leading)
                ProgressView(value: min(window.usedPercent, 100), total: 100)
                    .tint(usageBarColor(for: window.severity))
                Text("\(Int(window.usedPercent))%")
                    .font(.caption2.monospacedDigit())
                    .frame(width: 34, alignment: .trailing)
            }
            if let reset = usageResetDisplay(window: window) {
                Text(reset).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
```

- [ ] **Step 4: Render the section in `DevKillerMenuView`**

In `DevKillerMenuView.body`, insert at the top of the outer `VStack` (before the existing "clock" `HStack`):

```swift
            UsageSectionView(
                usage: store.usage,
                isLoading: store.isUsageLoading,
                refresh: { Task { await store.refreshUsage() } }
            )
```

And in the existing `.onAppear` closure (currently `store.startAutoRefresh()`), add:

```swift
            Task { await store.refreshUsage() }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter UsageSectionViewTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Full verification**

Run: `swift test && swift build && swift run devkillerctl usage`
Expected: all tests PASS; build succeeds; `devkillerctl usage` prints live Claude + Codex usage.

- [ ] **Step 7: Manual app check**

Run: `swift run devkillerbar` (or launch the built app), open the menu.
Expected: a "Usage" section shows Claude Code 5h/Week bars and Codex Week bar with percentages and a Refresh button; no crash; server list still works below it.

- [ ] **Step 8: Commit**

```bash
git add Sources/DevKillerBar/DevKillerBarApp.swift Tests/DevKillerBarTests/UsageSectionViewTests.swift
git commit -m "Add usage section to menu bar UI"
```

---

## Self-Review

**Spec coverage:**
- Official 5h + weekly for both tools → Tasks 2, 3 (parsers), 5, 6 (providers). ✓
- Claude via `claude -p "/usage"` → Task 5 provider + Task 7 `SystemCommandRunner`. ✓
- Codex via newest rollout `rate_limits` → Task 3 parser + Task 7 `SystemCodexRolloutLocator`. ✓
- Data model (windows/state) → Task 1. ✓
- Injected boundaries (`CommandRunning`, `CodexRolloutLocating`, binary discovery) → Tasks 4, 5, 6, 7. ✓
- Refresh on menu-open + manual, no polling → Task 9 (`refreshUsage`), Task 10 (`.onAppear` + Refresh button). ✓
- UI bars + % + reset, color thresholds, stale label, hide not-installed, hide empty section → Task 10. ✓
- GUI PATH problem → Task 4 candidates + Task 7 shell lookup. ✓
- Timeout (20s) → Task 7 `SystemCommandRunner` + Task 5 provider error path. ✓
- Format fragility degrades to `unavailable` → Tasks 2, 3 (empty/garbled), Task 5 (throw). ✓
- Codex staleness (24h) → Task 1 `isUsageStale` + Task 10 stale label. ✓
- Smoke test `devkillerctl usage` → Task 8. ✓
- Testing strategy (pure parsers, injected fakes, UI helper tests) → Tasks 1–10. ✓

**Placeholder scan:** No TBD/TODO; every code step contains complete code. ✓

**Type consistency:** `ToolUsage`, `ToolUsageState`, `UsageWindow`, `WindowKind`, `UsageSeverity`, `CommandRunning.run(executable:arguments:timeout:)`, `ClaudeBinaryLocating.locate()`, `CodexRolloutLocating.latestRateLimitLine()`, `CodexRolloutLookup`, `UsageProviding.fetchAll()`, `UsageService(claude:codex:)` / `UsageService(timeout:)`, `DevKillerStore.refreshUsage()` are used consistently across tasks. ✓
