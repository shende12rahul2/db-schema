-- Example 3 (sequences): a bigger cache for a hot sequence, and re-syncing a sequence after a bulk load.
-- Caching can leave gaps after a restart; never rely on gap-free IDs.
ALTER SEQUENCE seq_transaction_id CACHE 100;

-- ALTER SEQUENCE ... RESTART needs Oracle 18c or later (Oracle Free is 23ai).
DECLARE
  v_next NUMBER;
BEGIN
  SELECT NVL(MAX(payment_id), 0) + 1 INTO v_next FROM payments;
  EXECUTE IMMEDIATE 'ALTER SEQUENCE seq_payment_id RESTART START WITH ' || v_next;
END;
/
