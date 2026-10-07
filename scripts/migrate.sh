#!/usr/bin/env bash
# Schema migration runner for the local Oracle container.
#   ./scripts/migrate.sh migrate     apply pending versioned migrations, then changed code objects
#   ./scripts/migrate.sh status      show history and pending migrations
#   ./scripts/migrate.sh validate    verify history vs files (checksums, order, failures, invalid objects)
#   ./scripts/migrate.sh undo        undo the most recent versioned migration (needs migrations/undo/U<ver>__*.sql)
#   ./scripts/migrate.sh repair      remove FAILED rows after you cleaned up a failed migration
#   ./scripts/migrate.sh baseline    mark an existing DB (built by the old deploy.sh) as V001
# Env: CONTAINER, CONN, ENVIRONMENT (local|prod), CONFIRM=yes (required for prod migrate/undo/repair), OUT_OF_ORDER=1
set -uo pipefail
cd "$(dirname "$0")/.."

CONTAINER=${CONTAINER:-oracle-free}
CONN=${CONN:-bank/Bank123@//localhost:1521/FREEPDB1}
ENVIRONMENT=${ENVIRONMENT:-local}
LOG=migrate.log
CODE_DIRS=(Type Type_Body Function Procedure Package Package_Body Trigger View)
CODE_EXT=(tps tpb fnc prc spc bdy trg vw)

die() { echo "ERROR: $*" >&2; exit 1; }

sq() { docker exec -i "$CONTAINER" sqlplus -s -L "$CONN"; }
# q "<sql>" : run SQL, print bare rows
q() {
  { echo "SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF LINESIZE 500 TRIMSPOOL ON"; echo "$1"; echo "EXIT"; } \
    | sq 2>&1 | sed '/^[[:space:]]*$/d'
}
sha_stdin() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
sha_file() { sha_stdin < "$1"; }

sync_repo() {
  docker exec "$CONTAINER" rm -rf /tmp/db-schema
  docker cp . "$CONTAINER":/tmp/db-schema >/dev/null
}

# run_script <file>... : run SQL files inside the container; non-zero on any ORA-/SP2-/PLS- error
run_script() {
  local tmp rc f; tmp=$(mktemp)
  {
    echo "WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK"
    echo "WHENEVER OSERROR EXIT FAILURE"
    echo "SET FEEDBACK ON SERVEROUTPUT ON"
    for f in "$@"; do echo "@$f"; done
    echo "EXIT 0"
  } | docker exec -i -w /tmp/db-schema "$CONTAINER" sqlplus -s -L "$CONN" >"$tmp" 2>&1
  rc=${PIPESTATUS[1]}
  tee -a "$LOG" < "$tmp"
  if [ "$rc" -ne 0 ] || grep -qE '^(ORA|SP2|PLS)-' "$tmp"; then rm -f "$tmp"; return 1; fi
  rm -f "$tmp"; return 0
}

connect_check() {
  [ "$(q "SELECT 'OK' FROM dual;" | tr -d '[:space:]')" = "OK" ] \
    || die "cannot connect to Oracle ($CONTAINER / $CONN). Is the container running and ready?"
}

prod_guard() {
  if [ "$ENVIRONMENT" = "prod" ] && [ "${CONFIRM:-}" != "yes" ]; then
    die "ENVIRONMENT=prod: re-run with CONFIRM=yes to $1"
  fi
}

bootstrap() { sync_repo; run_script scripts/bootstrap_schema_version.sql >/dev/null || die "could not create schema_version"; }

# ---- file helpers -------------------------------------------------------
mig_files() { ls migrations/V*.sql 2>/dev/null | sort; }
ver_of()  { local b; b=$(basename "$1"); b=${b#[VU]}; echo "${b%%__*}"; }
desc_of() { local b; b=$(basename "$1" .sql); echo "${b#*__}"; }
undo_file_for() { ls migrations/undo/U"$1"__*.sql 2>/dev/null | head -1; }
code_files() {
  local i f
  for i in "${!CODE_DIRS[@]}"; do
    for f in "${CODE_DIRS[$i]}"/*."${CODE_EXT[$i]}"; do [ -f "$f" ] && echo "$f"; done
  done
}
code_checksum() { code_files | while read -r f; do echo "$f"; cat "$f"; done | sha_stdin; }

# APPLIED_ROWS: lines "version|status|checksum" for BASELINE/VERSIONED rows
load_applied() {
  APPLIED_ROWS=$(q "SELECT version||'|'||status||'|'||NVL(checksum,'-') FROM schema_version WHERE type IN ('BASELINE','VERSIONED') ORDER BY installed_rank;")
  if printf '%s\n' "$APPLIED_ROWS" | grep -qE 'ORA-|SP2-'; then die "cannot read schema_version: $APPLIED_ROWS"; fi
}
row_field() { # <version> <field 2|3>
  printf '%s\n' "$APPLIED_ROWS" | awk -F'|' -v v="$1" -v n="$2" '$1==v{print $n; exit}'
}

record() { # type version_literal description script checksum ms status
  local out
  out=$(q "INSERT INTO schema_version (type,version,description,script,checksum,execution_ms,status) VALUES ('$1',$2,'$3','$4','$5',$6,'$7'); COMMIT;")
  printf '%s\n' "$out" | grep -qE 'ORA-|SP2-' && echo "WARNING: could not record history: $out" >&2
  return 0
}

post_check() {
  q "EXEC DBMS_UTILITY.COMPILE_SCHEMA(USER, FALSE);" >/dev/null
  local n; n=$(q "SELECT COUNT(*) FROM user_objects WHERE status='INVALID';" | tr -d '[:space:]')
  if [ "$n" != "0" ]; then
    echo "x $n invalid object(s) after change:"
    q "SELECT '   '||object_type||' '||object_name FROM user_objects WHERE status='INVALID';"
    q "SELECT '   '||name||' line '||line||': '||text FROM user_errors ORDER BY name, sequence;"
    return 1
  fi
  return 0
}

# ---- validate -----------------------------------------------------------
validate_core() {
  local bad=0 max=-1 v s c f ver cur
  load_applied
  while IFS='|' read -r v s c; do
    [ -z "$v" ] && continue
    case "$s" in
      FAILED) echo "x V$v is recorded as FAILED. Clean up its partial changes, then: ./scripts/migrate.sh repair"; bad=1 ;;
      SUCCESS)
        f=$(ls migrations/V"$v"__*.sql 2>/dev/null | head -1)
        if [ -z "$f" ]; then echo "x V$v was applied but its file is missing from migrations/"; bad=1
        else
          cur=$(sha_file "$f")
          if [ "$cur" != "$c" ]; then echo "x V$v checksum mismatch: $f was edited after it was applied. Revert it and add a NEW migration."; bad=1; fi
        fi
        [ $((10#$v)) -gt "$max" ] && max=$((10#$v)) ;;
    esac
  done <<< "$APPLIED_ROWS"
  for f in $(mig_files); do
    ver=$(ver_of "$f"); s=$(row_field "$ver" 2)
    if [ "$s" != "SUCCESS" ] && [ $((10#$ver)) -lt "$max" ] && [ "$s" != "FAILED" ] && [ "${OUT_OF_ORDER:-0}" != "1" ]; then
      echo "x $f is pending but a higher version is already applied (out of order). Renumber it, or set OUT_OF_ORDER=1 if intended."; bad=1
    fi
  done
  return $bad
}

cmd_validate() {
  connect_check; bootstrap
  local bad=0
  validate_core || bad=1
  post_check || bad=1
  local last; last=$(q "SELECT checksum FROM (SELECT checksum FROM schema_version WHERE type='REPEATABLE' AND status='SUCCESS' ORDER BY installed_rank DESC) WHERE ROWNUM=1;" | tr -d '[:space:]')
  [ "$last" != "$(code_checksum)" ] && echo "i code objects (Type..View) differ from what is deployed: run ./scripts/migrate.sh migrate"
  if [ $bad -eq 0 ]; then echo "VALIDATE OK"; else echo "VALIDATE FAILED" >&2; return 1; fi
}

# ---- migrate ------------------------------------------------------------
apply_version() {
  local f=$1 ver desc sum start ms status
  ver=$(ver_of "$f"); desc=$(desc_of "$f"); sum=$(sha_file "$f")
  echo "-> applying V$ver  $desc"
  q "DELETE FROM schema_version WHERE version='$ver' AND status IN ('FAILED','UNDONE'); COMMIT;" >/dev/null
  start=$(date +%s)
  if run_script "$f" && post_check; then status=SUCCESS; else status=FAILED; fi
  ms=$(( ($(date +%s) - start) * 1000 ))
  if [ "$status" = SUCCESS ]; then
    record VERSIONED "'$ver'" "$desc" "$f" "$sum" "$ms" SUCCESS
    echo "   V$ver OK (${ms} ms)"
    return 0
  fi
  record VERSIONED "'$ver'" "$desc" "$f" "-" "$ms" FAILED
  cat >&2 <<MSG

x V$ver FAILED - details in $LOG. The database may be PARTIALLY changed (Oracle DDL auto-commits).
  1. Check what was applied (e.g. SELECT column_name FROM user_tab_columns WHERE table_name='...').
  2. Put the schema back to its pre-migration state by hand (or run migrations/undo/U${ver}__*.sql if it fits).
  3. ./scripts/migrate.sh repair      (clears the FAILED row)
  4. Fix $f (allowed: it never succeeded) and run ./scripts/migrate.sh migrate again.
MSG
  return 1
}

apply_code() {
  local sum last files
  sum=$(code_checksum)
  last=$(q "SELECT checksum FROM (SELECT checksum FROM schema_version WHERE type='REPEATABLE' AND status='SUCCESS' ORDER BY installed_rank DESC) WHERE ROWNUM=1;" | tr -d '[:space:]')
  if [ "$sum" = "$last" ]; then echo "code objects up to date"; return 0; fi
  echo "-> applying code objects (Type, Type_Body, Function, Procedure, Package, Package_Body, Trigger, View)"
  files=$(code_files)
  # shellcheck disable=SC2086
  if run_script $files && post_check; then
    record REPEATABLE NULL "code objects" "Type..View" "$sum" 0 SUCCESS
    echo "   code objects OK"
  else
    record REPEATABLE NULL "code objects" "Type..View" "-" 0 FAILED
    echo "x code objects FAILED - fix the object and re-run migrate (CREATE OR REPLACE is safe to repeat)." >&2
    return 1
  fi
}

cmd_migrate() {
  connect_check; prod_guard "migrate"; bootstrap
  local n; n=$(q "SELECT COUNT(*) FROM schema_version;" | tr -d '[:space:]')
  if [ "$n" = "0" ] && [ "$(q "SELECT COUNT(*) FROM user_tables WHERE table_name='CUSTOMERS';" | tr -d '[:space:]')" != "0" ]; then
    die "tables already exist but there is no history. Run ./scripts/migrate.sh baseline first."
  fi
  validate_core || die "validation failed - fix the problems above before migrating"
  load_applied
  local f ver applied=0
  for f in $(mig_files); do
    ver=$(ver_of "$f")
    [ "$(row_field "$ver" 2)" = "SUCCESS" ] && continue
    apply_version "$f" || exit 1
    applied=$((applied + 1))
  done
  [ $applied -eq 0 ] && echo "no pending versioned migrations"
  apply_code || exit 1
  echo "MIGRATE OK"
}

# ---- undo / repair / baseline / status ---------------------------------------
cmd_undo() {
  connect_check; prod_guard "undo"; bootstrap
  local ver uf
  ver=$(q "SELECT version FROM (SELECT version FROM schema_version WHERE type='VERSIONED' AND status='SUCCESS' ORDER BY installed_rank DESC) WHERE ROWNUM=1;" | tr -d '[:space:]')
  [ -z "$ver" ] && die "nothing to undo (the baseline cannot be undone)"
  uf=$(undo_file_for "$ver"); [ -z "$uf" ] && die "no undo script migrations/undo/U${ver}__*.sql for V$ver"
  echo "-> undoing V$ver using $uf"
  if run_script "$uf" && post_check; then
    q "UPDATE schema_version SET status='UNDONE' WHERE version='$ver'; COMMIT;" >/dev/null
    echo "V$ver undone. Check out the matching older code and run migrate so code objects are redeployed."
  else
    echo "x undo of V$ver FAILED - the database may be partially reverted; fix by hand. History still says V$ver is applied." >&2
    exit 1
  fi
}

cmd_repair() {
  connect_check; prod_guard "repair"; bootstrap
  echo "FAILED rows to be removed:"
  q "SELECT '  '||NVL(version,'code')||'  '||script FROM schema_version WHERE status='FAILED';"
  q "DELETE FROM schema_version WHERE status='FAILED'; COMMIT;" >/dev/null
  echo "repair done"
}

cmd_baseline() {
  connect_check; bootstrap
  [ "$(q "SELECT COUNT(*) FROM schema_version;" | tr -d '[:space:]')" != "0" ] && die "history is not empty; baseline only works on a fresh history table"
  [ "$(q "SELECT COUNT(*) FROM user_tables WHERE table_name='CUSTOMERS';" | tr -d '[:space:]')" = "0" ] && die "no application tables found; use migrate instead"
  local f; f=$(ls migrations/V001__*.sql | head -1)
  record BASELINE "'001'" "$(desc_of "$f")" "$f" "$(sha_file "$f")" 0 SUCCESS
  echo "baselined at V001. Run ./scripts/migrate.sh migrate to apply newer versions."
}

cmd_status() {
  connect_check; bootstrap
  echo "Applied history:"
  q "SELECT RPAD(installed_rank,4)||RPAD(NVL(version,'-'),6)||RPAD(type,11)||RPAD(status,9)||RPAD(TO_CHAR(installed_on,'YYYY-MM-DD HH24:MI'),18)||description FROM schema_version ORDER BY installed_rank;"
  load_applied
  echo "Pending:"
  local f ver any=0
  for f in $(mig_files); do
    ver=$(ver_of "$f")
    if [ "$(row_field "$ver" 2)" != "SUCCESS" ]; then echo "  V$ver  $(desc_of "$f")"; any=1; fi
  done
  [ $any -eq 0 ] && echo "  (none)"
  return 0
}

case "${1:-help}" in
  migrate)  cmd_migrate ;;
  status)   cmd_status ;;
  validate) cmd_validate ;;
  undo)     cmd_undo ;;
  repair)   cmd_repair ;;
  baseline) cmd_baseline ;;
  *) sed -n '2,10p' "$0" ;;
esac
