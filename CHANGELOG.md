# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-06-12

### Added
- Second menu bar widget showing the **context window usage** of the Claude Code
  session you are currently looking at — a `scroll` glyph plus the occupied
  percentage, styled to match the usage widget.
- Reads occupancy from the local transcript (`~/.claude/projects/<cwd>/<uuid>.jsonl`):
  the last main-thread `usage` line, skipping `<synthetic>` / zero-usage resume
  markers. No server API involved.
- Automatic 200K vs 1M context-window detection (recorded `/context` output,
  `<budget:token_budget>` tag, Fable/Mythos model, occupancy ratchet, default-model
  and per-project `[1m]` keys).
- Active-session identification via a self-installed Claude Code hook relay
  (`--hook-relay` mode) plus a tty-atime bridge, so the widget follows whichever
  terminal pane you last typed in — no Accessibility permissions, terminal-agnostic.
- Idempotent hook installation into `~/.claude/settings.json` on first launch,
  preserving any existing hooks.

## [0.1.0] - 2026-06-12

### Added
- Menu bar app showing Claude Code usage: current session (5-hour), current week
  (all models / Sonnet only), and pay-as-you-go usage credits.
- Reads the OAuth token from Claude Code's Keychain item via `/usr/bin/security`
  (no password prompts) and calls `api.anthropic.com/api/oauth/usage`.
- Per-window reset times, traffic-light utilization bars, live countdowns.
- Selectable menu bar icon and refresh interval; settings and last report persist
  across launches.
- Rate-limit (HTTP 429) backoff and a grace window before showing a stale warning.
- `bundle.sh` for local builds and `release.sh` for Developer ID signing + notarization.

[Unreleased]: https://github.com/Bread-bang/claude-usage/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/Bread-bang/claude-usage/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Bread-bang/claude-usage/releases/tag/v0.1.0
