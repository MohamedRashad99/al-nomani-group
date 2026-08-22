# REST API — `/api/v1`

Base URL is configured per environment (`API_BASE_URL`). All mutating routes require `Authorization: Bearer <jwt>` except login.

## Auth

| Method | Path | Auth | Description |
| --- | --- | --- | --- |
| POST | `/auth/login` | no | Username/password → JWT |
| POST | `/auth/refresh` | refresh | New access token |
| GET | `/auth/me` | yes | Current user + permissions |

## Sync (idempotent)

| Method | Path | Description |
| --- | --- | --- |
| POST | `/sync/push` | Upload a batch of queue operations. Each item has `operation_id`. Duplicates return the original result. |
| GET | `/sync/pull` | Changes since `since` / `cursor` for the device |
| GET | `/sync/status` | Server time, protocol version, last accepted op |
| POST | `/sync/conflicts/resolve` | Admin reconciliation |

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

## Resources

Standard CRUD (view/create/update, soft-delete or cancel) for:

- `/products` `/categories` `/customers` `/sales` `/collections`
- `/inventory/movements` `/users` `/roles`
- `/reports/sales` `/reports/debt` `/reports/inventory`
- `/backup/live` `/backup/full` `/reconciliation`

## Money

All money fields are **decimal strings** with a fixed scale of 3 (thousandths), e.g. `"12.500"`. Never IEEE floats.
