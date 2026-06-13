<p align="center">
  <img src="docs/icon.png" alt="Claude Usage" width="120">
</p>

<h1 align="center">Claude Usage</h1>

A lightweight, native macOS **menu bar app** that shows your Claude Code usage — current
session (5‑hour), weekly (all models / Sonnet), and pay‑as‑you‑go credits — in real time,
without launching Claude Code or spending Agent SDK credits. It also drops a compact
**context‑window readout** into Claude Code's status line, right under your prompt.

<p align="center">
  <img src="docs/screenshot.png" alt="Claude Usage menu bar app showing session, weekly, Sonnet, and credit usage" width="480">
</p>

<p align="center">
  <img src="docs/statusline.png" alt="Context-window readout in Claude Code's status line: model, percent full, and tokens used" width="420">
</p>

- **100% local.** No backend, no telemetry, no cookies — it reuses the OAuth token already
  in your Keychain from Claude Code.
- Pure Swift + SwiftUI + `MenuBarExtra`. No Electron, no dependencies. Notarized.

## Install

**Homebrew**
```bash
brew install bread-bang/tap/claude-usage
```
After the tap is added, `brew install claude-usage` works too. The build is notarized, so
it opens with no Gatekeeper warnings.

**Build from source**
```bash
git clone https://github.com/Bread-bang/claude-usage.git
cd claude-usage
./scripts/bundle.sh --open
```

**Requirements:** macOS 13+ and Claude Code signed in (run `claude` once so the Keychain
item exists). To start it at login: System Settings → General → Login Items → add
*Claude Usage.app*.

## Features

- Current session (5‑hour), current week (all models and Sonnet only), and usage credits —
  each with a utilization bar and its reset time.
- **Context in the status line:** a one‑line readout under your Claude Code prompt — model,
  percent full, and tokens used (e.g. `Opus 4.8 · 11% · 113K/1M`), with the 200K vs 1M window
  reported directly by Claude Code. Because each pane renders its own, it's always the right
  session — even across many panes (tmux, cmux) — with no guesswork and no Accessibility
  permissions.
- Menu‑bar number for the window of your choice, with traffic‑light colors.
- Selectable icon and refresh interval (30s / 1m / 5m); settings and the last report
  persist across launches.
- Keeps showing the last good data with a subtle warning when a refresh fails, and backs
  off on rate limits.

## Privacy & trust

- The only network request is `GET https://api.anthropic.com/api/oauth/usage` — the same
  endpoint Claude Code uses. Nothing is sent anywhere else; no analytics.
- The token is read from Claude Code's Keychain item through Apple's `/usr/bin/security`
  tool and held only in memory for each request — never written to disk or logged.
- The context readout is local too: Claude Code passes the live context window to a
  status‑line command on stdin, and we just format it. We register that command in
  `~/.claude/settings.json` only when the status‑line slot is empty or already ours —
  another tool's status line is never overwritten. Nothing leaves your machine.

## Development

```bash
swift run               # run from source
open Package.swift       # or open in Xcode
./scripts/bundle.sh      # build dist/Claude Usage.app (locally signed)
./scripts/release.sh     # Developer ID-signed + notarized .zip for a release
```

Getting repeated Keychain prompts on every rebuild? Run `./scripts/create-signing-cert.sh`
once. Architecture and the reverse‑engineering notes (endpoint choice, Keychain access,
token refresh) are in **[DESIGN.md](DESIGN.md)**.

## Limitations

- Relies on the **undocumented** `api.anthropic.com/api/oauth/usage` endpoint and on Claude
  Code's Keychain format — both can change without notice.
- The `claude.ai/api/.../usage` endpoint is intentionally not used (Cloudflare‑walled for
  non‑browser clients; see [DESIGN.md](DESIGN.md)).

## License

[MIT](LICENSE) © Bread-bang
