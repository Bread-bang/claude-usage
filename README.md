# Claude Usage — macOS Menu Bar App

A lightweight, native **SwiftUI menu bar app** that shows your Claude Code usage
(5‑hour session, 7‑day, Sonnet, and extra‑usage credits) in real time — without
launching Claude Code, parsing terminal output, or spending any Agent SDK credits.

```
◔ 41%                         ← in the menu bar

┌────────────────────────────────────┐
│ ⓘ Claude Usage                     │
│   you@example.com                  │
│                                    │
│ Current session              41%   │  ███████░░░░░░░░░
│ Current week (all models)    44%   │  ████████░░░░░░░░
│ Current week (Sonnet only)    0%   │  ░░░░░░░░░░░░░░░░
│ Usage credits        $0.62 / $40   │  ░░░░░░░░░░░░░░░░
│ ────────────────────────────────── │
│ Reset In                  3h 42m   │
│ Updated 12s ago         ⚙ ↻ ⏻     │
└────────────────────────────────────┘
```

- 100% local. No backend, no telemetry, no cookie copy‑paste.
- Uses your **existing Claude Code session** (the OAuth token already in your Keychain).
- Pure Swift + SwiftUI + `MenuBarExtra` + `URLSession`. No Electron, no dependencies.

---

## How it works

```
 macOS Keychain                 api.anthropic.com
 "Claude Code-credentials"      /api/oauth/usage
        │                              ▲
        │ accessToken (Bearer)         │ GET + Authorization: Bearer
        ▼                              │
  TokenProvider ──────────────►  UsageClient ──────► UsageReport (Codable)
        ▲ refresh on 401                                   │
        │                                                  ▼
        └────────────── UsageViewModel (poll 60s) ──► MenuBarExtra UI
```

### The endpoint (this is the important part)

The Claude **web app** calls `https://claude.ai/api/organizations/{org_id}/usage`,
but that host sits behind a **Cloudflare bot challenge** ("Just a moment…") that returns
`HTTP 403` to any non‑browser client — `URLSession`/`curl` cannot reach it without a
`cf_clearance` cookie and a JS challenge solve.

Claude Code itself uses a different, un‑walled endpoint that this app calls:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <oauth access token>
anthropic-beta: oauth-2025-04-20          # optional; sent for forward‑compat
```

It returns the **same data** and derives the organization from the token, so **no
`organization_id` is required**. A bare bearer token returns `HTTP 200`.

---

## Authentication strategy

Claude Code stores its OAuth bundle as a **generic password** in your login Keychain:

| Field   | Value                                                                       |
|---------|-----------------------------------------------------------------------------|
| Service | `Claude Code-credentials`                                                   |
| Account | your macOS short user name                                                  |
| Secret  | JSON: `{ "claudeAiOauth": { "accessToken", "refreshToken", "expiresAt", … } }` |

The app reads `claudeAiOauth.accessToken` and sends it as a bearer token. No cookies,
no manual copy‑paste, no scraping.

> **No password prompts:** a third‑party GUI app reading another app's Keychain item
> normally triggers the *"… wants to use information stored in Claude Code‑credentials"*
> password prompt on **every launch** — the item's partition list only trusts Apple‑signed
> tools, so the "Always Allow" grant never validates for outside apps. This app therefore
> reads the item through the Apple‑signed **`/usr/bin/security`** tool (the same access
> path Claude Code itself uses), which is silent. The secret only ever travels through an
> in‑memory pipe between the two local processes.

### Token refresh (tokens are short‑lived — a few hours)

Two layers, in priority order:

1. **Piggyback (primary).** The token is re‑read from the Keychain on *every* poll. While
   you use Claude Code it refreshes the token, and this app picks up the fresh one for free
   — zero writes, zero races.
2. **Self‑refresh (fallback, on by default).** On `401` or near‑expiry, `TokenProvider`
   exchanges the `refreshToken` at the OAuth token endpoint and writes the new bundle back
   into the same Keychain item. If that ever fails (e.g. Claude Code rotated the refresh
   token first, or the client values changed), the app degrades gracefully to
   *"Open Claude Code to sign in again"* — it never gets stuck.

> The refresh endpoint/`client_id` in `TokenProvider.swift` are Claude Code's public OAuth
> client values. They are **not verified live** in this skeleton (doing so would rotate
> your real token and disrupt Claude Code). If you rely on self‑refresh, confirm them
> against your Claude Code version, or simply leave the app to piggyback while Claude Code
> keeps the token fresh.

## Organization ID discovery

Not needed for the `/api/oauth/usage` endpoint. For cosmetic display only, the dropdown
header reads `oauthAccount.emailAddress` / `organizationName` from `~/.claude.json`
(best‑effort; the app works fine without it).

---

## Project structure

```
ClaudeUsageMiniBar/
├── Package.swift                     # SwiftPM executable, macOS 13+, Security+AppKit
├── Resources/Info.plist              # LSUIElement (menu‑bar‑only) bundle metadata
├── scripts/bundle.sh                 # build → assemble → ad‑hoc sign → dist/*.app
└── Sources/ClaudeUsageMiniBar/
    ├── App/
    │   └── ClaudeUsageMiniBarApp.swift   # @main, MenuBarExtra, accessory policy
    ├── Models/
    │   └── UsageReport.swift             # Codable models (nullable buckets)
    ├── Auth/
    │   ├── KeychainStore.swift           # Security.framework read/write
    │   ├── ClaudeCredentials.swift       # JSON bundle + expiry logic
    │   ├── TokenProvider.swift           # actor: valid token + refresh
    │   └── AccountInfo.swift             # ~/.claude.json (display only)
    ├── Networking/
    │   ├── UsageClient.swift             # URLSession, 401→refresh→retry
    │   └── UsageError.swift              # typed errors + reauth hints
    ├── ViewModel/
    │   └── UsageViewModel.swift          # @MainActor, polling loop, state
    ├── Views/
    │   ├── MenuBarLabel.swift            # the in‑menu‑bar label
    │   ├── UsageDropdownView.swift       # the panel (live countdown)
    │   └── Components.swift              # bars, rows, color thresholds
    └── Util/
        └── Formatters.swift              # tolerant ISO‑8601, %, countdown, money
```

## Data models

Strongly typed `Decodable` structs mirror the response. Every window is optional and
unknown keys are ignored, so the app survives Anthropic adding/renaming buckets
(`seven_day_opus`, `seven_day_cowork`, `tangelo`, `iguana_necktie`, …):

```swift
struct UsageReport: Decodable, Sendable {
    let fiveHour: RateLimitWindow?        // "five_hour"
    let sevenDay: RateLimitWindow?        // "seven_day"
    let sevenDaySonnet: RateLimitWindow?  // "seven_day_sonnet"
    let sevenDayOpus: RateLimitWindow?    // "seven_day_opus"
    let extraUsage: ExtraUsage?           // "extra_usage"
}
struct RateLimitWindow: Decodable, Sendable {
    let utilization: Double               // 0…100
    let resetsAtRaw: String?              // ISO‑8601, parsed tolerantly → resetsAt: Date?
}
```

Reset timestamps arrive with **microsecond precision** (`…:00.508711+00:00`), which
`ISO8601Parser` handles (fractional seconds → plain → trimmed‑to‑milliseconds fallback).

## Polling & refresh

- `UsageViewModel` runs an async loop: fetch → sleep `refreshInterval` (default **60s**,
  user‑selectable 30s/1m/5m) → repeat.
- The last good report is retained, so a failed refresh shows **stale data with a subtle
  warning** rather than blanking out.
- The dropdown's "Reset In" and "Updated … ago" use `TimelineView(.periodic)`, so they
  tick live **only while the panel is open** (no wasted work when closed).

## Error handling

`UsageError` maps every failure to a friendly message and a `requiresReauth` flag:

| Situation                | State shown                                           |
|--------------------------|-------------------------------------------------------|
| No Keychain item         | "Not signed in to Claude Code."                       |
| Expired / 401 / refresh ✗| "Session expired. Open Claude Code to sign in again." |
| Offline / DNS / timeout  | "Network unavailable." (keeps last data)              |
| Non‑2xx HTTP             | "Server returned HTTP NNN."                           |
| Bad JSON                 | "Could not read the usage data."                      |

## Security considerations

- **Least privilege.** Read‑only access to one Keychain item; the only write is the
  refreshed token back into that same item.
- **No exfiltration.** The only network call is `GET api.anthropic.com/api/oauth/usage`.
  Nothing is sent anywhere else; no analytics.
- **No secret logging.** Tokens are never printed; `.gitignore` blocks `*.token`,
  `secrets.json`, and captured responses.
- **Token lifetime.** The app holds the bearer token only in memory for the duration of a
  request. It does not copy it to disk (other than the Keychain it already lives in).
- **Code signing.** Ship with a Developer ID + notarization for distribution; the bundle
  script uses ad‑hoc signing for local use.

---

## Install

**Homebrew (once the tap is published):**
```bash
brew install bread-bang/tap/claude-usage
```

**Build from source:**
```bash
git clone https://github.com/Bread-bang/claude-usage.git
cd claude-usage
./scripts/bundle.sh --open      # builds dist/Claude Usage.app and launches it
```

Then add *Claude Usage.app* to System Settings → General → Login Items to start it at login.
Requires macOS 13+ and a signed‑in Claude Code (run `claude` once so the Keychain item exists).

## Build & run

**Quick run (development):**
```bash
swift run
```

**Build a distributable menu‑bar app:**
```bash
./scripts/bundle.sh          # → dist/Claude Usage.app
./scripts/bundle.sh --open   # build and launch
```

**Open in Xcode:** `open Package.swift` (or `xed .`), then Run.

To launch at login: System Settings → General → Login Items → add *Claude Usage.app*.

Requires macOS 13+ and a signed‑in Claude Code (`claude` run at least once so the
Keychain item exists).

## Limitations & caveats

- Depends on the **undocumented** `api.anthropic.com/api/oauth/usage` endpoint and on
  Claude Code's Keychain format. Both can change without notice.
- Self‑refresh uses Claude Code's OAuth client values — verify before relying on it
  (see Authentication). Piggyback mode needs none of this.
- The `claude.ai/api/...usage` endpoint in the original spec is intentionally **not**
  used — it's Cloudflare‑walled for non‑browser clients.

## License

Open source — add your preferred license (MIT recommended) before publishing.
