CREATE OR REPLACE TRIGGER trg_payments_bi
  BEFORE INSERT ON payments
  FOR EACH ROW
BEGIN
  IF :NEW.payment_id IS NULL THEN
    :NEW.payment_id := seq_payment_id.NEXTVAL;
  END IF;
END trg_payments_bi;
/
