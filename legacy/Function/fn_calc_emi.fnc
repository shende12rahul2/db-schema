CREATE OR REPLACE FUNCTION fn_calc_emi (
  p_principal NUMBER, p_annual_rate NUMBER, p_months NUMBER
) RETURN NUMBER
IS
  v_r NUMBER := p_annual_rate / 12 / 100;
BEGIN
  IF v_r = 0 THEN RETURN ROUND(p_principal / p_months, 2); END IF;
  RETURN ROUND(p_principal * v_r * POWER(1 + v_r, p_months) / (POWER(1 + v_r, p_months) - 1), 2);
END fn_calc_emi;
/
