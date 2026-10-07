# Configuration reference

Two places, no code edits:

| File | Committed? | Holds |
|---|---|---|
| `config/default.conf` | yes | **project layout**: folders, history table name, smoke script. Same for everybody |
| `.env` (or `.env.<name>`) | **no** (git-ignored) | **the target**: which database, which schema user, which environment. Template: `.env.example` |

Resolution order, later wins: built-in defaults → `config/default.conf` → `.env` → real environment variables (CI, one-off overrides).

`.env` is **read as data, never executed**: `KEY=VALUE` lines, optional single/double quotes, `#` comments, `export` prefix tolerated,
Windows line endings tolerated, unknown keys ignored. A password may contain `@ / # $` or spaces; it is never expanded or evaluated
(`DB_PASSWORD="p@ss w#rd"`). Not supported: a password that contains a double quote (use `CONN` or a wallet).

```bash
./db/scripts/migrate.sh config                      # effective settings (password shown as set/EMPTY)
./db/scripts/migrate.sh --env test config           # uses .env.test
./db/scripts/migrate.sh --env-file secrets/client1.env config          # path relative to the db folder, or absolute (docker runners: inside the db folder)
DB_PASSWORD=from-vault ./db/scripts/migrate.sh plan                  # environment variable beats the file
```
Windows: `db\migrate.cmd --env test config`, or `set DB_PASSWORD=...` first.

## `.env` keys (the target)

| Key | Default | Meaning |
|---|---|---|
| `APP_ENV` | `dev` | label of this target (`dev`, `test`, `prod` ...). Names listed in `PROTECTED_ENVS` get extra protection |
| `PROTECTED_ENVS` | `prod` | comma-separated. For these, commands that change the target need `CONFIRM=<EXPECTED_DB>` and `EXPECTED_DB` must be set |
| `EXPECTED_DB` | empty | service/PDB you **expect** to be connected to; compared (case-insensitive) with `SYS_CONTEXT('USERENV','CON_NAME')` and `DB_NAME`. Mismatch aborts before any SQL. **Required for protected environments, recommended everywhere** |
| `RUNNER` | `local` | `local`: `sqlplus` on this machine. `docker-client`: helper container provides `sqlplus`, database is **not** in Docker. `docker`: throw-away Oracle in Docker (optional) |
| `DB_HOST` | `localhost` | host **as seen by the runner**. Local database on your own machine with `docker-client`: `host.docker.internal` |
| `DB_PORT` | `1521` | listener port |
| `DB_SERVICE` | empty (`FREEPDB1` for `docker`) | service name / PDB |
| `DB_USER` | empty | **schema owner**: the account the objects are created in. One per developer / client / environment |
| `DB_PASSWORD` | empty | its password (never commit; `.env` is git-ignored) |
| `CONN` | built from the five values above | full SQL*Plus connect string (wallet, TNS alias: `/@MYALIAS`); overrides them |
| `CONFIRM` | empty | set per command for protected environments: `CONFIRM=<EXPECTED_DB>` (not `yes`) |
| `OUT_OF_ORDER` | `0` | `1` allows a lower pending version after a higher one was applied |

Only for `RUNNER=docker` (read by `docker-compose.yml`): `ORACLE_IMAGE`, `CONTAINER_NAME`, `HOST_PORT` (use different ports for
projects side by side), `ORACLE_PASSWORD`, `APP_USER`, `APP_USER_PASSWORD`, `COMPOSE_PROJECT`.

## `config/default.conf` keys (the layout)

| Key | Default | Meaning |
|---|---|---|
| `PROJECT_NAME` | `dbproject` | used for container, compose project and log names |
| `HISTORY_TABLE` | `schema_version` | history table in the target schema (a `<name>_lock` table is created next to it) |
| `MIGRATIONS_DIR` | `migrations` | versioned `V<NNN>__name.sql`; `checks/` and `undo/` live below (`UNDO_DIR` overrides undo) |
| `BASELINE_DIR` | `baseline` | `V<NNN>.manifest` files |
| `REPEATABLE_DIR` | `repeatable` | `CREATE OR REPLACE` objects; sub-folders run in name order |
| `SMOKE_SQL` | empty | script for `smoke` / `deploy`; empty or `none` = skip |
| `LOG` | `/tmp/<project>-migrate.log` | runner log (inside the container for docker runners): `migrate.sh log` |

Paths are relative to the `db` folder and must stay inside the repository (only the repository is mounted into containers).

## Choosing a runner

| Situation | `RUNNER` | `DB_HOST` |
|---|---|---|
| Shared server, you have `sqlplus` | `local` | server name |
| Shared server, no Oracle client installed | `docker-client` | server name |
| Oracle installed on your own machine, no `sqlplus` | `docker-client` | `host.docker.internal` |
| No database at all, just trying it out | `docker` | (default) |

## Several targets

```bash
cp .env.example .env.test    # edit
./db/scripts/migrate.sh --env test plan
CONFIRM=BANKPDB ./db/scripts/migrate.sh --env prod migrate     # .env.prod has APP_ENV=prod and EXPECTED_DB=BANKPDB
```
CI/CD: keep no secrets in files; pass `DB_PASSWORD` (and the rest) as environment variables from the secret store.

Docker runners: the runner executes inside the container, which reads the same `.env` from the mounted repository; values you
set as environment variables on the host are forwarded (`CONFIRM`, `DB_PASSWORD`, `CONN`, `EXPECTED_DB`, ...).

## Use the same structure for another project

```bash
./db/scripts/init_project.sh ../payments-service payments        # [db-folder] optional, default: db
cd ../payments-service && cp db/.env.example db/.env              # edit, then:
./db/scripts/migrate.sh config
```
It copies the runner, config loader, linter, admin script and docs, writes `config/default.conf` for that project, and creates empty
`migrations/`, `baseline/`, `repeatable/`. No schema objects are copied. To update the tooling later, copy `scripts/migrate.sh`,
`scripts/lib/config.sh`, `scripts/lint_migrations.sh`, `scripts/new_migration.sh`, `docker-compose.yml` and `migrate.cmd` again;
your SQL and `.env` files stay untouched.
