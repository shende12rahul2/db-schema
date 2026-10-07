#!/usr/bin/env bash
# Usage: ./scripts/new_migration.sh "add customer nickname"
# Creates the next V<NNN>__<name>.sql and its undo skeleton (folders from config/: MIGRATIONS_DIR, UNDO_DIR).
set -euo pipefail
DB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$DB_DIR"
. "$DB_DIR/scripts/lib/config.sh" 2>/dev/null
[ $# -ge 1 ] || { echo "usage: $0 \"short description\"" >&2; exit 1; }
name=$(echo "$*" | tr '[:upper:] ' '[:lower:]_' | tr -cd 'a-z0-9_')
mkdir -p "$MIGRATIONS_DIR" "$UNDO_DIR"
last=$(ls "$MIGRATIONS_DIR"/V*.sql 2>/dev/null | sed -E 's#.*/V([0-9]+)__.*#\1#' | sort -n | tail -1 || true)
next=$(printf '%03d' $((10#${last:-0} + 1)))
printf -- "-- V%s: %s\n-- Rules: never edit after merge; DDL auto-commits in Oracle; fix data before adding constraints.\n\n" "$next" "$*" > "$MIGRATIONS_DIR/V${next}__${name}.sql"
printf -- "-- Undo of V%s: %s\n\n" "$next" "$*" > "$UNDO_DIR/U${next}__${name}.sql"
echo "created $MIGRATIONS_DIR/V${next}__${name}.sql"
echo "created $UNDO_DIR/U${next}__${name}.sql"
