# Views - 3 examples (branch `example/views`, V015)

Views are **repeatable** objects: edit the file, run `migrate`, only that file is redeployed.

## 1. Change a view in place (`08_views/v_customer_summary.vw`)
Added a `pending_loans` column. Because the file is `CREATE OR REPLACE VIEW`, no migration is needed.
- Append new columns at the end: code selecting by position keeps working.
- Removing/renaming a column breaks dependents (other views, packages). The post-migration recompile reports them as INVALID and the step fails, so fix them in the same PR.

## 2. Add a view (`08_views/v_account_statement.vw`)
Just add the file (named after the view, in `08_views/`). Lint checks the name and the `CREATE OR REPLACE`.
Window functions (running balance) are fine in views; make sure the underlying tables have the index the query needs.

## 3. Retire a view (`08_views/v_pending_kyc.vw` removed + `V015__drop_view_pending_kyc.sql`)
Deleting the file is **not enough**; the object stays in the database. Add a migration with a **guarded** drop (ignore `ORA-00942`)
so fresh installs, where the view never existed, still succeed. `validate` prints an info line if you forget the migration.
Undo recreates the view; after an undo, check out the older code so the file exists again.
