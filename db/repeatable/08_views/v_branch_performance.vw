CREATE OR REPLACE VIEW v_branch_performance AS
SELECT b.branch_id, b.branch_name, COUNT(a.account_id) AS account_count, NVL(SUM(a.balance), 0) AS total_balance
  FROM branches b
  LEFT JOIN accounts a ON a.branch_id = b.branch_id
 GROUP BY b.branch_id, b.branch_name;
