-- Example 3 (views): retiring a view. The repeatable file was deleted in the same PR; deleting a file never drops the object.
-- Guarded drop: on a fresh database the view was never created, and ORA-00942 must not fail the install.
BEGIN
  EXECUTE IMMEDIATE 'DROP VIEW v_pending_kyc';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -942 THEN RAISE; END IF;
END;
/
