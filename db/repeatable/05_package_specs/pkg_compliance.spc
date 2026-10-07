CREATE OR REPLACE PACKAGE pkg_compliance AS
  FUNCTION is_kyc_complete(p_customer_id NUMBER) RETURN BOOLEAN;
  PROCEDURE flag_suspicious(p_account_id NUMBER, p_reason VARCHAR2);
END pkg_compliance;
/
