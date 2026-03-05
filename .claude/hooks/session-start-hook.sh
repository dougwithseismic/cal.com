#!/bin/bash
# Hook: SessionStart — insert a new session row
DB_PATH="$CLAUDE_PROJECT_DIR/.claude/journal/journal.db"

# Read JSON from stdin
INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

if [ ! -f "$DB_PATH" ]; then
  exit 0
fi

# Insert or ignore (in case of resume with existing session)
sqlite3 "$DB_PATH" "INSERT OR IGNORE INTO sessions (id, started_at) VALUES ('$SESSION_ID', datetime('now'));"

exit 0
