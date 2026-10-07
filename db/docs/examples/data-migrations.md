# Data migrations - 3 examples (branch `example/data-migrations`, V012-V014)

Data changes are versioned migrations too. Three habits keep them safe: **idempotent** (re-runnable), **batched** (small commits), **reversible** (backup table).

## 1. Seed reference data (`V012__create_ref_loan_types.sql`)
`MERGE` inserts missing rows and updates existing ones, so re-running after a partial failure is harmless. Later changes to the reference data (new loan type) are new migrations, never edits of V012.

## 2. Batched backfill (`V013__backfill_credit_score_risk_band.sql`)
Updating millions of rows in one statement fills undo space and holds locks. Loop with `ROWNUM <= 10000` and `COMMIT` per batch.
Because committed batches cannot roll back, the migration first records the affected IDs (`credit_scores_bak_v013`); the undo script uses them.

## 3. Data clean-up with a backup (`V014__normalize_customer_contacts.sql`)
Create `<table>_bak_v014` with the old values, update, and let undo restore from it. Possible failure: upper-casing creates a duplicate PAN
(`ORA-00001`). Then: fix the offending rows, `migrate.sh repair`, drop `customers_bak_v014`, re-run `migrate`.

Production tips: take a real backup first, test on a copy of production volumes, and run long backfills outside business hours.
