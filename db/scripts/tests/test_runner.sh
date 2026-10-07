#!/usr/bin/env bash
# Behaviour tests for scripts/migrate.sh WITHOUT a database: sqlplus is replaced by scripts/tests/fake_sqlplus.py,
# which emulates only the history/lock/inventory bookkeeping. They prove the runner's DECISIONS (what it runs, refuses,
# records), not that the SQL files are valid Oracle SQL - the CI job against a real Oracle does that.
#
#   ./scripts/tests/test_runner.sh            run everything
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; SRC="$(cd "$HERE/.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"; printf '#!/bin/sh\nexec python3 "%s/scripts/tests/fake_sqlplus.py" "$@"\n' "$SRC" > "$T/bin/sqlplus"; chmod +x "$T/bin/sqlplus"
fail=0; n=0
ok()   { n=$((n + 1)); echo "ok   $1"; }
bad()  { n=$((n + 1)); fail=1; echo "FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       | /'; }
is()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi; }
has()  { if grep -qF -- "$2" "$T/out"; then ok "$1"; else bad "$1 (output lacks: $2)" "$(tail -8 "$T/out")"; fi; }
hasnt(){ if grep -qF -- "$2" "$T/out"; then bad "$1 (output has: $2)" "$(tail -8 "$T/out")"; else ok "$1"; fi; }

# newcase <name> [env lines...] : fresh copy of db/ with its own .env and its own fake database
newcase() {
  C="$T/$1"; shift; rm -rf "$C"; mkdir -p "$C"; cp -r "$SRC" "$C/db"; rm -f "$C/db/.env"
  { echo "RUNNER=local"; echo "APP_ENV=dev"; echo "DB_HOST=h"; echo "DB_SERVICE=FREEPDB1"; echo "DB_USER=bank"; echo "DB_PASSWORD=pw"; echo "EXPECTED_DB=FREEPDB1"
    for l in "$@"; do echo "$l"; done; } > "$C/db/.env"
  export FAKE_STATE="$C/state.json"; rm -f "$FAKE_STATE"; unset FAKE_HIST CONFIRM
  cd "$C/db"; export LOG="$C/run.log"
}
run() { PATH="$T/bin:$PATH" bash scripts/migrate.sh "$@" > "$T/out" 2>&1; RC=$?; }
st()  { python3 - "$FAKE_STATE" "$1" <<'PY'
import json, os, sys
s = {"sv": False, "hist": [], "log": [], "lock": None, "objs": [], "tables": False}
if os.path.exists(sys.argv[1]): s.update(json.load(open(sys.argv[1])))
print(eval(sys.argv[2]))
PY
}
setst() { python3 - "$FAKE_STATE" "$1" <<'PY'
import json, os, sys
_path, _code = sys.argv[1], sys.argv[2]
s = json.load(open(_path)) if os.path.exists(_path) else {}
exec(_code); json.dump(s, open(_path, "w"))
PY
}
# an "existing client database": tables + every code object of the V001 manifest already present, no history
existing_client() { setst "
objs = []
for l in open('baseline/V001.manifest'):
    if l.startswith('OBJECT|'):
        parts = l.split('|'); objs.append([parts[1], parts[2]])
s.update({'tables': True, 'objs': objs})"; }
nhist() { st "len(s['hist'])"; }

echo "== 1. FRESH INSTALL (empty schema)"
newcase fresh
run plan;    is "plan on empty schema succeeds" 0 $RC;  has "plan says empty schema" "none yet (empty schema)"
run migrate; is "fresh migrate succeeds" 0 $RC;         has "MIGRATE OK" "MIGRATE OK"
is "6 versioned rows recorded (V001..V006)" 6 "$(st "len([r for r in s['hist'] if r['type']=='VERSIONED' and r['status']=='SUCCESS'])")"
is "78 repeatable code files recorded" 78 "$(st "len([r for r in s['hist'] if r['type']=='REPEATABLE'])")"
is "V001 (legacy install) was executed" True "$(st "'migrations/V001__baseline.sql' in s['log']")"
is "dependency order: V001 before any code file, tables before later versions" True "$(st "s['log'].index('migrations/V001__baseline.sql') < s['log'].index('migrations/V002__add_customer_email_verified.sql') < s['log'].index('repeatable/01_types/t_address_typ.tps')")"
run validate; is "validate passes" 0 $RC;              has "VALIDATE OK" "VALIDATE OK"
before=$(nhist); logn=$(st "len(s['log'])")
echo "== 2. REPEAT EXECUTION"
run migrate; is "second migrate succeeds" 0 $RC;        has "nothing pending" "no pending versioned migrations"; has "code up to date" "repeatable objects up to date"
is "history unchanged by the repeat run" "$before" "$(nhist)"
is "no SQL file executed on the repeat run" "$logn" "$(st "len(s['log'])")"
is "lock released after a run" None "$(st "s['lock']")"

echo "== 3. EXISTING CLIENT DATABASE (verified adoption)"
newcase client; existing_client
run plan;    has "plan: not managed yet" "NOT managed yet"
run migrate; is "migrate REFUSES an unmanaged non-empty schema" 1 $RC; has "refusal text" "will NOT be changed"
is "refusal created nothing (no history table)" False "$(st "s['sv']")"
run status;   is "status works on an unmanaged schema" 0 $RC
run validate; is "validate flags an unmanaged schema" 1 $RC;   has "explains why" "not managed yet"
run config;   is "config works without touching the database" 0 $RC
is "read-only commands created nothing" False "$(st "s['sv']")"
run verify-baseline 001; is "verify-baseline READY" 0 $RC;  has "READY" "READY: the database matches V001"
is "verify changed nothing" False "$(st "s['sv']")"
run baseline 001; is "baseline succeeds after verification" 0 $RC; has "baseline recorded" "BASELINE recorded"
is "one BASELINE row, V001" "['001']" "$(st "[r['version'] for r in s['hist'] if r['type']=='BASELINE']")"
is "77 verified code objects recorded as already deployed" 77 "$(st "len([r for r in s['hist'] if r['type']=='REPEATABLE'])")"
is "nothing was executed against the client database" "[]" "$(st "s['log']")"
run baseline 001; is "a second baseline is refused" 1 $RC;  has "already has migration history" "already has migration history"
run plan; has "only V002 pending now" "V002"; hasnt "V001 not pending" "V001  migrations"
has "only the one new code file pending" "trg_customer_prefs_bi.trg  (new)"
run migrate; is "migrate applies only what is pending" 0 $RC
is "V001 never executed on the client database" False "$(st "'migrations/V001__baseline.sql' in s['log']")"
is "baselined code files were not re-created" False "$(st "'repeatable/03_functions/fn_calc_emi.fnc' in s['log']")"
is "the new trigger file was applied" True "$(st "'repeatable/07_triggers/trg_customer_prefs_bi.trg' in s['log']")"
is "V002..V006 applied in order" "['002', '003', '004', '005', '006']" "$(st "[r['version'] for r in s['hist'] if r['type']=='VERSIONED']")"
run validate; is "client validate passes" 0 $RC

echo "== 4. UNKNOWN / INCOMPATIBLE DATABASE (must stop and explain)"
newcase odd; existing_client
setst "s['inv_remove'] = ['COLUMN|CUSTOMERS|PAN_NUMBER|VARCHAR2', 'TABLE|COLLATERALS']; s['col_types'] = {'ACCOUNTS|BALANCE': 'VARCHAR2'}; s['invalid'] = ['PACKAGE BODY PKG_COMPLIANCE']"
run verify-baseline 001; is "verify-baseline NOT READY" 1 $RC
has "reports missing table" "missing table COLLATERALS"; has "reports missing column" "missing column CUSTOMERS.PAN_NUMBER"
has "reports incompatible type" "column ACCOUNTS.BALANCE has type VARCHAR2, expected NUMBER"; has "reports invalid object" "PACKAGE BODY PKG_COMPLIANCE exists but is INVALID"
run baseline 001; is "baseline REFUSED" 1 $RC;      has "refusal text" "baseline REFUSED"
is "nothing recorded" False "$(st "s['sv']")"
run migrate; is "migrate refused as well" 1 $RC
newcase odd2; existing_client
setst "s['pre'] = {'V003.pre.sql': ['loan_applications: 2 row(s) with status PENDING would be set to REJECTED by V003']}"
run verify-baseline 001; is "pre-check problem blocks adoption" 1 $RC; has "shows the pre-check message" "would be set to REJECTED by V003"
run baseline 001;        is "baseline refused on pre-check problem" 1 $RC
newcase nomanifest; existing_client
run verify-baseline 002; is "unknown starting state refused" 1 $RC;  has "asks for a manifest" "no baseline manifest"
is "unknown state: nothing changed" False "$(st "s['sv']")"

echo "== 5. FAILURE AND RECOVERY"
newcase fail; run migrate >/dev/null
printf 'ALTER TABLE accounts ADD (x NUMBER);\n-- MOCK_FAIL\n' > migrations/V007__bad.sql
run migrate; is "failing migration stops the run" 1 $RC;  has "failure explained" "V007 FAILED"
is "failure recorded" FAILED "$(st "[r['status'] for r in s['hist'] if r['version']=='007'][0]")"
run migrate; is "further runs are blocked" 1 $RC;        has "block explained" "recorded as FAILED"
run repair;  is "repair succeeds" 0 $RC
sed -i '/MOCK_FAIL/d' migrations/V007__bad.sql
run migrate; is "corrected migration applies" 0 $RC;     is "V007 now SUCCESS" SUCCESS "$(st "[r['status'] for r in s['hist'] if r['version']=='007'][0]")"
echo "-- edited after release" >> migrations/V002__add_customer_email_verified.sql
run migrate; is "edited released migration is rejected" 1 $RC; has "checksum drift reported" "checksum mismatch"
git checkout -q -- . 2>/dev/null || sed -i '$d' migrations/V002__add_customer_email_verified.sql

echo "== 6. WRONG TARGET"
newcase wrong "EXPECTED_DB=SOMETHING_ELSE"
run migrate; is "migrate aborts on identity mismatch" 1 $RC;  has "says wrong target" "WRONG TARGET"
is "nothing was created" False "$(st "s['sv']")"; is "no SQL ran" "[]" "$(st "s['log']")"
run plan; is "even plan stops" 1 $RC

echo "== 7. PROTECTED ENVIRONMENT"
newcase prod "APP_ENV=prod"
run migrate;                   is "prod without CONFIRM refused" 1 $RC;        has "asks to type the database name" "CONFIRM=FREEPDB1"
CONFIRM=yes run migrate;       is "CONFIRM=yes is not enough" 1 $RC
CONFIRM=OTHER run migrate;     is "wrong CONFIRM refused" 1 $RC
is "nothing happened" "[]" "$(st "s['log']")"
CONFIRM=FREEPDB1 run migrate;  is "typing the expected database name allows it" 0 $RC
newcase prod2 "APP_ENV=prod" "EXPECTED_DB="
run plan;                      is "protected env without EXPECTED_DB refused" 1 $RC;  has "explains" "needs EXPECTED_DB"
newcase prod3 "APP_ENV=prod"; run migrate >/dev/null 2>&1; CONFIRM=FREEPDB1 run migrate >/dev/null
run sql "UPDATE accounts SET balance = 0";  is "prod: non-SELECT sql needs confirmation" 1 $RC
run sql "SELECT 1 FROM dual";               is "prod: SELECT allowed" 0 $RC

echo "== 8. CONCURRENT RUNS"
newcase lock
setst "s['lock'] = 'ANOTHER on otherhost since 2026-01-01 00:00:00 (migrate)'"
run migrate; is "second run refused while locked" 1 $RC;  has "names the lock holder" "another run holds the lock"
run unlock;  is "unlock clears a stale lock" 0 $RC;       run migrate; is "migrate works after unlock" 0 $RC

echo "== 9. DESTRUCTIVE CHANGES"
newcase destr "APP_ENV=prod"; CONFIRM=FREEPDB1 run migrate >/dev/null
printf 'DROP TABLE accounts;\n' > migrations/V007__drop.sql
CONFIRM=FREEPDB1 run migrate; is "protected: unapproved destructive migration blocked" 1 $RC; has "explains the marker" "destructive-approved"
is "V007 neither applied nor marked failed" "[]" "$(st "[r for r in s['hist'] if r['version']=='007']")"
printf -- '-- destructive-approved: TICKET-42 retired table, backup taken\nDROP TABLE accounts;\n' > migrations/V007__drop.sql
CONFIRM=FREEPDB1 run migrate; is "approved destructive migration runs" 0 $RC
newcase destr2; run migrate >/dev/null; printf 'TRUNCATE TABLE payments;\n' > migrations/V007__t.sql
run migrate; is "dev: warns but continues" 0 $RC;  has "warning shown" "WITHOUT an approval marker"

echo "== 10. PRE-CHECK BLOCKS A PENDING MIGRATION"
newcase pre; existing_client; run baseline 001 >/dev/null
setst "s['pre'] = {'V003.pre.sql': ['loan_applications: 3 row(s) with status PENDING would be set to REJECTED by V003']}"
run migrate; is "migrate stops at the failing pre-check" 1 $RC;  has "message shown" "V003 pre-check"
is "V002 (clean) was applied before it" "['002']" "$(st "[r['version'] for r in s['hist'] if r['type']=='VERSIONED']")"
is "V003 not applied, not marked failed" "[]" "$(st "[r for r in s['hist'] if r['version']=='003']")"

echo "== 11. SEPARATE HISTORY PER TARGET"
newcase devA; run migrate >/dev/null; a=$(nhist)
newcase devB; is "a second schema starts with its own empty history" 0 "$(nhist)"
run migrate >/dev/null; is "and ends with the same set, independently" "$a" "$(nhist)"

[ $fail -eq 0 ] && echo "ALL $n RUNNER CHECKS PASSED" || { echo "RUNNER CHECKS FAILED"; exit 1; }
