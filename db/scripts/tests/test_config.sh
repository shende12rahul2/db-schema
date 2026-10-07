#!/usr/bin/env bash
# Tests for scripts/lib/config.sh (.env parsing and precedence). No database needed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; fail=1; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/config"; printf 'PROJECT_NAME=demo\nHISTORY_TABLE=hist_demo\n' > "$T/config/default.conf"
cat > "$T/.env" <<'ENVF'
# comment
APP_ENV=prod   # trailing comment
DB_HOST = bad-key-with-spaces-is-ignored
DB_PORT=1522
DB_USER=owner
DB_PASSWORD="p@ss w#rd$HOME `id`"
DB_SERVICE='SVC1'
EXPECTED_DB=SVC1
export PROTECTED_ENVS=prod,uat
NOT_ALLOWED=1
ENVF
printf 'DB_HOST=winhost\r\n' >> "$T/.env"
v() { VAR=$1 bash -c 'DB_DIR='"$T"'; VAR='"$1"'; . '"$HERE"'/lib/config.sh; eval "echo \"\${$VAR}\""' ; }
check "project name from default.conf"  demo          "$(v PROJECT_NAME)"
check "history table from default.conf" hist_demo     "$(v HISTORY_TABLE)"
check "APP_ENV, trailing comment cut"   prod          "$(v APP_ENV)"
check "CRLF line tolerated"             winhost       "$(v DB_HOST)"
check "single quotes removed"           SVC1          "$(v DB_SERVICE)"
check "EXPECTED_DB read (key at line break of the key list)" SVC1 "$(v EXPECTED_DB)"
check "PROTECTED_ENVS with export prefix" "prod,uat"  "$(v PROTECTED_ENVS)"
check "password kept literally (no expansion)" 'p@ss w#rd$HOME `id`' "$(v DB_PASSWORD)"
check "unknown key not imported"        unset         "$(v NOT_ALLOWED || true)$( [ -z "$(v NOT_ALLOWED)" ] && echo unset)"
check "CONN quotes the password"        'owner/"p@ss w#rd$HOME `id`"@//winhost:1522/SVC1' "$(v CONN)"
check "environment variable beats .env" 9999          "$(DB_PORT=9999 v DB_PORT)"
cp "$T/.env" "$T/.env.test"
check "--env name selects .env.<name>"  "$T/.env.test" "$(ENV_NAME=test v ENV_FILE)"
check "missing .env file is reported"   0 "$(rm "$T/.env" "$T/.env.test"; v ENV_FILE_FOUND)"
check "runner defaults to local"        local         "$(v RUNNER)"
[ $fail -eq 0 ] && echo "ALL CONFIG TESTS PASSED" || { echo "CONFIG TESTS FAILED"; exit 1; }
