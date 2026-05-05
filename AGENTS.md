# AGENTS.md

## Project

`devkiller` is a macOS-only utility that helps developers find and terminate local development servers listening on common ports.

## Architecture

- Keep process discovery and termination logic in `DevKillerCore`.
- Keep UI code thin. The future SwiftUI menu bar app should depend on `DevKillerCore`.
- Prefer structured command output such as `lsof -F` over parsing column-aligned text.
- Prefer graceful termination with `SIGTERM`; use `SIGKILL` only for an explicit force-kill action.

## Verification

Run before handing off changes:

```bash
swift test
swift build
```

For an end-to-end local smoke test:

```bash
swift run devkillerctl list
```

## macOS App Notes

- Target macOS 13 or newer for SwiftUI `MenuBarExtra`.
- Set `LSUIElement` to `true` in the app target Info.plist for a menu bar only app.
- Use `SMAppService` for launch-at-login support.
- Avoid requiring elevated privileges. If a process cannot be killed due to permissions, surface that clearly.

## Harness: devkiller development pipeline

Goal: Keep `devkiller` changes flowing through a small, testable pipeline centered on `DevKillerCore`, CLI smoke tests, and future SwiftUI menu bar integration.

Trigger: devkiller implementation, verification, pipeline, harness, retry, update, or review requests should use the `devkiller-pipeline` skill. Core process discovery and termination changes should also use `devkiller-core-change`; build/test/smoke-test work should use `devkiller-verification`.

Skills: project skill bodies live in `.agents/skills/`.

Codex agents: project-specific reviewer roles live in `.codex/config.toml` and `.codex/agents/*.toml`.

Change log:
| Date | Change | Target | Reason |
|---|---|---|---|
| 2026-04-28 | Fixed Codex agent role config paths and instruction keys | `.codex/config.toml`, `.codex/agents/*.toml` | Resolve malformed agent role warnings |
| 2026-04-28 | Initial development pipeline harness | `.agents/skills`, `.codex`, `_workspace/harness`, `AGENTS.md` | Reusable Codex workflow for core changes, verification, and future app integration |
