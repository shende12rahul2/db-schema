CREATE OR REPLACE TRIGGER trg_customers_bi
  BEFORE INSERT ON customers
  FOR EACH ROW
BEGIN
  IF :NEW.customer_id IS NULL THEN
    :NEW.customer_id := seq_customer_id.NEXTVAL;
  END IF;
END trg_customers_bi;
/
