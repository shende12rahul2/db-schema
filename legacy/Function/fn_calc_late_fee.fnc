CREATE OR REPLACE FUNCTION fn_calc_late_fee (
  p_overdue_amt NUMBER, p_days_late NUMBER
) RETURN NUMBER
IS
  c_daily_pct CONSTANT NUMBER := 0.05;
BEGIN
  RETURN ROUND(p_overdue_amt * c_daily_pct / 100 * p_days_late, 2);
END fn_calc_late_fee;
/
