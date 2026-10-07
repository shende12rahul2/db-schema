CREATE OR REPLACE PROCEDURE prc_transfer_funds (
  p_from_account NUMBER,
  p_to_account NUMBER,
  p_amount NUMBER
)
IS
BEGIN
  UPDATE accounts SET balance = balance - p_amount WHERE account_id = p_from_account;
  UPDATE accounts SET balance = balance + p_amount WHERE account_id = p_to_account;
  INSERT INTO transactions (account_id, txn_type, amount) VALUES (p_from_account, 'DEBIT', p_amount);
  INSERT INTO transactions (account_id, txn_type, amount) VALUES (p_to_account, 'CREDIT', p_amount);
END prc_transfer_funds;
/
