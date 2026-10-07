CREATE OR REPLACE FUNCTION fn_get_kyc_status (
  p_customer_id NUMBER
) RETURN VARCHAR2
IS
  v_status customers.kyc_status%TYPE;
BEGIN
  SELECT kyc_status INTO v_status FROM customers WHERE customer_id = p_customer_id;
  RETURN v_status;
EXCEPTION
  WHEN NO_DATA_FOUND THEN RETURN NULL;
END fn_get_kyc_status;
/
