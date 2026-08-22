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

Demo login (seed only, empty database): `admin` / `ChangeMe!Admin1`

## Secrets (GitHub → Settings → Secrets)

- `JWT_SECRET`
- `DATABASE_URL` (production Postgres)
- `GOOGLE_SERVICE_ACCOUNT_JSON` (backend only)
- `GOOGLE_LIVE_SPREADSHEET_ID` (default: the Al Nomani Live Backup sheet)
- `GOOGLE_FULL_SPREADSHEET_ID` (second spreadsheet for 5-day full backup)

Never put Google credentials in Flutter code.

## Google Sheets

Live backup spreadsheet:

https://docs.google.com/spreadsheets/d/1TvyxxkYH4iLyYfwHnVMMTuyPCekUNvFerfV-HgSp22I

Share that file with the service-account email as Editor. Create a second spreadsheet for Full Backup and set `GOOGLE_FULL_SPREADSHEET_ID`.
