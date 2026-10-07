CREATE OR REPLACE FUNCTION fn_calc_risk_score (
  p_customer_id NUMBER
) RETURN NUMBER
IS
  v_score NUMBER;
BEGIN
  SELECT NVL(MAX(score), 0) INTO v_score
    FROM credit_scores
   WHERE customer_id = p_customer_id;
  RETURN v_score;
END fn_calc_risk_score;
/
