#!/usr/bin/env bash
set -euo pipefail

plist="${HOME}/Library/LaunchAgents/io.github.tolboy.telegram-mcp.plist"
launcher="${HOME}/.local/bin/telegram-mcp-codex"
stdout_log="${HOME}/Library/Logs/telegram-mcp.log"
stderr_log="${HOME}/Library/Logs/telegram-mcp.error.log"

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'The managed singleton launch agent currently supports macOS only.\n' >&2
  exit 2
fi
if [[ -f "$plist" ]]; then
  plutil -lint "$plist" >/dev/null
  printf 'LaunchAgent already exists: %s\n' "$plist"
  exit 0
fi

mkdir -p "$(dirname -- "$plist")" "${HOME}/Library/Logs"
temporary_plist="$(mktemp "${TMPDIR:-/tmp}/telegram-mcp-launch-agent.XXXXXX")"
trap 'rm -f -- "$temporary_plist"' EXIT

escape_xml() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\\&apos;/g"
}

escaped_home="$(escape_xml "$HOME")"
escaped_launcher="$(escape_xml "$launcher")"
escaped_stdout="$(escape_xml "$stdout_log")"
escaped_stderr="$(escape_xml "$stderr_log")"

cat > "$temporary_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>io.github.tolboy.telegram-mcp</string>
  <key>ProgramArguments</key>
  <array>
    <string>${escaped_launcher}</string>
    <string>serve</string>
    <string>--transport</string>
    <string>streamable-http</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${escaped_home}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>SERVER_ADDRESS</key><string>127.0.0.1</string>
    <key>SERVER_PORT</key><string>8765</string>
    <key>MCP_AUTH_MODE</key><string>api-key</string>
    <key>MCP_TOOL_PROFILE</key><string>inbox</string>
    <key>MCP_READ_ONLY</key><string>false</string>
    <key>MCP_CONFIRMATION_REQUIRED</key><string>true</string>
    <key>MCP_DESTRUCTIVE_APPROVAL</key><string>loopback</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>${escaped_stdout}</string>
  <key>StandardErrorPath</key><string>${escaped_stderr}</string>
</dict>
</plist>
PLIST

plutil -lint "$temporary_plist" >/dev/null
install -m 644 "$temporary_plist" "$plist"
printf 'Installed LaunchAgent: %s\n' "$plist"
