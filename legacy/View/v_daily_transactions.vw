CREATE OR REPLACE VIEW v_daily_transactions AS
SELECT TRUNC(txn_date) AS txn_day, txn_type, COUNT(*) AS txn_count, SUM(amount) AS total_amount
  FROM transactions
 GROUP BY TRUNC(txn_date), txn_type;
