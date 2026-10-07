CREATE OR REPLACE TRIGGER trg_accounts_bi
  BEFORE INSERT ON accounts
  FOR EACH ROW
BEGIN
  IF :NEW.account_id IS NULL THEN
    :NEW.account_id := seq_account_id.NEXTVAL;
  END IF;
END trg_accounts_bi;
/
