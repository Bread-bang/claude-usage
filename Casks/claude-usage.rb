cask "claude-usage" do
  version "0.4.3"
  sha256 "e3613a021829bfdb3e2cda1624f038b996b269eb78901d64c90fd54e46286bb3"

  url "https://github.com/Bread-bang/claude-usage/releases/download/v#{version}/ClaudeUsage-#{version}.zip"
  name "Claude Usage"
  desc "Menu bar app showing Claude Code usage without launching Claude Code"
  homepage "https://github.com/Bread-bang/claude-usage"

  depends_on macos: :ventura

  app "Claude Usage.app"

  zap trash: "~/Library/Preferences/com.github.bread-bang.claude-usage.plist"

  caveats <<~EOS
    Claude Usage lives in the menu bar and has no Dock icon. Launch it with:

      open -a "Claude Usage"

    or from Spotlight / Launchpad. It reads your usage from Claude Code, so make sure
    you have signed in once (run `claude`). To start it automatically, add it under
    System Settings → General → Login Items.
  EOS
end
