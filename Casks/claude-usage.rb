cask "claude-usage" do
  version "0.2.0"
  sha256 "67c4b1e68ccf4c10e899c5d5b0f2565fa79a3621498e7e2d9a11c09b98500872"

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
