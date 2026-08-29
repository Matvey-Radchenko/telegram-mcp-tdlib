# Codex Singleton Deployment and Recovery

The fork branch `codex/singleton-http` and its `v1.16.0-codex.*` tags are the
source of truth for the Telegram MCP instance used by Codex. They preserve the
server changes, deployment scripts, rollback logic, and recovery instructions.

The repository never stores Telegram API credentials, the authorized TDLib
session, private chat IDs, or local MCP client configuration. On the same Mac,
preserve those files during recovery. On another Mac, create credentials and
authorize Telegram again.

## Supported topology

- One launchd-owned Streamable HTTP daemon listens on `127.0.0.1:8765`.
- Codex and OpenCode connect to `http://127.0.0.1:8765/mcp` as remote MCP
  clients.
- No Codex client starts a Telegram MCP STDIO child against the shared TDLib
  directory.
- The daemon is the only process allowed to own
  `~/Library/Application Support/TelegramMcpServer/tdlib/default/td.binlog`.
- Credentials remain in `~/.config/telegram-mcp`; they are not committed here.

The managed launcher refuses `serve --transport stdio` and refuses to start a
second server while another process owns the TDLib database.

## Local patch stack

Keep the commits independent and ordered:

1. `fix: return aggregate reactions for broadcast channels` — suitable for an
   upstream pull request.
2. `compat: omit content priority for Codex clients` — local workaround for the
   installed Rust MCP client's handling of `content[].annotations.priority`.
3. Local deployment scripts and this document — not an upstream product change.

## Stored recovery components

- `scripts/local/build-local.sh` — reproducible Java 25 build and full tests.
- `scripts/local/save-credentials.sh` — stores API credentials outside Git with
  mode `0600`.
- `scripts/local/auth-local.sh` — authorizes a fresh TDLib session locally.
- `scripts/local/install-launch-agent.sh` — generates a launchd definition for
  the current macOS user without hard-coded home paths.
- `scripts/local/manage-singleton.sh` — immutable release install, activation,
  health verification, and rollback.
- `scripts/local/smoke-singleton.sh` — read-only singleton and reaction-count
  verification using a target stored outside Git.

## Runtime paths

| Purpose | Path |
|---|---|
| Source repository | Any local clone of this fork |
| Java 25 toolchain | `TELEGRAM_MCP_JAVA_HOME`, or the documented local default |
| Managed releases | `~/.local/opt/telegram-mcp-codex/releases` |
| Active release | `~/.local/opt/telegram-mcp-codex/current` |
| Previous release | `~/.local/opt/telegram-mcp-codex/previous` |
| launchd definition | `~/Library/LaunchAgents/io.github.tolboy.telegram-mcp.plist` |
| Stable launcher | `~/.local/bin/telegram-mcp-codex` |
| Codex client config | `~/.codex/config.toml` |
| OpenCode client config | `~/.config/opencode/opencode.jsonc` |

## Build and install

Use a new local version for every changed artifact; never overwrite an existing
release directory.

```bash
scripts/local/build-local.sh 1.16.0-codex.1
scripts/local/manage-singleton.sh install 1.16.0-codex.1
```

The manager performs the only supported update sequence:

1. unload the launchd service;
2. wait for port `8765` and the TDLib lock to be released;
3. install the immutable JAR and atomically switch `current`;
4. load the launchd service;
5. run a read-only singleton and broadcast-reaction smoke test;
6. automatically restore the previous deployment if verification fails.

Do not copy a JAR over the file used by a running JVM.

## Restore on the current Mac

Do not delete either of these directories:

- `~/.config/telegram-mcp`
- `~/Library/Application Support/TelegramMcpServer/tdlib`

Then restore a tagged source version and install its JAR:

```bash
git clone https://github.com/Matvey-Radchenko/telegram-mcp-tdlib.git
cd telegram-mcp-tdlib
git switch --detach v1.16.0-codex.3
scripts/local/build-local.sh 1.16.0-codex.3
scripts/local/manage-singleton.sh install 1.16.0-codex.3
```

The tagged GitHub release also contains `telegram-mcp-server.jar`. It can be
passed as the optional third argument to `manage-singleton.sh install` instead
of building locally.

## Set up another Mac

1. Clone this fork and check out the latest `v1.16.0-codex.*` tag.
2. Install a complete JDK 25 and, when it is not at the documented default
   location, export `TELEGRAM_MCP_JAVA_HOME=/absolute/path/to/jdk/Contents/Home`.
3. Save Telegram application credentials locally:

   ```bash
   scripts/local/save-credentials.sh
   ```

4. Build the JAR, then authorize the `default` Telegram account. The auth
   command opens a nonce-protected loopback page and does not publish the QR or
   credentials:

   ```bash
   scripts/local/build-local.sh 1.16.0-codex.3
   scripts/local/auth-local.sh build/libs/telegram-mcp-server.jar
   ```

5. Create the private read-only smoke target. Use any channel post whose
   aggregate reactions the account can read:

   ```bash
   mkdir -p ~/.config/telegram-mcp
   cp scripts/local/smoke.env.example ~/.config/telegram-mcp/smoke.env
   chmod 600 ~/.config/telegram-mcp/smoke.env
   # Edit the two numeric values in ~/.config/telegram-mcp/smoke.env
   ```

6. Install and start the singleton:

   ```bash
   scripts/local/manage-singleton.sh install 1.16.0-codex.3
   ```

   When the launchd definition is missing, the manager generates it for the
   current macOS user. The default local profile enables inbox tools and writes,
   while keeping destructive-action confirmation enabled.

7. Point every MCP client at the same daemon. Codex needs this entry and no
   Telegram STDIO command:

   ```toml
   [mcp_servers.telegram]
   url = "http://127.0.0.1:8765/mcp"
   ```

   OpenCode uses a remote MCP entry with the same URL. Never configure either
   client to launch another Telegram process against the shared TDLib session.

## Verification and rollback

```bash
scripts/local/smoke-singleton.sh
scripts/local/manage-singleton.sh status
scripts/local/manage-singleton.sh rollback
```

The smoke test calls only `get_message_reactions` for the locally configured
post. It sends no Telegram message or reaction and changes no chat state.

## Updating from upstream

1. Fetch the upstream tag without starting another Telegram process.
2. Rebase the private maintenance branch onto that tag.
3. Drop any local commit already included upstream.
4. Resolve the compatibility commit separately; do not mix it into product
   fixes.
5. Build a new `X.Y.Z-codex.N` version.
6. Install through `manage-singleton.sh`; never patch the active JAR in place.
7. Publish a sanitized `codex/singleton-http` branch and a new immutable tag;
   never publish credentials, session files, or private smoke targets.
