-- Example 3 (data): fix dirty data with a backup table so the change can be reverted.
-- Digits-only mobile, upper-case trimmed PAN. May fail with ORA-00001 if two PANs differ only by case: resolve those rows, then repair + re-run.
CREATE TABLE customers_bak_v014 AS
SELECT customer_id, mobile, pan_number
  FROM customers
 WHERE mobile <> REGEXP_REPLACE(mobile, '[^0-9]', '')
    OR pan_number <> UPPER(TRIM(pan_number));

UPDATE customers
   SET mobile = REGEXP_REPLACE(mobile, '[^0-9]', ''),
       pan_number = UPPER(TRIM(pan_number))
 WHERE customer_id IN (SELECT customer_id FROM customers_bak_v014);
COMMIT;
