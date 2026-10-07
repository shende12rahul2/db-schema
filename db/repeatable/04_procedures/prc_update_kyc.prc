CREATE OR REPLACE PROCEDURE prc_update_kyc (
  p_customer_id NUMBER,
  p_status VARCHAR2
)
IS
BEGIN
  UPDATE customers SET kyc_status = p_status WHERE customer_id = p_customer_id;
END prc_update_kyc;
/
