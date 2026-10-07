# Data migrations - 3 examples (branch `example/data-migrations`, V013-V015)

Data changes are versioned migrations too. Three habits keep them safe: **idempotent** (re-runnable), **batched** (small commits), **reversible** (backup table).

## 1. Seed reference data (`V013__create_ref_loan_types.sql`)
`MERGE` inserts missing rows and updates existing ones, so re-running after a partial failure is harmless. Later changes to the reference data (new loan type) are new migrations, never edits of V013.

## 2. Batched backfill (`V014__backfill_credit_score_risk_band.sql`)
Updating millions of rows in one statement fills undo space and holds locks. Loop with `ROWNUM <= 10000` and `COMMIT` per batch.
Because committed batches cannot roll back, the migration first records the affected IDs (`credit_scores_bak_v013`); the undo script uses them.

## 3. Data clean-up with a backup (`V015__normalize_customer_contacts.sql`)
Create `<table>_bak_v014` with the old values, update, and let undo restore from it. Possible failure: upper-casing creates a duplicate PAN
(`ORA-00001`). Then: fix the offending rows, `migrate.sh repair`, drop `customers_bak_v014`, re-run `migrate`.

Production tips: take a real backup first, test on a copy of production volumes, and run long backfills outside business hours.

## Try it and verify by hand

Windows: use `db\migrate.cmd` instead of `./db/scripts/migrate.sh` (multi-line `<<` checks need Git Bash/WSL, or run them in SQL Developer/DBeaver).

```bash
git checkout example/data-migrations
./db/scripts/migrate.sh up            # if not running
./db/scripts/migrate.sh plan --sql    # read-only: what will run and why
```

**V013 - reference data**
```bash
./db/scripts/migrate.sh step
./db/scripts/migrate.sh sql "SELECT * FROM ref_loan_types ORDER BY loan_type"
```
Expected: 4 rows (AUTO, EDUCATION, HOME, PERSONAL).

**V014 - batched backfill.** First create a test row to backfill (local DB only; the explicit `COMMIT` keeps it):
```bash
./db/scripts/migrate.sh sql <<'SQL'
INSERT INTO branches (branch_id, branch_code, branch_name) VALUES (seq_branch_id.NEXTVAL, 'T001', 'Test');
INSERT INTO customers (first_name, last_name) VALUES ('Test', 'User');
INSERT INTO credit_scores (credit_score_id, customer_id, score) SELECT seq_credit_score_id.NEXTVAL, MAX(customer_id), 720 FROM customers;
COMMIT;
SQL
./db/scripts/migrate.sh step
./db/scripts/migrate.sh sql "SELECT score, risk_band FROM credit_scores"
./db/scripts/migrate.sh sql "SELECT COUNT(*) AS rows_touched FROM credit_scores_bak_v013"
```
Expected: `720 MEDIUM`, `rows_touched 1`. Without the `COMMIT`, `sql` would have rolled the test rows back.

**V015 - data fix with backup**
```bash
./db/scripts/migrate.sh sql <<'SQL'
UPDATE customers SET mobile = '+91 98765-43210', pan_number = ' abcde1234f ' WHERE ROWNUM = 1;
COMMIT;
SQL
./db/scripts/migrate.sh step
./db/scripts/migrate.sh sql "SELECT customer_id, mobile, pan_number FROM customers"
./db/scripts/migrate.sh sql "SELECT * FROM customers_bak_v014"
./db/scripts/migrate.sh undo
./db/scripts/migrate.sh sql "SELECT customer_id, mobile, pan_number FROM customers"
```
Expected: after `step` mobile `919876543210`, PAN `ABCDE1234F`; the backup holds the old values; after `undo` the old values are back.

Finish and prove it is reversible:
```bash
./db/scripts/migrate.sh migrate       # remaining migrations + repeatable files -> MIGRATE OK
./db/scripts/migrate.sh validate      # VALIDATE OK
./db/scripts/migrate.sh plan          # both sections "(none)"
./db/scripts/migrate.sh undo          # newest migration only; repeat to go further back
./db/scripts/migrate.sh migrate && ./db/scripts/migrate.sh validate
```
Full flow (PR, merge, release to test/prod): [`../RUNBOOK.md`](../RUNBOOK.md).
