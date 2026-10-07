-- Example 2 (tables): widen columns. Widening is safe and instant; narrowing can fail on existing data.
ALTER TABLE branches MODIFY (branch_name VARCHAR2(200));
ALTER TABLE notifications MODIFY (message VARCHAR2(1000));
