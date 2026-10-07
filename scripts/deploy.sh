#!/usr/bin/env bash
# One-shot: apply all pending migrations + code objects, validate, then run the smoke tests.
set -euo pipefail
cd "$(dirname "$0")/.."
CONTAINER=${CONTAINER:-oracle-free}
CONN=${CONN:-bank/Bank123@//localhost:1521/FREEPDB1}

./scripts/lint_migrations.sh
./scripts/migrate.sh migrate
./scripts/migrate.sh validate
docker exec -w /tmp/db-schema "$CONTAINER" sqlplus -s "$CONN" @scripts/validate.sql | tee deploy.log
if grep -qE "^(ORA|SP2|PLS)-" deploy.log; then echo "SMOKE TESTS FINISHED WITH ERRORS - see deploy.log" >&2; exit 1; fi
echo "DEPLOY OK"
