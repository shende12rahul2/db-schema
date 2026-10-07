CREATE OR REPLACE VIEW v_customer_contact_info AS
SELECT customer_id, first_name || ' ' || last_name AS full_name, fn_mask_mobile(mobile) AS mobile, email
  FROM customers;
