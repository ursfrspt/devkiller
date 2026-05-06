# DevKiller

DevKiller is a macOS menu bar app for finding and stopping local development servers.

It watches for common dev servers such as Vite, Next.js, React, Expo, Storybook, Django, Rails, PHP, Jupyter, and other processes listening on local ports. When a server is no longer needed, you can stop it from the menu bar instead of searching for the process manually.

## Requirements

- macOS 13 Ventura or newer
- Local Network permission, if macOS asks for it

## Open DevKiller

If you have `DevKiller.app`, open it like any other macOS app.

For a local development build:

```bash
./scripts/build-app.sh
open dist/DevKiller.app
```

DevKiller runs in the menu bar. It does not show a Dock icon.

## Use The Menu Bar App

1. Click the DevKiller icon in the macOS menu bar.
2. Review the detected development servers.
3. Choose a server to stop it.
4. Use `Kill All Dev Servers` when you want to stop every detected dev server at once.
5. Choose `Quit DevKiller` when you are done.

The app refreshes automatically while the menu is open. Each item shows the port and the likely framework or command, such as `Kill :5173 Vite` or `Kill :3000 Next.js`.

## What DevKiller Looks For

DevKiller checks local TCP listeners and highlights likely development servers. It favors common development ports and process names, including:

- Vite, React, Next.js, Nuxt, Astro, Angular, Storybook, Expo, and Metro
- Node.js, Bun, Deno, webpack, and Tauri
- Python, Django, Flask, Jupyter, Rails, Ruby, PHP, Java, Gradle, Hugo, and similar local servers

DevKiller hides low-confidence matches by default so system services are less likely to appear in the app.

## Stopping Servers

DevKiller uses normal process termination first. If macOS does not allow the process to be stopped, the app shows the error instead of asking for administrator privileges.

Some servers may restart automatically if another tool is supervising them. In that case, stop the parent tool or terminal command that started the server.

## Local Network Permission

On first launch, macOS may ask whether DevKiller can access the local network. Allow this permission so DevKiller can inspect local listening development servers.

If you denied the permission:

1. Open System Settings.
2. Go to Privacy & Security.
3. Open Local Network.
4. Enable DevKiller.
5. Quit and reopen DevKiller.

## Troubleshooting

If no servers appear:

- Make sure the development server is still running.
- Open the server in your browser to confirm it responds locally.
- Check that DevKiller has Local Network permission.
- Quit and reopen DevKiller.

If a server cannot be stopped:

- The process may belong to another user.
- The process may have already exited.
- Another development tool may be restarting it.
- Stop it from the terminal or the tool that launched it.

## Command Line

DevKiller also includes a command-line helper for advanced users:

```bash
swift run devkillerctl list
swift run devkillerctl kill 3000
swift run devkillerctl kill-all
```

Use `--all` with `list` to show low-confidence listeners:

```bash
swift run devkillerctl list --all
```

Use `--force` only when normal termination does not work:

```bash
swift run devkillerctl kill 3000 --force
```
