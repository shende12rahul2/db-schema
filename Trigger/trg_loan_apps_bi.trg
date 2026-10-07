CREATE OR REPLACE TRIGGER trg_loan_apps_bi
  BEFORE INSERT ON loan_applications
  FOR EACH ROW
BEGIN
  IF :NEW.loan_app_id IS NULL THEN
    :NEW.loan_app_id := seq_loan_app_id.NEXTVAL;
  END IF;
END trg_loan_apps_bi;
/
