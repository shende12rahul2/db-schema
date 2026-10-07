CREATE OR REPLACE TRIGGER trg_audit_logs_bi
  BEFORE INSERT ON audit_logs
  FOR EACH ROW
BEGIN
  IF :NEW.audit_id IS NULL THEN
    :NEW.audit_id := seq_audit_id.NEXTVAL;
  END IF;
END trg_audit_logs_bi;
/
