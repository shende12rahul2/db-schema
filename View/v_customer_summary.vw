CREATE OR REPLACE VIEW v_customer_summary AS
SELECT c.customer_id, c.first_name, c.last_name, c.kyc_status,
       COUNT(a.account_id) AS account_count, NVL(SUM(a.balance), 0) AS total_balance
  FROM customers c
  LEFT JOIN accounts a ON a.customer_id = c.customer_id
 GROUP BY c.customer_id, c.first_name, c.last_name, c.kyc_status;
