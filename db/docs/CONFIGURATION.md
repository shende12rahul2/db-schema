# Configuration

All database and file details live in `config/`, so the same tooling works for any Oracle project and any database:
the bundled local container, an Oracle you already have, or shared test/production servers.
The scripts themselves contain no project names, paths or credentials.

```
config/
  default.conf           project-wide settings (committed)
  local.conf             environment "local": throw-away Oracle in Docker (committed)
  dev.conf               your own environments, one file each (committed, no passwords)
  dev.secret.conf        DB_PASSWORD for "dev" (git-ignored via config/.gitignore)
  *.conf.example         templates: dev (existing DB), test, prod, secret
```

## 1. How settings are resolved

Later wins:

1. built-in defaults (in `scripts/lib/config.sh`)
2. `config/default.conf`
3. `config/<env>.conf`
4. `config/<env>.secret.conf`
5. environment variables with the same name (CI, one-off overrides)

The environment is chosen by `--env <name>` (first argument), else `DB_ENV`, else `DB_ENV` in `default.conf` (normally `local`).

```bash
./db/scripts/migrate.sh config                 # what will be used (password shown as set/EMPTY)
./db/scripts/migrate.sh --env dev config
DB_PORT=1600 ./db/scripts/migrate.sh --env dev config
```
Windows: `db\migrate.cmd --env dev config` or `set DB_ENV=dev`.

File format: plain `KEY=VALUE` lines, no quotes, no spaces around `=`, `#` comments. (Docker Compose and `migrate.cmd` read the
same files, so no shell syntax.)

## 2. All keys

### Database connection
| Key | Default | Meaning |
|---|---|---|
| `RUNNER` | `docker` | `docker`: bundled Oracle container (the runner runs inside it). `docker-client`: a helper container provides `sqlplus` and connects to `DB_HOST`. `local`: use `sqlplus` installed on this machine. |
| `DB_HOST` | `localhost` | DB host as seen **by the runner**. For a DB on your own machine with `docker-client`: `host.docker.internal`. |
| `DB_PORT` | `1521` | listener port |
| `DB_SERVICE` | `FREEPDB1` | service name (PDB), e.g. `ORCLPDB1`, `XEPDB1` |
| `DB_USER` | `APP_USER` | schema owner the objects are created in |
| `DB_PASSWORD` | `APP_USER_PASSWORD` for `docker`, else empty | put it in `<env>.secret.conf` or an env var, never in a committed file |
| `CONN` | built from the above | full SQL*Plus connect string; overrides the five keys above (e.g. for TNS aliases or wallets: `/@MYALIAS`) |

### Files and behaviour
| Key | Default | Meaning |
|---|---|---|
| `PROJECT_NAME` | `dbproject` | used in container, compose project and log names |
| `HISTORY_TABLE` | `schema_version` | table that records applied migrations (created automatically) |
| `MIGRATIONS_DIR` | `migrations` | versioned `V<NNN>__name.sql` files (relative to the db folder) |
| `UNDO_DIR` | `migrations/undo` | `U<NNN>__name.sql` files |
| `REPEATABLE_DIR` | `repeatable` | `CREATE OR REPLACE` objects; sub-folders run in name order |
| `SMOKE_SQL` | empty | script for `smoke`/`deploy`; empty or `none` = skip |
| `PROTECTED_ENVS` | `prod` | comma-separated; these need `CONFIRM=yes` for `migrate`, `step`, `undo`, `repair`, `baseline` |
| `LOG` | `/tmp/<project>-migrate.log` | runner log (inside the container for docker runners); print with `migrate.sh log` |
| `OUT_OF_ORDER` | `0` | `1` allows applying a lower pending version after a higher one |

### Bundled container (`RUNNER=docker` / `docker-client`), read by `docker-compose.yml`
| Key | Default | Meaning |
|---|---|---|
| `ORACLE_IMAGE` | `gvenzl/oracle-free:slim` | image for both the local DB and the sqlplus helper |
| `CONTAINER_NAME` | `<project>-oracle` | container name (helper: `<name>-client`) |
| `HOST_PORT` | `1521` | port on your machine for GUI tools; use different ports for projects running side by side |
| `ORACLE_PASSWORD` | `Oracle123` | SYS/SYSTEM password of the local container |
| `APP_USER`, `APP_USER_PASSWORD` | `app` / `App12345` | schema user created in the local container |
| `COMPOSE_PROJECT` | `PROJECT_NAME` | Docker Compose project name; changing it later makes `up` create a new, empty DB |

## 3. Use the database you already have

You do not need the bundled container. Point an environment at your DB:

```bash
cp db/config/dev.conf.example db/config/dev.conf          # edit host/port/service/user
printf 'DB_PASSWORD=your-password\n' > db/config/dev.secret.conf   # git-ignored
./db/scripts/migrate.sh --env dev config                   # check
./db/scripts/migrate.sh --env dev up                       # starts only the small sqlplus helper (docker-client)
./db/scripts/migrate.sh --env dev plan
```

Where is the DB?

| DB location | `RUNNER` | `DB_HOST` |
|---|---|---|
| Oracle installed on this machine (or another container with a published port) | `docker-client` | `host.docker.internal` |
| Server / VM on the network | `docker-client` | host name or IP |
| You have Oracle Instant Client + SQL*Plus installed and prefer no Docker | `local` | as reachable from your machine (`localhost` for a local DB) |

Then **adopt** it, depending on what is already in the schema (`plan` tells you which case you are in):

| Schema state | `plan` says | Do this |
|---|---|---|
| Empty schema (new deployment) | `History : none yet (empty schema)` | `migrate` - creates everything from V001 |
| Legacy objects deployed (flat files / `main`'s `scripts/deploy.sh`) | `none, but the schema already has tables` | `baseline` (= V001), then `migrate` (V002..V006 + repeatable; V006 removes the invalid empty type bodies of the legacy deploy) |
| Already contains the changes up to some version, e.g. V003 | `none, but the schema already has tables` | `baseline 003`, then `plan` / `migrate` |
| Already managed by this tool | `Current : Vnnn` | nothing special: `plan` / `migrate` |
| Built from the early `claude/schema-versioning` branch (old folder layout) | `V001 checksum mismatch` | local throw-away DB: `down`, `up`, `deploy` |

The old local container from `main`'s instructions (`docker run --name oracle-free ...`) has a ready-made environment:
`--env legacy-local` (`config/legacy-local.conf`, reached through the sqlplus helper on port 1521).

`baseline` records the chosen migrations as applied **without running them**. Run `plan` first: `migrate` refuses to start on a schema
that has tables but no history, and tells you to baseline. Repeatable objects are always (re)applied on the first `migrate`,
which is safe because they are `CREATE OR REPLACE`.

## 4. Several environments

One file per environment, same tooling:
```bash
./db/scripts/migrate.sh --env test status
./db/scripts/migrate.sh --env test plan --sql
CONFIRM=yes ./db/scripts/migrate.sh --env prod migrate     # prod is in PROTECTED_ENVS
```
For CI/CD, keep `config/<env>.conf` committed and pass `DB_PASSWORD` from the secret store as an environment variable.

## 5. Use the same structure for another project

```bash
./db/scripts/init_project.sh ../payments-service payments        # [db-folder] optional, default: db
cd ../payments-service
./db/scripts/migrate.sh config
./db/scripts/migrate.sh up
./db/scripts/new_migration.sh "create first table"
```
It creates `db/` with the tooling, `config/` for that project (own container name, user, smoke test), empty
`migrations/` and `repeatable/01_types ... 08_views`, plus `.gitattributes` and a CI workflow if they do not exist yet.
No bank objects are copied.

Updating the tooling later in another project: copy `scripts/migrate.sh`, `scripts/lib/config.sh`, `scripts/lint_migrations.sh`,
`scripts/new_migration.sh`, `docker-compose.yml` and `migrate.cmd` again; `config/` and your SQL stay untouched.

Running two projects locally at the same time: give them different `CONTAINER_NAME` (done by `init_project.sh`) and `HOST_PORT`.

## 6. Notes

- The history table name can be changed only before the first migration (or rename the table yourself and update `HISTORY_TABLE`).
- Paths are relative to the db folder. They must stay inside the repo, because only the repo is mounted into the container.
- Settings given as environment variables are forwarded into the container (Windows `migrate.cmd` forwards `CONN`, `DB_PASSWORD`, `CONFIRM`, `OUT_OF_ORDER`); everything else is read from the same `config/` files inside the container.
- The password is quoted in the connect string, so `@`, `/` and `#` are fine. A password containing `"` is not supported; use `CONN` or a wallet.
