CREATE OR REPLACE VIEW v_pending_kyc AS
SELECT customer_id, first_name, last_name, mobile, created_at
  FROM customers
 WHERE kyc_status = 'PENDING';
