CREATE OR REPLACE PACKAGE BODY pkg_account_service AS

  PROCEDURE open_account(p_customer_id NUMBER, p_branch_id NUMBER, p_type VARCHAR2, p_account_id OUT NUMBER) IS
  BEGIN
    INSERT INTO accounts (customer_id, branch_id, account_type)
    VALUES (p_customer_id, p_branch_id, p_type)
    RETURNING account_id INTO p_account_id;
  END open_account;

  PROCEDURE close_account(p_account_id NUMBER) IS
  BEGIN
    prc_close_account(p_account_id);
  END close_account;

  PROCEDURE freeze_account(p_account_id NUMBER) IS
  BEGIN
    UPDATE accounts SET status = 'FROZEN' WHERE account_id = p_account_id AND status = 'ACTIVE';
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20010, 'Account ' || p_account_id || ' is not ACTIVE');
    END IF;
  END freeze_account;

  PROCEDURE unfreeze_account(p_account_id NUMBER) IS
  BEGIN
    UPDATE accounts SET status = 'ACTIVE' WHERE account_id = p_account_id AND status = 'FROZEN';
    IF SQL%ROWCOUNT = 0 THEN
      RAISE_APPLICATION_ERROR(-20011, 'Account ' || p_account_id || ' is not FROZEN');
    END IF;
  END unfreeze_account;

  FUNCTION get_balance(p_account_id NUMBER) RETURN NUMBER IS
    v_bal NUMBER;

  BEGIN
    SELECT balance INTO v_bal FROM accounts WHERE account_id = p_account_id;
    RETURN v_bal;
  END get_balance;

END pkg_account_service;
/
