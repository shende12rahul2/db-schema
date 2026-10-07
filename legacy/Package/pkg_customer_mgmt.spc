CREATE OR REPLACE PACKAGE pkg_customer_mgmt AS
  PROCEDURE register(p_first_name VARCHAR2, p_last_name VARCHAR2, p_pan VARCHAR2, p_mobile VARCHAR2, p_customer_id OUT NUMBER);
  PROCEDURE update_kyc(p_customer_id NUMBER, p_status VARCHAR2);
END pkg_customer_mgmt;
/
