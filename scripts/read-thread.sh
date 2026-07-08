#!/bin/bash
# Read recent messages in one conversation, extracting text from attributedBody
# when the text column is NULL (common for sent messages).
# Usage: read-thread.sh <chat_identifier> [limit]
#   chat_identifier: phone (+13852965566), email, or group chat id (chat123...)
# Requires: Full Disk Access; run outside sandbox.
set -euo pipefail

IDENT="${1:?usage: read-thread.sh <chat_identifier> [limit]}"
LIMIT="${2:-20}"
CHATDB="$HOME/Library/Messages/chat.db"

sqlite3 -separator $'\t' "file:$CHATDB?mode=ro" "
SELECT
  datetime(m.date/1000000000 + strftime('%s','2001-01-01'), 'unixepoch', 'localtime'),
  CASE m.is_from_me WHEN 1 THEN 'me' ELSE COALESCE(h.id,'?') END,
  COALESCE(m.text,''),
  CASE WHEN m.text IS NULL AND m.attributedBody IS NOT NULL THEN hex(m.attributedBody) ELSE '' END
FROM message m
JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
JOIN chat c ON c.ROWID = cmj.chat_id
LEFT JOIN handle h ON h.ROWID = m.handle_id
WHERE c.chat_identifier = '$IDENT'
ORDER BY m.date DESC
LIMIT $LIMIT;" | python3 -c '
import sys

def extract_blob_text(hexstr):
    """Pull the NSString payload out of an NSKeyedArchiver attributedBody blob."""
    try:
        data = bytes.fromhex(hexstr)
        marker = b"NSString"
        i = data.find(marker)
        if i == -1:
            return "[unreadable]"
        i += len(marker) + 5  # skip class name + archiver framing
        if i >= len(data):
            return "[unreadable]"
        if data[i] == 0x81:  # 2-byte length
            length = int.from_bytes(data[i+1:i+3], "little")
            start = i + 3
        else:                # 1-byte length
            length = data[i]
            start = i + 1
        return data[start:start+length].decode("utf-8", errors="replace")
    except Exception:
        return "[unreadable]"

for line in sys.stdin:
    parts = line.rstrip("\n").split("\t")
    if len(parts) < 4:
        continue
    ts, sender, text, blob = parts[0], parts[1], parts[2], parts[3]
    if not text and blob:
        text = extract_blob_text(blob)
    if not text:
        text = "[attachment/no text]"
    print(f"[{ts}] {sender}: {text}")
' | tail -r
