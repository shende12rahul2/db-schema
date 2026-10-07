CREATE OR REPLACE FUNCTION fn_calc_late_fee (
  p_overdue_amt NUMBER, p_days_late NUMBER
) RETURN NUMBER
IS
  c_daily_pct CONSTANT NUMBER := 0.05;
  c_cap_pct   CONSTANT NUMBER := 10;   -- fee never exceeds 10% of the overdue amount
BEGIN
  IF p_overdue_amt IS NULL OR p_overdue_amt <= 0 OR NVL(p_days_late, 0) <= 0 THEN
    RETURN 0;
  END IF;
  RETURN LEAST(ROUND(p_overdue_amt * c_daily_pct / 100 * p_days_late, 2),
               ROUND(p_overdue_amt * c_cap_pct / 100, 2));
END fn_calc_late_fee;
/
