CREATE OR REPLACE VIEW v_audit_summary AS
SELECT table_name, operation, COUNT(*) AS event_count, MAX(changed_at) AS last_event
  FROM audit_logs
 GROUP BY table_name, operation;
