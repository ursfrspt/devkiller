# DevKiller — CLI Usage in Menu Bar (Design)

Date: 2026-07-13
Status: Approved (brainstorming)

## Goal

Add a section to the DevKiller menu bar that shows the **official** usage limits
of the locally installed Claude Code and Codex CLIs: the 5-hour rolling window
and the weekly window, as percent-used with reset times.

This is the "official rate-limit consumption" the provider reports — not a
locally computed token estimate.

## Feasibility (verified 2026-07-13)

Both tools expose the official numbers without replaying auth tokens or parsing
undocumented HTTP headers:

| | Claude Code | Codex |
|---|---|---|
| Source | `claude -p "/usage" --output-format text` (live query) | newest `~/.codex/sessions/**/rollout-*.jsonl`, last `rate_limits` entry (local snapshot) |
| 5-hour window | `Current session: N% used · resets <date>` | `rate_limits` entry with `window_minutes == 300` |
| Weekly window | `Current week (all models): N% used · resets <date>` (+ per-model `Current week (<model>)`) | `rate_limits` entry with `window_minutes == 10080` |
| Freshness | real time (few seconds, spawns a session) | snapshot from last Codex use; carries its own timestamp |

Sample captured on this machine:
- Claude: `Current session: 5% used`, `Current week (all models): 78% used`, `Current week (Fable): 97% used`
- Codex: `"rate_limits":{"primary":{"used_percent":19.0,"window_minutes":10080,"resets_at":1784495024},"secondary":null,"plan_type":"prolite"}`

Note: `primary`/`secondary` are **not** fixed to 5h/weekly — map by
`window_minutes` (300 → 5h, 10080 → weekly). Some plans have only a weekly
window (`secondary: null`).

## Non-Goals

- No token/cost aggregation from transcripts (ccusage-style). Official % only.
- No background polling of the Claude CLI. Refresh on menu-open + manual only.
- No auth token handling; DevKiller never reads Keychain/`auth.json`.

## Architecture

Follows the existing convention (logic in `DevKillerCore`, thin UI in
`DevKillerBar`, injected providers mirroring the existing `serverProvider`).

### DevKillerCore (new, pure + testable)

Data model:

```swift
enum UsageTool { case claudeCode, codex }
enum WindowKind { case fiveHour, weekly }

struct UsageWindow {
    let kind: WindowKind
    let label: String        // "5h", "Week (all models)", "Week (Fable)"
    let usedPercent: Double   // 0...100
    let resetsAt: Date?
}

enum ToolUsageState {
    case available(windows: [UsageWindow], asOf: Date?)  // asOf == nil → real time (Claude)
    case notInstalled
    case unavailable(reason: String)                      // parse failure / timeout / no data
}

struct ToolUsage { let tool: UsageTool; let state: ToolUsageState }
```

Providers:

- `ClaudeUsageProvider` — locates the `claude` binary, runs it via an injected
  `CommandRunner`, hands stdout to `ClaudeUsageTextParser`.
- `CodexUsageProvider` — via an injected `RolloutFileLocating`, finds the newest
  rollout file, reads the last `rate_limits` line, hands it to
  `CodexRateLimitParser`.
- `ClaudeUsageTextParser`, `CodexRateLimitParser` — pure functions
  (`String -> ToolUsageState`), the primary unit-test surface.

Injected boundaries (thin real adapters excluded from tests):

- `CommandRunner` — `run(binary, args, timeout) -> stdout` (or throws).
- `RolloutFileLocating` — newest rollout path + tail read.
- `FileSystem`/candidate list — for binary discovery.

### DevKillerBar

- `DevKillerStore` gains `@Published var usage: [ToolUsage]`, `isUsageLoading`,
  and `refreshUsage()`.
- `refreshUsage()` runs both providers in `Task.detached` (off main thread),
  invoked on menu appear and from a manual Refresh button. No periodic polling.
- `UsageSectionView` renders the section (bars + % + reset time), above the
  server list.

## Data Flow

1. Menu opens (or Refresh tapped) → `store.refreshUsage()`.
2. `Task.detached` runs both providers concurrently.
   - Claude: discover binary → `-p "/usage" --output-format text` with timeout →
     parse text → `[UsageWindow]`, `asOf = nil`.
   - Codex: newest `rollout-*.jsonl` → last `rate_limits` line → parse JSON →
     map by `window_minutes`, `resets_at` epoch → `Date`, `asOf` = event time.
3. Results published to `usage` → UI re-renders.

## UI

Section above the server list; one block per detected tool:

```
Usage                      ↻ Refresh

Claude Code
  5h    ▓▓░░░░░░░░   5%
  Week  ▓▓▓▓▓▓▓▓░░  78%   resets 1:59am

Codex
  Week  ▓▓░░░░░░░░  19%   (as of 3:04pm)
```

- Bar color by threshold: green `< 70`, amber `70–90`, red `> 90`.
- Reset time shown as short/relative time.
- Codex snapshots labeled `(as of <time>)`; if older than 24h, dimmed + `stale`.

## Error & Edge Handling

1. **GUI PATH problem (key risk).** A Finder-launched menu bar app gets a
   reduced PATH and won't find `~/.local/bin/claude` or nvm's `codex`. Binary
   discovery: probe known locations (`~/.local/bin`, `/opt/homebrew/bin`,
   `/usr/local/bin`, `~/.nvm/versions/node/*/bin`) plus one
   `$SHELL -lc 'command -v claude'` lookup, then cache. Not found →
   `notInstalled`.
2. **Claude CLI latency/hang.** Timeout (20s) + cancellation. On timeout →
   `unavailable("timed out")`. Spinner while loading.
3. **Format fragility.** Text/JSON schema drift → never crash; degrade to
   `unavailable(reason)`; app stays functional.
4. **Codex staleness.** Show `asOf`; if `> 24h` old, dim + `stale` label.
5. **Not installed / no data.** Hide that tool's block. If neither tool is
   present, hide the whole Usage section.
6. **Cost.** `claude -p "/usage"` may count as a request; call only on
   menu-open + manual to minimize.

Tunable constants: Claude timeout `20s`, stale threshold `24h`.

## Testing

Per `AGENTS.md` (`swift test`, `swift build`, `swift run devkillerctl`).

Unit tests (`DevKillerCoreTests`):
- `ClaudeUsageTextParser`: fixture of real `/usage` output → correct %/reset for
  `Current session`, `Current week (all models)`, `Current week (<model>)`;
  missing-reset variant; empty/garbled → `unavailable`.
- `CodexRateLimitParser`: real `rate_limits` JSON line → `window_minutes` 300→5h
  / 10080→weekly mapping, `secondary: null`, `resets_at` epoch→Date, missing
  fields → degrade.
- Binary discovery: injected filesystem/candidates → found / not-found branches.

Injection boundaries: `CommandRunner` (fixed stdout for Claude), 
`RolloutFileLocating` (fixed path/content for Codex).

Smoke test: add `devkillerctl usage` subcommand → `swift run devkillerctl usage`
prints resolved usage from the real environment.

UI tests (`DevKillerBarTests`): color-threshold logic and stale-label condition
extracted as pure functions and asserted.
