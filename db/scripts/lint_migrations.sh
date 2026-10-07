#!/usr/bin/env bash
# Static checks, no database needed (bash only: Linux, macOS, Git Bash or WSL on Windows).
# Paths come from config/ (MIGRATIONS_DIR, UNDO_DIR, REPEATABLE_DIR).
# Optional: BASE_REF=origin/main to forbid edits of already-merged migrations and the frozen baseline.
set -uo pipefail
shopt -s nullglob
DB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DB_DIR"
. "$DB_DIR/scripts/lib/config.sh" 2>/dev/null
bad=0
err() { echo "x $*"; bad=1; }

# ---- versioned migrations -------------------------------------------------
seen=""
for f in "$MIGRATIONS_DIR"/V*.sql; do
  b=$(basename "$f")
  [[ "$b" =~ ^V([0-9]{3,})__[A-Za-z0-9_]+\.sql$ ]] || { err "bad name: $b (expected V<NNN>__snake_case.sql)"; continue; }
  v=$((10#${BASH_REMATCH[1]}))
  case " $seen " in *" $v "*) err "duplicate version number $v ($b)";; esac
  seen="$seen $v"
  undo=("$UNDO_DIR"/U"${BASH_REMATCH[1]}"__*.sql)
  [ ${#undo[@]} -gt 0 ] || echo "! $b has no undo script (optional: not every change can be reverted; plan a forward fix and a backup)"
  [ -s "$f" ] || err "$b is empty"
  hits=$(sed -e 's/--.*$//' "$f" | tr '\n' ' ' | tr ';' '\n' | awk '{ st=toupper($0); gsub(/[ \t]+/," ",st); sub(/^ /,"",st) }
      st ~ /^DROP (TABLE|USER|SCHEMA|TABLESPACE|DATABASE|SEQUENCE)( |$)/ || st ~ /^TRUNCATE / || st ~ /^PURGE / || st ~ /^ALTER TABLE [^ ]+ DROP (COLUMN|\()/ || (st ~ /^DELETE( FROM)? / && st !~ / WHERE /) { print substr(st,1,60) }')
  if [ -n "$hits" ] && ! grep -qiE '^[[:space:]]*--[[:space:]]*destructive-approved:[[:space:]]*[^[:space:]]+' "$f"; then
    err "$b has destructive statement(s) without a reviewer approval line '-- destructive-approved: <ticket or reason>': $(echo "$hits" | head -2 | tr '\n' ';')"
  fi
done
for u in "$UNDO_DIR"/U*.sql; do
  b=$(basename "$u")
  [[ "$b" =~ ^U([0-9]{3,})__ ]] || { err "bad undo name: $b"; continue; }
  m=("$MIGRATIONS_DIR"/V"${BASH_REMATCH[1]}"__*.sql)
  [ ${#m[@]} -gt 0 ] || err "undo without migration: $b"
done
for c in "$MIGRATIONS_DIR"/checks/*; do
  b=$(basename "$c")
  [[ "$b" =~ ^V([0-9]{3,})\.pre\.sql$ ]] || { err "bad pre-check name: checks/$b (expected V<NNN>.pre.sql)"; continue; }
  m=("$MIGRATIONS_DIR"/V"${BASH_REMATCH[1]}"__*.sql)
  [ ${#m[@]} -gt 0 ] || err "pre-check without migration: checks/$b"
done
for m in "$BASELINE_DIR"/V*.manifest; do
  b=$(basename "$m")
  [[ "$b" =~ ^V([0-9]{3,})\.manifest$ ]] || { err "bad manifest name: $BASELINE_DIR/$b (expected V<NNN>.manifest)"; continue; }
  mm=("$MIGRATIONS_DIR"/V"${BASH_REMATCH[1]}"__*.sql)
  [ ${#mm[@]} -gt 0 ] || err "manifest for a version with no migration: $b"
  grep -q '^TABLE|' "$m" || err "$b has no TABLE lines"
  grep -q "^SCHEMA|${BASH_REMATCH[1]}\$" "$m" || err "$b: first data line must be SCHEMA|${BASH_REMATCH[1]}"
  # code objects listed in a manifest may be deleted later (a migration drops them): that is legitimate, manifests are history
done
prev=0
for v in $(echo $seen | tr ' ' '\n' | sort -n); do
  [ "$v" -ne $((prev + 1)) ] && echo "! gap in version numbers before V$v"
  prev=$v
done

# ---- repeatable objects ---------------------------------------------------
if [ -d "$REPEATABLE_DIR" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    base=$(basename "$f"); base=${base%.*}
    first=$(grep -iE -m1 '^[[:space:]]*CREATE[[:space:]]+OR[[:space:]]+REPLACE' "$f" | tr -s ' \t' '  ' | tr '[:upper:]' '[:lower:]')
    if [ -z "$first" ]; then err "$f: must contain CREATE OR REPLACE (repeatable files must be safe to re-run)"; continue; fi
    kind=$(echo "$first" | sed -E 's/^ *create or replace (force |editionable |noneditionable |no force )*(package body|type body|function|procedure|package|trigger|type|view|synonym) .*/\2/')
    case "$kind" in "package body"|"type body"|function|procedure|package|trigger|type|view|synonym) ;;
      *) err "$f: unsupported object (CREATE OR REPLACE of function, procedure, package [body], trigger, type [body], view or synonym)"; continue;; esac
    name=$(echo "$first" | sed -E 's/^ *create or replace (force |editionable |noneditionable |no force )*(package body|type body|function|procedure|package|trigger|type|view|synonym) +("?[a-z0-9_$#]+"?\.)?"?([a-z0-9_$#]+)"?.*/\4/')
    [ "$name" = "$base" ] || err "$f: object name '$name' does not match file name '$base'"
    grep -qiE '^[[:space:]]*(CREATE[[:space:]]+(TABLE|SEQUENCE|INDEX|UNIQUE[[:space:]]+INDEX)|ALTER[[:space:]]+TABLE)' "$f" \
      && err "$f: tables/sequences/indexes belong in a versioned migration, not in a repeatable file"
  done < <(find "$REPEATABLE_DIR" -type f ! -name 'README*' ! -name '.gitkeep' | sort)
fi

# ---- immutability of merged work --------------------------------------------
if [ -n "${BASE_REF:-}" ]; then
  mod=$(git diff --name-status "$BASE_REF"...HEAD -- "$MIGRATIONS_DIR/V*.sql" 'baseline' | awk '$1 ~ /^(M|D|R)/ {print $NF}')
  [ -n "$mod" ] && err "merged migrations/baseline were modified or deleted (add a new migration instead): $mod"
fi
[ $bad -eq 0 ] && echo "LINT OK" || { echo "LINT FAILED"; exit 1; }
