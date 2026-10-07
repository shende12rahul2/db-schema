-- Fails with ORA-01441 if any value is already longer than the old size. Truncate or fix those rows first.
ALTER TABLE branches MODIFY (branch_name VARCHAR2(100));
ALTER TABLE notifications MODIFY (message VARCHAR2(500));
