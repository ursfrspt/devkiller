# DevKiller

DevKiller is a macOS menu bar app that finds local development servers and lets you stop them with a click.

It is for people who run tools like Vite, Next.js, React, Expo, Storybook, Django, Rails, PHP, or Jupyter and later wonder which terminal command is still using a port. Instead of searching for a process ID or typing `kill`, open DevKiller from the menu bar and stop the server there.

## Who It Helps

- You started a local app and forgot which terminal tab is running it.
- A port such as `3000`, `5173`, `8000`, or `8081` is still busy.
- You want to stop old dev servers without learning `lsof`, `ps`, or `kill`.
- You are using AI coding tools and want a simple way to clean up local servers between runs.

## Requirements

- macOS 13 Ventura or newer
- Local Network permission, if macOS asks for it

DevKiller is a menu bar app. It does not show a Dock icon.

## Install And Open

If you downloaded `DevKiller.app` or a `DevKiller-*.zip` file:

1. Unzip the file if needed.
2. Move `DevKiller.app` to your Applications folder.
3. Open `DevKiller.app`.
4. Look for the DevKiller icon in the macOS menu bar.

If macOS says the app cannot be opened because it was downloaded from the internet, right-click `DevKiller.app`, choose `Open`, then confirm that you want to open it.

## Use DevKiller

1. Click the DevKiller icon in the macOS menu bar.
2. Review the detected development servers.
3. Click a server to stop it.
4. Use `Kill All Dev Servers` when you want to stop every detected dev server at once.
5. Choose `Quit DevKiller` when you are done.

Each menu item shows the port and the likely framework or command, such as `Kill :5173 Vite` or `Kill :3000 Next.js`.

## What DevKiller Finds

DevKiller checks local TCP listeners and highlights likely development servers. It looks for common development ports and process names, including:

- Vite, React, Next.js, Nuxt, Astro, Angular, Storybook, Expo, and Metro
- Node.js, Bun, Deno, webpack, and Tauri
- Python, Django, Flask, Jupyter, Rails, Ruby, PHP, Java, Gradle, Hugo, and similar local servers

DevKiller hides low-confidence matches by default so system services are less likely to appear in the app.

## Stopping Servers

DevKiller first asks the server to quit normally.

If macOS does not allow DevKiller to stop a process, the app shows the error instead of asking for administrator privileges. Some servers may also restart automatically if another tool is supervising them. In that case, stop the parent tool, terminal command, or editor task that started the server.

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
- Stop it from the terminal, editor task, or tool that launched it.

## For Developers

DevKiller is built as a small Swift package:

- `DevKillerCore` contains process discovery and termination logic.
- `DevKillerBar` is the macOS menu bar app.
- `devkillerctl` is a command-line helper for testing and advanced use.

Build and open the app locally:

```bash
./scripts/build-app.sh
open dist/DevKiller.app
```

Run checks before handing off changes:

```bash
swift test
swift build
swift run devkillerctl list
```

Advanced command-line usage:

```bash
swift run devkillerctl list
swift run devkillerctl list --all
swift run devkillerctl kill 3000
swift run devkillerctl kill 3000 --force
swift run devkillerctl kill-all
```

Use `--force` only when normal termination does not work.
