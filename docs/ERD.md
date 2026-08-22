# Database ERD (logical)

Shared by local Drift and PostgreSQL. IDs are UUID strings. Money is `NUMERIC(18,3)` / TEXT decimal. Soft delete: `is_deleted`, `deleted_at`, `deleted_by`. Versioning: `version`, `device_id`, `created_at`, `updated_at`.

```
roles 1──* users
roles *──* permissions  (role_permissions)

product_categories 1──* products
products 1──* inventory_movements
products 1──* sale_items

customers 1──1 customer_accounts
customer_accounts 1──* customer_account_transactions
customers 1──* sales
customers 1──* collections

sales 1──* sale_items
sales 1──* customer_account_transactions
collections 1──* customer_account_transactions

users 1──* audit_logs
sync_queue (client only, also mirrored as sync_operations on server)
sync_logs
conflicts
app_metadata
settings
```

## Inventory

`products.current_stock` is a cached decimal quantity. The source of truth for history is `inventory_movements` (`previous_stock`, `new_stock`, `quantity`, `type`, `reference_type`, `reference_id`).

## Customer balance

Never overwrite a single balance field as the source of truth.  
`customer_accounts.cached_balance` is derived from `customer_account_transactions` (sale +, payment −, cancel −/+).

## Sync queue (local)

`id, entity_type, entity_id, operation, payload, created_at, status, retry_count, last_attempt_at, last_error, synced_at, operation_id, idempotency_key`
