#!/bin/bash
# List recent Messages conversations with contact names resolved.
# Usage: list-chats.sh [limit]   (default 15)
# Requires: Full Disk Access; run outside sandbox.
# Note: macOS /bin/bash is 3.2 — no associative arrays, hence awk.
set -euo pipefail

LIMIT="${1:-15}"
CHATDB="$HOME/Library/Messages/chat.db"

# Phone→name pairs from ALL contact sources (last 10 digits as key)
CONTACTS=$(
  for DB in "$HOME/Library/Application Support/AddressBook/Sources"/*/AddressBook-v22.abcddb; do
    [ -f "$DB" ] || continue
    sqlite3 -separator '|' "file:$DB?mode=ro" "
    SELECT TRIM(COALESCE(r.ZFIRSTNAME,'') || ' ' || COALESCE(r.ZLASTNAME,'')), p.ZFULLNUMBER
    FROM ZABCDPHONENUMBER p JOIN ZABCDRECORD r ON r.Z_PK = p.ZOWNER;" 2>/dev/null
  done
)

CHATS=$(sqlite3 -separator '|' "file:$CHATDB?mode=ro" "
SELECT
  COALESCE(NULLIF(c.display_name,''), c.chat_identifier),
  c.chat_identifier,
  COUNT(m.ROWID),
  datetime(MAX(m.date)/1000000000 + strftime('%s','2001-01-01'), 'unixepoch', 'localtime')
FROM chat c
JOIN chat_message_join cmj ON cmj.chat_id = c.ROWID
JOIN message m ON m.ROWID = cmj.message_id
GROUP BY c.ROWID
ORDER BY MAX(m.date) DESC
LIMIT $LIMIT;")

echo "NAME|IDENTIFIER|MSGS|LAST_MESSAGE"
awk -F'|' '
function last10(s,  d) { d = s; gsub(/[^0-9]/, "", d); return substr(d, length(d) - 9) }
NR == FNR { if ($1 != "" && $2 != "") names[last10($2)] = $1; next }
{
  name = $1
  if ($1 == $2 && $2 ~ /^\+/ && last10($2) in names) name = names[last10($2)]
  print name "|" $2 "|" $3 "|" $4
}
' <(echo "$CONTACTS") <(echo "$CHATS")
