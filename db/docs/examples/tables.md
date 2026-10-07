# Tables - 3 examples (branch `example/tables`, V007-V009)

Tables always change through a **new versioned migration** + undo. Never edit `db/baseline/Table/*`.

## 1. Add a column (`V007__add_account_overdraft_limit.sql`)
```bash
./db/scripts/new_migration.sh "add account overdraft limit"   # creates V007 + U007
./db/scripts/migrate.sh deploy
```
- `ADD (col ... DEFAULT x NOT NULL)` is safe for live data and old code.
- Adding a plain `NOT NULL` column without a default fails on a table that has rows (`ORA-01758`).
- Code that uses the column goes in the same PR (repeatable files run after the migration).

## 2. Widen a column (`V008__widen_text_columns.sql`)
- Widening is instant. **Narrowing** can fail with `ORA-01441` if data is longer: that is why the undo script has a warning.
- Changing a type (VARCHAR2 to NUMBER) on a populated column: use expand/contract (add new column, backfill, switch code, drop old in a later release) - see guide example G.

## 3. New table with FK, index, sequence, trigger (`V009__create_customer_addresses.sql`)
- Sequence, table, constraints and index live in the migration.
- The `BEFORE INSERT` trigger lives in `db/repeatable/07_triggers/` (a code object), applied after the migration.
- Undo drops the table (which also drops its trigger) and the sequence.

If a table migration fails halfway, see guide examples B and C (`repair`, then fix and re-run).

## Try it and verify by hand

Windows: use `db\migrate.cmd` instead of `./db/scripts/migrate.sh` (multi-line `<<` checks need Git Bash/WSL, or run them in SQL Developer/DBeaver).

```bash
git checkout example/tables
./db/scripts/migrate.sh up            # if not running
./db/scripts/migrate.sh plan --sql    # read-only: what will run and why
```

**V007 - new column**
```bash
./db/scripts/migrate.sh step
./db/scripts/migrate.sh sql "SELECT column_name, data_type, nullable, data_default FROM user_tab_columns WHERE table_name='ACCOUNTS' AND column_name='OVERDRAFT_LIMIT'"
./db/scripts/migrate.sh sql "SELECT constraint_name, search_condition_vc FROM user_constraints WHERE constraint_name='CK_ACCOUNTS_OVERDRAFT'"
```
Expected: `OVERDRAFT_LIMIT NUMBER N 0` and the check `overdraft_limit >= 0`.

**V008 - widened columns**
```bash
./db/scripts/migrate.sh step
./db/scripts/migrate.sh sql "SELECT table_name, column_name, data_length FROM user_tab_columns WHERE (table_name, column_name) IN (('BRANCHES','BRANCH_NAME'), ('NOTIFICATIONS','MESSAGE'))"
```
Expected: `BRANCH_NAME 200`, `MESSAGE 1000`.

**V009 - new table (+ trigger after `migrate`)**
```bash
./db/scripts/migrate.sh step
./db/scripts/migrate.sh sql "SELECT constraint_name, constraint_type FROM user_constraints WHERE table_name='CUSTOMER_ADDRESSES'"
./db/scripts/migrate.sh sql "SELECT index_name FROM user_indexes WHERE table_name='CUSTOMER_ADDRESSES'"
./db/scripts/migrate.sh plan          # trg_customer_addresses_bi.trg listed as (new): it runs after the migrations
./db/scripts/migrate.sh migrate
./db/scripts/migrate.sh sql <<'SQL'
INSERT INTO branches (branch_id, branch_code, branch_name) VALUES (seq_branch_id.NEXTVAL, 'T001', 'Test');
INSERT INTO customers (first_name, last_name) VALUES ('Test', 'User');
INSERT INTO customer_addresses (customer_id, line1, city) SELECT MAX(customer_id), '1 Main St', 'Pune' FROM customers;
SELECT address_id, address_type, city FROM customer_addresses;
SQL
```
Expected: `address_id` filled by the trigger, `address_type = HOME`. The inserts are rolled back.
Undo check: `undo` drops the table **and its trigger**; the next `plan` shows the trigger as `(missing in database)` and `migrate` recreates it.

Finish and prove it is reversible:
```bash
./db/scripts/migrate.sh migrate       # remaining migrations + repeatable files -> MIGRATE OK
./db/scripts/migrate.sh validate      # VALIDATE OK
./db/scripts/migrate.sh plan          # both sections "(none)"
./db/scripts/migrate.sh undo          # newest migration only; repeat to go further back
./db/scripts/migrate.sh migrate && ./db/scripts/migrate.sh validate
```
Full flow (PR, merge, release to test/prod): [`../RUNBOOK.md`](../RUNBOOK.md).
