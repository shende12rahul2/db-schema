CREATE OR REPLACE PACKAGE pkg_reporting_utils AS
  FUNCTION daily_txn_count(p_date DATE) RETURN NUMBER;
  FUNCTION daily_txn_amount(p_date DATE) RETURN NUMBER;
END pkg_reporting_utils;
/
