# Views - 3 examples (branch `example/views`, V016)

Views are **repeatable** objects: edit the file, run `migrate`, only that file is redeployed.

## 1. Change a view in place (`08_views/v_customer_summary.vw`)
Added a `pending_loans` column. Because the file is `CREATE OR REPLACE VIEW`, no migration is needed.
- Append new columns at the end: code selecting by position keeps working.
- Removing/renaming a column breaks dependents (other views, packages). The post-migration recompile reports them as INVALID and the step fails, so fix them in the same PR.

## 2. Add a view (`08_views/v_account_statement.vw`)
Just add the file (named after the view, in `08_views/`). Lint checks the name and the `CREATE OR REPLACE`.
Window functions (running balance) are fine in views; make sure the underlying tables have the index the query needs.

## 3. Retire a view (`08_views/v_pending_kyc.vw` removed + `V016__drop_view_pending_kyc.sql`)
Deleting the file is **not enough**; the object stays in the database. Add a migration with a **guarded** drop (ignore `ORA-00942`)
so fresh installs, where the view never existed, still succeed. `validate` prints an info line if you forget the migration.
Undo recreates the view; after an undo, check out the older code so the file exists again.

## Try it and verify by hand

Windows: use `db\migrate.cmd` instead of `./db/scripts/migrate.sh` (multi-line `<<` checks need Git Bash/WSL, or run them in SQL Developer/DBeaver).

```bash
git checkout example/views
./db/scripts/migrate.sh up            # if not running
./db/scripts/migrate.sh plan --sql    # read-only: what will run and why
```

```bash
./db/scripts/migrate.sh plan
```
Expected: `V016` pending; `08_views/v_customer_summary.vw (changed)` and `08_views/v_account_statement.vw (new)` under repeatable files.

**V016 + view changes**
```bash
./db/scripts/migrate.sh migrate
./db/scripts/migrate.sh sql "SELECT view_name FROM user_views WHERE view_name IN ('V_PENDING_KYC','V_ACCOUNT_STATEMENT','V_CUSTOMER_SUMMARY')"
./db/scripts/migrate.sh sql "SELECT column_name FROM user_tab_columns WHERE table_name='V_CUSTOMER_SUMMARY' ORDER BY column_id"
./db/scripts/migrate.sh sql "SELECT * FROM v_account_statement WHERE ROWNUM <= 5"
```
Expected: `V_PENDING_KYC` gone; `V_CUSTOMER_SUMMARY` ends with `PENDING_LOANS`; `V_ACCOUNT_STATEMENT` exists.
Fresh-install check of the guarded drop: `down`, `up`, `deploy` -> V016 succeeds although the view never existed.

Finish and prove it is reversible:
```bash
./db/scripts/migrate.sh migrate       # remaining migrations + repeatable files -> MIGRATE OK
./db/scripts/migrate.sh validate      # VALIDATE OK
./db/scripts/migrate.sh plan          # both sections "(none)"
./db/scripts/migrate.sh undo          # newest migration only; repeat to go further back
./db/scripts/migrate.sh migrate && ./db/scripts/migrate.sh validate
```
Full flow (PR, merge, release to test/prod): [`../RUNBOOK.md`](../RUNBOOK.md).
