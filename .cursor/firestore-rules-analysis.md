# Firestore rules analysis (al-nomani-groub)

- Language: Dart / Flutter (`cloud_firestore`)
- Auth: Firebase Auth anonymous (and email/password). All writes require `request.auth != null`.
- Company workspace: `companies/al_nomani` only.
- Edition: STANDARD, database `(default)`, location eur3.

## Paths written by the app

| Path | Writer | Query |
|---|---|---|
| `companies/{companyId}` | merge set name + updatedAt | none |
| `companies/{companyId}/sales/{id}` | sync push | health: limit(1), count() |
| `companies/{companyId}/inventory/{id}` | sync push | none |
| `companies/{companyId}/customers/{id}` | sync push | none |
| `companies/{companyId}/products/{id}` | sync push | none |
| `companies/{companyId}/categories/{id}` | sync push | none |
| `companies/{companyId}/accounts/{id}` | sync push | none |
| `companies/{companyId}/account_transactions/{id}` | sync push | none |
| `companies/{companyId}/collections/{id}` | sync push | none |
| `companies/{companyId}/users/{id}` | sync push | none |
| `companies/{companyId}/settings/{id}` | sync push | none |
| `companies/{companyId}/audit_logs/{id}` | sync push | none |
| `companies/{companyId}/sale_items/{id}` | sync push | none |
| `companies/{companyId}/roles/{id}` | sync push | none |
| `companies/{companyId}/transactions/{operationId}` | every sync write (append-only ledger) | none |
| `companies/{companyId}/sessions/{sessionId}` | ERP login / restore | none |
| `companies/{companyId}/other/{id}` | unknown entity fallback | none |
| `companies/{companyId}/records/{id}` | legacy, read-only for old docs | none |
| `companies/{companyId}/files/{id}` | storage metadata | none |

No `where` / `orderBy` queries. Reads are get-by-id, `limit(1)`, and `count()`.

## Section document fields

Required metadata on every section doc:

- operationId: string
- operation: string (create, update, cancel, delete)
- version: number > 0 (int or float; Flutter web may send doubles)
- deviceId: string
- updatedAt: timestamp (server)
- updatedBy: string == auth.uid

Plus flattened business payload (sale_number, items, quantity, …). Extra keys allowed.

## CRUD

- create/update: signed-in, company `al_nomani`, valid section doc
- delete: denied (cancel is an update)
- company delete: denied
