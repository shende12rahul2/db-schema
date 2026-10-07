CREATE OR REPLACE PROCEDURE prc_process_payment (
  p_account_id NUMBER,
  p_amount NUMBER,
  p_mode VARCHAR2
)
IS
BEGIN
  INSERT INTO payments (account_id, amount, payment_mode, status)
  VALUES (p_account_id, p_amount, p_mode, 'SUCCESS');
  UPDATE accounts SET balance = balance - p_amount WHERE account_id = p_account_id;
END prc_process_payment;
/
