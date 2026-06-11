# Design notes

How Claude Usage works under the hood, and the reverse‑engineering behind it. None of this
is needed to use or install the app — see the [README](README.md) for that.

## Data flow

```
 macOS Keychain                 api.anthropic.com
 "Claude Code-credentials"      /api/oauth/usage
        │                              ▲
        │ accessToken (Bearer)         │ GET + Authorization: Bearer
        ▼                              │
  TokenProvider ──────────────►  UsageClient ──────► UsageReport (Codable)
        │                                                  │
        ▼                                                  ▼
  /usr/bin/security read                    UsageViewModel (poll 60s) ──► MenuBarExtra UI
```

## The endpoint

The Claude **web app** calls `https://claude.ai/api/organizations/{org_id}/usage`, but that
host sits behind a **Cloudflare bot challenge** ("Just a moment…") that returns `HTTP 403`
to any non‑browser client — `URLSession`/`curl` cannot reach it without a `cf_clearance`
cookie and a JS challenge solve.

Claude Code itself uses a different, un‑walled endpoint that this app calls:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <oauth access token>
anthropic-beta: oauth-2025-04-20          # optional; sent for forward‑compat
```

It returns the **same data** and derives the organization from the token, so **no
`organization_id` is required**. A bare bearer token returns `HTTP 200`.

## Authentication

Claude Code stores its OAuth bundle as a **generic password** in the login Keychain:

| Field   | Value                                                                       |
|---------|-----------------------------------------------------------------------------|
| Service | `Claude Code-credentials`                                                   |
| Account | the macOS short user name                                                   |
| Secret  | JSON: `{ "claudeAiOauth": { "accessToken", "refreshToken", "expiresAt", … } }` |

### Why it reads through `/usr/bin/security`

A third‑party GUI app calling `SecItemCopyMatching` on another app's Keychain item triggers
the *"… wants to use information stored in Claude Code‑credentials"* password prompt on
**every launch** — the item's partition list only trusts Apple‑signed tools, so the
"Always Allow" grant never validates for an outside app. So the app instead shells out to
the Apple‑signed **`/usr/bin/security`** tool (which is inside the `apple-tool:` partition
and reads silently — the same access path Claude Code uses). The secret only travels
through an in‑memory pipe between the two local processes. See `Auth/KeychainStore.swift`.

### Token refresh (tokens are short‑lived — a few hours)

Two layers, in priority order:

1. **Piggyback (primary).** The token is re‑read from the Keychain on *every* poll. While
   you use Claude Code it refreshes the token and this app picks up the fresh one for free.
2. **Self‑refresh (fallback, on by default).** On `401` or near‑expiry, `TokenProvider`
   exchanges the `refreshToken` at the OAuth token endpoint and writes the new bundle into
   **the app's own** Keychain item (`ClaudeUsageMiniBar-credentials`) — never Claude Code's
   (writing to another app's item prompts for a password and would clobber fields the app
   doesn't model, e.g. `mcpOAuth` server tokens). On the next read the fresher of the two
   bundles wins. If refresh fails, the app degrades to *"Open Claude Code to sign in again."*

> The refresh endpoint/`client_id` in `TokenProvider.swift` are Claude Code's public OAuth
> client values and are not verified live (doing so would rotate your real token). If you
> rely on self‑refresh, confirm them against your Claude Code version; otherwise piggyback
> mode needs none of this.

### Organization ID

Not needed for `/api/oauth/usage`. For cosmetic display only, the dropdown header reads
`oauthAccount.emailAddress` / `organizationName` from `~/.claude.json` (best‑effort).

## Data models

Strongly typed `Codable` structs mirror the response. Every window is optional and unknown
keys are ignored, so the app survives Anthropic adding/renaming buckets (`seven_day_opus`,
`seven_day_cowork`, `tangelo`, `iguana_necktie`, …):

```swift
struct UsageReport: Codable, Sendable {
    let fiveHour: RateLimitWindow?        // "five_hour"
    let sevenDay: RateLimitWindow?        // "seven_day"
    let sevenDaySonnet: RateLimitWindow?  // "seven_day_sonnet"
    let sevenDayOpus: RateLimitWindow?    // "seven_day_opus"
    let extraUsage: ExtraUsage?           // "extra_usage"
}
struct RateLimitWindow: Codable, Sendable {
    let utilization: Double               // 0…100
    let resetsAtRaw: String?              // ISO‑8601 → resetsAt: Date?
}
```

`extra_usage` reports credits in **cents** (`used_credits: 62.0`, `monthly_limit: 4000` →
`$0.62 / $40.00`). Reset timestamps arrive with **microsecond precision**
(`…:00.508711+00:00`), which `ISO8601Parser` handles (fractional → plain → trimmed‑to‑ms).

## Polling, refresh & errors

- `UsageViewModel` runs an async loop: fetch → sleep `refreshInterval` (default **60s**) →
  repeat. The last good report is cached to disk and restored on launch, so a relaunch shows
  data immediately instead of a blank state.
- On a cold start with no data it retries every 15s; after a `429` it backs off to 2× the
  interval. A failed refresh keeps the stale data and only surfaces a warning after a grace
  window.
- The dropdown's "Reset In" / "Updated … ago" use `TimelineView(.periodic)`, ticking only
  while the panel is open.

`UsageError` maps each failure to a friendly message; transient ones (rate limit, network)
are shown softer than auth failures, which prompt re‑signing in Claude Code.

## Menu bar label

MenuBarExtra forces the system status‑bar font on any `Text` in its label (a 7pt font
renders identically to 13pt). To control typography, the label is rendered into a template
`NSImage` via `ImageRenderer` and handed to the menu bar as an image, which the system
cannot restyle. `isTemplate = true` keeps it adapting to light/dark menu bars.

## Packaging & signing

- `scripts/bundle.sh` — local build into `dist/Claude Usage.app`, signed with a stable
  self‑signed local identity (created by `scripts/create-signing-cert.sh`). A stable
  signature keeps the Keychain "Always Allow" grant from resetting on every rebuild.
- `scripts/release.sh` — release build signed with a **Developer ID Application**
  certificate, hardened runtime, notarized via `notarytool`, stapled, and zipped. Prints the
  `sha256` for the Homebrew cask.

## Project structure

```
├── Package.swift                     # SwiftPM executable, macOS 13+
├── Resources/Info.plist              # LSUIElement (menu‑bar‑only) bundle metadata
├── scripts/{bundle,release,create-signing-cert}.sh
├── Casks/claude-usage.rb             # Homebrew cask (source of truth lives in the tap)
└── Sources/ClaudeUsageMiniBar/
    ├── App/          ClaudeUsageMiniBarApp.swift   # @main, MenuBarExtra, accessory policy
    ├── Models/       UsageReport.swift             # Codable models (nullable buckets)
    ├── Auth/         KeychainStore, ClaudeCredentials, TokenProvider, AccountInfo
    ├── Networking/   UsageClient, UsageError
    ├── ViewModel/    UsageViewModel.swift          # @MainActor, polling, caching
    ├── Views/        MenuBarLabel, UsageDropdownView, Components
    └── Util/         Formatters.swift              # ISO‑8601, %, countdown, money
```
