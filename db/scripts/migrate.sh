#!/usr/bin/env bash
# Schema migration runner for Oracle. Project-neutral: connection details come from .env, layout from config/default.conf.
#
# Read-only (safe anywhere):
#   config            print the effective settings (password hidden)
#   plan [--sql]      what 'migrate' would do, in order, and why; pre-checks of pending migrations
#   status            history, pending migrations, changed repeatable objects
#   validate          history vs files (checksums, order, FAILED rows) + invalid/missing objects
#   verify-baseline V check an EXISTING database against baseline/V<V>.manifest (changes nothing)
#   manifest V        print a manifest of the connected database (run on a reference DB at version V)
#   sql "..."         ad-hoc query (DML is rolled back at the end, DDL is not; protected targets: SELECT only)
#   log               runner log
# Changes the target (protected environments need CONFIRM=<EXPECTED_DB>):
#   baseline V        adopt an existing database AFTER verify-baseline passes: records V (and the verified code objects)
#   migrate           apply pending versioned migrations, then new/changed/missing repeatable objects
#   step              apply only the NEXT pending migration
#   deploy            migrate + validate + smoke
#   undo              revert the newest migration (only if an undo script exists)
#   repair            remove FAILED rows after you cleaned up a failed migration
#   unlock            clear a stale run lock
# Local helpers:      up | down   (docker runners only)   smoke
#
# Target: .env (default) | --env <name> = .env.<name> | --env-file <path>.   Docs: docs/ONBOARDING.md
set -uo pipefail
DB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DB_DIR"

die() { echo "ERROR: $*" >&2; exit 1; }

while [ "${1:-}" = "--env" ] || [ "${1:-}" = "--env-file" ]; do
  [ -n "${2:-}" ] || die "$1 needs a value"
  if [ "$1" = "--env" ]; then export ENV_NAME=$2; else export ENV_FILE=$2; fi
  shift 2
done
# shellcheck source=lib/config.sh
. "$DB_DIR/scripts/lib/config.sh"

case "$RUNNER" in docker|docker-client|local) ;; *) die "RUNNER must be docker, docker-client or local (got '$RUNNER')";; esac
SERVICE=oracle; [ "$RUNNER" = "docker-client" ] && SERVICE=client

is_protected() { case ",$PROTECTED_ENVS," in *",$APP_ENV,"*) return 0;; esac; return 1; }

cmd_config() {
  echo "env file       : $ENV_FILE   $([ "$ENV_FILE_FOUND" = 1 ] && echo '(found)' || echo '(NOT FOUND - copy .env.example to .env)')"
  echo "app env        : $APP_ENV   protected: $(is_protected && echo yes || echo no)   (PROTECTED_ENVS=$PROTECTED_ENVS)"
  echo "runner         : $RUNNER"
  echo "connection     : ${DB_USER:-?}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE:-?}   password: $([ -n "$DB_PASSWORD" ] && echo set || echo EMPTY)"
  echo "expected db    : ${EXPECTED_DB:-(not set)}"
  echo "history table  : $HISTORY_TABLE   baseline manifests: $BASELINE_DIR/"
  echo "migrations     : $MIGRATIONS_DIR   undo: $UNDO_DIR   repeatable: $REPEATABLE_DIR"
  echo "smoke script   : ${SMOKE_SQL:-(none)}"
  echo "log            : $LOG"
  if [ "$RUNNER" != "local" ]; then
    echo "container      : $CONTAINER_NAME (image $ORACLE_IMAGE, host port $HOST_PORT, compose project $COMPOSE_PROJECT_NAME)"
  fi
  echo "env overrides  :${CONFIG_FORWARD:- (none)}"
}

# ---- host side: start/stop, or delegate into the container ------------------
if [ "$RUNNER" != "local" ] && [ -z "${MIGRATE_IN_CONTAINER:-}" ]; then
  command -v docker >/dev/null 2>&1 || die "Docker is required for RUNNER=$RUNNER (or set RUNNER=local with sqlplus installed)."
  COMPOSE_FILE_HOST="$DB_DIR/docker-compose.yml"
  if [ -n "${MSYSTEM:-}" ]; then          # Git Bash / MSYS on Windows: no path mangling, Windows-style compose path
    export MSYS_NO_PATHCONV=1
    COMPOSE_FILE_HOST="$(cd "$DB_DIR" && pwd -W)/docker-compose.yml"
  fi
  COMPOSE=(docker compose -f "$COMPOSE_FILE_HOST")
  case "${1:-help}" in
    up)
      if [ "$SERVICE" = "oracle" ]; then
        svc=$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$CONTAINER_NAME" 2>/dev/null || true)
        if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1 && [ "$svc" != "$COMPOSE_PROJECT_NAME" ]; then
          die "a container named $CONTAINER_NAME already exists outside this project. Remove it (docker rm -f $CONTAINER_NAME) or set CONTAINER_NAME in .env"
        fi
        echo "Starting Oracle '$CONTAINER_NAME' (first run downloads the image and creates the DB: a few minutes)..."
        "${COMPOSE[@]}" up -d --wait oracle && echo "Oracle is ready (host port $HOST_PORT)."; exit $?
      fi
      echo "Starting sqlplus helper container (the database itself is not touched)..."
      "${COMPOSE[@]}" up -d client && echo "Ready. Target: ${DB_USER:-?}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE:-?}"; exit $? ;;
    down)
      is_protected && die "refusing 'down' for protected environment '$APP_ENV'"
      if [ "$SERVICE" = "oracle" ]; then echo "Removing local Oracle '$CONTAINER_NAME' and its data..."; fi
      "${COMPOSE[@]}" rm -s -f -v "$SERVICE"; exit $? ;;
    config) cmd_config; exit 0 ;;
    help|-h|--help) sed -n '2,29p' "$0"; exit 0 ;;
  esac
  [ -n "$("${COMPOSE[@]}" ps --status running -q "$SERVICE" 2>/dev/null)" ] \
    || die "the $SERVICE container is not running. Start it with: $0 up"
  fwd=(-e "MIGRATE_IN_CONTAINER=1")
  if [ -n "${ENV_NAME:-}" ]; then fwd+=(-e "ENV_NAME=$ENV_NAME"); fi
  case "$ENV_FILE" in "$DB_DIR"/*) [ "$ENV_FILE" = "$DB_DIR/.env" ] || [ -n "${ENV_NAME:-}" ] || fwd+=(-e "ENV_FILE=${ENV_FILE#"$DB_DIR"/}") ;;
    *) die "--env-file must be inside $DB_DIR (only that folder is visible to the container)" ;; esac
  for k in $CONFIG_FORWARD; do case "$k" in ENV_FILE|ENV_NAME) ;; *) fwd+=(-e "$k=${!k}");; esac; done
  exec "${COMPOSE[@]}" exec -T -w "/workspace/$(basename "$DB_DIR")" "${fwd[@]}" "$SERVICE" bash scripts/migrate.sh "$@"
fi

# ---- runner side (inside the container, or RUNNER=local): real work ----------------
case "${1:-help}" in
  config) cmd_config; exit 0 ;;
  help|-h|--help) sed -n '2,29p' "$0"; exit 0 ;;
  up|down) echo "RUNNER=local: nothing to start or stop (using sqlplus on this machine)"; exit 0 ;;
  log) cat "$LOG" 2>/dev/null || echo "no log yet ($LOG)"; exit 0 ;;
esac
command -v sqlplus >/dev/null 2>&1 || die "sqlplus not found. Install Oracle Instant Client + SQL*Plus, or use RUNNER=docker / docker-client."
HIST=$HISTORY_TABLE
HIST_UP=$(echo "$HIST" | tr '[:lower:]' '[:upper:]')

sq() { sqlplus -s -L "$CONN"; }
# q "<sql>" : run SQL, print bare rows
q() {
  { echo "SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF LINESIZE 500 TRIMSPOOL ON DEFINE OFF"; echo "$1"; echo "EXIT"; } \
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
    echo "SET FEEDBACK ON SERVEROUTPUT ON DEFINE OFF"   # DEFINE OFF: '&' in SQL is data, never a prompt
    for f in "$@"; do echo "PROMPT >>> $f"; echo "@$f"; done
    echo "EXIT 0"
  } | sq >"$tmp" 2>&1
  rc=${PIPESTATUS[1]}
  tee -a "$LOG" < "$tmp"
  LAST_FILE=$(grep '^>>> ' "$tmp" | tail -1 | sed 's/^>>> //')
  if [ "$rc" -ne 0 ] || grep -qE '^(ORA|SP2|PLS)-' "$tmp"; then rm -f "$tmp"; return 1; fi
  rm -f "$tmp"; return 0
}

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
TARGET_DESC=""
# connect_check: connect, print WHAT we are connected to, and abort if it is not the expected database.
connect_check() {
  if [ "$ENV_FILE_FOUND" != 1 ] && [ -z "${CONN_FROM_ENV:-}" ] && [ -z "$DB_USER" ]; then
    die "no target configured: copy .env.example to .env and fill it in (or use --env <name> / --env-file <path>)"
  fi
  local r id con usr dbn
  r=$(q "SELECT 'OK|'||SYS_CONTEXT('USERENV','CON_NAME')||'|'||SYS_CONTEXT('USERENV','SESSION_USER')||'|'||SYS_CONTEXT('USERENV','DB_NAME') FROM dual;")
  id=$(printf '%s\n' "$r" | grep '^OK|' | head -1)
  if [ -z "$id" ]; then
    echo "$r" | grep -E 'ORA-|SP2-' | head -3 >&2
    die "cannot connect to ${DB_USER:-?}@//${DB_HOST}:${DB_PORT}/${DB_SERVICE:-?} (app env '$APP_ENV'). Check .env, the password, and that the database is up."
  fi
  IFS='|' read -r _ con usr dbn <<< "$id"
  TARGET_DESC="$usr@$con (db $dbn, ${DB_HOST}:${DB_PORT}) app env '$APP_ENV'"
  echo "Target: $TARGET_DESC"
  if [ -n "$EXPECTED_DB" ]; then
    if [ "$(upper "$EXPECTED_DB")" != "$(upper "$con")" ] && [ "$(upper "$EXPECTED_DB")" != "$(upper "$dbn")" ]; then
      die "WRONG TARGET: connected to '$con' (db '$dbn') but EXPECTED_DB is '$EXPECTED_DB'. Nothing was changed. Fix .env."
    fi
  elif is_protected; then
    die "protected environment '$APP_ENV' needs EXPECTED_DB in .env (the service/PDB you intend to change)."
  fi
}
# guard <action>: for commands that change the target. Protected environments need CONFIRM=<EXPECTED_DB>.
guard() {
  if is_protected; then
    [ "$(upper "$CONFIRM")" = "$(upper "$EXPECTED_DB")" ] \
      || die "protected environment: to $1 target '$TARGET_DESC' re-run with CONFIRM=$EXPECTED_DB (you must type the expected database name)."
  fi
}

# ---- history + lock tables ------------------------------------------------
LOCK=${HIST}_lock
LOCK_UP=$(upper "$LOCK")
history_present() { [ "$(q "SELECT COUNT(*) FROM user_tables WHERE table_name='$HIST_UP';" | tr -d '[:space:]')" != "0" ]; }
bootstrap() {
  local out
  out=$(q "DECLARE n NUMBER; BEGIN
  SELECT COUNT(*) INTO n FROM user_tables WHERE table_name = '$HIST_UP';
  IF n = 0 THEN EXECUTE IMMEDIATE '
    CREATE TABLE $HIST (
      installed_rank NUMBER GENERATED ALWAYS AS IDENTITY,
      type           VARCHAR2(10)  NOT NULL,
      version        VARCHAR2(20),
      description    VARCHAR2(200) NOT NULL,
      script         VARCHAR2(300) NOT NULL,
      checksum       VARCHAR2(64),
      installed_by   VARCHAR2(60)  DEFAULT USER NOT NULL,
      installed_on   TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
      execution_ms   NUMBER,
      status         VARCHAR2(10)  NOT NULL,
      CONSTRAINT pk_${HIST} PRIMARY KEY (installed_rank),
      CONSTRAINT uk_${HIST}_ver UNIQUE (version),
      CONSTRAINT ck_${HIST}_type CHECK (type IN (''BASELINE'', ''VERSIONED'', ''REPEATABLE'')),
      CONSTRAINT ck_${HIST}_status CHECK (status IN (''SUCCESS'', ''FAILED'', ''UNDONE''))
    )';
  END IF;
  SELECT COUNT(*) INTO n FROM user_tables WHERE table_name = '$LOCK_UP';
  IF n = 0 THEN EXECUTE IMMEDIATE '
    CREATE TABLE $LOCK (
      id        NUMBER PRIMARY KEY,
      locked_by VARCHAR2(60),
      host      VARCHAR2(200),
      locked_at TIMESTAMP DEFAULT SYSTIMESTAMP,
      command   VARCHAR2(60)
    )';
  END IF;
END;
/")
  printf '%s\n' "$out" | grep -qE 'ORA-|SP2-|PLS-' && die "could not create the history/lock tables ($HIST): $out"
  return 0
}

# ---- run lock: one migration run per target at a time -------------------------
LOCK_HELD=0
release_lock() { if [ "$LOCK_HELD" = 1 ]; then q "DELETE FROM $LOCK WHERE id=1; COMMIT;" >/dev/null; LOCK_HELD=0; fi; }
acquire_lock() { # <command name>
  local host out who
  host=$(uname -n 2>/dev/null | tr -cd 'A-Za-z0-9._-'); [ -n "$host" ] || host=unknown
  out=$(q "INSERT INTO $LOCK (id, locked_by, host, command) VALUES (1, USER, '$host', '$1'); COMMIT;")
  if printf '%s\n' "$out" | grep -q 'ORA-00001'; then
    who=$(q "SELECT locked_by||' on '||host||' since '||TO_CHAR(locked_at,'YYYY-MM-DD HH24:MI:SS')||' ('||command||')' FROM $LOCK WHERE id=1;")
    die "another run holds the lock: $who. Wait for it. If it crashed, check nothing is running, then: migrate.sh unlock"
  fi
  printf '%s\n' "$out" | grep -qE 'ORA-|SP2-' && die "could not take the run lock: $out"
  LOCK_HELD=1
  trap release_lock EXIT
  trap 'exit 130' INT TERM
}
# begin <action>: the start of every command that changes the target.
# Order matters: identity + confirmation first, then "is this schema ours to touch?", and only then create/lock anything.
begin() {
  connect_check; guard "$1"
  case "$1" in
    migrate|step)
      if app_tables_without_history; then
        die "this schema already has tables but no migration history, so it will NOT be changed. Adopt it first: migrate.sh verify-baseline <version>, then migrate.sh baseline <version> (docs/ONBOARDING.md, part 3)."
      fi ;;
    undo|repair)
      history_present || die "no migration history in this schema: nothing to $1" ;;
  esac
  bootstrap
  acquire_lock "$1"
}

# ---- destructive statements ----------------------------------------------------
# destructive_hits <file>: print destructive statements (comments stripped, one line each); empty = none
destructive_hits() {
  sed -e 's/--.*$//' "$1" | tr '\n' ' ' | sed -e 's#/\*[^*]*\*\+\([^/*][^*]*\*\+\)*/##g' | tr ';' '\n' \
    | awk '{ st=toupper($0); gsub(/[ \t]+/," ",st); sub(/^ /,"",st) }
      st ~ /^DROP (TABLE|USER|SCHEMA|TABLESPACE|DATABASE|SEQUENCE) / || st ~ /^DROP (TABLE|USER|SCHEMA|TABLESPACE|DATABASE|SEQUENCE)$/ { print substr(st,1,70); next }
      st ~ /^TRUNCATE / { print substr(st,1,70); next }
      st ~ /^PURGE / { print substr(st,1,70); next }
      st ~ /^ALTER TABLE [^ ]+ DROP (COLUMN|\()/ { print substr(st,1,70); next }
      st ~ /^DELETE( FROM)? / && st !~ / WHERE / { print substr(st,1,70) }'
}
destructive_approved() { grep -qiE '^[[:space:]]*--[[:space:]]*destructive-approved:[[:space:]]*[^[:space:]]+' "$1"; }
# destructive_gate <file>: 0 = fine; 1 = blocked (protected env without approval marker)
destructive_gate() {
  local hits; hits=$(destructive_hits "$1")
  [ -z "$hits" ] && return 0
  destructive_approved "$1" && { echo "   ! $1 contains destructive statements, approved in the file:"; printf '%s\n' "$hits" | sed 's/^/       /'; return 0; }
  echo "   ! $1 contains destructive statements WITHOUT an approval marker:"; printf '%s\n' "$hits" | sed 's/^/       /'
  echo "     Add a line  -- destructive-approved: <ticket or reason>  after review (and take a backup)."
  is_protected && return 1
  echo "     (not a protected environment: continuing)"; return 0
}

# ---- pre-checks: conflicts a pending migration would run into --------------------------
# <MIGRATIONS_DIR>/checks/V<ver>.pre.sql: a SELECT returning one message per problem; no rows = fine.
precheck() { # <ver>: prints problems, returns 1 if any
  local f="$MIGRATIONS_DIR/checks/V$1.pre.sql" out
  [ -f "$f" ] || return 0
  out=$({ echo "SET HEADING OFF FEEDBACK OFF PAGESIZE 0 VERIFY OFF LINESIZE 500 TRIMSPOOL ON DEFINE OFF"; echo "@$f"; echo "EXIT"; } | sq 2>&1 | sed '/^[[:space:]]*$/d')
  [ -z "$out" ] && return 0
  printf '%s\n' "$out" | sed "s/^/   V$1 pre-check: /"
  return 1
}

app_tables_without_history() {   # 0 = schema has application tables but no recorded history
  local n
  if history_present; then
    [ "$(q "SELECT COUNT(*) FROM $HIST;" | tr -d '[:space:]')" = "0" ] || return 1
  fi
  n=$(q "SELECT COUNT(*) FROM user_tables WHERE table_name NOT IN ('$HIST_UP','$LOCK_UP') AND table_name NOT LIKE 'BIN\$%';" | tr -d '[:space:]')
  [ "$n" != "0" ]
}

# ---- file helpers -------------------------------------------------------
mig_files() { ls "$MIGRATIONS_DIR"/V*.sql 2>/dev/null | sort; }
mig_file_for() { ls "$MIGRATIONS_DIR"/V"$1"__*.sql 2>/dev/null | head -1; }
rep_files() { [ -d "$REPEATABLE_DIR" ] && find "$REPEATABLE_DIR" -type f ! -name 'README*' ! -name '.gitkeep' | sort; }   # folder order = run order
ver_of()  { local b; b=$(basename "$1"); b=${b#[VU]}; echo "${b%%__*}"; }
desc_of() { local b; b=$(basename "$1" .sql); echo "${b#*__}"; }
undo_file_for() { ls "$UNDO_DIR"/U"$1"__*.sql 2>/dev/null | head -1; }
obj_name() { local b; b=$(basename "$1"); b=${b%.*}; echo "$b" | tr '[:lower:]' '[:upper:]'; }
# object type from the file's CREATE OR REPLACE line (FUNCTION, PACKAGE BODY, VIEW, ...)
obj_type_of() {
  grep -iE -m1 '^[[:space:]]*CREATE[[:space:]]+OR[[:space:]]+REPLACE' "$1" | tr -s ' \t' '  ' | tr '[:lower:]' '[:upper:]' \
    | sed -E 's/^ *CREATE OR REPLACE (FORCE |EDITIONABLE |NONEDITIONABLE |NO FORCE )*(PACKAGE BODY|TYPE BODY|FUNCTION|PROCEDURE|PACKAGE|TRIGGER|TYPE|VIEW|SYNONYM).*/\2/'
}

# APPLIED_ROWS: "version|status|checksum" for BASELINE/VERSIONED rows
load_applied() {
  APPLIED_ROWS=""; history_present || return 0
  APPLIED_ROWS=$(q "SELECT version||'|'||status||'|'||NVL(checksum,'-') FROM $HIST WHERE type IN ('BASELINE','VERSIONED') ORDER BY installed_rank;")
  if printf '%s\n' "$APPLIED_ROWS" | grep -qE 'ORA-|SP2-'; then die "cannot read $HIST: $APPLIED_ROWS"; fi
}
# REP_ROWS: latest row per repeatable script: "script|status|checksum"
load_repeatable() {
  REP_ROWS=""; history_present && \
  REP_ROWS=$(q "SELECT script||'|'||status||'|'||NVL(checksum,'-') FROM (SELECT script,status,checksum,ROW_NUMBER() OVER (PARTITION BY script ORDER BY installed_rank DESC) rn FROM $HIST WHERE type='REPEATABLE') WHERE rn=1;")
  if printf '%s\n' "$REP_ROWS" | grep -qE 'ORA-|SP2-'; then die "cannot read $HIST: $REP_ROWS"; fi
  load_existing
}
load_existing() {
  EXISTING=$(q "SELECT object_type||'|'||object_name FROM user_objects WHERE object_type IN ('TYPE','TYPE BODY','FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW','SYNONYM');")
}
row_field() { printf '%s\n' "$APPLIED_ROWS" | awk -F'|' -v v="$1" -v n="$2" '$1==v{print $n; exit}'; }
rep_field() { printf '%s\n' "$REP_ROWS" | awk -F'|' -v s="$1" -v n="$2" '$1==s{print $n; exit}'; }
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
changed_rep_files() { local f; for f in $(rep_files); do [ -n "$(rep_reason "$f")" ] && echo "$f"; done; }

record() { # type version_literal description script checksum ms status
  local out
  out=$(q "INSERT INTO $HIST (type,version,description,script,checksum,execution_ms,status) VALUES ('$1',$2,'$3','$4','$5',$6,'$7'); COMMIT;")
  printf '%s\n' "$out" | grep -qE 'ORA-|SP2-' && echo "WARNING: could not record history: $out" >&2
  return 0
}

INVALID_NAMES=""
INVALID_ALL=""
invalid_list() {
  [ "${NO_COMPILE:-0}" = 1 ] || q "EXEC DBMS_UTILITY.COMPILE_SCHEMA(USER, FALSE);" >/dev/null   # read-only commands set NO_COMPILE=1
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
        f=$(mig_file_for "$v")
        if [ -z "$f" ]; then echo "x V$v was applied but its file is missing from $MIGRATIONS_DIR/"; bad=1
        else
          cur=$(sha_file "$f")
          if [ "$cur" != "$c" ]; then echo "x V$v checksum mismatch: $f was edited after it was applied. Revert it and add a NEW migration."; bad=1; fi
        fi
        [ $((10#$v)) -gt "$max" ] && max=$((10#$v)) ;;
    esac
  done <<< "$APPLIED_ROWS"
  for f in $(mig_files); do
    ver=$(ver_of "$f"); s=$(row_field "$ver" 2)
    if [ "$s" != "SUCCESS" ] && [ "$s" != "FAILED" ] && [ $((10#$ver)) -lt "$max" ] && [ "$OUT_OF_ORDER" != "1" ]; then
      echo "x $f is pending but a higher version is already applied (out of order). Renumber it, or set OUT_OF_ORDER=1 if intended."; bad=1
    fi
  done
  return $bad
}

cmd_validate() {
  NO_COMPILE=1                      # validate never changes the target (not even a recompile)
  connect_check
  local bad=0 s st c f r
  if ! history_present; then
    if app_tables_without_history; then
      echo "x the schema has tables but no migration history: it is not managed yet (verify-baseline / baseline, docs/ONBOARDING.md part 3)"
      echo "VALIDATE FAILED" >&2; return 1
    fi
    echo "i empty schema, no history yet: nothing to validate (run migrate.sh migrate)"; echo "VALIDATE OK"; return 0
  fi
  validate_core || bad=1
  post_check || bad=1
  load_repeatable
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
    case "$s" in "$REPEATABLE_DIR"/*) ;; *) continue ;; esac   # rows written by older tool versions
    [ -f "$s" ] || [ "$st" != "SUCCESS" ] || echo "i $s was removed from the repo but the object may still exist: add a migration that drops it"
  done <<< "$REP_ROWS"
  if [ $bad -eq 0 ]; then echo "VALIDATE OK"; else echo "VALIDATE FAILED" >&2; return 1; fi
}

# ---- migrate ------------------------------------------------------------
apply_version() {
  local f=$1 ver desc sum start ms status before
  ver=$(ver_of "$f"); desc=$(desc_of "$f"); sum=$(sha_file "$f")
  echo "-> applying V$ver  $desc"
  if ! precheck "$ver"; then
    echo "x V$ver NOT applied: its pre-check found problems (nothing was changed). Resolve them, then run again." >&2; return 1
  fi
  destructive_gate "$f" || { echo "x V$ver NOT applied (nothing was changed)." >&2; return 1; }
  q "DELETE FROM $HIST WHERE version='$ver' AND status IN ('FAILED','UNDONE'); COMMIT;" >/dev/null
  before=$(invalid_list)
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

x V$ver FAILED - details in $LOG
  The database may be PARTIALLY changed (Oracle DDL auto-commits).
  1. Check what was applied (e.g. migrate.sh sql "SELECT column_name FROM user_tab_columns WHERE table_name='...'").
  2. Put the schema back to its pre-migration state by hand (or run $UNDO_DIR/U${ver}__*.sql if it fits).
  3. migrate.sh repair      (clears the FAILED row)
  4. Fix $f (allowed: it never succeeded) and run migrate.sh migrate again.
MSG
  return 1
}

apply_repeatable() {
  local changed f ok=1 overall=0 bad_names before
  load_repeatable
  changed=$(changed_rep_files)
  if [ -z "$changed" ]; then echo "repeatable objects up to date"; return 0; fi
  echo "-> applying $(echo "$changed" | wc -l | tr -d '[:space:]') repeatable file(s):"
  for f in $changed; do echo "   $f  ($(rep_reason "$f"))"; done
  before=$(invalid_list)
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

preflight() { # common start of migrate/step
  begin "$1"
  validate_core || die "validation failed - fix the problems above first"
  load_applied
}

cmd_migrate() {
  preflight "migrate"
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

cmd_step() {
  preflight "step"
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

# ---- undo / repair / baseline / status / plan / sql / smoke ------------------
cmd_undo() {
  begin "undo"
  local ver uf
  ver=$(q "SELECT version FROM (SELECT version FROM $HIST WHERE type='VERSIONED' AND status='SUCCESS' ORDER BY installed_rank DESC) WHERE ROWNUM=1;" | tr -d '[:space:]')
  [ -z "$ver" ] && die "nothing to undo (baselined versions cannot be undone)"
  uf=$(undo_file_for "$ver"); [ -z "$uf" ] && die "no undo script $UNDO_DIR/U${ver}__*.sql for V$ver"
  echo "-> undoing V$ver using $uf"
  if run_script "$uf"; then
    q "UPDATE $HIST SET status='UNDONE' WHERE version='$ver'; COMMIT;" >/dev/null
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
  begin "repair"
  echo "FAILED rows to be removed:"
  q "SELECT '  '||NVL(version,'repeatable')||'  '||script FROM $HIST WHERE status='FAILED';"
  q "DELETE FROM $HIST WHERE status='FAILED'; COMMIT;" >/dev/null
  echo "repair done"
}

# ---- inventory / manifest / verify-baseline / baseline ------------------------------
# inventory: one line per table, column, sequence, code object of the connected schema (history tables excluded)
inventory() {
  q "SELECT 'TABLE|'||table_name FROM user_tables WHERE table_name NOT LIKE 'BIN\$%' AND table_name NOT IN ('$HIST_UP','$LOCK_UP')
UNION ALL
SELECT 'COLUMN|'||c.table_name||'|'||c.column_name||'|'||REGEXP_REPLACE(c.data_type,'\(.*\)','')
  FROM user_tab_columns c JOIN user_tables t ON t.table_name = c.table_name
 WHERE c.table_name NOT LIKE 'BIN\$%' AND c.table_name NOT IN ('$HIST_UP','$LOCK_UP')
UNION ALL
SELECT 'SEQUENCE|'||sequence_name FROM user_sequences
UNION ALL
SELECT 'OBJECT|'||object_type||'|'||object_name||'|'||status FROM user_objects
 WHERE object_type IN ('TYPE','TYPE BODY','FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW')
   AND object_name NOT LIKE 'SYS\_PLSQL\_%' ESCAPE '\'
ORDER BY 1;"
}

cmd_manifest() {
  local ver=${1:-}; [ -n "$ver" ] || die "usage: migrate.sh manifest <version>   (run it on a reference database that is at that version)"
  ver=${ver#V}
  connect_check >&2
  local inv f key map="" line t n path
  inv=$(inventory)
  printf '%s\n' "$inv" | grep -qE '^(ORA|SP2)-' && die "cannot read the schema inventory: $inv"
  for f in $(rep_files); do map="$map$(obj_type_of "$f")|$(obj_name "$f")|$f|$(sha_file "$f")"$'\n'; done
  echo "# Baseline manifest for V$ver: what an existing database must contain to be adopted at this version."
  echo "# Generated $(date -u +%Y-%m-%dT%H:%M:%SZ) from $TARGET_DESC. REVIEW before committing; regenerate on a fresh reference install."
  echo "SCHEMA|$ver"
  printf '%s\n' "$inv" | grep -E '^(TABLE|COLUMN|SEQUENCE)\|'
  printf '%s\n' "$inv" | grep '^OBJECT|' | while IFS='|' read -r _ t n st; do
    [ "$st" = "VALID" ] || { echo "# skipped $t $n: status $st" ; continue; }
    line=$(printf '%s' "$map" | awk -F'|' -v t="$t" -v n="$n" '$1==t && $2==n {print $3 "|" $4; exit}')
    if [ -n "$line" ]; then echo "OBJECT|$t|$n|${line%%|*}|${line#*|}"; else echo "# no repeatable file for $t $n (not required)"; fi
  done
}

# verify_manifest <ver>: compare the database with baseline/V<ver>.manifest. Prints problems; returns the problem count (0 = matches)
verify_manifest() {
  local m="$BASELINE_DIR/V$1.manifest" inv out
  [ -f "$m" ] || die "no baseline manifest $m. Only a known, documented starting state can be adopted. Create the manifest from a reference database at V$1: migrate.sh manifest $1 > $m"
  grep -q '^TABLE|' "$m" || die "$m has no TABLE lines: not a valid manifest"
  inv=$(inventory)
  printf '%s\n' "$inv" | grep -qE '^(ORA|SP2)-' && die "cannot read the schema inventory: $inv"
  out=$({ printf '%s\n' "$inv" | sed 's/^/A|/'; grep -E '^(TABLE|COLUMN|SEQUENCE|OBJECT)\|' "$m" | tr -d '\r' | sed 's/^/M|/'; } | awk -F'|' '
    $1=="A" { if ($2=="TABLE") at[$3]=1; else if ($2=="COLUMN") ac[$3 "|" $4]=$5; else if ($2=="SEQUENCE") as[$3]=1; else if ($2=="OBJECT") ao[$3 "|" $4]=$5; next }
    $1=="M" {
      if ($2=="TABLE") { mt[$3]=1; if (!($3 in at)) print "missing table " $3 }
      else if ($2=="COLUMN") { if (!($3 in at)) next; k=$3 "|" $4
        if (!(k in ac)) print "missing column " $3 "." $4 " (" $5 ")"; else if (ac[k]!=$5) print "column " $3 "." $4 " has type " ac[k] ", expected " $5 }
      else if ($2=="SEQUENCE") { if (!($3 in as)) print "missing sequence " $3 }
      else if ($2=="OBJECT") { k=$3 "|" $4; if (!(k in ao)) print "missing " $3 " " $4; else if (ao[k]!="VALID") print $3 " " $4 " exists but is " ao[k] " (must compile before adoption)" }
    }')
  VERIFY_PROBLEMS=$out
  if [ -n "$out" ]; then printf '%s\n' "$out" | sed 's/^/   x /'; printf '%s\n' "$out" | wc -l | tr -d '[:space:]'; else echo 0; fi
}

require_manifest() { # <ver>
  local m="$BASELINE_DIR/V$1.manifest"
  [ -f "$m" ] || die "no baseline manifest $m. Only a known, documented starting state can be adopted. Create it from a reference database at V$1: migrate.sh manifest $1 > $m"
  grep -q '^TABLE|' "$m" || die "$m has no TABLE lines: not a valid manifest"
}

cmd_verify_baseline() {
  local ver=${1:-}; [ -n "$ver" ] || die "usage: migrate.sh verify-baseline <version>"
  ver=${ver#V}
  [ -n "$(mig_file_for "$ver")" ] || die "no migration V${ver}__*.sql in $MIGRATIONS_DIR/"
  require_manifest "$ver"
  connect_check
  local out n bad=0 f v
  echo "Checking the database against $BASELINE_DIR/V$ver.manifest ..."
  out=$(verify_manifest "$ver"); n=$(printf '%s\n' "$out" | tail -1)
  printf '%s\n' "$out" | sed '$d'
  [ "$n" = "0" ] || bad=1
  if history_present && [ "$(q "SELECT COUNT(*) FROM $HIST;" | tr -d '[:space:]')" != "0" ]; then
    echo "i this schema already has migration history: it is managed. (baseline is only for schemas without history)"
  else
    echo "Pre-checks of the migrations that would be applied after V$ver:"
    local any=0
    for f in $(mig_files); do
      v=$(ver_of "$f"); [ $((10#$v)) -gt $((10#$ver)) ] || continue
      any=1
      if precheck "$v"; then echo "   V$v ok"; else bad=1; fi
    done
    [ $any -eq 0 ] && echo "   (no later migrations)"
  fi
  if [ $bad -eq 0 ]; then echo "READY: the database matches V$ver and the pending migrations have no conflicts. Next: migrate.sh baseline $ver"
  else echo "NOT READY: resolve the items above (fix the database or the plan), then run verify-baseline again. Nothing was changed." >&2; return 1; fi
}

cmd_baseline() {
  local ver=${1:-}; [ -n "$ver" ] || die "usage: migrate.sh baseline <version>   (run verify-baseline first)"
  ver=${ver#V}
  [ -n "$(mig_file_for "$ver")" ] || die "no migration V${ver}__*.sql in $MIGRATIONS_DIR/"
  require_manifest "$ver"
  connect_check; guard "baseline"
  if history_present && [ "$(q "SELECT COUNT(*) FROM $HIST;" | tr -d '[:space:]')" != "0" ]; then
    die "this schema already has migration history. Baseline is a one-time step for schemas without history."
  fi
  echo "Verifying before recording anything ..."
  local out n; out=$(verify_manifest "$ver"); n=$(printf '%s\n' "$out" | tail -1)
  printf '%s\n' "$out" | sed '$d'
  [ "$n" = "0" ] || die "baseline REFUSED: the database does not match V$ver ($n problem(s) above). Nothing was changed."
  local f v pc=0
  for f in $(mig_files); do
    v=$(ver_of "$f"); [ $((10#$v)) -gt $((10#$ver)) ] || continue
    precheck "$v" || pc=1
  done
  [ $pc -eq 0 ] || die "baseline REFUSED: pre-checks of the pending migrations found problems (above). Nothing was changed."
  bootstrap; acquire_lock "baseline"
  local sql="" t name path sum nv=0 nr=0 desc
  for f in $(mig_files); do
    v=$(ver_of "$f"); [ $((10#$v)) -le $((10#$ver)) ] || continue
    desc=$(desc_of "$f")
    sql="$sql INSERT INTO $HIST (type,version,description,script,checksum,execution_ms,status) VALUES ('BASELINE','$v','$desc','$f','$(sha_file "$f")',0,'SUCCESS');"$'\n'
    nv=$((nv + 1))
  done
  # code objects the manifest verified as present: recorded as already deployed (NOT executed again)
  while IFS='|' read -r _ t name path sum; do
    [ -n "$path" ] && [ "$path" != "-" ] || continue
    sql="$sql INSERT INTO $HIST (type,version,description,script,checksum,execution_ms,status) VALUES ('REPEATABLE',NULL,'baseline: already deployed','$path','$sum',0,'SUCCESS');"$'\n'
    nr=$((nr + 1))
  done < <(grep '^OBJECT|' "$BASELINE_DIR/V$ver.manifest" | tr -d '\r')
  out=$(q "$sql
COMMIT;")
  printf '%s\n' "$out" | grep -qE 'ORA-|SP2-' && die "could not record the baseline: $out"
  echo "BASELINE recorded: $nv migration(s) up to V$ver and $nr verified code object(s) marked as already deployed. Nothing was executed against your data."
  echo "Next: migrate.sh plan   (only later versions and new/changed code files are pending)"
}

cmd_unlock() {
  connect_check; guard "unlock"
  history_present || die "no history table: nothing to unlock"
  local who; who=$(q "SELECT locked_by||' on '||host||' since '||TO_CHAR(locked_at,'YYYY-MM-DD HH24:MI:SS')||' ('||command||')' FROM $LOCK WHERE id=1;" 2>/dev/null | grep -v 'ORA-')
  [ -n "$who" ] || { echo "no lock is held"; return 0; }
  echo "removing lock held by: $who"
  q "DELETE FROM $LOCK WHERE id=1; COMMIT;" >/dev/null
  echo "unlocked"
}

cmd_status() {
  connect_check
  if history_present; then
    echo "Applied history (versioned):"
    q "SELECT RPAD(installed_rank,4)||RPAD(NVL(version,'-'),6)||RPAD(type,11)||RPAD(status,9)||RPAD(TO_CHAR(installed_on,'YYYY-MM-DD HH24:MI'),18)||description FROM $HIST WHERE type<>'REPEATABLE' ORDER BY installed_rank;"
  else
    echo "No migration history in this schema yet."
    app_tables_without_history && echo "The schema has tables: adopt it with verify-baseline / baseline before migrating."
  fi
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

cmd_plan() {
  connect_check
  local show_sql=0 f ver n=0 cur r
  [ "${1:-}" = "--sql" ] && show_sql=1
  if [ "$(q "SELECT COUNT(*) FROM user_tables WHERE table_name='$HIST_UP';" | tr -d '[:space:]')" = "0" ]; then
    APPLIED_ROWS=""; REP_ROWS=""; load_existing
    if [ "$(q "SELECT COUNT(*) FROM user_tables;" | tr -d '[:space:]')" != "0" ]; then
      echo "History  : none, but the schema already has tables -> NOT managed yet: migrate will refuse."
      echo "           Adopt it: migrate.sh verify-baseline <version>, then migrate.sh baseline <version> (docs/ONBOARDING.md part 3)"
    else
      echo "History  : none yet (empty schema) - $HIST will be created by migrate"
    fi
  else
    load_applied; load_repeatable
    cur=$(q "SELECT MAX(TO_NUMBER(version)) FROM $HIST WHERE type IN ('BASELINE','VERSIONED') AND status='SUCCESS';" | tr -d '[:space:]')
    echo "Current  : V${cur:-none}"
    app_tables_without_history && echo "History  : empty, but the schema already has tables -> adopt it with verify-baseline / baseline first (migrate will refuse)"
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
  if [ $n -gt 0 ]; then
    echo "   Safety checks on the pending migrations:"
    local pc=0 managed=0
    history_present && [ "$(q "SELECT COUNT(*) FROM $HIST;" | tr -d '[:space:]')" != "0" ] && managed=1
    for f in $(mig_files); do
      ver=$(ver_of "$f"); [ "$(row_field "$ver" 2)" = "SUCCESS" ] && continue
      if [ $managed -eq 1 ]; then precheck "$ver" || pc=1; fi
      local dh; dh=$(destructive_hits "$f")
      if [ -n "$dh" ]; then
        if destructive_approved "$f"; then echo "   V$ver destructive statements (approved in file)"; else echo "   V$ver destructive statements WITHOUT approval marker - blocked on protected environments"; pc=1; fi
      fi
    done
    [ $pc -eq 0 ] && echo "   no conflicts found$([ $managed -eq 0 ] && echo ' (pre-checks run once the schema has history)')"
  fi
  echo
  echo "2) Repeatable files, run after the migrations:"
  n=0
  for f in $(rep_files); do
    r=$(rep_reason "$f")
    [ -z "$r" ] && continue
    n=$((n + 1)); echo "   - $f  ($r)"
  done
  [ $n -eq 0 ] && echo "   (none)"
  echo
  echo "Nothing was changed. Next: 'step' (one migration) or 'migrate' (everything above)."
}

cmd_sql() {
  connect_check
  local stmt=${1:-}
  [ -z "$stmt" ] && stmt=$(cat)
  if is_protected; then
    case "$(printf '%s' "$stmt" | tr '[:lower:]' '[:upper:]' | sed -e 's/^[[:space:]]*//')" in
      SELECT*|WITH*|"DESC "*|DESCRIBE*) ;;
      *) guard "run this non-SELECT statement" ;;
    esac
  fi
  case "$stmt" in *";"|*"/") ;; *) stmt="$stmt;";; esac
  { echo "SET LINESIZE 220 PAGESIZE 200 FEEDBACK ON TRIMOUT ON DEFINE OFF"; echo "COLUMN script FORMAT A60"; echo "COLUMN description FORMAT A40"; echo "COLUMN checksum FORMAT A12 TRUNCATED"; echo "$stmt"; echo "EXIT ROLLBACK"; } | sq
}

cmd_smoke() {
  if [ -z "$SMOKE_SQL" ] || [ "$SMOKE_SQL" = "none" ]; then echo "no SMOKE_SQL configured - skipping smoke tests"; return 0; fi
  [ -f "$SMOKE_SQL" ] || die "SMOKE_SQL=$SMOKE_SQL not found"
  connect_check; guard "run the smoke tests"
  run_script "$SMOKE_SQL"
}

case "${1:-help}" in
  plan)     cmd_plan "${2:-}" ;;
  step)     cmd_step ;;
  sql)      shift; cmd_sql "$*" ;;
  migrate)  cmd_migrate ;;
  status)   cmd_status ;;
  validate) cmd_validate ;;
  undo)     cmd_undo ;;
  repair)   cmd_repair ;;
  baseline) cmd_baseline "${2:-}" ;;
  verify-baseline) cmd_verify_baseline "${2:-}" ;;
  manifest) cmd_manifest "${2:-}" ;;
  unlock)   cmd_unlock ;;
  smoke)    cmd_smoke ;;
  deploy)   cmd_migrate && cmd_validate && cmd_smoke && echo "DEPLOY OK" ;;
  *) sed -n '2,29p' "$0" ;;
esac
