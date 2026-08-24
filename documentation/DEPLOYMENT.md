# Deployment

## Branches

| Branch | Deploys production? |
| --- | --- |
| `main` | Yes — GitHub Actions `deploy-production.yml` |
| `develop`, `feature/*`, `fix/*`, `test/*` | No. CI only. |

## What production deploy does

1. Analyze and test.
2. Build Flutter Web (versioned assets, PWA offline-first).
3. Publish `build/web` to GitHub Pages.
4. Optionally build the backend Docker image when `DOCKERHUB_TOKEN` is present.

A new web version **must not** wipe IndexedDB / Drift WASM. Migrations run on the client at startup.

## Local development

```bash
docker compose up postgres
cd server && dart pub get && dart run bin/server.dart
cd .. && flutter pub get && dart run build_runner build --delete-conflicting-outputs
flutter run -d chrome
```

Demo login (seed only, empty database): `admin` / `54321`

## Secrets (GitHub → Settings → Secrets)

- `JWT_SECRET`
- `DATABASE_URL` (production Postgres)
- `GOOGLE_SERVICE_ACCOUNT_JSON` (backend only)
- `GOOGLE_SERVICE_ACCOUNT_FILE` (preferred local path; Docker uses `/run/secrets/google-service-account.json`)
- `GOOGLE_LIVE_SPREADSHEET_ID` (default: the Al Nomani Live Backup sheet)
- `GOOGLE_FULL_SPREADSHEET_ID` (second spreadsheet for 5-day full backup)
- `BOOTSTRAP_ADMIN_USERNAME` / `BOOTSTRAP_ADMIN_PASSWORD` (first deployment only; password at least 12 characters)
- `DATABASE_SSL=true` for managed PostgreSQL
- `ALLOW_SEED=false` in production

Never put Google credentials in Flutter code.

## Google Sheets

Live backup spreadsheet:

https://docs.google.com/spreadsheets/d/1TvyxxkYH4iLyYfwHnVMMTuyPCekUNvFerfV-HgSp22I

Share that file with the service-account email as Editor. Create a separate spreadsheet for Full Backup and set `GOOGLE_FULL_SPREADSHEET_ID`; do not reuse the live ID.

The service account JSON is a backend secret. Never place it in Flutter assets or GitHub Pages. For local Docker, put a replacement key in `secrets/google-service-account.json` after revoking any leaked key, then share the live spreadsheet with the service-account email as Editor. The backup screen reports four separate states: API/server reachability, PostgreSQL queue acceptance, Google outbox completion, and full-backup completion.

## Production API URL

Set `api_base_url` in `assets/config/app_config.production.json` to the HTTPS origin of the Dart server before building. CORS must allow the deployed web origin. A localhost URL in this file makes production synchronization impossible.

For GitHub Pages, set the repository/environment variable `PRODUCTION_API_BASE_URL`. The production workflow injects it into the asset and deliberately fails if it is missing, preventing deployment of a build that can never synchronize.

## Safe upgrade

1. Back up PostgreSQL and verify the Google outbox has no unexplained failures.
2. Run server migrations before accepting traffic.
3. Deploy the server, then the web assets.
4. Do not change the application origin: Drift/SQLite WASM is stored in the browser origin's IndexedDB.
5. The update banner waits for active local transactions, attempts sync, then reloads. Offline local data and the queue are preserved.

## Diagnostics

- `/health`: server process is reachable.
- `/api/v1/sync/status`: authenticated API and protocol version.
- `/api/v1/backup/health`: credential configuration, pending/failed Google outbox rows, and last full backup.
- `backup_outbox.last_error`: exact sanitized Google API failure.
- `sync_operations.operation_id`: idempotency record for duplicate retries.

Google errors never roll back PostgreSQL. Resolve credential/sharing errors and use «إعادة محاولة العمليات الفاشلة»; do not delete outbox rows.
