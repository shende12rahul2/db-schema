CREATE OR REPLACE VIEW v_account_statement AS
SELECT a.account_id, a.customer_id, t.transaction_id, t.txn_date, t.txn_type, t.amount, t.description,
       SUM(CASE WHEN t.txn_type = 'CREDIT' THEN t.amount ELSE -t.amount END)
         OVER (PARTITION BY a.account_id ORDER BY t.txn_date, t.transaction_id) AS running_balance
  FROM accounts a
  JOIN transactions t ON t.account_id = a.account_id;
