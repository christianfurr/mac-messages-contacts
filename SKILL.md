---
name: "Mac Messages & Contacts Query"
description: "Query macOS Messages history (chat.db) and Contacts (AddressBook) via direct SQLite reads. Use when asked to read texts, list iMessage conversations, search message history, look up a contact by name or phone number, or resolve phone numbers to names. Handles Full Disk Access, Apple epoch timestamps, and multi-source contact databases."
---

# Mac Messages & Contacts Query

## What This Skill Does

Reads the user's iMessage/SMS history and macOS Contacts by querying the SQLite
databases directly — no MCP server needed. Includes ready-to-run scripts and the
gotchas that make naive queries silently fail.

## Critical Gotchas (read before querying)

1. **Sandbox blocks `~/Library`** — every Bash call touching these databases needs
   `dangerouslyDisableSandbox: true`. Inside the sandbox, sqlite3 fails with
   "unable to open database file" even when the file is readable.
2. **Full Disk Access required** — if the query fails even outside the sandbox, the
   terminal app lacks FDA. Tell the user: System Settings → Privacy & Security →
   Full Disk Access → enable for the terminal app, then fully restart it.
3. **Contacts are split across MULTIPLE sources** — one database per account
   (iCloud, Google, etc.) under `~/Library/Application Support/AddressBook/Sources/*/`.
   **Always loop over ALL of them.** Searching only the first source silently misses
   contacts (this happened: a top contact lived in source 3 of 4).
4. **`chat.display_name` is empty string, not NULL, for direct chats** — use
   `COALESCE(NULLIF(display_name,''), chat_identifier)`.
5. **Apple epoch timestamps** — `message.date` is nanoseconds since 2001-01-01:
   `datetime(m.date/1000000000 + strftime('%s','2001-01-01'), 'unixepoch', 'localtime')`.
6. **Sent-message text often lives in `attributedBody` (binary blob), not `text`** —
   `scripts/read-thread.sh` extracts it with a python3 helper. Don't assume
   `text IS NULL` means empty message.
7. **Open read-only** — use `sqlite3 "file:$DB?mode=ro"` so Messages/Contacts apps
   aren't disturbed. Never write to these databases.

## Quick Start

```bash
SKILL=~/.claude/skills/mac-messages-contacts

# List recent conversations (with contact names resolved)
$SKILL/scripts/list-chats.sh 15

# Read a thread by phone number (last N messages)
$SKILL/scripts/read-thread.sh "+13855551234" 20

# Search contacts by name, number fragment, or email
$SKILL/scripts/contacts-search.sh "jane"
$SKILL/scripts/contacts-search.sh "3855551234"
```

All three scripts must run with `dangerouslyDisableSandbox: true`.

## Database Locations

| Data | Path |
|---|---|
| Messages | `~/Library/Messages/chat.db` |
| Contacts (per account) | `~/Library/Application Support/AddressBook/Sources/*/AddressBook-v22.abcddb` |

## Key Schema — Messages (chat.db)

- `message` — `text`, `attributedBody` (blob), `date` (Apple epoch ns), `is_from_me`,
  `handle_id`, `ROWID`
- `handle` — `id` (phone/email of the other party)
- `chat` — `chat_identifier` (phone, email, or `chat…` group id), `display_name`
  (group name; empty for direct)
- Joins: `chat_message_join` (chat_id ↔ message_id), `chat_handle_join`
- `message.is_from_me = 1` → sent by user

Example — last messages in one thread:

```sql
SELECT datetime(m.date/1000000000 + strftime('%s','2001-01-01'),'unixepoch','localtime'),
       CASE m.is_from_me WHEN 1 THEN 'me' ELSE h.id END,
       m.text
FROM message m
JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
JOIN chat c ON c.ROWID = cmj.chat_id
LEFT JOIN handle h ON h.ROWID = m.handle_id
WHERE c.chat_identifier = '+13855551234'
ORDER BY m.date DESC LIMIT 20;
```

## Key Schema — Contacts (AddressBook-v22.abcddb)

- `ZABCDRECORD` — `ZFIRSTNAME`, `ZLASTNAME`, `ZORGANIZATION`, `Z_PK`
- `ZABCDPHONENUMBER` — `ZFULLNUMBER`, `ZOWNER` → `ZABCDRECORD.Z_PK`
- `ZABCDEMAILADDRESS` — `ZADDRESS`, `ZOWNER`

Phone formats vary (`+13855551234` vs `+1 (385) 555-1234`) — normalize before
matching:

```sql
REPLACE(REPLACE(REPLACE(REPLACE(ZFULLNUMBER,'(',''),')',''),'-',''),' ','') LIKE '%3855551234'
```

Match on the last 10 digits, and always loop over every `Sources/*/` database.

## Sending Messages

Reading uses SQLite; **sending uses AppleScript** (separate macOS permission,
prompted on first use):

```bash
osascript -e 'tell application "Messages" to send "text here" to buddy "+13855551234" of (service 1 whose service type is iMessage)'
```

The dvdsgl-claude-imessage plugin's send scripts also work
(`send-message.sh`, `send-to-chat.sh` for groups). Its `list-conversations.sh`
read script is broken (returns empty) — use this skill's scripts instead.
**Always confirm with the user before sending anything.**

## Troubleshooting

- **"unable to open database file"** in sandbox → retry with
  `dangerouslyDisableSandbox: true`; still failing → Full Disk Access (gotcha 2).
- **Contact not found but user says it's saved** → you searched one source; search
  all `Sources/*/` databases (gotcha 3).
- **Conversation names blank** → gotcha 4 (`NULLIF` on `display_name`).
- **Messages show NULL text** → body is in `attributedBody`; use
  `scripts/read-thread.sh` (gotcha 6).
