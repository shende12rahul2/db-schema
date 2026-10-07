CREATE OR REPLACE FUNCTION fn_get_customer_balance (
  p_customer_id NUMBER
) RETURN NUMBER
IS
  v_total NUMBER;
BEGIN
  SELECT NVL(SUM(balance), 0) INTO v_total
    FROM accounts
   WHERE customer_id = p_customer_id AND status = 'ACTIVE';
  RETURN v_total;
END fn_get_customer_balance;
/
