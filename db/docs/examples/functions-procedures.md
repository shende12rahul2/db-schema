# Functions and procedures - 3 examples (branch `example/functions-procedures`, V017)

## 1. Change a function (`03_functions/fn_calc_late_fee.fnc`)
Edit the file, run `migrate`. Only this file's checksum changed, so only this file is redeployed (and recorded as a `REPEATABLE` row).
Keep the signature stable; dependents (`pkg_*`, procedures) stay valid. Changing the *behaviour* is a business decision: mention it in the PR.

## 2. Add a function (`03_functions/fn_calc_processing_fee.fnc`)
New file named after the function. Nothing else to register: the runner discovers it. Lint checks the file name matches the object.

## 3. Extend a procedure that needs a new column (`V017` + `04_procedures/prc_send_notification.prc`)
Rules for signature changes:
- **Append** parameters at the end and give them a **DEFAULT**; never reorder or remove parameters used by callers
  (`pkg_notification_service.notify` still calls it with 3 arguments).
- Ship the migration (new column) and the procedure in **one PR**. Order is guaranteed: migrations, then repeatable files.
- If the procedure fails to compile, the run records that file as `FAILED`; fix and re-run `migrate` (safe to repeat).
- Rollback: `migrate.sh undo` (drops the column), then check out the older procedure and run `migrate`.

## Try it and verify by hand

Windows: use `db\migrate.cmd` instead of `./db/scripts/migrate.sh` (multi-line `<<` checks need Git Bash/WSL, or run them in SQL Developer/DBeaver).

```bash
git checkout example/functions-procedures
./db/scripts/migrate.sh up            # if not running
./db/scripts/migrate.sh plan --sql    # read-only: what will run and why
```

```bash
./db/scripts/migrate.sh plan
```
Expected: `V017` pending; `fn_calc_late_fee.fnc (changed)`, `fn_calc_processing_fee.fnc (new)`, `prc_send_notification.prc (changed)`.

**Functions**
```bash
./db/scripts/migrate.sh sql "SELECT fn_calc_late_fee(10000, 30) AS before_cap FROM dual"     # old: 150
./db/scripts/migrate.sh migrate
./db/scripts/migrate.sh sql "SELECT fn_calc_late_fee(10000, 30) AS fee_30d, fn_calc_late_fee(10000, 400) AS capped, fn_calc_late_fee(-5, 3) AS negative FROM dual"
./db/scripts/migrate.sh sql "SELECT fn_calc_processing_fee(5000000, 'HOME') AS home, fn_calc_processing_fee(10000, 'PERSONAL') AS min_fee FROM dual"
```
Expected: `150`, `1000` (10% cap), `0`; `25000` (max), `500` (min).

**Procedure with new parameter**
```bash
./db/scripts/migrate.sh sql "SELECT argument_name, position, defaulted FROM user_arguments WHERE object_name='PRC_SEND_NOTIFICATION' ORDER BY position"
./db/scripts/migrate.sh sql <<'SQL'
INSERT INTO branches (branch_id, branch_code, branch_name) VALUES (seq_branch_id.NEXTVAL, 'T001', 'Test');
INSERT INTO customers (first_name, last_name) VALUES ('Test', 'User');
DECLARE v_id NUMBER; BEGIN SELECT MAX(customer_id) INTO v_id FROM customers;
  pkg_notification_service.notify(v_id, 'SMS', 'old 3-argument call still works');
  prc_send_notification(v_id, 'SMS', 'urgent', 'HIGH'); END;
/
SELECT message, priority FROM notifications;
SQL
```
Expected: `P_PRIORITY` at position 4 with `DEFAULTED = Y`; rows with priority `NORMAL` and `HIGH` (rolled back afterwards).
Undo check: `undo` drops the column, and the output warns that `PRC_SEND_NOTIFICATION` is now invalid (expected); `migrate` re-applies V017 and it compiles again.

Finish and prove it is reversible:
```bash
./db/scripts/migrate.sh migrate       # remaining migrations + repeatable files -> MIGRATE OK
./db/scripts/migrate.sh validate      # VALIDATE OK
./db/scripts/migrate.sh plan          # both sections "(none)"
./db/scripts/migrate.sh undo          # newest migration only; repeat to go further back
./db/scripts/migrate.sh migrate && ./db/scripts/migrate.sh validate
```
Full flow (PR, merge, release to test/prod): [`../RUNBOOK.md`](../RUNBOOK.md).
