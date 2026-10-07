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
