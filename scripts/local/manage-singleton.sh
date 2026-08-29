#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  manage-singleton.sh install VERSION [JAR]
  manage-singleton.sh activate VERSION
  manage-singleton.sh rollback
  manage-singleton.sh status

Installs and switches versioned Telegram MCP JARs while the launchd singleton is
fully stopped. A failed read-only smoke test automatically restores the previous
managed release or the pre-managed launcher.
USAGE
}

script_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
repo_root="$(cd -- "$script_dir/../.." && pwd -P)"
install_root="${HOME}/.local/opt/telegram-mcp-codex"
releases_root="$install_root/releases"
current_link="$install_root/current"
previous_link="$install_root/previous"
launcher_source="$script_dir/telegram-mcp-codex"
launcher_target="${HOME}/.local/bin/telegram-mcp-codex"
launch_agent_installer="$script_dir/install-launch-agent.sh"
legacy_root="$install_root/legacy"
legacy_launcher="$legacy_root/telegram-mcp-codex.before-managed"
plist="${HOME}/Library/LaunchAgents/io.github.tolboy.telegram-mcp.plist"
label="io.github.tolboy.telegram-mcp"
domain="gui/$(id -u)"
service_target="$domain/$label"

require_version() {
  local version="$1"
  if [[ ! "$version" =~ ^[0-9A-Za-z][0-9A-Za-z._-]*$ ]]; then
    printf 'Invalid release version: %s\n' "$version" >&2
    exit 2
  fi
}

stop_service() {
  if launchctl print "$service_target" >/dev/null 2>&1; then
    launchctl bootout "$service_target"
  fi

  local attempt
  for attempt in $(seq 1 30); do
    if ! lsof -nP -t -iTCP:8765 -sTCP:LISTEN >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  printf 'Telegram MCP did not release port 8765 after 30 seconds\n' >&2
  return 1
}

start_service() {
  launchctl bootstrap "$domain" "$plist"
  launchctl kickstart "$service_target"

  local attempt
  for attempt in $(seq 1 45); do
    if curl --noproxy '*' --silent --fail --max-time 2 \
      http://127.0.0.1:8765/actuator/health >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  printf 'Telegram MCP did not become healthy after 45 seconds\n' >&2
  return 1
}

set_link() {
  local link_path="$1"
  local target="$2"
  local temporary_link="$install_root/.link.$$.tmp"
  rm -f -- "$temporary_link"
  ln -s "$target" "$temporary_link"
  mv -fh -- "$temporary_link" "$link_path"
}

restore_legacy() {
  stop_service || true
  if [[ -L "$current_link" ]]; then
    set_link "$previous_link" "$(readlink "$current_link")"
    rm -f -- "$current_link"
  fi
  if [[ -f "$legacy_launcher" ]]; then
    install -m 700 "$legacy_launcher" "$launcher_target"
  fi
  start_service
}

activate_release() {
  local version="$1"
  local release_dir="$releases_root/$version"
  local release_jar="$release_dir/telegram-mcp-server.jar"
  local prior_target=""

  require_version "$version"
  if [[ ! -f "$release_jar" ]]; then
    printf 'Managed release is missing: %s\n' "$release_jar" >&2
    exit 2
  fi
  if [[ ! -f "$plist" ]]; then
    "$launch_agent_installer"
  fi
  if [[ -L "$current_link" ]]; then
    prior_target="$(readlink "$current_link")"
  fi

  mkdir -p "$install_root" "$legacy_root" "${HOME}/.local/bin"
  if [[ ! -f "$legacy_launcher" && -f "$launcher_target" ]]; then
    install -m 700 "$launcher_target" "$legacy_launcher"
  fi

  stop_service
  install -m 700 "$launcher_source" "$launcher_target"
  set_link "$current_link" "releases/$version"

  if ! start_service || ! "$script_dir/smoke-singleton.sh"; then
    printf 'Activation of %s failed; restoring previous deployment\n' "$version" >&2
    stop_service || true
    if [[ -n "$prior_target" ]]; then
      set_link "$current_link" "$prior_target"
      start_service
    else
      rm -f -- "$current_link"
      if [[ -f "$legacy_launcher" ]]; then
        install -m 700 "$legacy_launcher" "$launcher_target"
      fi
      start_service
    fi
    exit 1
  fi

  if [[ -n "$prior_target" && "$prior_target" != "releases/$version" ]]; then
    set_link "$previous_link" "$prior_target"
  fi
  printf 'Activated Telegram MCP release %s\n' "$version"
}

install_release() {
  local version="$1"
  local jar_path="${2:-$repo_root/build/libs/telegram-mcp-server.jar}"
  local release_dir="$releases_root/$version"
  local release_jar="$release_dir/telegram-mcp-server.jar"

  require_version "$version"
  if [[ ! -f "$jar_path" ]]; then
    printf 'Build artifact is missing: %s\n' "$jar_path" >&2
    exit 2
  fi

  mkdir -p "$release_dir"
  if [[ -f "$release_jar" ]]; then
    local source_hash installed_hash
    source_hash="$(shasum -a 256 "$jar_path" | awk '{ print $1 }')"
    installed_hash="$(shasum -a 256 "$release_jar" | awk '{ print $1 }')"
    if [[ "$source_hash" != "$installed_hash" ]]; then
      printf 'Release %s already exists with a different JAR; choose a new version\n' "$version" >&2
      exit 2
    fi
  else
    install -m 600 "$jar_path" "$release_jar"
  fi
  activate_release "$version"
}

rollback_release() {
  if [[ -L "$previous_link" ]]; then
    local target version
    target="$(readlink "$previous_link")"
    version="${target##*/}"
    activate_release "$version"
    return
  fi
  if [[ -f "$legacy_launcher" ]]; then
    restore_legacy
    printf 'Restored the pre-managed Telegram MCP launcher\n'
    return
  fi
  printf 'No previous managed release or legacy launcher is available\n' >&2
  exit 2
}

status() {
  printf 'current=%s\n' "$(readlink "$current_link" 2>/dev/null || printf 'legacy')"
  printf 'previous=%s\n' "$(readlink "$previous_link" 2>/dev/null || printf 'none')"
  if launchctl print "$service_target" >/dev/null 2>&1; then
    printf 'launchd=loaded\n'
  else
    printf 'launchd=not-loaded\n'
  fi
  printf 'listeners=%s\n' "$(lsof -nP -t -iTCP:8765 -sTCP:LISTEN 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//' || true)"
  printf 'tdlibOwners=%s\n' "$(lsof -t -- "${HOME}/Library/Application Support/TelegramMcpServer/tdlib/default/td.binlog" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//' || true)"
}

command_name="${1:-}"
case "$command_name" in
  install)
    [[ $# -ge 2 && $# -le 3 ]] || { usage; exit 2; }
    install_release "$2" "${3:-$repo_root/build/libs/telegram-mcp-server.jar}"
    ;;
  activate)
    [[ $# -eq 2 ]] || { usage; exit 2; }
    activate_release "$2"
    ;;
  rollback)
    [[ $# -eq 1 ]] || { usage; exit 2; }
    rollback_release
    ;;
  status)
    [[ $# -eq 1 ]] || { usage; exit 2; }
    status
    ;;
  -h|--help|"")
    usage
    ;;
  *)
    printf 'Unknown command: %s\n' "$command_name" >&2
    usage
    exit 2
    ;;
esac
