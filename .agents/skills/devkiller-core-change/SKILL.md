---
name: devkiller-core-change
description: "DevKillerCore 변경, 포트 스캔, lsof 파싱, 프로세스 종료, SIGTERM/SIGKILL, 권한 오류 처리 요청 시 사용한다."
---

# DevKiller Core Change

Use this skill for process discovery, parser, model, and termination logic.

## Boundaries

- Keep reusable logic in `DevKillerCore`.
- Keep CLI and future SwiftUI app layers as adapters.
- Prefer structured `lsof -F` output. Avoid parsing whitespace-aligned tables.
- Default kill behavior must use `SIGTERM`.
- Use `SIGKILL` only when the caller asks for a force-kill action.
- Do not require elevated privileges. Return clear permission failures.

## Implementation Checklist

1. Locate package structure:
   - `Package.swift`
   - `Sources/DevKillerCore/`
   - `Sources/devkillerctl/`
   - `Tests/DevKillerCoreTests/`
2. Read the relevant core API and tests before editing.
3. Keep data models explicit enough for UI consumers:
   - port
   - pid
   - process name or command
   - owner/user when available
   - permission or termination error details when available
4. Add or update tests around parsers and signal selection.
5. Run focused tests first when possible, then full verification.

## Verification

```bash
swift test
swift build
swift run devkillerctl list
```

If the Swift package has not been created yet, report that setup gap before claiming verification.
