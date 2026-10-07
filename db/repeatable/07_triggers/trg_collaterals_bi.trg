CREATE OR REPLACE TRIGGER trg_collaterals_bi
  BEFORE INSERT ON collaterals
  FOR EACH ROW
BEGIN
  IF :NEW.collateral_id IS NULL THEN
    :NEW.collateral_id := seq_collateral_id.NEXTVAL;
  END IF;
END trg_collaterals_bi;
/
