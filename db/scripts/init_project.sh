#!/usr/bin/env bash
# Create an EMPTY versioned-schema structure (tooling + config, no schema objects) for a new project.
#
#   ./db/scripts/init_project.sh <target-repo-dir> <project-name> [db-folder]
#
#   <target-repo-dir>  root of the other project's git repo (created if missing)
#   <project-name>     short name, letters/digits/underscore: used for the container, DB user and log names
#   [db-folder]        folder to create inside the repo (default: db)
#
# Example: ./db/scripts/init_project.sh ../payments-service payments
set -euo pipefail
SRC_DB="$(cd "$(dirname "$0")/.." && pwd)"

[ $# -ge 2 ] || { sed -n '2,10p' "$0"; exit 1; }
TARGET=$1; NAME=$2; FOLDER=${3:-db}
[[ "$NAME" =~ ^[A-Za-z][A-Za-z0-9_]{1,25}$ ]] || { echo "ERROR: project name must start with a letter: letters, digits, underscore (2-26 chars)" >&2; exit 1; }
[[ "$FOLDER" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "ERROR: db-folder must be a simple folder name" >&2; exit 1; }
mkdir -p "$TARGET"
TARGET=$(cd "$TARGET" && pwd)
DEST="$TARGET/$FOLDER"
[ -e "$DEST" ] && { echo "ERROR: $DEST already exists - refusing to overwrite" >&2; exit 1; }
LNAME=$(echo "$NAME" | tr '[:upper:]' '[:lower:]')

echo "Creating $DEST for project '$LNAME'"
mkdir -p "$DEST"/{scripts/lib,config,docs,migrations/undo}
for d in 01_types 02_type_bodies 03_functions 04_procedures 05_package_specs 06_package_bodies 07_triggers 08_views; do
  mkdir -p "$DEST/repeatable/$d"; : > "$DEST/repeatable/$d/.gitkeep"
done
: > "$DEST/migrations/undo/.gitkeep"

# ---- tooling (identical copies; update later by copying these files again) ----
cp "$SRC_DB/scripts/migrate.sh" "$SRC_DB/scripts/lint_migrations.sh" "$SRC_DB/scripts/new_migration.sh" \
   "$SRC_DB/scripts/deploy.sh" "$SRC_DB/scripts/init_project.sh" "$DEST/scripts/"
cp "$SRC_DB/scripts/lib/config.sh" "$DEST/scripts/lib/"
cp "$SRC_DB/docker-compose.yml" "$SRC_DB/migrate.cmd" "$DEST/"
cp "$SRC_DB/docs/CONFIGURATION.md" "$SRC_DB/docs/RUNBOOK.md" "$DEST/docs/"
chmod +x "$DEST"/scripts/*.sh

# ---- config ----
cat > "$DEST/config/default.conf" <<EOF
# Project-wide settings (committed). Plain KEY=VALUE, no quotes, no spaces around '='. See docs/CONFIGURATION.md
PROJECT_NAME=$LNAME
DB_ENV=local

# ---- files ----
HISTORY_TABLE=schema_version
MIGRATIONS_DIR=migrations
UNDO_DIR=migrations/undo
REPEATABLE_DIR=repeatable
SMOKE_SQL=scripts/smoke.sql

# Environments that need CONFIRM=yes for migrate/step/undo/repair/baseline (comma separated)
PROTECTED_ENVS=prod

# ---- bundled local Oracle container (RUNNER=docker) ----
# Running several projects at the same time? Give each a different HOST_PORT (1521, 1522, ...).
ORACLE_IMAGE=gvenzl/oracle-free:slim
CONTAINER_NAME=${LNAME}-oracle
HOST_PORT=1521
ORACLE_PASSWORD=Oracle123
APP_USER=$LNAME
APP_USER_PASSWORD=${LNAME}_Dev123
EOF
cat > "$DEST/config/local.conf" <<'EOF'
# Local development: throw-away Oracle in Docker, created by 'migrate.sh up'.
RUNNER=docker
DB_SERVICE=FREEPDB1
EOF
for f in dev.conf.example test.conf.example prod.conf.example secret.conf.example .gitignore; do
  sed -e "s/^DB_USER=.*/DB_USER=$LNAME/" -e "s/^DB_SERVICE=BANKPDB$/DB_SERVICE=$(echo "$LNAME" | tr '[:lower:]' '[:upper:]')PDB/" \
    "$SRC_DB/config/$f" > "$DEST/config/$f"
done

# ---- generic smoke test ----
cat > "$DEST/scripts/smoke.sql" <<'EOF'
-- Smoke test run by 'migrate.sh smoke' / 'deploy'. Add project checks below (each must not change data permanently).
SET LINESIZE 200 PAGESIZE 100

PROMPT === Objects by type ===
SELECT object_type, COUNT(*) AS total FROM user_objects GROUP BY object_type ORDER BY object_type;

PROMPT === Invalid objects (expected: no rows selected) ===
SELECT object_type, object_name FROM user_objects WHERE status = 'INVALID';

PROMPT === Compile errors (expected: no rows selected) ===
SELECT name, type, line, text FROM user_errors ORDER BY name, sequence;

PROMPT === Migration history ===
SELECT NVL(version, '-') AS version, type, status, script FROM schema_version ORDER BY installed_rank;

-- Example project check (uncomment and adapt):
-- PROMPT === Insert test (rolled back) ===
-- INSERT INTO my_table (id, name) VALUES (1, 'test');
-- SELECT * FROM my_table WHERE id = 1;
-- ROLLBACK;
EOF

# ---- readme ----
cat > "$DEST/README.md" <<EOF
# $LNAME database schema

Versioned Oracle schema. Only Docker is required (Windows, macOS, Linux).

\`\`\`
$FOLDER/
  config/          default.conf (project), local.conf, <env>.conf, <env>.secret.conf (git-ignored)
  migrations/      V<NNN>__name.sql run once, in order  + undo/U<NNN>__name.sql
  repeatable/      01_types .. 08_views: CREATE OR REPLACE objects, re-applied when changed
  scripts/         migrate.sh, lint_migrations.sh, new_migration.sh, smoke.sql
  migrate.cmd      Windows launcher
\`\`\`

## Start

\`\`\`bash
./$FOLDER/scripts/migrate.sh config                  # effective settings
./$FOLDER/scripts/migrate.sh up                      # local Oracle in Docker (first time: a few minutes)
./$FOLDER/scripts/new_migration.sh "create first table"
#   edit $FOLDER/migrations/V001__create_first_table.sql and $FOLDER/migrations/undo/U001__create_first_table.sql
./$FOLDER/scripts/lint_migrations.sh
./$FOLDER/scripts/migrate.sh plan --sql
./$FOLDER/scripts/migrate.sh deploy                  # migrate + validate + smoke
\`\`\`
Windows cmd/PowerShell: \`$FOLDER\\migrate.cmd <command>\`.

Existing database: copy \`config/dev.conf.example\` to \`config/dev.conf\`, put the password in \`config/dev.secret.conf\`,
then \`./$FOLDER/scripts/migrate.sh --env dev up\` and \`--env dev plan\`. Details: [docs/CONFIGURATION.md](docs/CONFIGURATION.md).
Day-to-day flow (branch, PR, release): [docs/RUNBOOK.md](docs/RUNBOOK.md).
EOF

# ---- repo-level files (only if missing) ----
if [ ! -f "$TARGET/.gitattributes" ]; then
  printf '# LF everywhere so scripts and SQL work inside the Linux container, also on Windows checkouts.\n* text=auto eol=lf\n*.cmd text eol=crlf\n' > "$TARGET/.gitattributes"
  echo "  + .gitattributes"
else
  grep -q 'eol=lf' "$TARGET/.gitattributes" || echo "  ! add '* text=auto eol=lf' and '*.cmd text eol=crlf' to .gitattributes"
fi
WF="$TARGET/.github/workflows/${FOLDER}-schema-ci.yml"
if [ ! -f "$WF" ] && [ -f "$SRC_DB/../.github/workflows/schema-ci.yml" ]; then
  mkdir -p "$(dirname "$WF")"
  sed "s#\./db/#./$FOLDER/#g; s# db/docker-compose.yml# $FOLDER/docker-compose.yml#g" "$SRC_DB/../.github/workflows/schema-ci.yml" > "$WF"
  echo "  + .github/workflows/${FOLDER}-schema-ci.yml"
fi

echo "Done. Next:"
echo "  cd $TARGET && ./$FOLDER/scripts/migrate.sh config && ./$FOLDER/scripts/migrate.sh up"
