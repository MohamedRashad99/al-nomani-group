# Data reconciliation

Admin compares three stores. None may silently overwrite another.

| Store | Role |
| --- | --- |
| Local Drift | Operational truth while offline |
| PostgreSQL | Server-of-record after verified sync |
| Google Sheets | Backup only |

The Backup screen lists pending, failed, and synced queue rows. Conflicts are stored in `conflicts` (`open` until an admin resolves them). Resolution writes an audit row and never deletes the losing payload.
