# Functions and procedures - 3 examples (branch `example/functions-procedures`, V016)

## 1. Change a function (`03_functions/fn_calc_late_fee.fnc`)
Edit the file, run `migrate`. Only this file's checksum changed, so only this file is redeployed (and recorded as a `REPEATABLE` row).
Keep the signature stable; dependents (`pkg_*`, procedures) stay valid. Changing the *behaviour* is a business decision: mention it in the PR.

## 2. Add a function (`03_functions/fn_calc_processing_fee.fnc`)
New file named after the function. Nothing else to register: the runner discovers it. Lint checks the file name matches the object.

## 3. Extend a procedure that needs a new column (`V016` + `04_procedures/prc_send_notification.prc`)
Rules for signature changes:
- **Append** parameters at the end and give them a **DEFAULT**; never reorder or remove parameters used by callers
  (`pkg_notification_service.notify` still calls it with 3 arguments).
- Ship the migration (new column) and the procedure in **one PR**. Order is guaranteed: migrations, then repeatable files.
- If the procedure fails to compile, the run records that file as `FAILED`; fix and re-run `migrate` (safe to repeat).
- Rollback: `migrate.sh undo` (drops the column), then check out the older procedure and run `migrate`.
