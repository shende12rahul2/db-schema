CREATE OR REPLACE PROCEDURE prc_close_account (
  p_account_id NUMBER
)
IS
BEGIN
  UPDATE accounts
     SET status = 'CLOSED', closed_at = SYSTIMESTAMP
   WHERE account_id = p_account_id;
END prc_close_account;
/
