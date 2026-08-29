#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
jar_path="${1:-$repo_root/build/libs/telegram-mcp-server.jar}"
default_java_home="${HOME}/.local/opt/jdks/temurin-25.0.4.1/Contents/Home"
java_home="${TELEGRAM_MCP_JAVA_HOME:-$default_java_home}"

if [[ ! -x "$java_home/bin/java" ]]; then
  printf 'Java runtime is missing at %s\n' "$java_home" >&2
  exit 2
fi
if [[ ! -f "$jar_path" ]]; then
  printf 'Telegram MCP JAR is missing: %s\n' "$jar_path" >&2
  exit 2
fi

exec "$java_home/bin/java" --enable-native-access=ALL-UNNAMED \
  -jar "$jar_path" auth --account default --method qr
