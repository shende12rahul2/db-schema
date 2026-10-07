CREATE OR REPLACE PACKAGE BODY pkg_audit_service AS

  PROCEDURE log_event(p_table VARCHAR2, p_operation VARCHAR2, p_record_id NUMBER, p_details VARCHAR2 DEFAULT NULL) IS
  BEGIN
    INSERT INTO audit_logs (table_name, operation, record_id, details)
    VALUES (p_table, p_operation, p_record_id, p_details);
  END log_event;

  PROCEDURE archive(p_older_than_days NUMBER DEFAULT 365) IS
  BEGIN
    prc_archive_audit_log(p_older_than_days);
  END archive;

END pkg_audit_service;
/
