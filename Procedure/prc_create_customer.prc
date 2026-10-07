CREATE OR REPLACE PROCEDURE prc_create_customer (
  p_first_name VARCHAR2,
  p_last_name VARCHAR2,
  p_pan VARCHAR2,
  p_mobile VARCHAR2,
  p_customer_id OUT NUMBER
)
IS
BEGIN
  IF NOT fn_validate_pan(p_pan) THEN
    RAISE_APPLICATION_ERROR(-20001, 'Invalid PAN');
  END IF;
  INSERT INTO customers (first_name, last_name, pan_number, mobile)
  VALUES (p_first_name, p_last_name, p_pan, p_mobile)
  RETURNING customer_id INTO p_customer_id;
END prc_create_customer;
/
