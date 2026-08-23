# Download Drift / SQLite WASM assets required for Flutter Web offline database.
# Safe to re-run. Never deletes IndexedDB data.

set -euo pipefail
mkdir -p web
curl -L "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-2.9.4/sqlite3.wasm" -o web/sqlite3.wasm
curl -L "https://github.com/simolus3/drift/releases/download/drift-2.31.0/drift_worker.js" -o web/drift_worker.js
echo "Web database assets ready."
