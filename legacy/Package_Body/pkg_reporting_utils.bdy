CREATE OR REPLACE PACKAGE BODY pkg_reporting_utils AS

  FUNCTION daily_txn_count(p_date DATE) RETURN NUMBER IS
    v_n NUMBER;

  BEGIN
    SELECT COUNT(*) INTO v_n FROM transactions WHERE TRUNC(txn_date) = TRUNC(p_date);
    RETURN v_n;
  END daily_txn_count;

  FUNCTION daily_txn_amount(p_date DATE) RETURN NUMBER IS
    v_n NUMBER;

  BEGIN
    SELECT NVL(SUM(amount), 0) INTO v_n FROM transactions WHERE TRUNC(txn_date) = TRUNC(p_date);
    RETURN v_n;
  END daily_txn_amount;

END pkg_reporting_utils;
/
