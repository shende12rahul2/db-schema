# Runbook: how a schema change flows from a branch to a database

Everything here is **manual and verifiable**: nothing deploys automatically. After every step there is a command to see what happened.
Commands are shown for macOS/Linux; on Windows replace `./db/scripts/migrate.sh` with `db\migrate.cmd` (same arguments).

```
 feature branch                PR to main                   main (merged)                 each environment
 ───────────────               ──────────                   ─────────────                 ────────────────
 1 write V/U or edit   ──►  4 CI: lint, fresh install,  ──► 5 nothing runs by itself ──►  6 release engineer:
   repeatable file             undo/redo round trip           main = what SHOULD be          plan -> backup -> migrate
 2 plan / step / verify        reviewer checklist             deployed next                  -> validate -> smoke -> tag
 3 undo + migrate again
```

## Commands at a glance

| Command | Changes the DB? | Use it to |
|---|---|---|
| `up` / `down` | starts / wipes local container | local Oracle |
| `plan` / `plan --sql` | **no** | see exactly what will run, in order, and why |
| `status` | no | history + pending |
| `sql "SELECT ..."` | no: DML is rolled back at the end (DDL is not) | verify by hand; multi-line via stdin |
| `step` | yes, one migration | apply the next migration only, then inspect |
| `migrate` | yes | apply all pending migrations, then changed/missing repeatable files |
| `validate` | no | history matches files, no invalid or missing objects |
| `smoke` | no (rolled back) | object counts, function results, test insert |
| `undo` | yes | revert the newest migration |
| `repair` | history only | clear a FAILED row after you cleaned up |
| `baseline` | history only | adopt a DB built from the legacy files |
| `deploy` | yes | `migrate` + `validate` + `smoke` |

## 0. One-time setup (each developer)

```bash
git clone https://github.com/shende12rahul2/db-schema.git && cd db-schema
./db/scripts/migrate.sh up          # first start: 1-3 minutes; prints "Oracle is ready."
./db/scripts/migrate.sh deploy      # builds the schema at the current version; ends with DEPLOY OK
./db/scripts/migrate.sh status      # V001..V005 SUCCESS, nothing pending
```

## 1. Make the change on a feature branch

```bash
git checkout -b feature/add-account-nickname
```

**Table / column / index / constraint / sequence / data** -> new versioned migration:
```bash
./db/scripts/new_migration.sh "add account nickname"
# edit db/migrations/V006__add_account_nickname.sql       ALTER TABLE accounts ADD (nickname VARCHAR2(40));
# edit db/migrations/undo/U006__add_account_nickname.sql  ALTER TABLE accounts DROP COLUMN nickname;
```
**Function / procedure / package / trigger / view / type** -> edit or add the file in `db/repeatable/<folder>/`.
Both kinds can be in the same branch (typical when code needs a new column).

```bash
./db/scripts/lint_migrations.sh     # LINT OK
```

## 2. Apply locally, one step at a time, and verify

```bash
./db/scripts/migrate.sh plan --sql
```
Expected (abridged):
```
Target   : bank@//localhost:1521/FREEPDB1   ENVIRONMENT=local
Current  : V005
Checks   :
  history OK
1) Versioned migrations, run once, in this order:
   1. V006  migrations/V006__add_account_nickname.sql
        | ALTER TABLE accounts ADD (nickname VARCHAR2(40));
2) Repeatable files, run after the migrations:
   - repeatable/04_procedures/prc_rename_account.prc  (new)
Nothing was changed.
```
Apply only the migration, then look at the database:
```bash
./db/scripts/migrate.sh step
./db/scripts/migrate.sh sql "SELECT column_name, data_type, data_length, nullable FROM user_tab_columns WHERE table_name='ACCOUNTS' ORDER BY column_id"
./db/scripts/migrate.sh sql "SELECT version, status, script FROM schema_version WHERE type<>'REPEATABLE' ORDER BY installed_rank"
```
Then the rest (repeatable files) and the full check:
```bash
./db/scripts/migrate.sh migrate     # MIGRATE OK
./db/scripts/migrate.sh validate    # VALIDATE OK
./db/scripts/migrate.sh smoke
./db/scripts/migrate.sh plan        # both sections "(none)": the DB matches the branch
```

## 3. Prove the change can be rolled back and re-applied

```bash
./db/scripts/migrate.sh undo        # V006 undone (warns if current code needs the column - expected)
./db/scripts/migrate.sh plan        # V006 pending again; dropped/invalid objects listed
./db/scripts/migrate.sh migrate     # re-applies V006 and any repeatable object the undo removed
./db/scripts/migrate.sh validate
```
Also prove a **fresh install** works (this is what CI does):
```bash
./db/scripts/migrate.sh down && ./db/scripts/migrate.sh up && ./db/scripts/migrate.sh deploy
```

## 4. Pull request

Push the branch and open a PR to `main`. CI (`.github/workflows/schema-ci.yml`) runs on the PR **merged with main**:
1. lint, plus "merged migrations and baseline unchanged" (`BASE_REF`);
2. fresh Oracle -> `plan` -> `deploy` (migrate + validate + smoke);
3. `undo` the newest migration -> `migrate` -> `validate`.

Reviewer checklist:
- [ ] One concern per migration; undo script really reverts it (or says why it cannot).
- [ ] Data is fixed **before** constraints are added; large updates are batched.
- [ ] New columns on existing tables are nullable or have a DEFAULT.
- [ ] Procedure/package signatures only gain parameters at the end, with defaults.
- [ ] Removed repeatable files have a guarded DROP migration.
- [ ] Version number is still the next free one after the latest on `main` (rename if another PR merged first).

If another PR with the same number merged first, CI lint fails with `duplicate version number`: rename your `V`/`U` files to the next number, push again.

## 5. Merge to main

Merging changes **no database**. `main` now describes the version every environment should reach next.
Main stays releasable because every PR passed a fresh install against main.

## 6. Release to an environment (after merge)

Run from a clean checkout of `main` (or a release tag). For a shared/remote database pass `CONN`; the runner inside the local container connects to it.

```bash
git checkout main && git pull
export CONN='bank/<password>@//test-db.company.local:1521/BANKPDB'   # target DB
export ENVIRONMENT=test                                                # 'prod' also requires CONFIRM=yes

./db/scripts/migrate.sh up                 # local helper container (runner + sqlplus), if not running
./db/scripts/migrate.sh status             # where is the target now?
./db/scripts/migrate.sh plan --sql         # exactly what will run - attach to the change ticket
# backup / snapshot the target DB here (Data Pump expdp or storage snapshot)
./db/scripts/migrate.sh migrate            # MIGRATE OK
./db/scripts/migrate.sh validate           # VALIDATE OK
./db/scripts/migrate.sh smoke
git tag db-release-$(date +%Y%m%d) && git push --tags     # record which commit is deployed
```
Windows (PowerShell): `$env:CONN='bank/...@//host:1521/SVC'; $env:ENVIRONMENT='test'; db\migrate.cmd plan`

Production: same steps with `ENVIRONMENT=prod CONFIRM=yes`, in the agreed window, after the same version passed test.
The target needs network access from your machine (the container uses your machine's network).

Promotion order: **local -> test -> prod**, always the same commit/tag; `status` on each shows the same history.

## 7. When something fails

| Symptom | Meaning | What to do |
|---|---|---|
| `cannot connect to Oracle` | container not ready, wrong `CONN` | `up` (wait for "ready"), check `CONN` |
| `service "oracle" is not running` | container stopped | `migrate.sh up` |
| `ORA-01017` | wrong user/password | fix `CONN` |
| `Vnnn FAILED` | statement error; DDL before it is committed | check with `sql`, undo partial changes by hand or with the U file, `repair`, fix file, `migrate` |
| `is recorded as FAILED` | an earlier failure not repaired | as above |
| `checksum mismatch` | an applied migration was edited | `git checkout -- <file>`; put the change in a new migration |
| `out of order` | lower version pending than applied | renumber; `OUT_OF_ORDER=1` only if agreed |
| `duplicate version number` (lint) | two branches used the same number | renumber the one not yet applied anywhere |
| `object(s) became invalid` | code no longer compiles against the schema | fix the code in the same PR, `migrate` again |
| `does not exist in the database` (validate) | a repeatable object was dropped (e.g. by an undo) | `migrate` recreates it |
| `tables already exist but there is no history` | DB built from legacy files | `baseline`, then `migrate` |

Logs: every statement and its output is in the container log:
`docker compose -f db/docker-compose.yml exec oracle cat /tmp/migrate.log`.

## 8. Verification queries (copy/paste into `sql "..."`)

Multi-line checks (macOS/Linux/Git Bash) - the insert is rolled back automatically when the session ends:
```bash
./db/scripts/migrate.sh sql <<'SQL'
INSERT INTO branches (branch_id, branch_code, branch_name) VALUES (seq_branch_id.NEXTVAL, 'T001', 'Test');
SELECT branch_id, branch_code FROM branches WHERE branch_code = 'T001';
SQL
```


```sql
SELECT installed_rank, version, type, status, script, installed_on FROM schema_version ORDER BY installed_rank
SELECT column_name, data_type, data_length, nullable, data_default FROM user_tab_columns WHERE table_name='ACCOUNTS' ORDER BY column_id
SELECT constraint_name, constraint_type, search_condition_vc, status, validated FROM user_constraints WHERE table_name='ACCOUNTS'
SELECT index_name, column_name, column_position FROM user_ind_columns WHERE table_name='TRANSACTIONS' ORDER BY index_name, column_position
SELECT sequence_name, last_number, cache_size FROM user_sequences ORDER BY sequence_name
SELECT object_type, object_name, status, last_ddl_time FROM user_objects WHERE object_name LIKE 'PRC%' ORDER BY last_ddl_time DESC
SELECT object_type, object_name FROM user_objects WHERE status='INVALID'
SELECT name, type, line, text FROM user_errors ORDER BY name, sequence
SELECT text FROM user_source WHERE name='PRC_SEND_NOTIFICATION' ORDER BY line
SELECT argument_name, position, data_type, defaulted FROM user_arguments WHERE object_name='PRC_SEND_NOTIFICATION' ORDER BY position
```
