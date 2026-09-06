# Patched backend and external gateway

This fork is the recoverable source for the patched **Telegram backend**, not a
process supervisor. Its historical default branch remains `codex/singleton-http`;
the branch name does not imply that current code installs a singleton wrapper.

## Preserved patches

- Broadcast-channel reaction counts come from `message.interactionInfo.reactions`.
  When Telegram disallows enumerating reactors (`BROADCAST_FORBIDDEN`), the tool
  still returns available aggregate counts, without pretending to know identities.
- Content annotations omit the optional `priority` field for Codex compatibility.
- The canonical upload-path test accepts the platform's resolved temporary path.

The old local launch-agent installer, shell singleton launcher/manager and its HTTP
smoke script have been removed. Upstream stdio and HTTP transports remain available.
Historical `v1.16.0-codex.*` tags retain older deployments for explicit rollback.

## Build or restore on another device

1. Clone this fork's default branch (not upstream's release binary).
2. Install a complete Java 25 JDK; set `TELEGRAM_MCP_JAVA_HOME` if it is not at the
   local build helper's default location.
3. Run `scripts/local/build-local.sh 1.16.0-codex.4`. This runs tests and builds
   `build/libs/telegram-mcp-server.jar`. Keep the JAR together with its checksum.
4. Obtain your own Telegram API ID/hash. `scripts/local/save-credentials.sh`
   stores them privately outside Git. Supply `TDLIB_API_ID` and
   `TDLIB_API_HASH_FILE` to the process; never commit their values.
5. With every other owner of the target TDLib directory stopped, authenticate
   using `scripts/local/auth-local.sh` (with the credential environment set),
   or the upstream `auth` CLI documented in the README.
6. Configure your external gateway as below. The gateway is a separate project;
   this fork alone does not install or reconstruct it.

## Backend contract for an external gateway

Start the tested JAR directly, without a shell wrapper:

```text
/absolute/java --enable-native-access=ALL-UNNAMED -jar /absolute/telegram-mcp-server.jar serve --transport stdio
```

Use a shared, lazy backend with exactly one worker for this account-data directory.
Use private credentials and explicit data paths. Retain the intended policy:

```text
TDLIB_API_ID=<private credential>
TDLIB_API_HASH_FILE=/absolute/private/api-hash
TELEGRAM_MCP_DATA_DIR=/absolute/private/application-data
TDLIB_DATA_DIR=/absolute/private/application-data/tdlib/default
MCP_TOOL_PROFILE=inbox
MCP_READ_ONLY=false
MCP_CONFIRMATION_REQUIRED=true
MCP_DESTRUCTIVE_APPROVAL=loopback
SPRING_AI_MCP_SERVER_CAPABILITIES_COMPLETION=false
```

These are example policy settings, not a recommendation to enable writes for every
installation. For read-only use set `MCP_READ_ONLY=true`. Keep destructive approval
enabled. The gateway must not impersonate a user's confirmation. HTTP authentication
is enforced by the gateway; clients connect to its authenticated loopback MCP URL.
Spring advertises completion by default even though this backend has no completion
handlers; turn it off for a gateway that does not implement that optional capability.

With `mcp-session-gateway`, use the generic stdio profile, `ownership="shared"`,
`max_workers=1`, and `shared_client_roots="ignore"`: this account API does not use
the calling project's filesystem roots. Set `command` to Java, `command_args` to
`["--enable-native-access=ALL-UNNAMED", "-jar"]`, `entrypoint` to the JAR, and `args`
to `["serve", "--transport", "stdio"]`. The runtime pins the artifact and catalog.
Private environment-file references can supply both API credentials instead of
embedding secrets in configuration. Keep the account registry/confirmation storage
at their established locations as well as the TDLib data directory.

## Cutover and rollback invariants

- Stop/disable the previous service and verify it has released TDLib files **before**
  catalog discovery, authentication, or launching a replacement backend. Discovery
  itself starts a process; it is not safe alongside an existing owner of the same DB.
- Back up session/account data privately while offline. Do not copy it into Git or
  create a second concurrently running installation from that backup.
- Verify discovery, read-only history and aggregate reaction retrieval. Test two
  clients against the same gateway and verify there is exactly one TDLib owner.
- Do not validate with messages, reactions, joins, deletes or other Telegram writes.
- Update all clients that used the old endpoint; restart clients retaining old MCP
  connections. Keep old runtime artifacts and disabled service definitions until the
  new deployment is accepted.
- To roll back, stop the new gateway, verify TDLib files are released, restore the
  previous service and client endpoint. Never enable both services simultaneously.

Tokens, account registry, auth/session material and local service configuration are
device-local recovery assets. On a new device, reauthentication may be necessary.
