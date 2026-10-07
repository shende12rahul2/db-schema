CREATE OR REPLACE PACKAGE BODY pkg_customer_mgmt AS

  PROCEDURE register(p_first_name VARCHAR2, p_last_name VARCHAR2, p_pan VARCHAR2, p_mobile VARCHAR2, p_customer_id OUT NUMBER) IS
  BEGIN
    prc_create_customer(p_first_name, p_last_name, p_pan, p_mobile, p_customer_id);
  END register;

  PROCEDURE update_kyc(p_customer_id NUMBER, p_status VARCHAR2) IS
  BEGIN
    prc_update_kyc(p_customer_id, p_status);
  END update_kyc;

END pkg_customer_mgmt;
/
