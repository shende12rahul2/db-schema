#!/usr/bin/env bash
# Static checks, no database needed (bash only: Linux, macOS, Git Bash or WSL on Windows).
# Optional: BASE_REF=origin/main to forbid edits of already-merged migrations and the frozen baseline.
set -uo pipefail
cd "$(dirname "$0")/.."
bad=0
err() { echo "x $*"; bad=1; }

# ---- versioned migrations -------------------------------------------------
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
prev=0
for v in $(echo $seen | tr ' ' '\n' | sort -n); do
  [ "$v" -ne $((prev + 1)) ] && echo "! gap in version numbers before V$v"
  prev=$v
done

# ---- repeatable objects ---------------------------------------------------
declare_ext() {
  case "$1" in
    01_types) echo tps;; 02_type_bodies) echo tpb;; 03_functions) echo fnc;; 04_procedures) echo prc;;
    05_package_specs) echo spc;; 06_package_bodies) echo bdy;; 07_triggers) echo trg;; 08_views) echo vw;;
    *) echo "";;
  esac
}
for f in $(find repeatable -type f ! -name 'README*' | sort); do
  dir=$(basename "$(dirname "$f")"); file=$(basename "$f"); ext=${file##*.}; base=${file%.*}
  want=$(declare_ext "$dir")
  [ -z "$want" ] && { err "$f: unknown repeatable folder '$dir'"; continue; }
  [ "$ext" = "$want" ] || err "$f: files in $dir must end in .$want"
  first=$(grep -iE -m1 '^[[:space:]]*CREATE[[:space:]]+OR[[:space:]]+REPLACE' "$f" | tr -s ' ' | tr '[:upper:]' '[:lower:]')
  if [ -z "$first" ]; then err "$f: must start with CREATE OR REPLACE (repeatable files must be safe to re-run)"; continue; fi
  name=$(echo "$first" | sed -E 's/^[[:space:]]*create or replace (force |editionable |noneditionable )*(function|procedure|package body|package|trigger|type body|type|view) +([a-z0-9_.$"]+).*/\3/')
  [ "$name" = "$base" ] || err "$f: object name '$name' does not match file name '$base'"
  grep -qiE '^[[:space:]]*(CREATE[[:space:]]+(TABLE|SEQUENCE|INDEX)|ALTER[[:space:]]+TABLE)' "$f" \
    && err "$f: tables/sequences/indexes belong in a versioned migration, not in a repeatable file"
done

# ---- immutability of merged work --------------------------------------------
if [ -n "${BASE_REF:-}" ]; then
  mod=$(git diff --name-status "$BASE_REF"...HEAD -- 'migrations/V*.sql' 'baseline' | awk '$1 ~ /^(M|D|R)/ {print $NF}')
  [ -n "$mod" ] && err "merged migrations/baseline were modified or deleted (add a new migration instead): $mod"
fi
[ $bad -eq 0 ] && echo "LINT OK" || { echo "LINT FAILED"; exit 1; }
