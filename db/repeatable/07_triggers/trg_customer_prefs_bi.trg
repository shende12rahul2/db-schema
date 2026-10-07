CREATE OR REPLACE TRIGGER trg_customer_prefs_bi
  BEFORE INSERT ON customer_preferences
  FOR EACH ROW
BEGIN
  IF :NEW.pref_id IS NULL THEN
    :NEW.pref_id := seq_customer_pref_id.NEXTVAL;
  END IF;
END trg_customer_prefs_bi;
/
