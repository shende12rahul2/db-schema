# Schema versioning

Every database change is a numbered, immutable **migration file**. A runner (`scripts/migrate.sh`) applies pending
migrations in order and records each one in a `schema_version` table, so any database can answer
"which version am I at?" and any file can answer "has it been applied?".

> The outputs shown below are **illustrative** of what the runner prints. The runner itself has only been
> syntax-checked and the lint script run, not executed against a live Oracle instance yet; the CI job in
> `.github/workflows/schema-ci.yml` does that on every PR.

## 1. Model

| Kind | Where | Rule |
|---|---|---|
| **Versioned migration** | `migrations/V<NNN>__<name>.sql` | Runs once, in number order. **Never edited after merge.** Tables, sequences, indexes, constraints, data fixes. |
| **Undo script** | `migrations/undo/U<NNN>__<name>.sql` | One per migration. Reverts it (data fixes cannot always be reverted). |
| **Code objects** | `Type/ Type_Body/ Function/ Procedure/ Package/ Package_Body/ Trigger/ View/` | `CREATE OR REPLACE`. Edit in place; re-applied automatically whenever any of these files changes (checksum). |
| **Baseline** | `migrations/V001__baseline.sql` | Includes `Sequence/` and `Table/` exactly as first delivered. Those two folders are **frozen**; later table changes are new migrations. |
| **History table** | `schema_version` (in the DB) | version, type, script, SHA-256 checksum, who/when, duration, status `SUCCESS/FAILED/UNDONE`. |

Why split this way: tables hold data, so they must be altered step by step. Code objects hold no data, so the
repo simply states the desired final version and the runner redeploys it.

Current versions: V001 baseline, V002 `customers.email_verified`, V003 loan status check, V004 `customer_preferences`
(+ trigger in `Trigger/`), V005 index on `transactions`.

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
./scripts/new_migration.sh "add customer nickname"   # creates V006 + U006 skeletons
# edit migrations/V006__add_customer_nickname.sql and the undo file; edit code objects if needed
./scripts/lint_migrations.sh                          # static checks, no DB needed
./scripts/migrate.sh migrate                          # apply to your local DB
./scripts/migrate.sh status                           # see history + pending
./scripts/migrate.sh validate                         # history vs files, invalid objects
# open a PR; CI repeats this on a fresh database
```

## 3. How it is validated (layers)

1. **Lint (before PR):** file naming, every V has a U, no duplicate numbers, merged migrations unchanged (`BASE_REF`).
2. **Pre-flight (`migrate`/`validate`):** a FAILED row blocks everything; a SUCCESS file whose SHA-256 changed is rejected; a pending migration numbered below an applied one is rejected (out of order).
3. **Post-change:** `DBMS_UTILITY.COMPILE_SCHEMA` then `invalid objects = 0`. PL/SQL "created with compilation errors" is only a warning in SQL*Plus, so this is the check that catches it.
4. **Smoke tests (`scripts/validate.sql`):** object counts, function results, an insert that fires a trigger, rolled back.
5. **CI:** fresh install from nothing + undo/redo round trip of the newest migration.

## 4. Commands

| Command | Purpose |
|---|---|
| `migrate` | Apply pending migrations, then changed code objects |
| `status` | History table and pending list |
| `validate` | Verify DB history against files; exit code 1 on any problem |
| `undo` | Revert the **most recent** versioned migration via its `U` file |
| `repair` | Delete `FAILED` rows after you cleaned up a failed migration |
| `baseline` | Adopt a database that was built with the old `deploy.sh` (marks V001 applied) |

Environment: `CONTAINER`, `CONN`, `ENVIRONMENT=prod` (then `migrate/undo/repair` need `CONFIRM=yes`), `OUT_OF_ORDER=1`.

## 5. Handling errors: key facts

- **Oracle DDL auto-commits.** `ALTER/CREATE/DROP` cannot be rolled back, so a migration that fails halfway leaves the first statements applied. Only DML (INSERT/UPDATE) before the failing statement is rolled back (the runner uses `WHENEVER SQLERROR ... ROLLBACK`).
- The runner records `FAILED`, stops, and refuses further migrations until you run `repair`.
- A migration that **failed may be edited** (its checksum is only stored on success). One that **succeeded may not**.
- Prefer **small migrations (one concern each)** so a failure leaves little to clean up, and write risky ones **re-runnable** (example C).
- Take a backup/snapshot before touching production (Data Pump `expdp`, or a storage snapshot); undo scripts are not a backup.

## 6. Examples

### A. Add a column (happy path) - V002

```sql
-- migrations/V002__add_customer_email_verified.sql
ALTER TABLE customers ADD (email_verified CHAR(1) DEFAULT 'N' NOT NULL);
ALTER TABLE customers ADD CONSTRAINT ck_customers_email_verified CHECK (email_verified IN ('Y','N'));
```
```
$ ./scripts/migrate.sh migrate
-> applying V002  add_customer_email_verified
   V002 OK (412 ms)
code objects up to date
MIGRATE OK
$ ./scripts/migrate.sh status
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
./scripts/migrate.sh repair                       # clears the FAILED row
# edit migrations/V003__...sql: add the UPDATE before the ALTER (allowed, it never succeeded)
./scripts/migrate.sh migrate
```

### C. Failure in the middle of a migration (partial apply)

Demo files: `examples/failing/V900__broken_example.sql` (typo `overdraft_limt` in statement 2).

```bash
cp examples/failing/V900__broken_example.sql   migrations/
cp examples/failing/U900__broken_example.sql   migrations/undo/
./scripts/migrate.sh migrate
```
```
-> applying V900  broken_example
ORA-00904: "OVERDRAFT_LIMT": invalid identifier
x V900 FAILED ... The database may be PARTIALLY changed (Oracle DDL auto-commits).
```
State now: column `accounts.overdraft_limit` **exists** (statement 1 auto-committed), the constraint does not.

Option 1 - clean up, fix, retry:
```bash
./scripts/migrate.sh status                       # V900 shows FAILED
docker exec -i oracle-free sqlplus -s bank/Bank123@//localhost:1521/FREEPDB1 <<< "ALTER TABLE accounts DROP COLUMN overdraft_limit;"
./scripts/migrate.sh repair
# fix the typo in migrations/V900__broken_example.sql
./scripts/migrate.sh migrate
```
Option 2 - make it re-runnable so no manual cleanup is needed: `examples/failing/V900__guarded_rerunnable.sql` ignores only
"already exists" errors (`ORA-01430`, `ORA-02264`), so after fixing the typo you just `repair` and `migrate` again.

Remove the demo files afterwards: `rm migrations/V900__* migrations/undo/U900__*`.

### D. Someone edited an applied migration (checksum drift)

A teammate "fixes a typo" in `V002` after it was applied everywhere:
```
$ ./scripts/migrate.sh validate
x V002 checksum mismatch: migrations/V002__add_customer_email_verified.sql was edited after it was applied. Revert it and add a NEW migration.
VALIDATE FAILED
```
Fix: `git checkout -- migrations/V002__add_customer_email_verified.sql`, then put the change in a new `V006`.
CI catches this earlier: `BASE_REF=origin/main ./scripts/lint_migrations.sh` fails the PR when an existing `V*.sql` is modified or deleted.

### E. Two branches both create V006

Branch A and B each run `new_migration.sh`, both get `V006`. After the second merge:
```
$ ./scripts/lint_migrations.sh
x duplicate version number 6 (V006__add_branch_region.sql)
LINT FAILED
```
Fix on the branch that merged second, **before it is applied anywhere**: rename its `V006`/`U006` to `V007`, re-run lint. If one of them was already applied in an environment, renumber the *other* one.

### F. Rollback a released migration (undo)

V004 created `customer_preferences` and caused a production problem, but V005 (the index) was applied after it.
Undo works newest-first, so run `undo` once per migration:
```bash
export ENVIRONMENT=prod CONFIRM=yes
./scripts/migrate.sh undo          # reverts V005 (newest)
./scripts/migrate.sh undo          # reverts V004
git checkout <previous-release-tag>   # older code objects
./scripts/migrate.sh migrate       # redeploys the older code objects (their checksum differs)
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

### H. Adopt a database created with the old `deploy.sh`

You already have a database with tables but no history:
```
$ ./scripts/migrate.sh migrate
ERROR: tables already exist but there is no history. Run ./scripts/migrate.sh baseline first.
$ ./scripts/migrate.sh baseline
baselined at V001. Run ./scripts/migrate.sh migrate to apply newer versions.
$ ./scripts/migrate.sh migrate        # applies V002..V005 and the code objects
```

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
or update the view first, then `repair`, update `View/v_customer_contact_info.vw` in the same PR, and re-run `migrate`.
Lesson: change dependent code objects in the same PR as the migration; CI's fresh install catches mismatches.

### J. Pending migration older than an applied one (out of order)

Your branch adds `V006`, but `main` already shipped `V007` to the shared database:
```
x migrations/V006__add_nickname.sql is pending but a higher version is already applied (out of order). Renumber it, or set OUT_OF_ORDER=1 if intended.
```
Normal fix: rename to `V008`. Use `OUT_OF_ORDER=1 ./scripts/migrate.sh migrate` only when the two changes are independent and you have agreed to it.

### K. Hotfix a stored procedure (no migration needed)

Edit `Procedure/prc_transfer_funds.prc`, run `./scripts/migrate.sh migrate`. The code checksum changed, so the code objects
are redeployed and recorded as a new `REPEATABLE` row. If the new body has a compile error, the post-check reports the invalid object,
the row is `FAILED`, and you fix the file and run `migrate` again (`CREATE OR REPLACE` is safe to repeat).

## 7. Release checklist

1. `lint_migrations.sh` green, CI green on a fresh database.
2. Backup/snapshot taken (production).
3. `ENVIRONMENT=prod CONFIRM=yes ./scripts/migrate.sh migrate`.
4. `./scripts/migrate.sh validate` and `scripts/validate.sql` smoke tests.
5. Tag the release in git (the tag + `schema_version` together describe the deployed state).
