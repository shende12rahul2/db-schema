CREATE OR REPLACE PACKAGE pkg_credit_scoring AS
  FUNCTION get_score(p_customer_id NUMBER) RETURN NUMBER;
  PROCEDURE record_score(p_customer_id NUMBER, p_score NUMBER);
END pkg_credit_scoring;
/
