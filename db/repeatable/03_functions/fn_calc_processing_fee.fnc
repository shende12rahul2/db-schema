CREATE OR REPLACE FUNCTION fn_calc_processing_fee (
  p_amount NUMBER, p_loan_type VARCHAR2
) RETURN NUMBER
IS
  v_pct NUMBER;
BEGIN
  v_pct := CASE UPPER(p_loan_type) WHEN 'HOME' THEN 0.5 WHEN 'AUTO' THEN 1 ELSE 2 END;
  RETURN LEAST(GREATEST(ROUND(p_amount * v_pct / 100, 2), 500), 25000);
END fn_calc_processing_fee;
/
