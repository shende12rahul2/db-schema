UPDATE customers c
   SET (mobile, pan_number) = (SELECT b.mobile, b.pan_number FROM customers_bak_v014 b WHERE b.customer_id = c.customer_id)
 WHERE c.customer_id IN (SELECT customer_id FROM customers_bak_v014);
COMMIT;
DROP TABLE customers_bak_v014 PURGE;
