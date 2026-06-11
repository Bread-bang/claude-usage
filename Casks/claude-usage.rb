# Homebrew Cask for Claude Usage.
#
# This file lives in your TAP repository, not the app repo. Create a repo named
# `homebrew-tap` under your account and place this at `Casks/claude-usage.rb`:
#
#   github.com/Bread-bang/homebrew-tap → Casks/claude-usage.rb
#
# Users then install with:
#   brew install bread-bang/tap/claude-usage
#
# After each release, bump `version` and replace `sha256` with the value printed by
# scripts/release.sh (or run `brew bump-cask-pr` once the cask is published).
cask "claude-usage" do
  version "0.1.0"
  sha256 "e437646de54235ad3f023d0b564ad8e1fd152879faf347dfb1bfdebfbe45e429"

  url "https://github.com/Bread-bang/claude-usage/releases/download/v#{version}/ClaudeUsage-#{version}.zip"
  name "Claude Usage"
  desc "Menu bar app showing Claude Code usage without launching Claude Code"
  homepage "https://github.com/Bread-bang/claude-usage"

  depends_on macos: :ventura

  app "Claude Usage.app"

  zap trash: [
    "~/Library/Preferences/com.github.bread-bang.claude-usage.plist",
  ]
end
