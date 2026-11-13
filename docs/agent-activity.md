# AI agent activity on the Touch Bar

The **AI Activity** menu shows running work. It removes sessions when the provider reports that they finished or are waiting for permission. Tap an item to open its Codex chat or bring the terminal or editor hosting it to the front, when the integration supplies a destination.

## Connect Codex

The local installer adds Pock's Codex hooks automatically when it finds a Codex configuration directory. The installed app also sets them up the first time you open **AI Activity**. Existing hooks are preserved.

Approve the Pock Community entries in **Settings → Hooks** in Codex or with `/hooks` in the CLI. Codex requires this review before it runs new hook commands. Pock's hook commands verify the bundled script's SHA-256 before running it. A change to the script requires a new review. [Codex hooks](https://learn.chatgpt.com/docs/hooks#review-and-trust-hooks)

## Connect Claude Code or Gemini CLI

From a checkout you intend to keep, generate the configuration for your provider.

```sh
/usr/bin/ruby scripts/pock-agent-activity.rb claude --config
/usr/bin/ruby scripts/pock-agent-activity.rb gemini --config
```

Each command prints JSON with the script's absolute path. Add its `hooks` entries to the appropriate file and preserve the existing entries for each event. A new file can use the complete generated JSON.

| Agent | User-level configuration | Activation |
| --- | --- | --- |
| Claude Code | `~/.claude/settings.json` | Start a new session or restart Claude Code. |
| Gemini CLI | `~/.gemini/settings.json` | Start a new session or restart Gemini CLI with hooks enabled. |

Start a turn and open **AI Activity**. The card shows the project folder name, or a generic session label when no project name is available. The integration writes the session ID, project label, process ID, expiry time, and optional destination to a local file. It discards prompt and response text. Processing and storage stay on this Mac.

The hooks publish and renew an activity record when the provider reports work. They remove it on the corresponding stop, session-end, or permission events. If a provider exits unexpectedly, Pock hides records from its stopped process. Providers can skip an end hook on cancellation, so records also expire after ten minutes without a new activity signal. A long operation with no events can disappear until its next activity signal. [Codex hooks](https://learn.chatgpt.com/docs/hooks), [Claude Code hooks](https://code.claude.com/docs/en/hooks), [Gemini CLI hooks](https://geminicli.com/docs/hooks/reference/)

Disable Pock's entries in **Settings → Hooks** or `/hooks` to disconnect Codex. For Claude Code or Gemini CLI, remove the generated entries from the provider's configuration before moving or deleting the script.

## Connect another local agent

An integration can publish one `.json` file per active session under `~/Library/Application Support/Pock/AgentActivity/`. Write through a temporary file and rename it into place so Pock can read a complete record. Use a process ID that remains alive for the run, and refresh the expiration while the session is active. Remove the record when the run finishes, is cancelled, or enters an idle or waiting state.

| Field | Value |
| --- | --- |
| `provider` | Provider display name. |
| `id` | Stable session identifier for that provider. |
| `title` | Short label to display on the Touch Bar. |
| `pid` | Live process ID for the local runner. |
| `expiresAt` | Expiration time in Unix seconds. |
| `url` | Optional HTTPS chat link or a Codex thread URL. |
| `bundleIdentifier` | Optional macOS app to activate. |

OpenCode v1 provides `GET /session/status` on its local server. A bridge for that version can publish `busy` and `retry` sessions, remove records when they become `idle` or disappear from the response, and clear the records on disconnect. [OpenCode v1 server API](https://opencode.ai/v1/docs/server/#sessions)

The Codex, Claude, and Gemini marks identify their respective integrations. They come from the ChatGPT app resources, the [Anthropic press kit](https://www.anthropic.com/press-kit), and the [Gemini website](https://gemini.google.com/).
