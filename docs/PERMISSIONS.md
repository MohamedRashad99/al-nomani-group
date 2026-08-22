# Permission Matrix

| Permission | Admin | Manager | Cashier | Viewer |
| --- | --- | --- | --- | --- |
| products.view | ✓ | ✓ | ✓ | ✓ |
| products.create | ✓ | ✓ | | |
| products.update | ✓ | ✓ | | |
| products.delete | ✓ | | | |
| inventory.view | ✓ | ✓ | ✓ | ✓ |
| inventory.create | ✓ | ✓ | | |
| inventory.adjust | ✓ | ✓ | | |
| customers.view | ✓ | ✓ | ✓ | ✓ |
| customers.create | ✓ | ✓ | ✓ | |
| customers.update | ✓ | ✓ | | |
| sales.view | ✓ | ✓ | ✓ | ✓ |
| sales.create | ✓ | ✓ | ✓ | |
| sales.cancel | ✓ | ✓ | | |
| collections.view | ✓ | ✓ | ✓ | ✓ |
| collections.create | ✓ | ✓ | ✓ | |
| reports.view | ✓ | ✓ | | ✓ |
| reports.export | ✓ | ✓ | | |
| users.view | ✓ | | | |
| users.create | ✓ | | | |
| users.update | ✓ | | | |
| users.disable | ✓ | | | |
| backup.view | ✓ | ✓ | | |
| backup.sync | ✓ | | | |
| backup.retry | ✓ | | | |
| backup.full_sync | ✓ | | | |
| settings.view | ✓ | ✓ | | |
| settings.update | ✓ | | | |

Seed roles are created only when the local/server database is empty and seed is explicitly allowed.
