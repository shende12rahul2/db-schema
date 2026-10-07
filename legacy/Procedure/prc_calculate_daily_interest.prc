CREATE OR REPLACE PROCEDURE prc_calculate_daily_interest (
  p_rate NUMBER DEFAULT 3.5
)
IS
BEGIN
  UPDATE accounts
     SET balance = balance + fn_calc_interest(balance, p_rate, 1)
   WHERE status = 'ACTIVE' AND account_type = 'SAVINGS';
END prc_calculate_daily_interest;
/
