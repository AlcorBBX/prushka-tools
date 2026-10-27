# Prushka L

Local macOS control center for a [Prushka](https://github.com/AlcorBBX) checkout: start/stop web, desktop, mobile, API and stems workers, run tab-source demo tools, and tail logs — without typing the same shell commands every day.

This repository is **only the launcher**. It does not contain the Prushka monorepo. Point Settings at a checkout that has:

- `scripts/registry.json`
- `scripts/up.sh`, `scripts/down.sh`, `scripts/status.sh`
- `front/package.json`

## Requirements

- macOS 14+
- Swift 6.1+ (Command Line Tools or Xcode)
- A local Prushka workspace with the scripts above
- Tools you already use for that workspace (`pnpm`, and optionally `bun`, `go`, Expo, etc.)

## Build

```bash
./Scripts/package-app.sh
open "dist/Prushka L.app"
```

Release binary:

```bash
./Scripts/package-app.sh --release
```

The package script builds with SwiftPM, wraps the binary as `Prushka L.app`, copies `Resources/AppIcon.icns`, and ad-hoc codesigns. **App Sandbox is off** on purpose so the app can run your repo scripts.

## Usage

1. Open **Prushka L**.
2. In **Settings**, choose the Prushka repository root (or use the detected path).
3. **Services** — start/stop units, open local URLs, jump to logs.
4. **Tools** — tab-source fetch / fill / notes-from-lead with forms.
5. **Logs** — tail `.run/logs/<unit>.log` for launcher-started processes.

Status also discovers processes started outside the app (terminal, agents) via ports and cmdline fingerprints from `scripts/status.sh --json`.

## Security

See [SECURITY.md](./SECURITY.md). Short version: treat this like Terminal.app for your own machine. It only runs allowlisted scripts and tools under a validated checkout, but it is not a sandboxed App Store app.

## License

[MIT](./LICENSE)
