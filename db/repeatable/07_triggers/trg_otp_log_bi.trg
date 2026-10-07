CREATE OR REPLACE TRIGGER trg_otp_log_bi
  BEFORE INSERT ON otp_log
  FOR EACH ROW
BEGIN
  IF :NEW.otp_id IS NULL THEN
    :NEW.otp_id := seq_otp_id.NEXTVAL;
  END IF;
END trg_otp_log_bi;
/
