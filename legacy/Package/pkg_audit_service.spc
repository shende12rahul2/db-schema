CREATE OR REPLACE PACKAGE pkg_audit_service AS
  PROCEDURE log_event(p_table VARCHAR2, p_operation VARCHAR2, p_record_id NUMBER, p_details VARCHAR2 DEFAULT NULL);
  PROCEDURE archive(p_older_than_days NUMBER DEFAULT 365);
END pkg_audit_service;
/
