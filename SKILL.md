---
name: mac-messages-contacts
description: "Query macOS Messages history (chat.db) and Contacts (AddressBook) via direct SQLite reads, and send iMessages (direct or group chats) via AppleScript. Use when asked to read texts, list iMessage conversations, search message history, look up a contact by name or phone number, resolve phone numbers to names, or send a text. Handles Full Disk Access, Apple epoch timestamps, multi-source contact databases, and group-chat send syntax."
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
8. **Tapbacks are messages too — filtering them out silently deletes replies.**
   `associated_message_type = 0` for a normal message; 2000–2005 are tapbacks
   (2000 heart, 2001 like, 2002 dislike, 2003 haha, 2004 emphasis, 2005 question;
   3000+ = removed). Filtering `COALESCE(associated_message_type,0)=0` to clean up a
   thread dump is correct for *reading* it and **wrong for any analysis of who
   reciprocates**. This produced a real false conclusion on 2026-08-05: Ady was
   reported as never answering three "I love you"s when she had hearted all three.
   Some people reply almost entirely in tapbacks — always count them before claiming
   someone didn't respond. Join reactions to their target with:
   `r.associated_message_guid LIKE '%' || t.guid` (the column is prefixed, e.g. `p:0/<guid>`).

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

### Group chats (verified 2026-07-08)

`send ... to buddy` only works for direct messages. For a group chat, target it
by chat id using the format `any;+;<chat_identifier>`, where `chat_identifier`
comes from the `chat` table in chat.db (a hex GUID like
`d4c1b2a3e5f6478899aabbccddeeff00` or a `chatNNN…` id):

```bash
osascript -e 'tell application "Messages" to send "text here" to chat id "any;+;CHAT_IDENTIFIER"'
```

Formats that FAIL:
- `"iMessage;+;<identifier>"` → error -1728 "Can't get chat id" (even though
  chat.db shows `service_name = iMessage`)
- dvdsgl-claude-imessage plugin's `send-to-chat.sh` → errors with
  "Can't get text (chat id …) of account id" even when given the correct id.
  Its `list-conversations.sh` is also broken (returns empty). Don't use the
  plugin's scripts — use direct osascript and this skill's read scripts.

### Attachments — file MUST live in `~/Pictures` (verified 2026-07-26)

Sending a file via AppleScript only works if the file is inside `~/Pictures`.
Messages.app is sandboxed and cannot read attachments from anywhere else
(`~/`, `~/Desktop`, `~/Documents`, `/tmp` all FAIL). A send from a bad location
does NOT error at the osascript layer — `osascript` exits 0, the row is created
with a progress bar, then flips to "Not Delivered": chat.db shows
`message.error = 34`, `is_sent = 0`, `attachment.transfer_state = 6`. Success
looks like `error = 0`, `is_sent = 1`, `transfer_state = 5`.

```bash
cp /tmp/report.png ~/Pictures/report.png
osascript <<'EOF'
set f to POSIX file "/Users/USERNAME/Pictures/report.png"
tell application "Messages"
    send f to buddy "+1XXXXXXXXXX" of (1st service whose service type is iMessage)
end tell
EOF
```

`message.error = 34` is an IMCore delivery error (daemon rejected the upload),
NOT the AppleScript language error 34 ("disk full") — different namespaces.
Note failed attempts leave stuck "Not Delivered" rows sender-side; they are
never delivered to the recipient, but clutter the sender's thread.

You cannot send by writing chat.db directly — the `imagent` daemon owns
delivery; an inserted row transmits nothing and writing the live DB risks
corruption. AppleScript is the only supported automation path.

After sending, verify by re-reading the thread from chat.db (allow a few
seconds for the message to land).
**Always confirm with the user before sending anything.**

## Troubleshooting

- **"unable to open database file"** in sandbox → retry with
  `dangerouslyDisableSandbox: true`; still failing → Full Disk Access (gotcha 2).
- **Contact not found but user says it's saved** → you searched one source; search
  all `Sources/*/` databases (gotcha 3).
- **Conversation names blank** → gotcha 4 (`NULLIF` on `display_name`).
- **Messages show NULL text** → body is in `attributedBody`; use
  `scripts/read-thread.sh` (gotcha 6).
