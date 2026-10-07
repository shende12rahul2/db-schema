# Tables - 3 examples (branch `example/tables`, V006-V008)

Tables always change through a **new versioned migration** + undo. Never edit `db/baseline/Table/*`.

## 1. Add a column (`V006__add_account_overdraft_limit.sql`)
```bash
./db/scripts/new_migration.sh "add account overdraft limit"   # creates V006 + U006
./db/scripts/migrate.sh deploy
```
- `ADD (col ... DEFAULT x NOT NULL)` is safe for live data and old code.
- Adding a plain `NOT NULL` column without a default fails on a table that has rows (`ORA-01758`).
- Code that uses the column goes in the same PR (repeatable files run after the migration).

## 2. Widen a column (`V007__widen_text_columns.sql`)
- Widening is instant. **Narrowing** can fail with `ORA-01441` if data is longer: that is why the undo script has a warning.
- Changing a type (VARCHAR2 to NUMBER) on a populated column: use expand/contract (add new column, backfill, switch code, drop old in a later release) - see guide example G.

## 3. New table with FK, index, sequence, trigger (`V008__create_customer_addresses.sql`)
- Sequence, table, constraints and index live in the migration.
- The `BEFORE INSERT` trigger lives in `db/repeatable/07_triggers/` (a code object), applied after the migration.
- Undo drops the table (which also drops its trigger) and the sequence.

If a table migration fails halfway, see guide examples B and C (`repair`, then fix and re-run).
