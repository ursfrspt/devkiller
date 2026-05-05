---
name: devkiller-verification
description: "devkiller 검증, 테스트, 빌드, CLI smoke test, 릴리스 전 점검, 하네스 드라이런 요청 시 사용한다."
---

# DevKiller Verification

Use this skill for build/test/smoke-test work and final handoff checks.

## Standard Commands

Run from the project root:

```bash
swift test
swift build
swift run devkillerctl list
```

If `scripts/check.sh` exists, it may be used as a convenience wrapper after reading it.

## Checks

- `DevKillerCore` contains process discovery and termination behavior.
- CLI behavior is a thin wrapper over core APIs.
- Parser tests cover representative `lsof -F` records.
- Termination tests distinguish graceful kill from force kill.
- Permission failures are surfaced as user-facing errors, not swallowed.
- Future SwiftUI menu bar app notes remain macOS 13+ and `LSUIElement` aware.

## Harness Drift Checks

```bash
find .agents/skills -maxdepth 2 -name SKILL.md -print | sort
rg -n "Team(Create|Delete)|Task(Create|Update)|Send(Message)" .agents/skills AGENTS.md .codex 2>/dev/null
ls -la .codex .codex/agents 2>/dev/null
```

The drift scan should produce no Claude-only tool names in project harness files.
