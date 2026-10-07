# db-schema

Oracle PL/SQL schema for a retail banking / lending system, with a reusable migration setup:
one `.env`, one command, safe for new environments **and** existing client databases.

```
db/                      <- live, versioned schema (use this)
  .env.example           copy to db/.env: target database, schema user, environment (never committed)
  config/default.conf    project layout (folders, history table)
  baseline/              V001.manifest: what an existing client database must contain to be adopted at V001
  migrations/            V<NNN>__name.sql (run once, in order); checks/ (conflict checks); undo/ (optional)
  repeatable/            01_types .. 08_views: CREATE OR REPLACE objects, re-applied only when their file changes
  scripts/               migrate.sh (runner), lint_migrations.sh, new_migration.sh, init_project.sh,
                         admin/create_schema_user.sql (DBA prerequisite), tests/
  docs/                  ONBOARDING.md (start here), CONFIGURATION.md, LOCAL_TESTING.md, RUNBOOK.md, SCHEMA_VERSIONING.md
  migrate.cmd            Windows launcher
legacy/                  the flat layout as deployed to clients (reference; the V001 manifest is derived from it)
```

## The three situations

| Target database | What you run | Docs |
|---|---|---|
| **Empty schema** (new developer, new environment) | `cp db/.env.example db/.env` → edit → `./db/scripts/migrate.sh plan` → `deploy` | [ONBOARDING part 2](db/docs/ONBOARDING.md) |
| **Existing client database** (legacy objects + business data) | `verify-baseline 001` → `baseline 001` (once) → `plan` → `migrate` | [ONBOARDING part 3](db/docs/ONBOARDING.md) |
| **Already managed** | `plan` → `migrate` (only pending versions run) | [ONBOARDING part 4](db/docs/ONBOARDING.md) |

A schema that has tables but no history is **never** migrated or baselined blindly: the runner refuses, and `baseline` only
succeeds when the database matches the documented starting state (`db/baseline/V001.manifest`).

## Quick start

```bash
cd db && cp .env.example .env      # fill in host, service, schema user, password; set EXPECTED_DB
./scripts/migrate.sh config        # what will be used (password hidden)
./scripts/migrate.sh plan          # read-only: target, what would run, why
./scripts/migrate.sh deploy        # migrate + validate + smoke
```
Windows without bash: `db\migrate.cmd <command>`. Docker is **optional**: with `RUNNER=local` (sqlplus on your PATH) or
`RUNNER=docker-client` (helper container) you connect to an existing shared server, each developer with their own schema user
(prerequisite script: `db/scripts/admin/create_schema_user.sql`). `RUNNER=docker` gives a throw-away local Oracle.

## Commands

| Read-only | Changes the target |
|---|---|
| `config`, `plan [--sql]`, `status`, `validate`, `verify-baseline V`, `manifest V`, `sql "SELECT ..."`, `log` | `migrate`, `step`, `baseline V`, `undo`, `repair`, `unlock`, `deploy`, `smoke`, `up`/`down` (docker) |

Protected environments (`PROTECTED_ENVS`, default `prod`) additionally need `EXPECTED_DB` and `CONFIRM=<that database name>`.

## Making changes

| Change | Where | Applied |
|---|---|---|
| table, column, index, constraint, sequence, reference data, data fix | `./db/scripts/new_migration.sh "..."` → `migrations/V<NNN>__*.sql` | once, in order, recorded with a checksum |
| function, procedure, package, trigger, view, object type | edit the file in `db/repeatable/` | when its file changed |
| mistake in a released migration | **new** corrective migration (released files are never edited; the runner and CI reject it) | once |

Destructive statements (`DROP TABLE`, `TRUNCATE`, unbounded `DELETE` ...) need a reviewer line `-- destructive-approved: <reason>`
(enforced by lint and by the runner on protected environments). Failure handling: the run stops, records `FAILED`, blocks further runs
until `repair`; recovery is manual (undo script or backup) because Oracle DDL cannot be rolled back automatically - see
[ONBOARDING part 6](db/docs/ONBOARDING.md).

## What is verified

| | How |
|---|---|
| `.env` parsing and precedence | `db/scripts/tests/test_config.sh` |
| runner decisions (fresh, repeat, existing client, unknown DB refused, failure/repair, wrong target, protected, lock, destructive) | `db/scripts/tests/test_runner.sh` - against a test double of `sqlplus`, i.e. the logic, **not** Oracle SQL |
| SQL, manifest and adoption on real Oracle | CI job `oracle` (`.github/workflows/schema-ci.yml`) - **first run pending** |
| Windows launcher | written, not yet executed on Windows |

See [ONBOARDING part 8](db/docs/ONBOARDING.md) for the full statement and what to do before a real client rollout.

## Other projects

`./db/scripts/init_project.sh ../other-repo other` copies the runner, config loader, linter and docs with empty `migrations/`,
`baseline/` and `repeatable/`. Each project supplies its own schema; each target keeps its own history.

Notes: `pkg_login_otp` is a placeholder (OTP verify always returns `FALSE`). `branches` and `credit_scores` have sequences but no insert trigger.
