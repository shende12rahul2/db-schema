#!/usr/bin/env bash
# Schema migration runner (Windows / macOS / Linux: the only requirement is Docker).
#
#   up        start the local Oracle container (docker compose) and wait until it is ready
#   down      stop it and delete its data
#   plan      READ-ONLY: show what migrate would run, in order, and why  (plan --sql also prints the SQL)
#   step      apply only the NEXT pending versioned migration (to verify one change at a time)
#   migrate   apply all pending versioned migrations, then changed/missing repeatable objects
#   status    history, pending migrations, changed repeatable objects
#   sql "..." run an ad-hoc query for manual verification, e.g. sql "SELECT * FROM schema_version"
#             (multi-line: pipe a script on stdin; DML is ROLLED BACK at the end, DDL is not)
#   validate  history vs files (checksums, order, FAILED rows) + invalid objects
#   undo      revert the most recent versioned migration (needs migrations/undo/U<ver>__*.sql)
#   repair    remove FAILED rows after you cleaned up a failed migration
#   baseline  adopt a database built with the legacy layout (marks V001 applied)
#   smoke     run scripts/validate.sql (object counts, function checks, rolled-back insert)
#   deploy    migrate + validate + smoke
#
# On the host (no sqlplus) the script re-runs itself inside the container, so the same commands work everywhere.
# Env: CONN (user/pass@//host:port/service, default = local container), ENVIRONMENT (local|prod), CONFIRM=yes (required for prod migrate/undo/repair), OUT_OF_ORDER=1
set -uo pipefail
DB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DB_DIR"
COMPOSE_FILE_HOST="$DB_DIR/docker-compose.yml"
if [ -n "${MSYSTEM:-}" ]; then          # Git Bash / MSYS on Windows: no path mangling, Windows-style compose path
  export MSYS_NO_PATHCONV=1
  COMPOSE_FILE_HOST="$(cd "$DB_DIR" && pwd -W)/docker-compose.yml"
fi
COMPOSE=(docker compose -f "$COMPOSE_FILE_HOST")

die() { echo "ERROR: $*" >&2; exit 1; }

# ---- host side: start/stop, or delegate into the container ------------------
if ! command -v sqlplus >/dev/null 2>&1; then
  command -v docker >/dev/null 2>&1 || die "Docker is required (or a local sqlplus). Install Docker Desktop / Docker Engine."
  case "${1:-help}" in
    up)
      svc=$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.service" }}' oracle-free 2>/dev/null || true)
      if docker inspect oracle-free >/dev/null 2>&1 && [ "$svc" != "oracle" ]; then
        die "a container named oracle-free already exists (from the old 'docker run' instructions). Remove it: docker rm -f oracle-free"
      fi
      echo "Starting Oracle (first run downloads the image and initialises the DB: a few minutes)..."
      "${COMPOSE[@]}" up -d --wait && echo "Oracle is ready."; exit $? ;;
    down) "${COMPOSE[@]}" down -v; exit $? ;;
    help) sed -n '2,24p' "$0"; exit 0 ;;
  esac
  [ -n "$("${COMPOSE[@]}" ps --status running -q oracle 2>/dev/null)" ] \
    || die "the Oracle container is not running. Start it with: ${0} up"
  exec "${COMPOSE[@]}" exec -T -w /workspace/db \
    -e "CONN=${CONN:-}" -e "ENVIRONMENT=${ENVIRONMENT:-local}" -e "CONFIRM=${CONFIRM:-}" -e "OUT_OF_ORDER=${OUT_OF_ORDER:-0}" \
    oracle bash scripts/migrate.sh "$@"
fi

# ---- container side: real work ------------------------------------------------
CONN=${CONN:-bank/Bank123@//localhost:1521/FREEPDB1}
ENVIRONMENT=${ENVIRONMENT:-local}
LOG=${LOG:-${TMPDIR:-/tmp}/migrate.log}

sq() { sqlplus -s -L "$CONN"; }
# q "<sql>" : run SQL, print bare rows
q() {
  { echo "SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF LINESIZE 500 TRIMSPOOL ON"; echo "$1"; echo "EXIT"; } \
    | sq 2>&1 | sed '/^[[:space:]]*$/d'
}
sha_stdin() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
sha_file() { sha_stdin < "$1"; }

LAST_FILE=""
# run_script <file>... : run SQL files in one sqlplus session; non-zero on any ORA-/SP2-/PLS- error.
# LAST_FILE = the file that was running when the session ended.
run_script() {
  local tmp rc f; tmp=$(mktemp)
  {
    echo "WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK"
    echo "WHENEVER OSERROR EXIT FAILURE"
    echo "SET FEEDBACK ON SERVEROUTPUT ON"
    for f in "$@"; do echo "PROMPT >>> $f"; echo "@$f"; done
    echo "EXIT 0"
  } | sq >"$tmp" 2>&1
  rc=${PIPESTATUS[1]}
  tee -a "$LOG" < "$tmp"
  LAST_FILE=$(grep '^>>> ' "$tmp" | tail -1 | sed 's/^>>> //')
  if [ "$rc" -ne 0 ] || grep -qE '^(ORA|SP2|PLS)-' "$tmp"; then rm -f "$tmp"; return 1; fi
  rm -f "$tmp"; return 0
}

connect_check() {
  [ "$(q "SELECT 'OK' FROM dual;" | tr -d '[:space:]')" = "OK" ] \
    || die "cannot connect to Oracle with $CONN. Run: migrate.sh up (and wait until it is ready)."
}
prod_guard() {
  if [ "$ENVIRONMENT" = "prod" ] && [ "${CONFIRM:-}" != "yes" ]; then die "ENVIRONMENT=prod: re-run with CONFIRM=yes to $1"; fi
}
bootstrap() { run_script scripts/bootstrap_schema_version.sql >/dev/null || die "could not create schema_version"; }

# ---- file helpers -------------------------------------------------------
mig_files() { ls migrations/V*.sql 2>/dev/null | sort; }
rep_files() { find repeatable -type f ! -name 'README*' 2>/dev/null | sort; }   # 01_types ... 08_views = dependency order
ver_of()  { local b; b=$(basename "$1"); b=${b#[VU]}; echo "${b%%__*}"; }
desc_of() { local b; b=$(basename "$1" .sql); echo "${b#*__}"; }
undo_file_for() { ls migrations/undo/U"$1"__*.sql 2>/dev/null | head -1; }
obj_name() { local b; b=$(basename "$1"); b=${b%.*}; echo "$b" | tr '[:lower:]' '[:upper:]'; }

# APPLIED_ROWS: "version|status|checksum" for BASELINE/VERSIONED rows
load_applied() {
  APPLIED_ROWS=$(q "SELECT version||'|'||status||'|'||NVL(checksum,'-') FROM schema_version WHERE type IN ('BASELINE','VERSIONED') ORDER BY installed_rank;")
  if printf '%s\n' "$APPLIED_ROWS" | grep -qE 'ORA-|SP2-'; then die "cannot read schema_version: $APPLIED_ROWS"; fi
}
# REP_ROWS: latest row per repeatable script: "script|status|checksum"
load_repeatable() {
  REP_ROWS=$(q "SELECT script||'|'||status||'|'||NVL(checksum,'-') FROM (SELECT script,status,checksum,ROW_NUMBER() OVER (PARTITION BY script ORDER BY installed_rank DESC) rn FROM schema_version WHERE type='REPEATABLE') WHERE rn=1;")
  if printf '%s\n' "$REP_ROWS" | grep -qE 'ORA-|SP2-'; then die "cannot read schema_version: $REP_ROWS"; fi
  load_existing
}
row_field() { printf '%s\n' "$APPLIED_ROWS" | awk -F'|' -v v="$1" -v n="$2" '$1==v{print $n; exit}'; }
rep_field() { printf '%s\n' "$REP_ROWS" | awk -F'|' -v s="$1" -v n="$2" '$1==s{print $n; exit}'; }
obj_type_of() {
  case "$(basename "$(dirname "$1")")" in
    01_types) echo "TYPE";; 02_type_bodies) echo "TYPE BODY";; 03_functions) echo "FUNCTION";;
    04_procedures) echo "PROCEDURE";; 05_package_specs) echo "PACKAGE";; 06_package_bodies) echo "PACKAGE BODY";;
    07_triggers) echo "TRIGGER";; 08_views) echo "VIEW";;
  esac
}
load_existing() {
  EXISTING=$(q "SELECT object_type||'|'||object_name FROM user_objects WHERE object_type IN ('TYPE','TYPE BODY','FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW');")
}
# rep_reason <file>: why the file must be (re)applied; empty = up to date
rep_reason() {
  local f=$1 st sum
  st=$(rep_field "$f" 2); sum=$(rep_field "$f" 3)
  if [ -z "$st" ]; then echo "new"; return; fi
  if [ "$st" != "SUCCESS" ]; then echo "failed last time"; return; fi
  if [ "$sum" != "$(sha_file "$f")" ]; then echo "changed"; return; fi
  # e.g. a trigger dropped together with its table by an undo script
  printf '%s\n' "$EXISTING" | grep -qxF "$(obj_type_of "$f")|$(obj_name "$f")" || echo "missing in database"
}
# changed_rep_files: repeatable files that are new, edited, failed last time, or missing in the DB
changed_rep_files() {
  local f
  for f in $(rep_files); do [ -n "$(rep_reason "$f")" ] && echo "$f"; done
}

record() { # type version_literal description script checksum ms status
  local out
  out=$(q "INSERT INTO schema_version (type,version,description,script,checksum,execution_ms,status) VALUES ('$1',$2,'$3','$4','$5',$6,'$7'); COMMIT;")
  printf '%s\n' "$out" | grep -qE 'ORA-|SP2-' && echo "WARNING: could not record history: $out" >&2
  return 0
}

INVALID_NAMES=""
INVALID_ALL=""
invalid_list() {
  q "EXEC DBMS_UTILITY.COMPILE_SCHEMA(USER, FALSE);" >/dev/null
  q "SELECT object_type||' '||object_name FROM user_objects WHERE status='INVALID' ORDER BY 1;"
}
# post_check [<invalid objects before the change>]: recompile; fail if any object is invalid that was not invalid before
post_check() {
  local before=${1:-} after new
  after=$(invalid_list)
  if [ -n "$before" ]; then new=$(printf '%s\n' "$after" | grep -vxF -f <(printf '%s\n' "$before") || true); else new=$after; fi
  INVALID_NAMES=$(printf '%s\n' "$new" | sed 's/^.* //')
  INVALID_ALL=$after   # "TYPE NAME" lines
  if [ -n "$before" ] && [ -n "$after" ]; then
    echo "i already invalid before this change (not blocking):"; printf '%s\n' "$before" | sed 's/^/   /'
  fi
  if [ -n "$new" ]; then
    echo "x object(s) became invalid:"
    printf '%s\n' "$new" | sed 's/^/   /'
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
      FAILED) echo "x V$v is recorded as FAILED. Clean up its partial changes, then: migrate.sh repair"; bad=1 ;;
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
    if [ "$s" != "SUCCESS" ] && [ "$s" != "FAILED" ] && [ $((10#$ver)) -lt "$max" ] && [ "${OUT_OF_ORDER:-0}" != "1" ]; then
      echo "x $f is pending but a higher version is already applied (out of order). Renumber it, or set OUT_OF_ORDER=1 if intended."; bad=1
    fi
  done
  return $bad
}

cmd_validate() {
  connect_check; bootstrap
  local bad=0 s n
  validate_core || bad=1
  post_check || bad=1
  load_repeatable
  local f r
  for f in $(rep_files); do
    r=$(rep_reason "$f")
    case "$r" in
      "") ;;
      "missing in database") echo "x $f: object $(obj_name "$f") does not exist in the database - run migrate.sh migrate"; bad=1 ;;
      *) echo "i $f: $r - run migrate.sh migrate" ;;
    esac
  done
  while IFS='|' read -r s st c; do
    [ -z "$s" ] && continue
    [ -f "$s" ] || [ "$st" != "SUCCESS" ] || echo "i $s was removed from the repo but the object may still exist: add a migration that drops it"
  done <<< "$REP_ROWS"
  if [ $bad -eq 0 ]; then echo "VALIDATE OK"; else echo "VALIDATE FAILED" >&2; return 1; fi
}

# ---- migrate ------------------------------------------------------------
apply_version() {
  local f=$1 ver desc sum start ms status
  ver=$(ver_of "$f"); desc=$(desc_of "$f"); sum=$(sha_file "$f")
  echo "-> applying V$ver  $desc"
  q "DELETE FROM schema_version WHERE version='$ver' AND status IN ('FAILED','UNDONE'); COMMIT;" >/dev/null
  local before; before=$(invalid_list)
  start=$(date +%s)
  if run_script "$f" && post_check "$before"; then status=SUCCESS; else status=FAILED; fi
  ms=$(( ($(date +%s) - start) * 1000 ))
  if [ "$status" = SUCCESS ]; then
    record VERSIONED "'$ver'" "$desc" "$f" "$sum" "$ms" SUCCESS
    echo "   V$ver OK (${ms} ms)"
    return 0
  fi
  record VERSIONED "'$ver'" "$desc" "$f" "-" "$ms" FAILED
  cat >&2 <<MSG

x V$ver FAILED - details in $LOG (inside the container: docker compose -f db/docker-compose.yml exec oracle cat $LOG).
  The database may be PARTIALLY changed (Oracle DDL auto-commits).
  1. Check what was applied (e.g. SELECT column_name FROM user_tab_columns WHERE table_name='...').
  2. Put the schema back to its pre-migration state by hand (or run migrations/undo/U${ver}__*.sql if it fits).
  3. migrate.sh repair      (clears the FAILED row)
  4. Fix $f (allowed: it never succeeded) and run migrate.sh migrate again.
MSG
  return 1
}

apply_repeatable() {
  local changed f ok=1 overall=0 bad_names
  load_repeatable
  changed=$(changed_rep_files)
  if [ -z "$changed" ]; then echo "repeatable objects up to date"; return 0; fi
  echo "-> applying $(echo "$changed" | wc -l | tr -d '[:space:]') repeatable file(s):"
  for f in $changed; do echo "   $f  ($(rep_reason "$f"))"; done
  local before; before=$(invalid_list)
  # shellcheck disable=SC2086
  run_script $changed || ok=0
  if [ $ok -eq 1 ]; then
    post_check "$before" || overall=1
    bad_names="$INVALID_ALL"   # a file whose own object is invalid is FAILED, even if it was invalid before
    for f in $changed; do
      if printf '%s\n' "$bad_names" | grep -qxF "$(obj_type_of "$f") $(obj_name "$f")"; then
        record REPEATABLE NULL "$(basename "$f")" "$f" "-" 0 FAILED; echo "   x $f compiled with errors" >&2; overall=1
      else
        record REPEATABLE NULL "$(basename "$f")" "$f" "$(sha_file "$f")" 0 SUCCESS
      fi
    done
  else
    overall=1
    # files before the failing one succeeded; the failing one is FAILED; the rest never ran
    for f in $changed; do
      if [ "$f" = "$LAST_FILE" ]; then record REPEATABLE NULL "$(basename "$f")" "$f" "-" 0 FAILED; echo "   x $f FAILED" >&2; break; fi
      record REPEATABLE NULL "$(basename "$f")" "$f" "$(sha_file "$f")" 0 SUCCESS
    done
    post_check >/dev/null || true
  fi
  if [ $overall -ne 0 ]; then
    echo "x repeatable step finished with errors - fix the file(s) and run migrate.sh migrate again (CREATE OR REPLACE is safe to repeat)." >&2
    return 1
  fi
  echo "   repeatable objects OK"
}

cmd_migrate() {
  connect_check; prod_guard "migrate"; bootstrap
  local n; n=$(q "SELECT COUNT(*) FROM schema_version;" | tr -d '[:space:]')
  if [ "$n" = "0" ] && [ "$(q "SELECT COUNT(*) FROM user_tables WHERE table_name='CUSTOMERS';" | tr -d '[:space:]')" != "0" ]; then
    die "tables already exist but there is no history. Run migrate.sh baseline first."
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
  apply_repeatable || exit 1
  echo "MIGRATE OK"
}

# ---- undo / repair / baseline / status / smoke --------------------------------
cmd_undo() {
  connect_check; prod_guard "undo"; bootstrap
  local ver uf
  ver=$(q "SELECT version FROM (SELECT version FROM schema_version WHERE type='VERSIONED' AND status='SUCCESS' ORDER BY installed_rank DESC) WHERE ROWNUM=1;" | tr -d '[:space:]')
  [ -z "$ver" ] && die "nothing to undo (the baseline cannot be undone)"
  uf=$(undo_file_for "$ver"); [ -z "$uf" ] && die "no undo script migrations/undo/U${ver}__*.sql for V$ver"
  echo "-> undoing V$ver using $uf"
  if run_script "$uf"; then
    q "UPDATE schema_version SET status='UNDONE' WHERE version='$ver'; COMMIT;" >/dev/null
    echo "V$ver undone."
    if ! post_check >/dev/null; then
      echo "! some objects are now invalid (expected when current code uses what V$ver added):"
      printf '%s\n' "$INVALID_NAMES" | sed 's/^/   /'
      echo "  Either re-apply with: migrate.sh migrate   or roll the code back: git checkout <older tag>; migrate.sh migrate"
    else
      echo "  Next: migrate.sh migrate re-applies it, or check out older code and run migrate.sh migrate."
    fi
  else
    echo "x undo of V$ver FAILED - the database may be partially reverted; fix by hand. History still says V$ver is applied." >&2
    exit 1
  fi
}

cmd_repair() {
  connect_check; prod_guard "repair"; bootstrap
  echo "FAILED rows to be removed:"
  q "SELECT '  '||NVL(version,'repeatable')||'  '||script FROM schema_version WHERE status='FAILED';"
  q "DELETE FROM schema_version WHERE status='FAILED'; COMMIT;" >/dev/null
  echo "repair done"
}

cmd_baseline() {
  connect_check; bootstrap
  [ "$(q "SELECT COUNT(*) FROM schema_version;" | tr -d '[:space:]')" != "0" ] && die "history is not empty; baseline only works on a fresh history table"
  [ "$(q "SELECT COUNT(*) FROM user_tables WHERE table_name='CUSTOMERS';" | tr -d '[:space:]')" = "0" ] && die "no application tables found; use migrate instead"
  local f; f=$(ls migrations/V001__*.sql | head -1)
  record BASELINE "'001'" "$(desc_of "$f")" "$f" "$(sha_file "$f")" 0 SUCCESS
  echo "baselined at V001. Run migrate.sh migrate to apply newer versions."
}

cmd_status() {
  connect_check; bootstrap
  echo "Applied history (versioned):"
  q "SELECT RPAD(installed_rank,4)||RPAD(NVL(version,'-'),6)||RPAD(type,11)||RPAD(status,9)||RPAD(TO_CHAR(installed_on,'YYYY-MM-DD HH24:MI'),18)||description FROM schema_version WHERE type<>'REPEATABLE' ORDER BY installed_rank;"
  load_applied; load_repeatable
  echo "Pending versioned migrations:"
  local f ver any=0
  for f in $(mig_files); do
    ver=$(ver_of "$f")
    if [ "$(row_field "$ver" 2)" != "SUCCESS" ]; then echo "  V$ver  $(desc_of "$f")"; any=1; fi
  done
  [ $any -eq 0 ] && echo "  (none)"
  echo "Repeatable files that will be (re)applied:"
  any=0
  for f in $(changed_rep_files); do echo "  $f"; any=1; done
  [ $any -eq 0 ] && echo "  (none)"
  return 0
}


# ---- plan / step / sql ------------------------------------------------------
target_label() { echo "${CONN%%/*}@${CONN#*@}"; }

cmd_plan() {
  connect_check
  local show_sql=0 f ver n=0 cur
  [ "${1:-}" = "--sql" ] && show_sql=1
  echo "Target   : $(target_label)   ENVIRONMENT=$ENVIRONMENT"
  if [ "$(q "SELECT COUNT(*) FROM user_tables WHERE table_name='SCHEMA_VERSION';" | tr -d '[:space:]')" = "0" ]; then
    echo "History  : none yet (fresh database) - schema_version will be created by migrate"
    APPLIED_ROWS=""; REP_ROWS=""; load_existing
  else
    load_applied; load_repeatable
    cur=$(q "SELECT MAX(TO_NUMBER(version)) FROM schema_version WHERE type IN ('BASELINE','VERSIONED') AND status='SUCCESS';" | tr -d '[:space:]')
    echo "Current  : V${cur:-none}"
    echo "Checks   :"; if validate_core | sed 's/^/  /'; then echo "  history OK"; else echo "  -> migrate will REFUSE to run until these are fixed"; fi
  fi
  echo
  echo "1) Versioned migrations, run once, in this order:"
  for f in $(mig_files); do
    ver=$(ver_of "$f")
    [ "$(row_field "$ver" 2)" = "SUCCESS" ] && continue
    n=$((n + 1)); echo "   $n. V$ver  $f"
    if [ $show_sql -eq 1 ]; then sed 's/^/        | /' "$f"; fi
  done
  [ $n -eq 0 ] && echo "   (none)"
  echo
  echo "2) Repeatable files, run after the migrations:"
  n=0
  for f in $(rep_files); do
    local r; r=$(rep_reason "$f")
    [ -z "$r" ] && continue
    n=$((n + 1)); echo "   - $f  ($r)"
  done
  [ $n -eq 0 ] && echo "   (none)"
  echo
  echo "Nothing was changed. Next: 'step' (one migration) or 'migrate' (everything above)."
}

cmd_step() {
  connect_check; prod_guard "step"; bootstrap
  local n; n=$(q "SELECT COUNT(*) FROM schema_version;" | tr -d '[:space:]')
  if [ "$n" = "0" ] && [ "$(q "SELECT COUNT(*) FROM user_tables WHERE table_name='CUSTOMERS';" | tr -d '[:space:]')" != "0" ]; then
    die "tables already exist but there is no history. Run migrate.sh baseline first."
  fi
  validate_core || die "validation failed - fix the problems above first"
  load_applied
  local f ver
  for f in $(mig_files); do
    ver=$(ver_of "$f")
    [ "$(row_field "$ver" 2)" = "SUCCESS" ] && continue
    apply_version "$f" || exit 1
    echo "Verify it now (e.g. migrate.sh sql \"SELECT ... \"), then run 'step' again or 'migrate' to finish."
    echo "Repeatable files were NOT applied by 'step'; 'migrate' applies them at the end."
    return 0
  done
  echo "no pending versioned migrations - run 'migrate' to apply repeatable files if 'plan' lists any"
}

cmd_sql() {
  connect_check
  local stmt=${1:-}
  [ -z "$stmt" ] && stmt=$(cat)
  case "$stmt" in *";") ;; *) stmt="$stmt;";; esac
  { echo "SET LINESIZE 220 PAGESIZE 200 FEEDBACK ON TRIMOUT ON"; echo "COLUMN script FORMAT A60"; echo "COLUMN description FORMAT A40"; echo "COLUMN checksum FORMAT A12 TRUNCATED"; echo "$stmt"; echo "EXIT ROLLBACK"; } | sq
}

cmd_smoke() { connect_check; run_script scripts/validate.sql; }

case "${1:-help}" in
  plan)     cmd_plan "${2:-}" ;;
  step)     cmd_step ;;
  sql)      shift; cmd_sql "$*" ;;
  migrate)  cmd_migrate ;;
  status)   cmd_status ;;
  validate) cmd_validate ;;
  undo)     cmd_undo ;;
  repair)   cmd_repair ;;
  baseline) cmd_baseline ;;
  smoke)    cmd_smoke ;;
  deploy)   cmd_migrate && cmd_validate && cmd_smoke && echo "DEPLOY OK" ;;
  *) sed -n '2,24p' "$0" ;;
esac
