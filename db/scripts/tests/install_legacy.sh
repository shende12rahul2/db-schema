#!/usr/bin/env bash
# Installs the flat legacy DDL (../legacy: exactly what was deployed to client databases) into the schema in the current .env,
# WITHOUT the migration tool. Used by the integration test to build a realistic "existing client database".
#   ./scripts/tests/install_legacy.sh [--env <name>|--env-file <path>] [--only-table <name>]
# Needs a working target (RUNNER=local needs sqlplus; docker runners run it in the container).
set -uo pipefail
DB_DIR="$(cd "$(dirname "$0")/../.." && pwd)"; cd "$DB_DIR"
LEGACY="$(cd "$DB_DIR/../legacy" && pwd)"
while [ "${1:-}" = "--env" ] || [ "${1:-}" = "--env-file" ]; do if [ "$1" = "--env" ]; then export ENV_NAME=$2; else export ENV_FILE=$2; fi; shift 2; done
ONLY=""; [ "${1:-}" = "--only-table" ] && ONLY=$2
. "$DB_DIR/scripts/lib/config.sh"
TABLE_ORDER="branches customers accounts transactions payments loan_applications collaterals credit_scores documents notifications otp_log audit_logs"
files=()
if [ -n "$ONLY" ]; then files+=("$LEGACY/Table/$ONLY.tab")
else
  for f in "$LEGACY"/Sequence/*.seq; do files+=("$f"); done
  for t in $TABLE_ORDER; do files+=("$LEGACY/Table/$t.tab"); done
  for d in Type:tps Type_Body:tpb Function:fnc Procedure:prc Package:spc Package_Body:bdy Trigger:trg View:vw; do
    for f in "$LEGACY/${d%%:*}"/*."${d##*:}"; do files+=("$f"); done
  done
fi
script=$(mktemp)
{ echo "SET DEFINE OFF"; for f in "${files[@]}"; do echo "@${f}"; done; echo "EXIT"; } > "$script"
errors() { grep -E '^(ORA|SP2|PLS)-' | sort | uniq -c | sort -rn | head -5; }
if [ "$RUNNER" = "local" ]; then
  sqlplus -s -L "$CONN" @"$script" | errors || true
else
  svc=oracle; [ "$RUNNER" = "docker-client" ] && svc=client
  # inside the container the repo is mounted at /workspace
  sed -i "s#@${LEGACY}#@/workspace/legacy#" "$script"
  C=(docker compose -f "$DB_DIR/docker-compose.yml" exec -T "$svc")
  "${C[@]}" sh -c 'cat > /tmp/legacy_install.sql' < "$script"
  "${C[@]}" sqlplus -s -L "$CONN" @/tmp/legacy_install.sql | errors || true
fi
rm -f "$script"
echo "legacy install finished (errors listed above, if any, are expected: the 8 empty TYPE BODY files cannot compile)"
