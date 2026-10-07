CREATE OR REPLACE VIEW v_account_balances AS
SELECT a.account_id, a.customer_id, a.account_type, a.balance, a.status
  FROM accounts a;
