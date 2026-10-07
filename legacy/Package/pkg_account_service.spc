CREATE OR REPLACE PACKAGE pkg_account_service AS
  PROCEDURE open_account(p_customer_id NUMBER, p_branch_id NUMBER, p_type VARCHAR2, p_account_id OUT NUMBER);
  PROCEDURE close_account(p_account_id NUMBER);
  FUNCTION get_balance(p_account_id NUMBER) RETURN NUMBER;
END pkg_account_service;
/
