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
mkdir -p "$DEST"/{scripts/lib,scripts/admin,scripts/tests,config,docs,baseline,migrations/undo,migrations/checks}
for d in 01_types 02_type_bodies 03_functions 04_procedures 05_package_specs 06_package_bodies 07_triggers 08_views; do
  mkdir -p "$DEST/repeatable/$d"; : > "$DEST/repeatable/$d/.gitkeep"
done
: > "$DEST/migrations/undo/.gitkeep"; : > "$DEST/migrations/checks/.gitkeep"; : > "$DEST/baseline/.gitkeep"

# ---- tooling (identical copies; update later by copying these files again) ----
cp "$SRC_DB/scripts/migrate.sh" "$SRC_DB/scripts/lint_migrations.sh" "$SRC_DB/scripts/new_migration.sh" \
   "$SRC_DB/scripts/deploy.sh" "$SRC_DB/scripts/init_project.sh" "$DEST/scripts/"
cp "$SRC_DB/scripts/lib/config.sh" "$DEST/scripts/lib/"
cp "$SRC_DB/scripts/admin/create_schema_user.sql" "$DEST/scripts/admin/"
cp "$SRC_DB/scripts/tests/test_config.sh" "$DEST/scripts/tests/"
cp "$SRC_DB/docker-compose.yml" "$SRC_DB/migrate.cmd" "$DEST/"
cp "$SRC_DB/docs/ONBOARDING.md" "$SRC_DB/docs/CONFIGURATION.md" "$SRC_DB/docs/RUNBOOK.md" "$DEST/docs/"
chmod +x "$DEST"/scripts/*.sh "$DEST"/scripts/tests/*.sh

# ---- config: layout (committed) and target template (.env.example) ----
cat > "$DEST/config/default.conf" <<EOF
# Project layout (committed, no secrets). Connection details are NOT here: they live in .env (see .env.example).
PROJECT_NAME=$LNAME

HISTORY_TABLE=schema_version
MIGRATIONS_DIR=migrations
UNDO_DIR=migrations/undo
REPEATABLE_DIR=repeatable
BASELINE_DIR=baseline
SMOKE_SQL=scripts/smoke.sql
EOF
sed -e "s/^DB_USER=.*/DB_USER=                    # schema owner = one per developer \/ client (e.g. ${LNAME}_alice)/" "$SRC_DB/.env.example" > "$DEST/.env.example"
cp "$SRC_DB/.gitignore" "$DEST/.gitignore"

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

Versioned Oracle schema. Connection details live in \`.env\` (git-ignored); the layout in \`config/default.conf\`.

\`\`\`
$FOLDER/
  .env.example     copy to .env and fill in: which database, which schema user, which environment
  config/          default.conf (project layout, committed)
  baseline/        V<NNN>.manifest: what an EXISTING database must contain to be adopted at that version
  migrations/      V<NNN>__name.sql run once, in order; checks/V<NNN>.pre.sql conflict checks; undo/ optional
  repeatable/      01_types .. 08_views: CREATE OR REPLACE objects, re-applied when their file changes
  scripts/         migrate.sh, lint_migrations.sh, new_migration.sh, admin/create_schema_user.sql, smoke.sql
  migrate.cmd      Windows launcher
\`\`\`

## New environment or new developer

1. A DBA creates an empty schema user: \`scripts/admin/create_schema_user.sql\` (see docs/ONBOARDING.md part 1).
2. \`cp $FOLDER/.env.example $FOLDER/.env\` and fill it in.
3. \`./$FOLDER/scripts/migrate.sh config\` then \`plan\` then \`deploy\`.

## First migration of this project

\`\`\`bash
./$FOLDER/scripts/new_migration.sh "create first table"      # creates V001 (+ optional undo)
./$FOLDER/scripts/lint_migrations.sh
./$FOLDER/scripts/migrate.sh plan --sql
./$FOLDER/scripts/migrate.sh deploy
\`\`\`
Windows cmd/PowerShell: \`$FOLDER\\migrate.cmd <command>\`.

An existing client database is adopted with \`verify-baseline\` / \`baseline\`, never by running V001 on it:
[docs/ONBOARDING.md](docs/ONBOARDING.md) part 3. Settings: [docs/CONFIGURATION.md](docs/CONFIGURATION.md).
EOF

# ---- repo-level files (only if missing) ----
if [ ! -f "$TARGET/.gitattributes" ]; then
  printf '# LF everywhere so scripts and SQL work inside the Linux container, also on Windows checkouts.\n* text=auto eol=lf\n*.cmd text eol=crlf\n' > "$TARGET/.gitattributes"
  echo "  + .gitattributes"
else
  grep -q 'eol=lf' "$TARGET/.gitattributes" || echo "  ! add '* text=auto eol=lf' and '*.cmd text eol=crlf' to .gitattributes"
fi
WF="$TARGET/.github/workflows/${FOLDER}-schema-ci.yml"
if [ ! -f "$WF" ]; then
  mkdir -p "$(dirname "$WF")"
  cat > "$WF" <<EOF
name: ${FOLDER}-schema-ci
on:
  pull_request:
  push:
    branches: [main]
jobs:
  schema:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - name: Lint and config tests
        run: |
          ./$FOLDER/scripts/lint_migrations.sh
          ./$FOLDER/scripts/tests/test_config.sh
      - name: Merged migrations must not be edited
        if: github.event_name == 'pull_request'
        run: BASE_REF=origin/\${{ github.base_ref }} ./$FOLDER/scripts/lint_migrations.sh
      - name: Fresh install on an empty Oracle (bundled container)
        run: |
          printf 'RUNNER=docker\nAPP_ENV=ci\nEXPECTED_DB=FREEPDB1\nDB_SERVICE=FREEPDB1\n' > $FOLDER/.env
          ./$FOLDER/scripts/migrate.sh up
          ./$FOLDER/scripts/migrate.sh deploy
          ./$FOLDER/scripts/migrate.sh plan      # nothing left to apply
EOF
  echo "  + .github/workflows/${FOLDER}-schema-ci.yml"
fi

echo "Done. Next:"
echo "  cd $TARGET && cp $FOLDER/.env.example $FOLDER/.env   # then edit it"
echo "  ./$FOLDER/scripts/migrate.sh config"
