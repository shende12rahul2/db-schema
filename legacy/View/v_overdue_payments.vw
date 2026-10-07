CREATE OR REPLACE VIEW v_overdue_payments AS
SELECT p.payment_id, p.account_id, p.amount, p.payment_date
  FROM payments p
 WHERE p.status = 'PENDING'
   AND p.payment_date < SYSTIMESTAMP - INTERVAL '30' DAY;
