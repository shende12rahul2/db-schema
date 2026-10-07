#!/usr/bin/env bash
# Host-side one-shot: lint, start the environment's container if needed, migrate, validate, smoke test.
# Usage: ./scripts/deploy.sh [--env NAME]
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/lint_migrations.sh
./scripts/migrate.sh "$@" up
./scripts/migrate.sh "$@" deploy
