# Prushka Tools

Companion tooling for a local [Prushka](https://github.com/AlcorBBX) checkout. This repository lives beside the main product tree (typically as `prushka/tools`) and holds developer utilities that are **not** part of the web/desktop/mobile apps themselves.

## Contents

| Path | What it is |
| --- | --- |
| [`macos-dev-launcher/`](./macos-dev-launcher/) | **Prushka L** — macOS SwiftUI launcher (start/stop services, tab-source tools, logs) |

More tools may land here later; each subdirectory should keep its own README for build/run details.

## Relationship to Prushka

These tools expect a Prushka workspace nearby, for example:

```text
prushka/
  front/
  scripts/
  prushka-services/
  tools/                 ← this repository
    macos-dev-launcher/
```

They do not vendor the monorepo. Point each tool at the checkout that contains `scripts/` and `front/`.

## Quick start (Prushka L)

```bash
cd macos-dev-launcher
./Scripts/package-app.sh
open "dist/Prushka L.app"
```

Full docs: [macos-dev-launcher/README.md](./macos-dev-launcher/README.md).

## Security

See [SECURITY.md](./SECURITY.md). Local tools may run shell commands against your checkout; treat them like Terminal helpers, not App Store apps.

## License

[MIT](./LICENSE) — same terms for the packages under this tree unless a subdirectory states otherwise.
