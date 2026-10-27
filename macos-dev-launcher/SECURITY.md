# Security

Prushka L is a **local developer tool**, not a multi-tenant or App Store product.

## Trust model

- The app runs **without App Sandbox**.
- It executes `/bin/bash` against allowlisted scripts (`up.sh`, `down.sh`, `status.sh`) and allowlisted tool binaries (`pnpm`, `node`, …) inside a checkout you select.
- Stop may terminate processes on known ports, including ones not started by the launcher, after confirmation when the status source is external.

If you do not trust the checkout (or its `scripts/`), do not point the launcher at it.

## Guardrails already in the app

- Repo root must contain several markers (`scripts/registry.json`, `up`/`down`/`status.sh`, `front/package.json`).
- Script paths must stay under `scripts/`; arguments are allowlisted.
- Tool ids, command tokens, and form values are validated (no shell metacharacters; relative `cwd` without `..`).
- **Open** only accepts `http(s)://localhost` or `127.0.0.1`.
- Log reads are limited to `.run/logs`.
- Destructive stops ask for confirmation where it matters (stop all / external).

## Not included

- Notarization / Developer ID distribution
- Hardened Runtime as a shipping requirement
- Network services or remote control
- Secrets storage (none are shipped in this repo)

## Reporting

If you find a way for the launcher to run arbitrary shell or leave the selected checkout without deliberate misuse of a malicious repo, open an issue on this repository.
