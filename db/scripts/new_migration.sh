#!/usr/bin/env bash
# Usage: ./scripts/new_migration.sh "add customer nickname"
# Creates the next V<NNN>__<name>.sql and its undo skeleton.
set -euo pipefail
cd "$(dirname "$0")/.."
[ $# -ge 1 ] || { echo "usage: $0 \"short description\"" >&2; exit 1; }
name=$(echo "$*" | tr '[:upper:] ' '[:lower:]_' | tr -cd 'a-z0-9_')
last=$(ls migrations/V*.sql 2>/dev/null | sed -E 's#.*/V([0-9]+)__.*#\1#' | sort -n | tail -1)
next=$(printf '%03d' $((10#${last:-0} + 1)))
printf -- "-- V%s: %s\n-- Rules: never edit after merge; DDL auto-commits in Oracle; fix data before adding constraints.\n\n" "$next" "$*" > "migrations/V${next}__${name}.sql"
printf -- "-- Undo of V%s: %s\n\n" "$next" "$*" > "migrations/undo/U${next}__${name}.sql"
echo "created migrations/V${next}__${name}.sql"
echo "created migrations/undo/U${next}__${name}.sql"
