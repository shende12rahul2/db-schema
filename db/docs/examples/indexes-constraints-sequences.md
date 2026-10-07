# Indexes, constraints, sequences - 3 examples (branch `example/indexes-constraints-sequences`, V009-V011)

## 1. Indexes (`V009__add_payment_and_email_indexes.sql`)
- Composite index: put the equality column first (`account_id`), then the next filter (`status`).
- Function-based index (`UPPER(email)`) only helps queries that use the same expression: `WHERE UPPER(email) = UPPER(:x)`.
- Large tables: indexing takes time and I/O; schedule it, and consider `CREATE INDEX ... ONLINE`.

## 2. Constraints with data cleanup (`V010__add_integrity_constraints.sql`)
Adding a constraint to a table with bad data fails (`ORA-02299` duplicates for UNIQUE, `ORA-02293` for CHECK).
Pattern: **archive -> fix -> constrain**, all in one migration, in that order. The undo script restores the archived rows.
- `ENABLE NOVALIDATE` enforces the rule for new data without scanning old rows (fast on huge tables).
- If it still fails midway, the guide's example C explains `repair`; clean up the archive table before retrying.

## 3. Sequences (`V011__sequence_cache_and_resync.sql`)
- `CACHE 100` speeds up inserts, but cached numbers are lost on restart (gaps are normal).
- After loading rows with explicit IDs, re-sync the sequence to `MAX(id) + 1` or the next insert hits a duplicate key (`ORA-00001`).
- Never `DROP`/recreate a sequence that is in use: its current value is lost.
