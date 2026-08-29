#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: build-local.sh VERSION

Builds and tests the local Telegram MCP release with a pinned Java 25 toolchain.
Set TELEGRAM_MCP_JAVA_HOME to override the default toolchain location.
USAGE
}

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  [[ $# -eq 1 ]] && exit 0
  exit 2
fi

release_version="$1"
if [[ ! "$release_version" =~ ^[0-9A-Za-z][0-9A-Za-z._-]*$ ]]; then
  printf 'Invalid release version: %s\n' "$release_version" >&2
  exit 2
fi

script_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
default_java_home="${HOME}/.local/opt/jdks/temurin-25.0.4.1/Contents/Home"
java_home="${TELEGRAM_MCP_JAVA_HOME:-$default_java_home}"

if [[ ! -x "$java_home/bin/java" || ! -x "$java_home/bin/javac" ]]; then
  printf 'Java 25 toolchain is missing at %s\n' "$java_home" >&2
  printf 'Set TELEGRAM_MCP_JAVA_HOME to a complete JDK 25 installation.\n' >&2
  exit 2
fi

java_major="$($java_home/bin/java -version 2>&1 | awk -F'[\".]' '/version/ { print $2; exit }')"
if [[ "$java_major" != "25" ]]; then
  printf 'Expected Java 25 at %s, found Java %s\n' "$java_home" "${java_major:-unknown}" >&2
  exit 2
fi

cd "$repo_root"
env \
  JAVA_HOME="$java_home" \
  PATH="$java_home/bin:$PATH" \
  ./gradlew test bootJar -PreleaseVersion="$release_version"

jar_path="$repo_root/build/libs/telegram-mcp-server.jar"
if [[ ! -f "$jar_path" ]]; then
  printf 'Expected build artifact was not created: %s\n' "$jar_path" >&2
  exit 1
fi

printf 'Built %s\n' "$jar_path"
shasum -a 256 "$jar_path"
