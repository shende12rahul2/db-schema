CREATE OR REPLACE PACKAGE pkg_payment_gateway AS
  PROCEDURE pay(p_account_id NUMBER, p_amount NUMBER, p_mode VARCHAR2);
  PROCEDURE transfer(p_from_account NUMBER, p_to_account NUMBER, p_amount NUMBER);
END pkg_payment_gateway;
/
