# mac-messages-contacts

A Claude Code skill for querying macOS Messages history and Contacts directly
via SQLite — no MCP server required.

## What it does

- **List conversations** with contact names auto-resolved across all contact sources
- **Read threads** including sent messages whose text is buried in the
  `attributedBody` binary blob
- **Search contacts** by name, phone fragment, email, or organization across
  every account database (iCloud, Google, local, …)

See [SKILL.md](SKILL.md) for the full schema reference and the seven gotchas
that make naive queries silently fail (Full Disk Access, sandbox, Apple epoch
timestamps, multi-source contacts, and more).

## Install

```bash
./install.sh          # symlink into ~/.claude/skills (edits here stay live)
./install.sh --copy   # or copy instead, if symlinked skills aren't picked up
```

Then restart Claude Code. Asking about your texts or contacts triggers the
skill automatically.

## Requirements

- macOS with Messages signed in
- **Full Disk Access** for your terminal app
  (System Settings → Privacy & Security → Full Disk Access, then restart the app)
- `sqlite3` and `python3` (both ship with macOS)

## Scripts

| Script | Usage |
|---|---|
| `scripts/list-chats.sh [limit]` | Recent conversations, names resolved |
| `scripts/read-thread.sh <identifier> [limit]` | Read one thread (phone, email, or group chat id) |
| `scripts/contacts-search.sh <query>` | Search all contact sources |

All reads are strictly read-only (`mode=ro`). Sending messages is out of scope
for the scripts — SKILL.md documents the AppleScript path for that.
