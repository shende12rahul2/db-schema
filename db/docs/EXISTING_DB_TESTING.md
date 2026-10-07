# Testing on a local database that ALREADY has your tables

Use this guide when your local Oracle already contains the bank schema (tables, data, packages ...), for example because you
followed the old instructions on `main` (`docker run --name oracle-free ...` + `scripts/deploy.sh`).
For an empty machine use [LOCAL_TESTING.md](LOCAL_TESTING.md) instead.

What you will do: identify your database -> **back it up** -> check it -> adopt it (`baseline`) -> apply the new versions one
at a time while checking your data -> validate -> (optional) try an example branch -> keep or restore.

Commands are for macOS/Linux/**Git Bash** on Windows. In cmd/PowerShell use `db\migrate.cmd` instead of `./db/scripts/migrate.sh`
(the `<<'SQL'` blocks need Git Bash).

---

## Step 1 - Get the branch

```bash
cd db-schema                         # your existing clone
git fetch origin
git checkout claude/versioned-db-structure
git pull
./db/scripts/lint_migrations.sh      # LINT OK
```

## Step 2 - Find out which kind of database you have

```bash
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Label "com.docker.compose.project"}}'
```

| What you see | Your case | Environment to use |
|---|---|---|
| `oracle-free`, last column **empty** | **A** - created by the old `docker run` instructions on `main` | `--env legacy-local` |
| `oracle-free`, last column **db** | **B** - created by `migrate.sh up` from this branch | default (no `--env`) |
| no Oracle container (Oracle installed on the machine, a VM, ...) | **C** - your own Oracle | `--env dev` (create it in Step 3) |

Most people coming from `main` are case **A**. The rest of this guide uses `--env legacy-local`; for case B leave `--env ...` out,
for case C write `--env dev`.

Make sure the database container is running: `docker start oracle-free` (cases A and B).

## Step 3 - Point the tool at your database

Case A: `db/config/legacy-local.conf` already has the values from the old instructions (port 1521, service `FREEPDB1`,
user `bank`, password `Bank123`). If you used other values, edit that file.

Case C: create the environment once:
```bash
cp db/config/dev.conf.example db/config/dev.conf            # set DB_HOST, DB_PORT, DB_SERVICE, DB_USER
printf 'DB_PASSWORD=your-password\n' > db/config/dev.secret.conf   # git-ignored
```
DB on your own machine: `DB_HOST=host.docker.internal`. Have SQL*Plus installed and prefer no Docker: `RUNNER=local`, `DB_HOST=localhost`.

Check and start the small sqlplus helper container (it does **not** touch your database):
```bash
./db/scripts/migrate.sh --env legacy-local config
./db/scripts/migrate.sh --env legacy-local up
./db/scripts/migrate.sh --env legacy-local sql "SELECT USER, SYS_CONTEXT('USERENV','CON_NAME') AS pdb FROM dual"
```
Expected: `runner : docker-client`, `connection : bank@//host.docker.internal:1521/FREEPDB1   password: set`, then `Ready.`, then `BANK  FREEPDB1`.

If the `sql` command shows `ORA-12541` / `ORA-12514` / `ORA-01017`, the host/port/service/password do not match: fix the config file and retry.

> Do **not** run plain `./db/scripts/migrate.sh up` in case A: that is for a new managed DB. It refuses anyway because the name `oracle-free` is taken.

## Step 4 - Back up the schema (do not skip)

Case A/B (container) - Data Pump export of the `BANK` schema into the container:
```bash
docker exec oracle-free expdp system/Oracle123@//localhost:1521/FREEPDB1 \
  schemas=BANK directory=DATA_PUMP_DIR dumpfile=bank_before_versioning.dmp logfile=bank_before_versioning.log
```
Expected last line: `Job "SYSTEM"."SYS_EXPORT_SCHEMA_01" successfully completed`. (Use your `ORACLE_PASSWORD` if it was not `Oracle123`.)
Keep a copy outside the container too:
```bash
docker exec oracle-free sh -c 'ls $ORACLE_BASE/admin/*/dpdump/*/bank_before_versioning.dmp 2>/dev/null || find / -name bank_before_versioning.dmp 2>/dev/null | head -1'
docker cp oracle-free:<path printed above> ./bank_before_versioning.dmp
```
Case C: run the same `expdp` on your server (or use your normal backup).

How to restore is in Step 12.

## Step 5 - Record the current state (to compare later)

```bash
./db/scripts/migrate.sh --env legacy-local sql "SELECT table_name, num_rows FROM user_tables ORDER BY table_name"
./db/scripts/migrate.sh --env legacy-local sql <<'SQL'
SELECT 'customers' t, COUNT(*) n FROM customers UNION ALL
SELECT 'accounts', COUNT(*) FROM accounts UNION ALL
SELECT 'transactions', COUNT(*) FROM transactions UNION ALL
SELECT 'loan_applications', COUNT(*) FROM loan_applications UNION ALL
SELECT 'payments', COUNT(*) FROM payments;
SQL
./db/scripts/migrate.sh --env legacy-local sql "SELECT object_type, object_name FROM user_objects WHERE status='INVALID' ORDER BY 1,2"
```
Write the row counts down. In case A the invalid list shows **8 `TYPE BODY`** objects (`T_APPLICANT_TYP` ... `T_SCORE_TYP`):
the old flat files contain empty type bodies Oracle cannot compile. V006 removes them.

## Step 6 - Check the data the new migrations will touch

Two migrations change **data**, so look first:
```bash
# V003 sets every loan status NOT in this list to 'REJECTED', then adds a check constraint
./db/scripts/migrate.sh --env legacy-local sql "SELECT status, COUNT(*) FROM loan_applications GROUP BY status ORDER BY 1"
```
Allowed: `SUBMITTED, UNDER_REVIEW, APPROVED, REJECTED, DISBURSED`. If you see other statuses you want to keep, **stop**:
those rows would become `REJECTED`. Ask for V003 to be changed (on a branch) before going on.

V004 creates `customer_preferences` and inserts **one row per customer** (defaults: channel `SMS`, opt-in `N`). Nothing else is changed.

## Step 7 - See what the tool thinks (changes nothing)

```bash
./db/scripts/migrate.sh --env legacy-local plan
```
Expected:
```
History  : none, but the schema already has tables -> run 'baseline <version>' first (migrate will refuse)
1) Versioned migrations ...   V001 ... V006
2) Repeatable files ...       78 files (new)
```
Prove it refuses to touch an unmanaged schema:
```bash
./db/scripts/migrate.sh --env legacy-local migrate
```
Expected: `ERROR: the database already has tables but no history in schema_version. Adopt it first: migrate.sh baseline <version>`.

## Step 8 - Decide the baseline version

Your schema already contains V001 (the original tables). Check that none of the later changes are there yet:
```bash
./db/scripts/migrate.sh --env legacy-local sql <<'SQL'
SELECT 'V002 customers.email_verified' AS change, COUNT(*) AS present FROM user_tab_columns WHERE table_name='CUSTOMERS' AND column_name='EMAIL_VERIFIED' UNION ALL
SELECT 'V003 ck_loan_app_status', COUNT(*) FROM user_constraints WHERE constraint_name='CK_LOAN_APP_STATUS' UNION ALL
SELECT 'V004 customer_preferences', COUNT(*) FROM user_tables WHERE table_name='CUSTOMER_PREFERENCES' UNION ALL
SELECT 'V005 idx_txn_account_date', COUNT(*) FROM user_indexes WHERE index_name='IDX_TXN_ACCOUNT_DATE';
SQL
```
- All `0` (normal for case A): baseline = **V001** -> `baseline`.
- If, say, V002 and V003 show `1` (you applied them by hand): baseline = **V003** -> `baseline 003`.

## Step 9 - Adopt the database

```bash
./db/scripts/migrate.sh --env legacy-local baseline          # or: baseline 003
```
Expected: `V001 marked as applied (baseline, not executed)` and `baselined 1 migration(s) up to V001`.
Nothing in your tables changed; only the `SCHEMA_VERSION` table was created and filled:
```bash
./db/scripts/migrate.sh --env legacy-local sql "SELECT version, type, status, script FROM schema_version"
./db/scripts/migrate.sh --env legacy-local plan --sql        # now: V002..V006 pending, with their SQL
```

## Step 10 - Apply the new versions one at a time

Until V006 has run, each step also prints `i already invalid before this change (not blocking):` with the 8 type bodies
from Step 5 (case A). That is expected: only objects a migration newly breaks make it fail.

```bash
./db/scripts/migrate.sh --env legacy-local step        # V002 OK
./db/scripts/migrate.sh --env legacy-local sql "SELECT email_verified, COUNT(*) FROM customers GROUP BY email_verified"
```
Expected: every existing customer has `N`.
```bash
./db/scripts/migrate.sh --env legacy-local step        # V003 OK
./db/scripts/migrate.sh --env legacy-local sql "SELECT status, COUNT(*) FROM loan_applications GROUP BY status ORDER BY 1"
```
Expected: same counts as in Step 6 (unless you had unknown statuses).
```bash
./db/scripts/migrate.sh --env legacy-local step        # V004 OK
./db/scripts/migrate.sh --env legacy-local sql "SELECT (SELECT COUNT(*) FROM customers) AS customers, (SELECT COUNT(*) FROM customer_preferences) AS preferences FROM dual"
```
Expected: both numbers equal.
```bash
./db/scripts/migrate.sh --env legacy-local step        # V005 OK
./db/scripts/migrate.sh --env legacy-local step        # V006 OK - may print "dropped invalid empty type body T_..." (8 lines)
./db/scripts/migrate.sh --env legacy-local sql "SELECT object_type, object_name FROM user_objects WHERE status='INVALID'"
```
Expected after V006: `no rows selected`.

If a step fails: read the message (it lists 4 recovery steps), see [RUNBOOK.md](RUNBOOK.md) section 7, and ask before improvising -
your backup from Step 4 is the safety net.

## Step 11 - Apply the code objects and validate

```bash
./db/scripts/migrate.sh --env legacy-local migrate     # 78 repeatable files (new) -> repeatable objects OK, MIGRATE OK
./db/scripts/migrate.sh --env legacy-local validate    # VALIDATE OK
./db/scripts/migrate.sh --env legacy-local smoke       # counts, function results, rolled-back insert
./db/scripts/migrate.sh --env legacy-local status      # V001 BASELINE, V002..V006 SUCCESS, nothing pending
./db/scripts/migrate.sh --env legacy-local plan        # both sections "(none)"
```
The 78 files are re-created with `CREATE OR REPLACE`; they are the same code you already had (plus the new trigger for
`customer_preferences`), so behaviour does not change.

Compare with Step 5: re-run the row-count query. Same counts for your tables; one new table `CUSTOMER_PREFERENCES` and `SCHEMA_VERSION`.
Smoke-test counts may be higher than the README numbers if your schema has extra objects of its own - that is fine.

**Your database is now managed by the tool.** From here on, `plan` / `migrate` apply only new changes.

## Step 12 - Undo, or go back completely

Undo the newest migration and re-apply it (proves rollback works on your DB):
```bash
./db/scripts/migrate.sh --env legacy-local undo        # V006 (nothing to undo) - repeat to undo V005, V004 ...
./db/scripts/migrate.sh --env legacy-local migrate
./db/scripts/migrate.sh --env legacy-local validate
```
Note: undo of V003 cannot restore statuses that were changed to `REJECTED`; undo of V001 is blocked (it would drop the schema).

Go back **completely** to how it was before Step 9 (restore the backup from Step 4):
```bash
docker exec -i oracle-free sqlplus -s system/Oracle123@//localhost:1521/FREEPDB1 <<< "DROP USER bank CASCADE;"
docker exec oracle-free impdp system/Oracle123@//localhost:1521/FREEPDB1 \
  schemas=BANK directory=DATA_PUMP_DIR dumpfile=bank_before_versioning.dmp logfile=bank_restore.log
```
The import recreates the user with its old password, tables, data and code.

## Step 13 (optional) - Try an example branch on your database

```bash
git checkout example/tables
./db/scripts/migrate.sh --env legacy-local plan --sql      # V007-V009 + new trigger file
./db/scripts/migrate.sh --env legacy-local step            # then the checks from db/docs/examples/tables.md
./db/scripts/migrate.sh --env legacy-local migrate
./db/scripts/migrate.sh --env legacy-local validate
```
Before switching back, **undo what the branch added**, otherwise `validate` on the base branch reports
"V009 was applied but its file is missing":
```bash
./db/scripts/migrate.sh --env legacy-local undo            # V009
./db/scripts/migrate.sh --env legacy-local undo            # V008
./db/scripts/migrate.sh --env legacy-local undo            # V007
git checkout claude/versioned-db-structure
./db/scripts/migrate.sh --env legacy-local migrate         # restores base code objects if needed
./db/scripts/migrate.sh --env legacy-local validate
```
Other branches: same pattern; the page of each branch (`db/docs/examples/*.md`) lists its checks and versions.

## Step 14 - Clean up

```bash
./db/scripts/migrate.sh --env legacy-local down            # removes only the sqlplus helper container
```
Your database container `oracle-free` and its data stay as they are.

## Checklist

- [ ] Step 2 case identified
- [ ] Step 3 `sql` connects as `BANK`
- [ ] Step 4 export completed and copied out
- [ ] Step 5 row counts written down; 8 invalid type bodies seen (case A)
- [ ] Step 6 no unexpected loan statuses
- [ ] Step 7 `migrate` refused before baseline
- [ ] Step 9 baseline recorded, tables unchanged
- [ ] Step 10 each step verified; no invalid objects after V006
- [ ] Step 11 `VALIDATE OK`, row counts unchanged
- [ ] Step 12 undo + migrate works

If anything differs, save the output and the log (`./db/scripts/migrate.sh --env legacy-local log > migrate.log`) and send both.
