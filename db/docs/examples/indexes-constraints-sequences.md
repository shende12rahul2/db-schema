# Indexes, constraints, sequences - 3 examples (branch `example/indexes-constraints-sequences`, V010-V012)

## 1. Indexes (`V010__add_payment_and_email_indexes.sql`)
- Composite index: put the equality column first (`account_id`), then the next filter (`status`).
- Function-based index (`UPPER(email)`) only helps queries that use the same expression: `WHERE UPPER(email) = UPPER(:x)`.
- Large tables: indexing takes time and I/O; schedule it, and consider `CREATE INDEX ... ONLINE`.

## 2. Constraints with data cleanup (`V011__add_integrity_constraints.sql`)
Adding a constraint to a table with bad data fails (`ORA-02299` duplicates for UNIQUE, `ORA-02293` for CHECK).
Pattern: **archive -> fix -> constrain**, all in one migration, in that order. The undo script restores the archived rows.
- `ENABLE NOVALIDATE` enforces the rule for new data without scanning old rows (fast on huge tables).
- If it still fails midway, the guide's example C explains `repair`; clean up the archive table before retrying.

## 3. Sequences (`V012__sequence_cache_and_resync.sql`)
- `CACHE 100` speeds up inserts, but cached numbers are lost on restart (gaps are normal).
- After loading rows with explicit IDs, re-sync the sequence to `MAX(id) + 1` or the next insert hits a duplicate key (`ORA-00001`).
- Never `DROP`/recreate a sequence that is in use: its current value is lost.

## Try it and verify by hand

Windows: use `db\migrate.cmd` instead of `./db/scripts/migrate.sh` (multi-line `<<` checks need Git Bash/WSL, or run them in SQL Developer/DBeaver).

```bash
git checkout example/indexes-constraints-sequences
./db/scripts/migrate.sh up            # if not running
./db/scripts/migrate.sh plan --sql    # read-only: what will run and why
```

**V010 - indexes**
```bash
./db/scripts/migrate.sh step
./db/scripts/migrate.sh sql "SELECT index_name, column_name, column_position FROM user_ind_columns WHERE index_name IN ('IDX_PAYMENTS_ACCOUNT_STATUS','IDX_CUSTOMERS_EMAIL_UPPER') ORDER BY 1, 3"
./db/scripts/migrate.sh sql "SELECT index_name, column_expression FROM user_ind_expressions WHERE index_name='IDX_CUSTOMERS_EMAIL_UPPER'"
```

**V011 - constraints after cleanup**
```bash
./db/scripts/migrate.sh step
./db/scripts/migrate.sh sql "SELECT constraint_name, constraint_type, status, validated FROM user_constraints WHERE constraint_name IN ('UK_DOCUMENTS_CUSTOMER_TYPE','CK_CREDIT_SCORES_RANGE','CK_ACCOUNTS_STATUS')"
./db/scripts/migrate.sh sql "SELECT COUNT(*) AS archived_duplicates FROM documents_dupes_v010"
```
Expected: three constraints `ENABLED`; `CK_ACCOUNTS_STATUS` shows `NOT VALIDATED` (NOVALIDATE).
Negative test (rolled back): `./db/scripts/migrate.sh sql "UPDATE accounts SET status='BROKEN' WHERE ROWNUM = 1"` -> `ORA-02290: check constraint ... violated` (only if an account exists).

**V012 - sequences**
```bash
./db/scripts/migrate.sh sql "SELECT sequence_name, cache_size, last_number FROM user_sequences WHERE sequence_name IN ('SEQ_TRANSACTION_ID','SEQ_PAYMENT_ID')"
./db/scripts/migrate.sh step
./db/scripts/migrate.sh sql "SELECT sequence_name, cache_size, last_number FROM user_sequences WHERE sequence_name IN ('SEQ_TRANSACTION_ID','SEQ_PAYMENT_ID')"
```
Expected: `SEQ_TRANSACTION_ID` cache 0 -> 100; `SEQ_PAYMENT_ID` last_number = MAX(payment_id) + 1.

Finish and prove it is reversible:
```bash
./db/scripts/migrate.sh migrate       # remaining migrations + repeatable files -> MIGRATE OK
./db/scripts/migrate.sh validate      # VALIDATE OK
./db/scripts/migrate.sh plan          # both sections "(none)"
./db/scripts/migrate.sh undo          # newest migration only; repeat to go further back
./db/scripts/migrate.sh migrate && ./db/scripts/migrate.sh validate
```
Full flow (PR, merge, release to test/prod): [`../RUNBOOK.md`](../RUNBOOK.md).
