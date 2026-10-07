#!/usr/bin/env bash
# Deploys every schema file into the local Oracle container, then runs validation.
# Usage: ./scripts/deploy.sh            (container "oracle-free" must be running)
set -euo pipefail
cd "$(dirname "$0")/.."

CONTAINER=${CONTAINER:-oracle-free}
CONN=${CONN:-bank/Bank123@//localhost:1521/FREEPDB1}

TABLE_ORDER="branches customers accounts transactions payments loan_applications collaterals credit_scores documents notifications otp_log audit_logs"

{
  echo "SET ECHO ON"
  echo "WHENEVER OSERROR EXIT FAILURE"
  for f in Sequence/*.seq; do echo "@$f"; done
  for t in $TABLE_ORDER; do echo "@Table/$t.tab"; done
  for d in Type:tps Type_Body:tpb Function:fnc Procedure:prc Package:spc Package_Body:bdy Trigger:trg View:vw; do
    for f in "${d%%:*}"/*."${d##*:}"; do echo "@$f"; done
  done
  echo "@scripts/validate.sql"
  echo "EXIT"
} > scripts/.deploy_all.sql

docker exec "$CONTAINER" rm -rf /tmp/db-schema
docker cp . "$CONTAINER":/tmp/db-schema
docker exec -w /tmp/db-schema "$CONTAINER" sqlplus -s "$CONN" @scripts/.deploy_all.sql | tee deploy.log
rm -f scripts/.deploy_all.sql

if grep -qE "^(ORA|SP2|PLS)-|Warning: .* created with compilation errors" deploy.log; then
  echo "DEPLOY FINISHED WITH ERRORS - see deploy.log" >&2; exit 1
fi
echo "DEPLOY OK"
