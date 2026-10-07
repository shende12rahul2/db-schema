# Testing it yourself

Three levels, from "no database needed" to "simulate a real client". Commands are for macOS/Linux/Git Bash; on Windows without bash use
`db\migrate.cmd <command>` for the runner (needs `RUNNER=docker-client` or `docker` in `.env`).

## Level 0 - No database (1 minute)

```bash
git clone https://github.com/shende12rahul2/db-schema.git && cd db-schema
git checkout claude/migration-framework
./db/scripts/lint_migrations.sh             # LINT OK
./db/scripts/tests/test_config.sh           # ALL CONFIG TESTS PASSED   (.env parsing and precedence)
./db/scripts/tests/test_runner.sh           # ALL 100 RUNNER CHECKS PASSED   (about 2-3 minutes; needs python3)
```
`test_runner.sh` replaces `sqlplus` with a test double and proves the runner's **decisions**: fresh install, repeat run, verified
adoption of an existing database, refusal of unknown/incompatible ones, failure and repair, wrong target, protected environment, run
lock, destructive gate, pre-checks, separate histories. It does **not** prove the SQL is valid Oracle SQL: that is Level 1/2.

## Level 1 - Real Oracle in Docker, fresh install (10-15 minutes, Docker only)

```bash
cd db && cp .env.example .env
```
Edit `.env` for the bundled database:
```ini
RUNNER=docker
APP_ENV=dev
DB_SERVICE=FREEPDB1
EXPECTED_DB=FREEPDB1
APP_USER=bank
APP_USER_PASSWORD=Bank123
```
```bash
./scripts/migrate.sh config                  # check: runner docker, connection bank@//localhost:1521/FREEPDB1, password: set
./scripts/migrate.sh up                      # first start: image download + DB creation, a few minutes -> "Oracle ... is ready"
./scripts/migrate.sh plan                    # "Target: BANK@FREEPDB1 ..." / "History: none yet (empty schema)" / V001..V006 + 78 files
./scripts/migrate.sh deploy                  # migrate + validate + smoke -> DEPLOY OK
```
| Check | Command | Expected |
|---|---|---|
| everything applied | `status` | V001..V006 `SUCCESS`, pending `(none)` |
| healthy | `validate` | `VALIDATE OK` |
| manifest matches reality | `verify-baseline 001` | `READY` |
| repeat does nothing | `migrate` | `no pending versioned migrations` and `repeatable objects up to date` |
| smoke test | `smoke` | object counts, function results, rolled-back insert; no `ORA-` lines |

Failure and recovery (uses a temporary bad migration; nothing real is touched):
```bash
printf 'CREATE TABLE probe (id NUMBER);\nTHIS IS NOT SQL;\n' > migrations/V099__probe.sql
./scripts/migrate.sh migrate                 # fails; V099 recorded as FAILED, partial table "probe" exists (DDL auto-commits)
./scripts/migrate.sh migrate                 # refused: "recorded as FAILED"
./scripts/migrate.sh sql "DROP TABLE probe PURGE"      # clean up the partial change
./scripts/migrate.sh repair
rm migrations/V099__probe.sql && ./scripts/migrate.sh validate      # VALIDATE OK
```
Wrong target (nothing may run):
```bash
EXPECTED_DB=SOMETHING_ELSE ./scripts/migrate.sh migrate     # WRONG TARGET: connected to 'FREEPDB1' ... Nothing was changed.
```
Clean up: `./scripts/migrate.sh down` (removes the container and its data).

## Level 2 - Simulate an existing client database (15 minutes, Docker only)

Builds a schema from the **flat legacy files** (what clients have) with no migration tool, then adopts it. Continue from Level 1
(`up` already done).
```bash
cd db
S="docker exec -i bank-oracle"     # the bundled container (name = <PROJECT_NAME>-oracle, see ./scripts/migrate.sh config)
# a DBA-style, least-privilege schema user for the "client" (the prerequisite script)
$S sqlplus -s system/Oracle123@//localhost:1521/FREEPDB1 @/workspace/db/scripts/admin/create_schema_user.sql client1 Client1Pass USERS
printf 'RUNNER=docker\nAPP_ENV=client1\nDB_SERVICE=FREEPDB1\nEXPECTED_DB=FREEPDB1\nDB_USER=client1\nDB_PASSWORD=Client1Pass\n' > .env.client1
./scripts/tests/install_legacy.sh --env client1      # tables + code from ../legacy; the 8 empty TYPE BODY files report errors (expected)
```
Now work as you would on a client (`M` = the runner for that target):
```bash
M="./scripts/migrate.sh --env client1"
$M plan                  # "History: none, but the schema already has tables -> NOT managed yet"
$M migrate               # REFUSED: "this schema already has tables but no migration history, so it will NOT be changed"
$M sql "SELECT COUNT(*) FROM user_tables WHERE table_name LIKE 'SCHEMA_VERSION%'"     # 0: the refusal created nothing
$M verify-baseline 001   # READY (read-only)
$M baseline 001          # BASELINE recorded: 1 migration(s) up to V001 and 77 verified code object(s) ... Nothing was executed
$M baseline 001          # refused: already has migration history
$M plan                  # V002..V006 pending; only trg_customer_prefs_bi.trg is a new code file
$M migrate               # applies only those; V001 and the 77 existing code objects are NOT executed
$M validate              # VALIDATE OK
$M migrate               # nothing pending
```
Evidence to keep: the `plan` output before and after, `status`, and `$M sql "SELECT version,type,status,script FROM schema_version"`.

Unknown / incompatible client (must be refused):
```bash
$S sqlplus -s system/Oracle123@//localhost:1521/FREEPDB1 @/workspace/db/scripts/admin/create_schema_user.sql client2 Client2Pass USERS
printf 'RUNNER=docker\nAPP_ENV=client2\nDB_SERVICE=FREEPDB1\nEXPECTED_DB=FREEPDB1\nDB_USER=client2\nDB_PASSWORD=Client2Pass\n' > .env.client2
./scripts/tests/install_legacy.sh --env client2 --only-table accounts       # only one table
./scripts/migrate.sh --env client2 verify-baseline 001     # NOT READY: missing table ..., missing column ...
./scripts/migrate.sh --env client2 baseline 001            # baseline REFUSED
./scripts/migrate.sh --env client2 migrate                 # refused
```
Protected-environment behaviour: set `APP_ENV=prod` in `.env.client1` and run `$M migrate`: it refuses until you pass
`CONFIRM=FREEPDB1` (typing the expected database name).

Clean up: `./scripts/migrate.sh down`; delete `.env.client1`, `.env.client2`.

## Level 3 - Your own shared database

Follow [ONBOARDING.md](ONBOARDING.md) part 1 (DBA creates your schema user), then Part 2 (empty schema) or Part 3 (existing
database). For a copy of a real client database, do Part 3 on the copy first and compare row counts before and after.

## Tester checklist

- [ ] Level 0: lint, config tests, runner tests all pass
- [ ] Level 1: `DEPLOY OK`; `verify-baseline 001` READY; repeat run applies nothing; failure/repair works; wrong target aborts
- [ ] Level 2: unmanaged schema refused → verify → baseline → only V002.. and one new code file applied → `VALIDATE OK`
- [ ] Level 2: partial schema refused at `verify-baseline`, `baseline` and `migrate`; nothing created in it
- [ ] Log saved for any surprise: `./scripts/migrate.sh log > migrate.log`

## Troubleshooting

| Problem | Fix |
|---|---|
| `no target configured: copy .env.example to .env` | create `db/.env` (Level 1 shows the bundled-database values) |
| `Docker is required` / `Cannot connect to the Docker daemon` | start Docker Desktop / the Docker service |
| `the oracle container is not running` | `./scripts/migrate.sh up` |
| `cannot connect to ...` right after `up` | wait ~30 s; `docker logs <container>` should end with `DATABASE IS READY TO USE!` |
| `WRONG TARGET` | `EXPECTED_DB` in the env file does not match the service you connected to |
| `port is already allocated` (1521) | set `HOST_PORT=1522` in `.env` (docker runner) |
| `bash\r: No such file` | Windows line endings: `git add --renormalize . && git checkout -- .` or re-clone (`.gitattributes` forces LF) |
| Git Bash path errors like `C:/Program Files/Git/workspace` | use the current `migrate.sh` (it disables MSYS path conversion) |
