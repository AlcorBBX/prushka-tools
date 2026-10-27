# Security

This repository hosts **local developer tools** for a Prushka checkout.

## Scope

- Tools here are meant to run on your machine against a workspace you trust.
- They are not sandboxed App Store products and may invoke `bash`, `pnpm`, and other CLI tools.
- Do not point them at untrusted repositories.

## Packages

| Package | Notes |
| --- | --- |
| [macos-dev-launcher](./macos-dev-launcher/SECURITY.md) | Prushka L: allowlisted scripts/tools, confirmed destructive stops, localhost-only Open |

When adding a new tool under this tree, add a short security section (or `SECURITY.md`) describing what it executes and what it never touches (secrets, network, etc.).

## Reporting

Open an issue on this repository if a tool can leave its intended checkout or run arbitrary shell without an explicit, trusted script/command path.
