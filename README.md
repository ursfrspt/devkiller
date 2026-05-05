# devkiller

macOS menu bar utility for finding and stopping local development servers.

## Harness

This repository starts with a Swift Package harness:

- `DevKillerCore`: port scanning and process signaling logic.
- `devkillerctl`: CLI smoke-test wrapper for the core behavior.
- `DevKillerCoreTests`: parser and scanner tests using Swift Testing.
- `scripts/check.sh`: one-command local verification.

The GUI app should wrap `DevKillerCore` from a macOS SwiftUI `MenuBarExtra` target.

## Commands

```bash
swift test
swift run devkillerctl list
swift run devkillerctl kill 3000
swift run devkillerctl kill-all
swift run devkillerbar
./scripts/build-app.sh
./scripts/package-zip.sh
./scripts/check.sh
```

## Direct Distribution

The release path is GitHub Releases with a signed, notarized `.zip` containing `DevKiller.app`.
Developer ID, notarization, and GitHub Actions setup steps are documented in [docs/release.md](docs/release.md).

Local unsigned development bundle:

```bash
./scripts/build-app.sh
open dist/DevKiller.app
```

Release zip:

```bash
DEVKILLER_VERSION=0.1.0 ./scripts/package-zip.sh
```

GitHub release from a tag:

```bash
git init
git add .
git commit -m "Initial DevKiller release"
git branch -M main
git remote add origin git@github.com:YOUR_GITHUB_USER/devkiller.git
git push -u origin main

git tag v0.1.0
git push origin v0.1.0
```

The `Release` GitHub Actions workflow runs tests, builds the app, creates `DevKiller-<version>.zip`, generates a `.sha256` file, and uploads both files to GitHub Releases. Pushes to `main` create prerelease builds titled `DevKiller Nightly build-<run>-<sha>`. Tags such as `v0.1.0` create normal releases.

Unsigned builds are useful for testing, but public macOS downloads should be Developer ID signed and notarized to avoid Gatekeeper warnings. Add these GitHub repository secrets before publishing a public release:

- `DEVKILLER_DEVELOPER_ID_CERTIFICATE_BASE64`: base64-encoded Developer ID Application `.p12`
- `DEVKILLER_DEVELOPER_ID_CERTIFICATE_PASSWORD`: password for the `.p12`
- `DEVKILLER_CODESIGN_IDENTITY`: Developer ID Application identity
- `DEVKILLER_KEYCHAIN_PASSWORD`: temporary CI keychain password
- `APPLE_ID`: Apple ID used for notarization
- `APPLE_TEAM_ID`: Apple Developer Team ID
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for notarization

Developer ID signing and notarization:

```bash
xcrun notarytool store-credentials devkiller-notary \
  --apple-id you@example.com \
  --team-id YOURTEAMID \
  --password APP_SPECIFIC_PASSWORD

DEVKILLER_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
DEVKILLER_NOTARY_PROFILE=devkiller-notary \
DEVKILLER_VERSION=0.1.0 \
./scripts/notarize-zip.sh
```

Useful release environment variables:

- `DEVKILLER_BUNDLE_ID`: bundle identifier, defaults to `com.igyeongjun.DevKiller`
- `DEVKILLER_VERSION`: marketing version, defaults to `0.1.0`
- `DEVKILLER_BUILD_NUMBER`: build number, defaults to `1`
- `DEVKILLER_CODESIGN_IDENTITY`: Developer ID Application identity for public releases
- `DEVKILLER_NOTARY_PROFILE`: `notarytool` keychain profile name

## Development Server Detection

`DevKillerCore` scans listening TCP processes with structured `lsof -F` output. It classifies likely development servers with a conservative heuristic:

- known development ports, such as 3000, 5173, 4200, 6006, 8000, and 8081
- process command hints, such as `node`, `vite`, `python`, `rails`, `puma`, `php`, and `uvicorn`
- a small macOS system-process deny-list to avoid killing services such as `ControlCenter` on port 5000

The menu bar app and CLI only show medium/high confidence matches by default. `devkillerctl list --all` can show low-confidence listeners for debugging.

## macOS App Direction

- Use SwiftUI `MenuBarExtra` for a menu bar only app.
- Set `LSUIElement` to `true` so the app does not appear in the Dock or app switcher.
- Use `SMAppService.mainApp.register()` for optional launch at login on macOS 13+.
- Keep shell/process code in `DevKillerCore`; the app target should only present state and call core services.
