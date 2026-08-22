# REST API — `/api/v1`

Base URL is configured per environment (`API_BASE_URL`). All mutating routes require `Authorization: Bearer <jwt>` except login.

## Auth

| Method | Path | Auth | Description |
| --- | --- | --- | --- |
| POST | `/auth/login` | no | Username/password → JWT |
| POST | `/auth/refresh` | refresh | New access token |

## Sync (idempotent)

| Method | Path | Description |
| --- | --- | --- |
| POST | `/sync/push` | Upload a batch of queue operations. Each item has `operation_id`. Duplicates return the original result. |
| GET | `/sync/status` | Server time and protocol version |

Push body:

```json
{
  "device_id": "uuid",
  "app_version": "1.0.0",
  "sync_protocol_version": 1,
  "operations": [
    {
      "operation_id": "uuid",
      "entity_type": "sale",
      "entity_id": "uuid",
      "operation": "create",
      "payload": {},
      "version": 1,
      "created_at": "2026-08-22T00:00:00.000Z"
    }
  ]
}
```

Response per operation: `accepted` | `duplicate` | `conflict` | `rejected` with Arabic-safe `error_code`.

## Implemented resources

| Method | Path | Description |
| --- | --- | --- |
| GET | `/products` | Central product list |
| POST | `/users` | Admin online user provisioning/password update |
| GET | `/backup/health` | Durable Google outbox and full-backup health |
| POST | `/backup/retry` | Retry live backup outbox |
| POST | `/backup/full` | PostgreSQL full snapshot to the separate full spreadsheet |

Local conflict resolution is performed in the admin backup screen. Choosing the server applies its version locally; choosing local increments the version and retries the same idempotency key.

## Money

All money fields are **decimal strings** with a fixed scale of 3 (thousandths), e.g. `"12.500"`. Never IEEE floats.
