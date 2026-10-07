# Schema versioning

Every database change is a numbered, immutable **migration file**. A runner (`db/scripts/migrate.sh`) applies pending
migrations in order and records each one in a `schema_version` table, so any database can answer
"which version am I at?" and any file can answer "has it been applied?".

> The outputs shown below are **illustrative** of what the runner prints. The runner itself has only been
> syntax-checked and the lint script run, not executed against a live Oracle instance yet; the CI job in
> `.github/workflows/schema-ci.yml` does that on every PR.

## 1. Model

| Kind | Where | Rule |
|---|---|---|
| **Versioned migration** | `db/migrations/V<NNN>__<name>.sql` | Runs once, in number order. **Never edited after merge.** Tables, columns, indexes, constraints, sequences, reference data, data fixes. |
| **Undo script** | `db/migrations/undo/U<NNN>__<name>.sql` | One per migration. Reverts it (data fixes cannot always be reverted). |
| **Repeatable objects** | `db/repeatable/01_types ... 08_views/` | `CREATE OR REPLACE`. Edit in place; each changed file is re-applied automatically (per-file checksum). |
| **Baseline** | `db/migrations/V001__baseline.sql` | Includes `db/baseline/Sequence` and `db/baseline/Table` exactly as first delivered. **Frozen**; later table changes are new migrations. |
| **History table** | `schema_version` (in the DB) | version/script, type, SHA-256 checksum, who/when, duration, status `SUCCESS/FAILED/UNDONE`. |

Why split this way: tables hold data, so they must be altered step by step. Code objects hold no data, so the
repo simply states the desired final version and the runner redeploys it.

See also the step-by-step [RUNBOOK](RUNBOOK.md) (branch -> PR -> main -> environments).

Run order on every `migrate`: all pending versioned migrations (ascending), then all changed repeatable files in folder order.

Current versions: V001 baseline, V002 `customers.email_verified`, V003 loan status check, V004 `customer_preferences`
(+ trigger in `07_triggers/`), V005 index on `transactions`, V006 cleanup of invalid empty type bodies left by legacy deployments (no-op on new databases).

## 2. How a change travels

```
developer                      PR / CI                              environment
---------                      -------                              -----------
new_migration.sh "..."   -->   lint_migrations.sh                   migrate.sh migrate
edit V + U files               (names, undo pairs, no dup numbers,    1. validate history (checksums, order, FAILED)
edit code objects               no edits to merged migrations)        2. apply each pending V in order
local: deploy.sh               fresh install on empty Oracle          3. recompile + require 0 invalid objects
                               undo + re-migrate round trip           4. record row in schema_version
                               validate + smoke tests                 5. redeploy code objects if checksum changed
```

Daily workflow:

```bash
./db/scripts/new_migration.sh "add customer nickname"   # creates V007 + U007 skeletons
# edit migrations/V007__add_customer_nickname.sql and the undo file; edit code objects if needed
./db/scripts/lint_migrations.sh                          # static checks, no DB needed
./db/scripts/migrate.sh migrate                          # apply to your local DB
./db/scripts/migrate.sh status                           # see history + pending
./db/scripts/migrate.sh validate                         # history vs files, invalid objects
# open a PR; CI repeats this on a fresh database
```

## 3. How it is validated (layers)

1. **Lint (before PR):** file naming, every V has a U, no duplicate numbers, merged migrations unchanged (`BASE_REF`).
2. **Pre-flight (`migrate`/`validate`):** a FAILED row blocks everything; a SUCCESS file whose SHA-256 changed is rejected; a pending migration numbered below an applied one is rejected (out of order).
3. **Post-change:** `DBMS_UTILITY.COMPILE_SCHEMA` then `invalid objects = 0`. PL/SQL "created with compilation errors" is only a warning in SQL*Plus, so this is the check that catches it.
4. **Smoke tests (`db/scripts/validate.sql`):** object counts, function results, an insert that fires a trigger, rolled back.
5. **CI:** fresh install from nothing + undo/redo round trip of the newest migration.

## 4. Commands

| Command | Purpose |
|---|---|
| `plan` (`--sql`) | Read-only: what `migrate` would run, in order, and why |
| `step` | Apply only the next pending migration |
| `sql "..."` | Ad-hoc query for manual verification |
| `migrate` | Apply pending migrations, then changed/missing repeatable files |
| `status` | History table and pending list |
| `validate` | Verify DB history against files; exit code 1 on any problem |
| `undo` | Revert the **most recent** versioned migration via its `U` file |
| `repair` | Delete `FAILED` rows after you cleaned up a failed migration |
| `verify-baseline V` | Read-only: does an existing database match `baseline/V<V>.manifest`, and are the pending migrations free of conflicts? |
| `baseline V` | Adopt an existing database **after** verification passes (history must be empty); executes nothing |
| `manifest V` | Print a manifest of the connected (reference) database |
| `unlock` | Clear the run lock left by a crashed run |

Target: `.env`, or `--env <name>` = `.env.<name>` (see [CONFIGURATION.md](CONFIGURATION.md)); protected environments (`prod`) need `CONFIRM=<EXPECTED_DB>`; `OUT_OF_ORDER=1` allows an out-of-order version.

## 5. Handling errors: key facts

- **Oracle DDL auto-commits.** `ALTER/CREATE/DROP` cannot be rolled back, so a migration that fails halfway leaves the first statements applied. Only DML (INSERT/UPDATE) before the failing statement is rolled back (the runner uses `WHENEVER SQLERROR ... ROLLBACK`).
- The runner records `FAILED`, stops, and refuses further migrations until you run `repair`.
- A migration that **failed may be edited** (its checksum is only stored on success). One that **succeeded may not**.
- Prefer **small migrations (one concern each)** so a failure leaves little to clean up, and write risky ones **re-runnable** (example C).
- Take a backup/snapshot before touching production (Data Pump `expdp`, or a storage snapshot); undo scripts are not a backup.

## 6. Examples

Version numbers in these scenarios are illustrative ("the next free number").

### A. Add a column (happy path) - V002

```sql
-- migrations/V002__add_customer_email_verified.sql
ALTER TABLE customers ADD (email_verified CHAR(1) DEFAULT 'N' NOT NULL);
ALTER TABLE customers ADD CONSTRAINT ck_customers_email_verified CHECK (email_verified IN ('Y','N'));
```
```
$ ./db/scripts/migrate.sh migrate
-> applying V002  add_customer_email_verified
   V002 OK (412 ms)
code objects up to date
MIGRATE OK
$ ./db/scripts/migrate.sh status
Applied history:
1   001   BASELINE   SUCCESS  2026-10-07 10:02  baseline
2   002   VERSIONED  SUCCESS  2026-10-07 10:03  add_customer_email_verified
3   -     REPEATABLE SUCCESS  2026-10-07 10:03  code objects
Pending:
  (none)
```
Because the new column has a default and is `NOT NULL`, existing rows get `'N'` and old code keeps working.

### B. Constraint fails on existing data - V003

Adding `CHECK (status IN (...))` while some row holds `'PENDING'` fails with `ORA-02293: cannot validate (BANK.CK_LOAN_APP_STATUS) - check constraint violated`.
That is why V003 fixes the data **first**, then adds the constraint. If you forget:

```
-> applying V003  loan_status_check
ORA-02293: cannot validate (BANK.CK_LOAN_APP_STATUS) - check constraint violated

x V003 FAILED - details in migrate.log. The database may be PARTIALLY changed ...
```
Recovery (nothing was applied, the constraint never got created):
```bash
./db/scripts/migrate.sh repair                       # clears the FAILED row
# edit migrations/V003__...sql: add the UPDATE before the ALTER (allowed, it never succeeded)
./db/scripts/migrate.sh migrate
```

### C. Failure in the middle of a migration (partial apply)

Demo files: `db/examples/failing/V900__broken_example.sql` (typo `overdraft_limt` in statement 2).

```bash
cp db/examples/failing/V900__broken_example.sql   db/migrations/
cp db/examples/failing/U900__broken_example.sql   db/migrations/undo/
./db/scripts/migrate.sh migrate
```
```
-> applying V900  broken_example
ORA-00904: "OVERDRAFT_LIMT": invalid identifier
x V900 FAILED ... The database may be PARTIALLY changed (Oracle DDL auto-commits).
```
State now: column `accounts.overdraft_limit` **exists** (statement 1 auto-committed), the constraint does not.

Option 1 - clean up, fix, retry:
```bash
./db/scripts/migrate.sh status                       # V900 shows FAILED
docker compose -f db/docker-compose.yml exec -T oracle sqlplus -s bank/Bank123@//localhost:1521/FREEPDB1 <<< "ALTER TABLE accounts DROP COLUMN overdraft_limit;"
./db/scripts/migrate.sh repair
# fix the typo in db/migrations/V900__broken_example.sql
./db/scripts/migrate.sh migrate
```
Option 2 - make it re-runnable so no manual cleanup is needed: `db/examples/failing/V900__guarded_rerunnable.sql` ignores only
"already exists" errors (`ORA-01430`, `ORA-02264`), so after fixing the typo you just `repair` and `migrate` again.

Remove the demo files afterwards: `rm db/migrations/V900__* db/migrations/undo/U900__*`.

### D. Someone edited an applied migration (checksum drift)

A teammate "fixes a typo" in `V002` after it was applied everywhere:
```
$ ./db/scripts/migrate.sh validate
x V002 checksum mismatch: migrations/V002__add_customer_email_verified.sql was edited after it was applied. Revert it and add a NEW migration.
VALIDATE FAILED
```
Fix: `git checkout -- migrations/V002__add_customer_email_verified.sql`, then put the change in a new `V006`.
CI catches this earlier: `BASE_REF=origin/main ./db/scripts/lint_migrations.sh` fails the PR when an existing `V*.sql` is modified or deleted.

### E. Two branches both create V006

Branch A and B each run `new_migration.sh`, both get `V006`. After the second merge:
```
$ ./db/scripts/lint_migrations.sh
x duplicate version number 6 (V006__add_branch_region.sql)
LINT FAILED
```
Fix on the branch that merged second, **before it is applied anywhere**: rename its `V006`/`U006` to `V007`, re-run lint. If one of them was already applied in an environment, renumber the *other* one.

### F. Rollback a released migration (undo)

V004 created `customer_preferences` and caused a production problem, but V005 (the index) was applied after it.
Undo works newest-first, so run `undo` once per migration:
```bash
export CONFIRM=BANKPDB           # protected environment: the expected database name
./db/scripts/migrate.sh --env prod undo      # reverts V005 (newest)
./db/scripts/migrate.sh --env prod undo      # reverts V004
git checkout <previous-release-tag>          # older code objects
./db/scripts/migrate.sh --env prod migrate   # redeploys the older code objects (their checksum differs)
```
Rules: undo reverts only the **latest** applied migration, so undo newest-first. Run undo from the **newer** checkout
(the undo file only exists there), then switch code. Undo does not bring back deleted data - restore from backup if the
migration dropped or rewrote data.

### G. Rename a column without downtime (expand / contract)

Never `RENAME COLUMN` in one step while old code is running. Do it over two releases.

Release 1 (expand), `V006__expand_customer_mobile.sql`:
```sql
ALTER TABLE customers ADD (mobile_number VARCHAR2(15));
UPDATE customers SET mobile_number = mobile;
COMMIT;
```
Code now writes both columns (update the procedures/views in the same PR). Release 2 (contract), after all code reads only the new column, `V007__contract_customer_mobile.sql`:
```sql
ALTER TABLE customers DROP COLUMN mobile;
```
Undo for V007 can only re-add the empty column - take a backup before contracting.

### H. Adopt a database that already has the legacy objects (verified, once)

The client schema was built with the flat legacy files: tables, code and business data exist, there is no history table.
```
$ ./db/scripts/migrate.sh --env client1 migrate
ERROR: this schema already has tables but no migration history, so it will NOT be changed. Adopt it first: ...
$ ./db/scripts/migrate.sh --env client1 verify-baseline 001          # read-only
READY: the database matches V001 and the pending migrations have no conflicts. Next: migrate.sh baseline 001
$ CONFIRM=CLIENT1PDB ./db/scripts/migrate.sh --env client1 baseline 001
BASELINE recorded: 1 migration(s) up to V001 and 77 verified code object(s) marked as already deployed. Nothing was executed ...
$ CONFIRM=CLIENT1PDB ./db/scripts/migrate.sh --env client1 migrate   # V002.. + only new/changed code files
```
If the client differs (`x missing column CUSTOMERS.PAN_NUMBER`, `x column ACCOUNTS.BALANCE has type VARCHAR2, expected NUMBER`,
`x PACKAGE BODY ... exists but is INVALID`), `verify-baseline` stops and `baseline` is refused. Full walk-through:
[ONBOARDING.md](ONBOARDING.md) part 3. V006 drops the 8 empty type bodies a legacy deployment leaves INVALID.

### I. A migration breaks a view or package (invalid objects)

Dropping `customers.mobile` (example G, step 2) while `v_customer_contact_info` still selects it: the DDL succeeds but
dependents become INVALID and cannot recompile.
```
-> applying V007  contract_customer_mobile
x 1 invalid object(s) after change:
   VIEW V_CUSTOMER_CONTACT_INFO
x V007 FAILED ...
```
Fix: the migration is marked FAILED even though the column is already gone. Re-add it (`ALTER TABLE customers ADD (mobile VARCHAR2(15))`)
or update the view first, then `repair`, update `db/repeatable/08_views/v_customer_contact_info.vw` in the same PR, and re-run `migrate`.
Lesson: change dependent code objects in the same PR as the migration; CI's fresh install catches mismatches.

### J. Pending migration older than an applied one (out of order)

Your branch adds `V006`, but `main` already shipped `V007` to the shared database:
```
x migrations/V006__add_nickname.sql is pending but a higher version is already applied (out of order). Renumber it, or set OUT_OF_ORDER=1 if intended.
```
Normal fix: rename to `V008`. Use `OUT_OF_ORDER=1 ./db/scripts/migrate.sh migrate` only when the two changes are independent and you have agreed to it.

### K. Hotfix a stored procedure (no migration needed)

Edit `db/repeatable/04_procedures/prc_transfer_funds.prc`, run `./db/scripts/migrate.sh migrate`. Only that file's checksum changed, so only that file
is redeployed and recorded as a new `REPEATABLE` row. If the new body has a compile error, the post-check reports the invalid object,
the row is `FAILED`, and you fix the file and run `migrate` again (`CREATE OR REPLACE` is safe to repeat).

## 7. Release checklist

1. `lint_migrations.sh` green, CI green on a fresh database.
2. Backup/snapshot taken (production).
3. `CONFIRM=BANKPDB ./db/scripts/migrate.sh --env prod migrate`.
4. `./db/scripts/migrate.sh validate` and `db/scripts/validate.sql` smoke tests.
5. Tag the release in git (the tag + `schema_version` together describe the deployed state).

## 8. How repeatable objects (procedures, packages, views, ...) are handled

- Each file under `db/repeatable/` is tracked **separately** in `schema_version` (type `REPEATABLE`, script = path, SHA-256 checksum).
- On `migrate`, a file is applied if it is **new**, **changed** (checksum), **failed last time**, or its object is **missing in the database**
  (for example a trigger dropped together with its table by an undo script). Unchanged files are skipped. `plan` shows the reason per file.
- A type without member methods has no body file: Oracle rejects an empty `TYPE BODY`.
- Files run in folder order: types, type bodies, functions, procedures, package specs, package bodies, triggers, views.
  After the run the schema is recompiled, so dependency-order mistakes inside a folder do not matter; only objects still INVALID fail the step.
- Every file must start with `CREATE OR REPLACE` and be named after its object (lint enforces both), so re-running is always safe.
- Repeatable objects always run **after** the versioned migrations. That is why a procedure using a new column ships in the same PR as the migration adding it.
- A failing file is recorded `FAILED` (files before it succeeded, files after it did not run); fix it and run `migrate` again.
- **Deleting** a repeatable file does not drop the object. Add a migration with a guarded drop (see `db/docs/examples/views.md`); `validate` prints a hint when a deployed file disappeared.
- Package spec changes invalidate dependents and running sessions (`ORA-04068` once); deploy them in a quiet window.

| Object | Versioned migration or repeatable? |
|---|---|
| Table, column, index, constraint, sequence | migration |
| Reference/seed data, backfills, data fixes | migration |
| Function, procedure, package spec/body, trigger, view | repeatable |
| Object type with **no** table/column depending on it | repeatable (`CREATE OR REPLACE TYPE`) |
| Object type used by a table column or other type | migration (`ALTER TYPE ... CASCADE`), because `CREATE OR REPLACE` fails with dependents |
| Dropping any object | migration (guarded drop) + delete the file |

## 9. Platforms

The runner needs only Docker. On the host, `migrate.sh` (macOS/Linux/Git Bash/WSL) or `migrate.cmd` (Windows cmd/PowerShell)
starts the compose file in `db/` and executes the real runner **inside the container**, which has bash, sqlplus and the Linux tools it uses.
`.gitattributes` forces LF line endings so a Windows checkout still works in the container.
`lint_migrations.sh` and `new_migration.sh` are plain bash and run on the host (Git Bash or WSL on Windows).
Logs: `./db/scripts/migrate.sh log`. All connection and path settings: [CONFIGURATION.md](CONFIGURATION.md).
