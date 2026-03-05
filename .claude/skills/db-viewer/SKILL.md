---
description: Open the journal SQLite database in DB Browser for SQLite GUI
disable-model-invocation: true
---

# /db-viewer

Opens the journal database (`$CLAUDE_PROJECT_DIR/.claude/journal/journal.db`) in DB Browser for SQLite.

## Usage

```
/db-viewer           # Open the journal database
/db-viewer <path>    # Open a specific SQLite database file
```

## Instructions

1. Determine which database to open:
   - If the user provided a `<path>` argument, use that path
   - Otherwise default to `$CLAUDE_PROJECT_DIR/.claude/journal/journal.db`

2. Verify the database file exists using the Read tool (just check existence, don't read content)

3. Launch DB Browser for SQLite:
   ```bash
   start "" "C:/Users/GODZILLA/scoop/apps/sqlitebrowser/current/DB Browser for SQLite.exe" "<db-path>" &
   ```

4. Confirm to the user that the viewer has been launched and which database was opened.

## Notes

- DB Browser for SQLite was installed via scoop (`scoop install extras/sqlitebrowser`)
- The journal database contains tables: `entries`, `sessions`, `compaction_snapshots`, `tool_usage`
- If the GUI doesn't launch, suggest the user check that sqlitebrowser is installed: `scoop list | grep sqlite`
