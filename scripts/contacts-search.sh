#!/bin/bash
# Search ALL macOS Contacts sources by name, phone fragment, email, or org.
# Usage: contacts-search.sh <query>
# Requires: Full Disk Access; run outside sandbox.
set -euo pipefail

QUERY="${1:?usage: contacts-search.sh <query>}"
DIGITS=$(echo "$QUERY" | tr -dc '0-9')

for DB in "$HOME/Library/Application Support/AddressBook/Sources"/*/AddressBook-v22.abcddb; do
  [ -f "$DB" ] || continue
  if [ -n "$DIGITS" ] && [ ${#DIGITS} -ge 7 ]; then
    PHONE_CLAUSE="OR REPLACE(REPLACE(REPLACE(REPLACE(COALESCE(p.ZFULLNUMBER,''),'(',''),')',''),'-',''),' ','') LIKE '%$DIGITS%'"
  else
    PHONE_CLAUSE=""
  fi
  sqlite3 -separator '|' "file:$DB?mode=ro" "
  SELECT DISTINCT
    TRIM(COALESCE(r.ZFIRSTNAME,'') || ' ' || COALESCE(r.ZLASTNAME,'')),
    COALESCE(r.ZORGANIZATION,''),
    COALESCE(p.ZFULLNUMBER,''),
    COALESCE(e.ZADDRESS,'')
  FROM ZABCDRECORD r
  LEFT JOIN ZABCDPHONENUMBER p ON p.ZOWNER = r.Z_PK
  LEFT JOIN ZABCDEMAILADDRESS e ON e.ZOWNER = r.Z_PK
  WHERE r.ZFIRSTNAME LIKE '%$QUERY%'
     OR r.ZLASTNAME LIKE '%$QUERY%'
     OR r.ZORGANIZATION LIKE '%$QUERY%'
     OR e.ZADDRESS LIKE '%$QUERY%'
     $PHONE_CLAUSE;" 2>/dev/null
done | sort -u
