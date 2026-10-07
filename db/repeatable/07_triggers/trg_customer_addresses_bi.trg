CREATE OR REPLACE TRIGGER trg_customer_addresses_bi
  BEFORE INSERT ON customer_addresses
  FOR EACH ROW
BEGIN
  IF :NEW.address_id IS NULL THEN
    :NEW.address_id := seq_address_id.NEXTVAL;
  END IF;
END trg_customer_addresses_bi;
/
