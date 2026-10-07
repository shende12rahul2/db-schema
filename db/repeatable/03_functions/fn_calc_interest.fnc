CREATE OR REPLACE FUNCTION fn_calc_interest (
  p_principal NUMBER, p_annual_rate NUMBER, p_days NUMBER
) RETURN NUMBER
IS
BEGIN
  RETURN ROUND(p_principal * p_annual_rate / 100 * p_days / 365, 2);
END fn_calc_interest;
/
