# Database migrations: onboarding, existing clients, daily use

One runner, one `.env`, one command. It builds a complete schema on an empty database, adopts an existing client
database **without** re-running the legacy install, and afterwards applies only what is pending.

```
migrate.sh  (db/scripts)          reads  .env (target, git-ignored)   +   config/default.conf (layout, committed)
   |                                       |
   |  plan / verify-baseline / validate    |  read-only, safe anywhere
   |  migrate / baseline / ...             |  change the target; protected environments need CONFIRM=<database name>
   v
target schema:  your objects + SCHEMA_VERSION (history, one row per applied file) + SCHEMA_VERSION_LOCK
```

## What is where

| Path | Purpose |
|---|---|
| `.env.example` → `.env` | **the target**: environment, database, schema user, runner. Never committed. |
| `config/default.conf` | project layout (folders, history table name, smoke test) - same for everybody |
| `migrations/V001__baseline.sql` ... | versioned changes, run **once**, in order. V001 = the legacy sequences and tables; the legacy code objects are in `repeatable/` and applied right after |
| `migrations/checks/V<NNN>.pre.sql` | optional conflict checks run before that version |
| `migrations/undo/U<NNN>__*.sql` | optional undo scripts (a convenience, not a guarantee) |
| `baseline/V<NNN>.manifest` | what an **existing** database must contain to be adopted at that version |
| `repeatable/` | procedures, packages, views ... re-applied only when their file changes |
| `scripts/admin/create_schema_user.sql` | DBA prerequisite: an isolated schema user |

---

## Part 1 - One-time setup (prerequisites)

Done once per developer, environment or client. **The runner never creates databases, users or grants.**

1. **A database and an empty schema user** (DBA task).
   - Shared dev/test server: **one user per developer** (`DEV_ALICE`, `DEV_BOB`). The history table lives inside the user's own
     schema, so every developer has separate objects and separate history automatically.
   - Run the template (least privilege: create objects in its own schema only, no DBA rights):
     ```bash
     sqlplus system@//dbserver:1521/DEVPDB @scripts/admin/create_schema_user.sql DEV_ALICE "Alice#Pass1" USERS
     ```
   - New environment / client: one user per environment (`BANK_TEST`, `BANK_PROD`), created by the DBA with the same privileges.
2. **A SQL client path** - pick one in `.env` (`RUNNER`). **A database in Docker or on your laptop is never required.**

   | `RUNNER` | You need | The database is |
   |---|---|---|
   | `local` | `sqlplus` on your PATH (Oracle Instant Client + SQL*Plus) | the shared server |
   | `docker-client` | Docker only; a small helper container provides `sqlplus` | the shared server |
   | `docker` | Docker only | a throw-away Oracle in Docker (optional, for people without a server) |
3. **Create `.env`:**
   ```bash
   cd db && cp .env.example .env        # edit it; it is git-ignored
   ```
   Minimum for a shared server:
   ```ini
   APP_ENV=dev
   EXPECTED_DB=DEVPDB            # the service/PDB you intend to change; a mismatch aborts before anything runs
   RUNNER=docker-client          # or local
   DB_HOST=dbserver
   DB_PORT=1521
   DB_SERVICE=DEVPDB
   DB_USER=DEV_ALICE
   DB_PASSWORD=Alice#Pass1
   ```
   Another environment: `.env.test`, `.env.prod` (same keys) and run `migrate.sh --env test <command>`. Nothing else is edited:
   not the runner, not the SQL.
4. **Check the target without changing anything:**
   ```bash
   ./db/scripts/migrate.sh config          # effective settings, password hidden
   ./db/scripts/migrate.sh up              # docker runners only: starts the helper (or local Oracle)
   ./db/scripts/migrate.sh plan            # prints "Target: DEV_ALICE@DEVPDB ..." and what would run
   ```
   Windows without bash: `db\migrate.cmd <command>` (needs `RUNNER=docker-client` or `docker`).

---

## Part 2 - New environment or new developer: complete install

Target: an **empty** schema. One command builds everything in dependency order: the legacy tables and sequences (V001), required
reference data and later versions (V002...), then the code objects (types, functions, procedures, packages, triggers, views).

```bash
./db/scripts/migrate.sh plan        # "History: none yet (empty schema)", V001..Vn listed in order
./db/scripts/migrate.sh deploy      # migrate + validate + smoke tests  ->  DEPLOY OK
```
Evidence that it worked:

| Check | Expected |
|---|---|
| `./db/scripts/migrate.sh status` | every version `SUCCESS`, nothing pending, repeatable files `(none)` |
| `./db/scripts/migrate.sh validate` | `VALIDATE OK` (checksums match, no invalid objects) |
| `./db/scripts/migrate.sh verify-baseline 001` | `READY` (the install matches the manifest) |
| second `./db/scripts/migrate.sh migrate` | `no pending versioned migrations`, nothing executed |

Required **reference data** goes into versioned migrations written as upserts (`MERGE`), so a re-run is harmless; it then reaches
every new environment automatically. (This repository's legacy schema contains no reference data; add it as its own `V<NNN>`.)

**A non-empty schema without history is never migrated.** If someone runs `migrate` against a schema that already has tables,
the runner refuses and tells you to adopt it first (Part 3). It cannot accidentally "install on top".

---

## Part 3 - Existing client database: verified adoption (once per database)

The client database already has the legacy objects **and business data**. Goal: record the correct starting point **without
touching data or re-running V001**, then apply only what is pending.

**Rule: the runner will only baseline a database that matches a documented starting state (`baseline/V<NNN>.manifest`).** A database
that is merely non-empty is not adopted.

### 3.1 Before you start
- Back it up (Data Pump `expdp`, RMAN, or storage snapshot) and note the row counts of key tables.
- Create `.env.<client>` (`APP_ENV=prod`, `EXPECTED_DB=<client service>`, the client's schema user).
- A protected environment (`PROTECTED_ENVS`, default `prod`) additionally needs `CONFIRM=<EXPECTED_DB>` on every command that changes it.

### 3.2 Look (read-only)
```bash
./db/scripts/migrate.sh --env client1 config
./db/scripts/migrate.sh --env client1 plan
```
Expect: `History: none, but the schema already has tables -> NOT managed yet: migrate will refuse.`

### 3.3 Verify the starting state and the prerequisites for the intended changes (read-only)
```bash
./db/scripts/migrate.sh --env client1 verify-baseline 001
```
It compares the database with `baseline/V001.manifest` (tables, columns and their types, sequences, code objects that must exist and
compile) and runs the **pre-checks** of every migration that would follow (for example "V003 would set these loan statuses to
REJECTED"). Possible outcomes:

| Output | Meaning | Action |
|---|---|---|
| `READY: the database matches V001 and the pending migrations have no conflicts` | known starting state | go to 3.4 |
| `x missing table ...`, `x missing column ...`, `x column X has type A, expected B`, `x PACKAGE BODY ... exists but is INVALID` | this client differs from the known state | **stop**. Fix the database or decide with the team (for example a reviewed bridge migration); re-run `verify-baseline`. Nothing was changed |
| `V003 pre-check: ...` | a later migration would change or conflict with data | decide first (clean the data, or change the migration in a reviewed PR) |
| `no baseline manifest baseline/V<NNN>.manifest` | this client is at a state nobody has described | create the manifest from a reference database at that version (`migrate.sh manifest <ver>`), review it, commit it |

### 3.4 Record the baseline (once)
```bash
CONFIRM=<EXPECTED_DB> ./db/scripts/migrate.sh --env client1 baseline 001
```
It verifies **again**, refuses on any problem, then records in the history: V001 as `BASELINE`, plus every verified code object as
"already deployed". **Nothing is executed against the client's data or objects.** A second `baseline` is refused (history exists).

### 3.5 Apply only what is pending
```bash
./db/scripts/migrate.sh --env client1 plan      # V002.. pending; only NEW/CHANGED code files pending
CONFIRM=<EXPECTED_DB> ./db/scripts/migrate.sh --env client1 migrate
./db/scripts/migrate.sh --env client1 validate  # VALIDATE OK
```
Evidence for the client rollout:

| Check | Expected |
|---|---|
| business-table row counts before / after | identical (migrations changed structure, not data, unless a migration says so) |
| `status` | `001 BASELINE`, later versions `SUCCESS` |
| `V001` in the runner log | never executed |
| second `migrate` | nothing pending |

Different clients can sit at different versions: each has its own history and `baseline <ver>` (only versions that have a manifest
can be adopted). They then follow the same `migrate` path.

---

## Part 4 - Normal updates

```bash
./db/scripts/migrate.sh plan        # pending versions, in order, with their pre-checks and destructive-statement warnings
./db/scripts/migrate.sh migrate     # applies only pending versions, then new/changed repeatable files
./db/scripts/migrate.sh status      # history
./db/scripts/migrate.sh validate    # history vs files; invalid objects
```
Successfully applied versions never run again: the history table records them with a SHA-256 checksum.

**Add a change:**
```bash
./db/scripts/new_migration.sh "add customer nickname"   # next number: migrations/V007__add_customer_nickname.sql
#   write the SQL; optionally migrations/checks/V007.pre.sql (conflict check) and migrations/undo/U007__...sql
./db/scripts/lint_migrations.sh
./db/scripts/migrate.sh plan --sql && ./db/scripts/migrate.sh deploy
```
- Tables, columns, indexes, constraints, sequences, reference data, data fixes → **versioned migration**.
- Procedures, functions, packages, triggers, views → edit the file in `repeatable/` (applied again when its checksum changes).
- A new object type or dependency order inside a version: put the statements in order in that file; versions run in number order.

**Correct a mistake:**
- In a version that already succeeded **anywhere**: never edit it (the runner rejects a changed checksum). Add a new corrective version.
- In a version that has **never succeeded** (it failed): fix the file, then `repair` and re-run.
- Wrong data fix: write a new migration that repairs the data; restore from backup when data was lost.

**Pre-check files** (`migrations/checks/V<NNN>.pre.sql`) are SELECTs that return one message per problem; no rows = fine. Write them
against the state *before* the migration, independent of other pending migrations.

---

## Part 5 - Production safeguards

| Risk | What prevents it |
|---|---|
| Wrong target | `EXPECTED_DB` is compared with the service/PDB actually connected to; mismatch aborts **before any SQL**. Every command prints `Target: USER@SERVICE`. Protected environments refuse to run without `EXPECTED_DB` |
| Accidental change of production | `PROTECTED_ENVS` (default `prod`): `migrate`, `step`, `baseline`, `undo`, `repair`, `unlock`, `smoke` need `CONFIRM=<EXPECTED_DB>` (typing the database name; `CONFIRM=yes` is rejected). Non-SELECT `sql` needs it too |
| Accidental cleanup | the runner has **no** drop/clean command; `down` refuses protected environments; the migration account (create_schema_user.sql) has no DBA or other-schema rights |
| Destructive migration | pending migrations with `DROP TABLE/COLUMN/SEQUENCE/USER`, `TRUNCATE`, `PURGE` or `DELETE` without `WHERE` are **blocked on protected environments** unless the file carries a reviewer line `-- destructive-approved: <ticket/reason>`; lint enforces the same in the pull request. (The scan reads SQL text; dynamic SQL in strings is not detected, so review those by hand.) |
| Unknown database adopted | `baseline` only for manifests; verification must pass; history must be empty |
| Two runs at once | run lock in `SCHEMA_VERSION_LOCK`; a second run is refused with the holder's name; `unlock` for a crashed run |
| Edited released migration | checksum validation; CI also rejects edits to merged migrations (`BASE_REF`) |
| Out-of-order / skipped versions | pending lower versions behind an applied one are rejected |
| Read-only commands changing things | `plan`, `status`, `validate`, `verify-baseline`, `manifest`, `config` never write; `validate` does not even recompile |

## Part 6 - Failure handling and recovery

Not every change can be rolled back: Oracle commits DDL immediately, so a migration that fails halfway leaves its earlier
statements applied. The tool therefore **stops, records, blocks and explains** rather than guessing.

1. The failing version is recorded as `FAILED`; the run stops; further runs are refused (`... recorded as FAILED`).
   (A version stopped by a **pre-check** or the **destructive gate** was not started: nothing to clean up.)
2. **Inspect** what was applied: `migrate.sh sql "SELECT column_name FROM user_tab_columns WHERE table_name='...'"`, and the log: `migrate.sh log`.
3. **Return the schema to its pre-migration state**: run the matching undo script by hand if it fits, or restore from the backup
   taken before the release (the only guaranteed rollback). Never "just re-run".
4. `migrate.sh repair` clears the `FAILED` row (protected environments: `CONFIRM=...`).
5. Fix the migration file (allowed: it never succeeded) and run `migrate` again. Prefer small migrations (one concern each) and
   re-runnable statements so a failure leaves little behind.
6. A crashed run leaves a lock: confirm nothing is running, then `migrate.sh unlock`.

`undo` reverts the newest version only when an undo script exists, and still needs `CONFIRM` on protected environments. Treat it as
a convenience for development, not as the production recovery plan.

## Part 7 - Reuse

- **Developers / environments / clients:** same runner, different `.env`. Each target keeps its own history and baseline.
- **Another project:** `./db/scripts/init_project.sh ../other-repo other` copies the runner, config loader, linter, admin script and
  these docs, with empty `migrations/`, `baseline/`, `repeatable/`. The project supplies its own schema and files. Nothing is re-run
  on every deployment: only what the history says is pending.
- **A new baseline manifest** (a client at a state that has no manifest yet): install that version on a fresh reference schema, then
  `./db/scripts/migrate.sh manifest <ver> > baseline/V<ver>.manifest`, review it, commit it.

## Part 8 - What has and has not been proven

| Claim | Evidence |
|---|---|
| `.env` parsing, precedence, no code execution | `scripts/tests/test_config.sh` (14 checks) |
| Runner decisions: fresh install, repeat run, verified adoption, refusal of unknown/incompatible DBs, failure + repair, wrong target, protected environment, lock, destructive gate, pre-checks, separate histories | `scripts/tests/test_runner.sh` (100 checks) against a test double of `sqlplus` - proves the **logic**, not Oracle SQL |
| The SQL, the V001 manifest and the adoption path on real Oracle | CI job `oracle` in `.github/workflows/schema-ci.yml` (builds a legacy client schema with the flat files, adopts it, refuses a partial one) - **first run pending**; run Part 2 and Part 3 on a copy of a client database before relying on it |
| Windows launcher `migrate.cmd` | written, **not executed on Windows** |

Before using on a real client database: restore a backup of that database to a copy, run Part 3 on the copy, compare row counts,
and have a second person review its manifest verification output.
