CREATE OR REPLACE PROCEDURE prc_archive_audit_log (
  p_older_than_days NUMBER DEFAULT 365
)
IS
BEGIN
  -- TODO: move rows to an archive table before deleting
  DELETE FROM audit_logs
   WHERE changed_at < SYSTIMESTAMP - p_older_than_days;
END prc_archive_audit_log;
/
