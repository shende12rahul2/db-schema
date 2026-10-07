#!/usr/bin/env bash
# Static checks, no database needed. Optional: BASE_REF=origin/main to forbid edits of existing migrations.
set -uo pipefail
cd "$(dirname "$0")/.."
bad=0
err() { echo "x $*"; bad=1; }

seen=""
for f in migrations/V*.sql; do
  b=$(basename "$f")
  [[ "$b" =~ ^V([0-9]{3,})__[A-Za-z0-9_]+\.sql$ ]] || { err "bad name: $b (expected V<NNN>__snake_case.sql)"; continue; }
  v=$((10#${BASH_REMATCH[1]}))
  case " $seen " in *" $v "*) err "duplicate version number $v ($b)";; esac
  seen="$seen $v"
  ls migrations/undo/U"${BASH_REMATCH[1]}"__*.sql >/dev/null 2>&1 || err "missing undo script for $b"
  [ -s "$f" ] || err "$b is empty"
  grep -qiE '^[[:space:]]*(DROP[[:space:]]+TABLE|TRUNCATE)' "$f" && echo "! $b contains DROP TABLE/TRUNCATE - make sure a backup/undo plan exists"
done
for u in migrations/undo/U*.sql; do
  b=$(basename "$u")
  [[ "$b" =~ ^U([0-9]{3,})__ ]] || { err "bad undo name: $b"; continue; }
  ls migrations/V"${BASH_REMATCH[1]}"__*.sql >/dev/null 2>&1 || err "undo without migration: $b"
done
# gaps
prev=0
for v in $(echo $seen | tr ' ' '\n' | sort -n); do
  [ "$v" -ne $((prev + 1)) ] && echo "! gap in version numbers before V$v"
  prev=$v
done
# immutability of already-merged migrations
if [ -n "${BASE_REF:-}" ]; then
  mod=$(git diff --name-status "$BASE_REF"...HEAD -- 'migrations/V*.sql' | awk '$1 ~ /^(M|D|R)/ {print $NF}')
  [ -n "$mod" ] && err "existing migrations were modified/deleted (add a new migration instead): $mod"
fi
[ $bad -eq 0 ] && echo "LINT OK" || { echo "LINT FAILED"; exit 1; }
