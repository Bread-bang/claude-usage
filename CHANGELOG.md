# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/Bread-bang/claude-usage/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Bread-bang/claude-usage/releases/tag/v0.1.0
