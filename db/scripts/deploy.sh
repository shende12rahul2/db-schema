#!/usr/bin/env bash
# Host-side one-shot: lint, start Oracle if needed, migrate, validate, smoke test.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/lint_migrations.sh
./scripts/migrate.sh up
./scripts/migrate.sh deploy
