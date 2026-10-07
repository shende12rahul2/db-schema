CREATE OR REPLACE PACKAGE BODY pkg_credit_scoring AS

  FUNCTION get_score(p_customer_id NUMBER) RETURN NUMBER IS
  BEGIN
    RETURN fn_calc_risk_score(p_customer_id);
  END get_score;

  PROCEDURE record_score(p_customer_id NUMBER, p_score NUMBER) IS
  BEGIN
    INSERT INTO credit_scores (customer_id, score) VALUES (p_customer_id, p_score);
  END record_score;

END pkg_credit_scoring;
/
