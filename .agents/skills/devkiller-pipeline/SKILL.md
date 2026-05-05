---
name: devkiller-pipeline
description: "devkiller 개발 파이프라인, 하네스 실행, 기능 구현, 재실행, 업데이트, 점검 요청 시 사용한다. DevKillerCore 중심 변경, CLI 검증, SwiftUI 메뉴바 앱 통합을 단계적으로 조율한다."
---

# DevKiller Pipeline

Use this orchestrator when a request asks to build, change, review, or harden `devkiller`.

## Goal

Keep development changes small, testable, and aligned with the project boundary:

- `DevKillerCore` owns process discovery and termination.
- CLI and future SwiftUI app code stay thin and call the core.
- Structured command output such as `lsof -F` is preferred over column parsing.
- Termination defaults to `SIGTERM`; `SIGKILL` is only for explicit force-kill flows.

## Modes

- Direct execution: use for narrow bug fixes, CLI tweaks, documentation, and tests.
- Generate then verify: use for core scanner, parser, signaling, or permission behavior.
- Parallel review: only use project agents when review can run independently from the next local edit.

## Pipeline

1. Audit current state:
   - Read `AGENTS.md`, `README.md`, `Package.swift`, and relevant `Sources/` or `Tests/` files.
   - Check for dirty files with `git status --short` when the directory is a Git repository.
   - Inspect `_workspace/` for prior pipeline artifacts when continuing previous work.
2. Classify the change:
   - Core behavior: use `devkiller-core-change`.
   - Verification, smoke tests, or release checks: use `devkiller-verification`.
   - SwiftUI menu bar integration: keep shell/process work in `DevKillerCore`.
3. Plan with `update_plan` for multi-step work.
4. Implement narrowly:
   - Preserve user edits.
   - Avoid broad rewrites unrelated to the requested behavior.
   - Add tests near the changed behavior when the Swift package exists.
5. Verify:
   - Prefer `swift test`, then `swift build`.
   - Run `swift run devkillerctl list` for end-to-end smoke checks when the CLI target exists.
   - If a command cannot run because package files are absent, say that explicitly.
6. Record useful pipeline findings:
   - Put temporary notes under `_workspace/harness/`.
   - Update `AGENTS.md` change log only for durable harness changes.

## Project Agents

Project-specific agent definitions live in `.codex/config.toml` and `.codex/agents/*.toml`.

- `devkiller-core-reviewer`: reviews process discovery, parsing, signaling, and permission boundaries.
- `devkiller-qa`: checks tests, CLI smoke coverage, macOS app constraints, and harness drift.

Use agents only for bounded parallel review or verification. The main Codex session remains responsible for final integration.

## Error Handling

- Retry a failed deterministic command once only when the failure looks environmental.
- Do not hide missing package structure. Report absent `Package.swift`, `Sources/`, or `Tests/` as a setup gap.
- If process termination is blocked by permissions, preserve the error and surface it clearly.

## Dry Run Scenarios

- Normal: implement a scanner/parser change in `DevKillerCore`, add tests, run `swift test`, `swift build`, and CLI list smoke test.
- Failure: `swift run devkillerctl list` finds a permission error or missing target; capture the exact limitation and keep the core API behavior explicit.
