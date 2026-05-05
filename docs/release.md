# 릴리스 가이드

DevKiller는 Mac App Store가 아니라 GitHub Releases를 통해 직접 배포한다. 배포 파일은 `DevKiller.app`을 담은 `.zip`이고, 공개 배포용 빌드는 Developer ID로 서명하고 Apple notarization까지 거치는 것을 기준으로 한다.

## 릴리스 방식

- `main` 브랜치에 push하면 `DevKiller Nightly build-<run>-<sha>` 제목의 GitHub prerelease가 생성된다.
- `v0.1.0` 같은 태그를 push하면 일반 GitHub release가 생성된다.
- unsigned 빌드는 로컬 테스트나 내부 테스트용으로만 사용한다.
- 공개 배포는 Developer ID 서명과 Apple notarization을 사용한다.

## Apple 최초 설정

Apple Developer 사이트에서 Developer ID Application 인증서를 만든다:

```text
Certificates, Identifiers & Profiles
Certificates
+
Developer ID Application
```

인증서를 Mac Keychain에 설치한 뒤 확인한다:

```bash
security find-identity -v -p codesigning
```

출력에 아래와 같은 identity가 있어야 한다:

```text
Developer ID Application: Your Name (TEAMID)
```

Apple ID용 app-specific password도 만든다. `notarytool` 인증에 사용하는 비밀번호이며, 일반 Apple ID 비밀번호를 쓰면 안 된다.

로컬 notary credentials는 한 번만 저장하면 된다:

```bash
xcrun notarytool store-credentials devkiller-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "APP_SPECIFIC_PASSWORD"
```

## 로컬 signed release

GitHub Secrets를 연결하기 전에 로컬에서 signed/notarized release가 성공하는지 먼저 확인한다:

```bash
cd /Users/igyeongjun/Desktop/devkiller

DEVKILLER_VERSION=0.1.0 \
DEVKILLER_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
DEVKILLER_NOTARY_PROFILE=devkiller-notary \
./scripts/notarize-zip.sh
```

성공하면 아래 파일이 생성된다:

```text
dist/DevKiller-0.1.0.zip
dist/DevKiller-0.1.0.zip.sha256
```

이 스크립트는 앱을 빌드하고, hardened runtime으로 서명하고, zip을 Apple notarization에 제출하고, `DevKiller.app`에 notarization ticket을 staple한 뒤, zip을 다시 만들고 `spctl` 검증까지 수행한다.

## GitHub Secrets

Keychain Access에서 Developer ID Application 인증서를 `.p12` 파일로 export한다. export할 때 비밀번호를 지정한다. 이 `.p12` 파일은 절대 커밋하지 않는다.

GitHub Secrets에 넣기 위해 base64로 변환한다:

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

GitHub repository settings에 아래 Secrets를 등록한다:

```text
DEVKILLER_DEVELOPER_ID_CERTIFICATE_BASE64
DEVKILLER_DEVELOPER_ID_CERTIFICATE_PASSWORD
DEVKILLER_CODESIGN_IDENTITY
DEVKILLER_KEYCHAIN_PASSWORD
APPLE_ID
APPLE_TEAM_ID
APPLE_APP_SPECIFIC_PASSWORD
```

`DEVKILLER_CODESIGN_IDENTITY`에는 인증서 common name 전체를 넣는다:

```text
Developer ID Application: Your Name (TEAMID)
```

`DEVKILLER_KEYCHAIN_PASSWORD`는 GitHub Actions 임시 keychain에만 쓰는 긴 임시 비밀번호면 된다.

## 자동 릴리스

최신 `main`으로 prerelease를 만들려면:

```bash
git push origin main
```

정식 공개 release를 만들려면:

```bash
git tag v0.1.0
git push origin v0.1.0
```

`Release` workflow는 아래 작업을 실행한다:

```text
swift test
swift build
./scripts/package-zip.sh
./scripts/notarize-zip.sh
gh release create
```

서명 관련 Secrets가 없으면 unsigned release artifact도 만들 수 있다. 다만 unsigned artifact는 공개 release로 취급하지 않는다.

## 사용자 설치 방식

사용자는 `DevKiller-<version>.zip`을 다운로드하고 압축을 푼 뒤, `DevKiller.app`을 `/Applications`로 옮겨 실행한다. Developer ID로 서명하고 notarization된 빌드는 unsigned 앱에서 뜨는 강한 Gatekeeper 차단을 피할 수 있다.

## 문제 해결

notarization이 실패하면 GitHub Actions 로그를 확인하거나, 같은 identity로 로컬에서 다시 실행한다. 흔한 원인은 아래와 같다:

- `Developer ID Application` 인증서가 없거나 identity 문자열이 정확하지 않다.
- GitHub Secrets에 넣은 `.p12` 비밀번호가 틀렸다.
- Apple app-specific password가 틀렸거나 만료됐다.
- `APPLE_TEAM_ID`가 인증서의 Team ID와 다르다.
- hardened runtime 또는 entitlements 설정이 잘못됐다.

로컬 검증 명령:

```bash
codesign --verify --deep --strict --verbose=2 dist/DevKiller.app
spctl --assess --type execute --verbose dist/DevKiller.app
xcrun stapler validate dist/DevKiller.app
```

### 개발 서버가 보이지 않을 때

배포 앱을 처음 실행하면 macOS가 Local Network 접근 허용 여부를 물을 수 있다. DevKiller는 로컬에서 listen 중인 개발 서버를 찾기 위해 이 권한이 필요하므로 허용해야 한다.

이미 거부했다면 System Settings > Privacy & Security > Local Network에서 DevKiller를 다시 허용한 뒤 앱을 재실행한다. 같은 서버가 CLI에서는 보이지만 앱에서 보이지 않는다면 먼저 아래 명령으로 코어 감지가 정상인지 확인한다:

```bash
swift run devkillerctl list --all
```
