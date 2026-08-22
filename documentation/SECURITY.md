# Security Model — Offline Authentication & Secrets

## Principles

- No secrets in Git or in the Flutter client.
- Google Sheets credentials live only on the backend (service account JSON via environment).
- Passwords are never stored in plain text, locally or on the server.
- Offline access still enforces roles and permissions.

## Online login

1. Client sends username + password over HTTPS to `POST /api/v1/auth/login`.
2. Server verifies bcrypt hash in PostgreSQL.
3. Server returns a short-lived JWT access token and a longer-lived refresh token.
4. Client stores tokens in Flutter **secure storage** (web: encrypted session + device-bound key in Drift `app_metadata`, never `localStorage` for tokens as plain text).
5. Client stores a **password verifier** locally: `bcrypt(password)` is **not** copied from the server. Instead the client stores `argon2id/bcrypt` of the password with a local salt **only after** the server accepted the login. This lets the same user unlock the app offline without keeping the raw password.
6. Client caches: `user_id`, display name, role, permission set, session expiry.

## Offline login / session resume

- If a valid cached session exists and has not expired, the user continues.
- If the session expired but a local verifier exists, the user re-enters the password. The verifier is checked locally. No internet is required.
- Disabled users (`is_active = false`) cached locally are denied.
- Permissions are evaluated from the cached permission set. Backend re-enforces them when online.

## Session policy

| Setting | Default | Notes |
| --- | --- | --- |
| Offline session max age | 14 days | Configurable in settings |
| Password verifier | bcrypt cost 10 | Local only |
| JWT access TTL | 15 minutes | Server |
| JWT refresh TTL | 7 days | Server; refresh requires online |

## Authorization

Permissions are checked:

- Flutter: before showing actions and before executing domain services.
- Backend: on every mutating route when the request reaches the server.

A local allow does not bypass server deny.

## Google Sheets

- Spreadsheet IDs and service-account JSON are backend environment variables.
- The Flutter app only talks to the ERP API. It never calls Google APIs.

## Audit

Every privileged change writes an audit row locally (and later syncs). Audit includes user, device, entity, old/new JSON, timestamp.
