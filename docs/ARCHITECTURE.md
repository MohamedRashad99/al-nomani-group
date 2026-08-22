# Al Nomani Group ERP — System Architecture

**Company:** Al Nomani Group  
**Owner:** Ahmed Noman Al Jabri  
**Priority:** Data protection and data integrity above UI, speed, and simplicity.

## Authoritative data stores

| Store | Role | When it is authoritative |
| --- | --- | --- |
| Local Drift / SQLite (WASM on web) | Operational database | Always for daily work, including multi-day offline use |
| Central PostgreSQL | Server-of-record after sync | After a verified, idempotent sync commit |
| Google Sheets | Backup / visibility / recovery aid | Never transactional. Never primary. |

```
Flutter Web (Arabic RTL)
        │
        ▼
Local Drift transaction
  sale + items + inventory + account + audit + sync_queue
        │
        ▼
Persistent sync_queue  (survives refresh, restart, app update)
        │
        ▼  (when due AND online)
Dart Shelf backend
        │
        ▼
PostgreSQL transaction (idempotent by operation_id)
        │
        ▼
Google Sheets live backup  →  periodic full backup
```

The client **never** requires the internet to complete a sale, collection, inventory movement, or customer change.

## Versioning

| Field | Meaning |
| --- | --- |
| `app_version` | Flutter / server release (`1.0.0`) |
| `database_version` | Local Drift schema version (starts at `1`) |
| `sync_protocol_version` | Wire format between client and server (starts at `1`) |

On startup the app:

1. Opens the **existing** local database (never deletes it).
2. Runs versioned Drift migrations sequentially.
3. Verifies critical tables and the sync queue.
4. Starts the UI only after migration succeeds.

If migration fails, the app shows a recovery screen and refuses to write business data.

## Offline-first write path

Every business mutation is a single local transaction:

1. Validate locally (permissions, stock, money scale).
2. Persist entity + side effects (inventory, customer account).
3. Write an audit log row.
4. Enqueue a sync_queue row (`pending`).
5. Commit. On any failure: rollback.

The user sees success after the local commit. Sync is a later backup process.

## Synchronization

- Production default: `sync_interval_days = 5` (configurable, never hardcoded in business logic).
- Development: `sync_mode = near_realtime` (attempt after each local commit when online).
- Sync **never deletes** local business rows after upload.
- Retries keep the queue row; status is `pending` / `processing` / `synced` / `failed`.
- Idempotency key = `operation_id` (UUID). Server unique-constrains it.
- Conflicts are recorded, never silently overwritten (last-write-wins is forbidden when versions diverge).

## Multi-device

Each install has a persistent `device_id`. Important rows store `device_id`, `version`, `updated_at`. Multiple authorized devices may sync; the server detects version conflicts and stores them for admin reconciliation.

## Deployment

- Only `main` deploys production.
- `develop`, `feature/*`, `fix/*`, `test/*` never replace production.
- A new web build must migrate the existing IndexedDB / SQLite WASM database, not recreate it.
