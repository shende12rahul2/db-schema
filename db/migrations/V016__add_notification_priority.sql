-- Example 3 (procedures): the procedure change below needs this column, so both ship in one PR.
-- Migrations run first, then the changed repeatable files, so the procedure never sees a missing column.
ALTER TABLE notifications ADD (priority VARCHAR2(6) DEFAULT 'NORMAL' NOT NULL);
ALTER TABLE notifications ADD CONSTRAINT ck_notifications_priority CHECK (priority IN ('LOW', 'NORMAL', 'HIGH'));
