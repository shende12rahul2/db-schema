CREATE OR REPLACE TRIGGER trg_transactions_bi
  BEFORE INSERT ON transactions
  FOR EACH ROW
BEGIN
  IF :NEW.transaction_id IS NULL THEN
    :NEW.transaction_id := seq_transaction_id.NEXTVAL;
  END IF;
END trg_transactions_bi;
/
