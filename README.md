# db-schema

Oracle PL/SQL schema for a retail banking / lending system, with versioned migrations.

```
db/                      <- live, versioned schema (use this)
  baseline/              Sequence + Table DDL as first delivered (frozen)
  migrations/            V<NNN>__name.sql  (run once, in order)   + undo/U<NNN>__name.sql
  repeatable/            objects that are re-applied whenever their file changes
    01_types  02_type_bodies  03_functions  04_procedures
    05_package_specs  06_package_bodies  07_triggers  08_views
  scripts/               migrate.sh, lint_migrations.sh, new_migration.sh, validate.sql ...
  docs/                  SCHEMA_VERSIONING.md (guide)  examples/ (one page per change type)
  docker-compose.yml     local Oracle
  migrate.cmd            Windows launcher
legacy/                  original flat layout, reference only (not used by any tool)
```

## Run it on your machine (Windows, macOS, Linux)

**Requirement: Docker only** (Docker Desktop on Windows/macOS, Docker Engine on Linux; Apple Silicon works). Nothing else is installed on your computer: the Oracle client and the migration runner both run inside the container.

| | Windows (cmd or PowerShell) | macOS / Linux (also Git Bash / WSL on Windows) |
|---|---|---|
| Start Oracle (first start takes 1-3 min) | `db\migrate.cmd up` | `./db/scripts/migrate.sh up` |
| Apply everything | `db\migrate.cmd deploy` | `./db/scripts/migrate.sh deploy` |
| See what would run (no changes) | `db\migrate.cmd plan` | `./db/scripts/migrate.sh plan` |
| Apply one migration at a time | `db\migrate.cmd step` | `./db/scripts/migrate.sh step` |
| Query the DB to verify | `db\migrate.cmd sql "SELECT * FROM schema_version"` | `./db/scripts/migrate.sh sql "SELECT * FROM schema_version"` |
| Status / validate | `db\migrate.cmd status` / `validate` | `./db/scripts/migrate.sh status` / `validate` |
| Stop and wipe | `db\migrate.cmd down` | `./db/scripts/migrate.sh down` |

`deploy` = `migrate` (pending versioned migrations, then changed repeatable files) + `validate` + smoke tests (`db/scripts/validate.sql`).
Success ends with `DEPLOY OK`.

Static checks (no database needed) and the migration generator are bash scripts: on macOS/Linux run them directly; on Windows use Git Bash or WSL:
```bash
./db/scripts/lint_migrations.sh
./db/scripts/new_migration.sh "add customer nickname"
```
(Without bash you can still create `V<NNN>__name.sql` and `undo/U<NNN>__name.sql` by hand; CI runs the lint for you.)

Connection details if you want a GUI (DBeaver, SQL Developer, VS Code): host `localhost`, port `1521`, service `FREEPDB1`, user `bank`, password `Bank123` (admin: `sys` / `Oracle123` as SYSDBA).
Interactive SQL*Plus: `docker compose -f db/docker-compose.yml exec oracle sqlplus bank/Bank123@//localhost:1521/FREEPDB1`.

Clone note for Windows: `.gitattributes` forces LF line endings so scripts work inside the Linux container. If you cloned before it existed, re-clone or run `git add --renormalize .`.

Already used the earlier `docker run --name oracle-free ...` container? Remove it first: `docker rm -f oracle-free`. If your database was built from the old flat files, run `migrate baseline` once, then `migrate`.

## Flow: branch -> PR -> main -> environments

Step-by-step with expected output and verification queries: **[`db/docs/RUNBOOK.md`](db/docs/RUNBOOK.md)**.

1. Feature branch: add a migration (`new_migration.sh`) and/or edit repeatable files; `lint_migrations.sh`.
2. Locally: `plan --sql` -> `step` -> verify with `sql "..."` -> `migrate` -> `validate` -> `undo` -> `migrate` (proves rollback).
3. PR to `main`: CI runs lint, a fresh install, and an undo/redo round trip.
4. Merge: **no database changes**; `main` is what each environment should reach next.
5. Release (manual, per environment): `CONN=... ENVIRONMENT=...` `status` -> `plan --sql` -> backup -> `migrate` -> `validate` -> `smoke` -> git tag.

## How changes are made (short version)

| Change | Where | Applied |
|---|---|---|
| Table, column, index, constraint, sequence, reference data, data fix | new file in `db/migrations/` (+ undo) | once, in order, recorded in `schema_version` |
| Function, procedure, package (spec + body), trigger, view, object type | edit the file in `db/repeatable/` | automatically when its checksum changes |
| Remove a repeatable object | delete the file **and** add a migration with a guarded `DROP` | once |
| Code that needs a new column | migration **and** code change in the same PR | migrations first, then repeatable files |

Rules: never edit a migration after it is merged; never edit `db/baseline/`; every repeatable file starts with `CREATE OR REPLACE`.
Lint enforces these. Full guide with failure/recovery scenarios: [`db/docs/SCHEMA_VERSIONING.md`](db/docs/SCHEMA_VERSIONING.md).
Copy-paste examples for every kind of change: [`db/docs/examples/`](db/docs/examples/README.md).

## Validate

`deploy` already runs these; to run them alone: `migrate.sh validate` and `migrate.sh smoke`.

| Check | Expected |
|---|---|
| `validate` | `VALIDATE OK` (history matches files, no invalid objects) |
| Object counts (smoke) | SEQUENCE 13, TABLE 14, TYPE 11, FUNCTION 11, PROCEDURE 11, PACKAGE 10, PACKAGE BODY 10, TRIGGER 11, VIEW 11 |
| `fn_calc_emi(500000, 9.5, 60)` | about 10,500 |
| `fn_mask_mobile('9876543210')` | `XXXXXX3210` |
| Insert test | customer row with `kyc_status = PENDING`, `email_verified = N` (then rolled back) |

Notes: `pkg_login_otp` is a placeholder (OTP verify always returns `FALSE`). `branches` and `credit_scores` have sequences but no insert trigger; pass `seq_branch_id.NEXTVAL` / `seq_credit_score_id.NEXTVAL`.
