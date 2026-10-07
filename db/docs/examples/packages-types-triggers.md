# Packages, triggers, object types - 3 examples (branch `example/packages-types-triggers`, no migration)

All three are repeatable: edit files, run `migrate`.

## 1. Extend a package (`05_package_specs/pkg_account_service.spc` + `06_package_bodies/pkg_account_service.bdy`)
Added `freeze_account` / `unfreeze_account`. Change **both** files: spec and body are tracked separately, and the spec runs first.
- Add new members at the end of the spec; do not change existing signatures that other code calls.
- A changed spec invalidates every dependent object; the recompile step fixes them, and any still-broken one fails the run.
- Sessions that already used the package get `ORA-04068` once ("package state discarded"); deploy in a quiet window.

## 2. Add a trigger (`07_triggers/trg_accounts_balance_aud.trg`)
An `AFTER UPDATE OF balance` row trigger that writes to `audit_logs` (its ID comes from the existing insert trigger).
- Use a `WHEN` clause so the trigger does not fire when nothing changed.
- Triggers on a hot table add cost to every write; load-test before releasing.
- Retiring a trigger: delete the file **and** add a migration with a guarded `DROP TRIGGER` (see `views.md` example 3).

## 3. Evolve an object type (`01_types/t_contact_typ.tps` + `02_type_bodies/t_contact_typ.tpb`)
Added an attribute and a member function. `CREATE OR REPLACE TYPE` works only while **nothing depends on the type**.
Once a table column or another type uses it, Oracle raises `ORA-02303`; at that point move the type into versioned migrations and use
`ALTER TYPE t_contact_typ ADD ATTRIBUTE (alt_mobile VARCHAR2(15)) CASCADE;`, and keep the repeatable file only for the type body.

## Try it and verify by hand

Windows: use `db\migrate.cmd` instead of `./db/scripts/migrate.sh` (multi-line `<<` checks need Git Bash/WSL, or run them in SQL Developer/DBeaver).

```bash
git checkout example/packages-types-triggers
./db/scripts/migrate.sh up            # if not running
./db/scripts/migrate.sh plan --sql    # read-only: what will run and why
```

```bash
./db/scripts/migrate.sh plan
```
Expected: no versioned migrations; repeatable: `t_contact_typ.tps`/`.tpb (changed)`, `pkg_account_service.spc`/`.bdy (changed)`, `trg_accounts_balance_aud.trg (new)`.
```bash
./db/scripts/migrate.sh migrate
./db/scripts/migrate.sh sql "SELECT object_type, object_name, status FROM user_objects WHERE object_name IN ('PKG_ACCOUNT_SERVICE','T_CONTACT_TYP','TRG_ACCOUNTS_BALANCE_AUD')"
./db/scripts/migrate.sh sql "SELECT procedure_name FROM user_procedures WHERE object_name='PKG_ACCOUNT_SERVICE' ORDER BY 1"
./db/scripts/migrate.sh sql "SELECT t_contact_typ('9876543210', 'a@b.c', NULL).masked_mobile() AS masked FROM dual"
```
Expected: all `VALID`; `FREEZE_ACCOUNT`, `UNFREEZE_ACCOUNT` listed; `XXXXXX3210`.

Package + trigger behaviour (rolled back at the end):
```bash
./db/scripts/migrate.sh sql <<'SQL'
INSERT INTO branches (branch_id, branch_code, branch_name) VALUES (seq_branch_id.NEXTVAL, 'T001', 'Test');
INSERT INTO customers (first_name, last_name) VALUES ('Test', 'User');
DECLARE v_c NUMBER; v_b NUMBER; v_a NUMBER; BEGIN
  SELECT MAX(customer_id) INTO v_c FROM customers; SELECT MAX(branch_id) INTO v_b FROM branches;
  pkg_account_service.open_account(v_c, v_b, 'SAVINGS', v_a);
  UPDATE accounts SET balance = 500 WHERE account_id = v_a;
  pkg_account_service.freeze_account(v_a); END;
/
SELECT account_id, status, balance FROM accounts;
SELECT operation, details FROM audit_logs WHERE table_name = 'ACCOUNTS';
SQL
```
Expected: account `FROZEN` with balance 500; one audit row `BALANCE  balance 0 -> 500`.
These examples have no migration, so `undo` does not apply; roll back by checking out the previous commit and running `migrate`.

Finish and prove it is reversible:
```bash
./db/scripts/migrate.sh migrate       # remaining migrations + repeatable files -> MIGRATE OK
./db/scripts/migrate.sh validate      # VALIDATE OK
./db/scripts/migrate.sh plan          # both sections "(none)"
./db/scripts/migrate.sh undo          # newest migration only; repeat to go further back
./db/scripts/migrate.sh migrate && ./db/scripts/migrate.sh validate
```
Full flow (PR, merge, release to test/prod): [`../RUNBOOK.md`](../RUNBOOK.md).
