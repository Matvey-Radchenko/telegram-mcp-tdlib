#!/usr/bin/env bash
set -euo pipefail

endpoint="${TELEGRAM_MCP_ENDPOINT:-http://127.0.0.1:8765/mcp}"
health_endpoint="${TELEGRAM_MCP_HEALTH_ENDPOINT:-http://127.0.0.1:8765/actuator/health}"
smoke_config="${TELEGRAM_MCP_SMOKE_CONFIG:-${HOME}/.config/telegram-mcp/smoke.env}"
if [[ -f "$smoke_config" ]]; then
  # The file is local-only and should be mode 0600. It contains no executable
  # secrets, only the read-only regression target.
  # shellcheck disable=SC1090
  source "$smoke_config"
fi
chat_id="${TELEGRAM_MCP_SMOKE_CHAT_ID:-}"
message_id="${TELEGRAM_MCP_SMOKE_MESSAGE_ID:-}"
tdlib_log="${HOME}/Library/Application Support/TelegramMcpServer/tdlib/default/td.binlog"
codex_config="${HOME}/.codex/config.toml"
opencode_config="${HOME}/.config/opencode/opencode.jsonc"
protocol_version="2025-06-18"

if [[ -z "$chat_id" || -z "$message_id" ]]; then
  printf 'Smoke target is missing. Copy scripts/local/smoke.env.example to %s and fill both IDs.\n' \
    "$smoke_config" >&2
  exit 2
fi
if [[ ! "$chat_id" =~ ^-?[0-9]+$ || ! "$message_id" =~ ^[0-9]+$ ]]; then
  printf 'Smoke target IDs must be integers: %s\n' "$smoke_config" >&2
  exit 2
fi

for command_name in curl lsof python3; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Required command is unavailable: %s\n' "$command_name" >&2
    exit 2
  fi
done

if [[ ! -f "$codex_config" ]] || \
  ! grep -q '^\[mcp_servers\.telegram\]$' "$codex_config" || \
  ! grep -q '^url = "http://127\.0\.0\.1:8765/mcp"$' "$codex_config"; then
  printf 'Codex is not configured for the singleton Telegram MCP endpoint\n' >&2
  exit 1
fi
if grep -Eq 'command = .*telegram-mcp|--transport[[:space:]]+stdio' "$codex_config"; then
  printf 'Codex still contains a local Telegram STDIO configuration\n' >&2
  exit 1
fi

if [[ -f "$opencode_config" ]]; then
  if ! grep -q '"url": "http://127\.0\.0\.1:8765/mcp"' "$opencode_config" || \
    grep -q 'Documents/Codex/mcp-servers/telegram-mcp' "$opencode_config"; then
    printf 'OpenCode is not configured exclusively for the singleton Telegram MCP endpoint\n' >&2
    exit 1
  fi
fi

listener_pids="$(lsof -nP -t -iTCP:8765 -sTCP:LISTEN 2>/dev/null | sort -u)"
listener_count="$(printf '%s\n' "$listener_pids" | awk 'NF { count++ } END { print count + 0 }')"
if [[ "$listener_count" -ne 1 ]]; then
  printf 'Expected exactly one listener on 127.0.0.1:8765, found %s: %s\n' \
    "$listener_count" "${listener_pids:-none}" >&2
  exit 1
fi

owner_pids="$(lsof -t -- "$tdlib_log" 2>/dev/null | sort -u)"
owner_count="$(printf '%s\n' "$owner_pids" | awk 'NF { count++ } END { print count + 0 }')"
if [[ "$owner_count" -ne 1 || "$owner_pids" != "$listener_pids" ]]; then
  printf 'TDLib owner mismatch; listener=%s owner=%s\n' \
    "$listener_pids" "${owner_pids:-none}" >&2
  exit 1
fi

health_status="$(curl --noproxy '*' --silent --show-error --fail --max-time 15 "$health_endpoint" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status", ""))')"
if [[ "$health_status" != "UP" ]]; then
  printf 'Telegram MCP health is not UP: %s\n' "${health_status:-missing}" >&2
  exit 1
fi

TELEGRAM_MCP_SMOKE_ENDPOINT="$endpoint" \
TELEGRAM_MCP_SMOKE_PROTOCOL="$protocol_version" \
TELEGRAM_MCP_SMOKE_CHAT="$chat_id" \
TELEGRAM_MCP_SMOKE_MESSAGE="$message_id" \
TELEGRAM_MCP_LISTENER_PID="$listener_pids" \
python3 <<'PY'
import json
import os
import urllib.request

endpoint = os.environ["TELEGRAM_MCP_SMOKE_ENDPOINT"]
protocol = os.environ["TELEGRAM_MCP_SMOKE_PROTOCOL"]
chat_id = int(os.environ["TELEGRAM_MCP_SMOKE_CHAT"])
message_id = int(os.environ["TELEGRAM_MCP_SMOKE_MESSAGE"])
api_key = os.environ.get("MCP_API_KEY", "")


def decode_payload(raw: bytes):
    text = raw.decode("utf-8").strip()
    data_lines = [line[5:].lstrip() for line in text.splitlines() if line.startswith("data:")]
    return json.loads("\n".join(data_lines) if data_lines else text)


def post(payload, session_id=None):
    headers = {
        "Accept": "application/json, text/event-stream",
        "Content-Type": "application/json",
        "MCP-Protocol-Version": protocol,
    }
    if session_id:
        headers["Mcp-Session-Id"] = session_id
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(payload, separators=(",", ":")).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return response.headers, response.read()


headers, raw = post({
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": protocol,
        "capabilities": {},
        "clientInfo": {"name": "telegram-mcp-singleton-smoke", "version": "1.0.0"},
    },
})
initialize = decode_payload(raw)
if initialize.get("error"):
    raise SystemExit(f"initialize failed: {initialize['error']}")
session_id = headers.get("Mcp-Session-Id")
if not session_id:
    raise SystemExit("initialize returned no Mcp-Session-Id")

post({
    "jsonrpc": "2.0",
    "method": "notifications/initialized",
    "params": {},
}, session_id)

_, raw = post({
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
        "name": "get_message_reactions",
        "arguments": {
            "account": "default",
            "chat_id": chat_id,
            "message_id": message_id,
            "limit": 100,
        },
    },
}, session_id)
result = decode_payload(raw)
if result.get("error"):
    raise SystemExit(f"get_message_reactions failed: {result['error']}")

tool_result = result.get("result", {})
if tool_result.get("isError"):
    raise SystemExit(f"get_message_reactions returned an error: {tool_result}")
data = tool_result.get("structuredContent", {}).get("data", {})
counts = data.get("reactionCounts")
if data.get("chatId") != chat_id or data.get("messageId") != message_id:
    raise SystemExit(f"unexpected message identity: {data}")
if not isinstance(counts, list):
    raise SystemExit(f"aggregate reaction counts are missing: {data}")
calculated_total = sum(item.get("totalCount", 0) for item in counts)
if data.get("totalCount") != calculated_total:
    raise SystemExit(f"reaction total mismatch: {data}")

print(json.dumps({
    "listenerPid": int(os.environ.get("TELEGRAM_MCP_LISTENER_PID", "0")) or None,
    "serverVersion": initialize.get("result", {}).get("serverInfo", {}).get("version"),
    "chatId": chat_id,
    "messageId": message_id,
    "reactionCounts": counts,
    "totalCount": calculated_total,
    "canGetAddedReactions": data.get("canGetAddedReactions"),
    "telegramWrites": 0,
}, ensure_ascii=False, separators=(",", ":")))
PY

printf 'Singleton verified: listener=%s TDLib-owner=%s health=%s\n' \
  "$listener_pids" "$owner_pids" "$health_status"
