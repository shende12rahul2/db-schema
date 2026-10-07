-- DEMO ONLY. Same change written so it can be re-run safely after a partial failure.
DECLARE
  PROCEDURE ddl(p_sql VARCHAR2, p_ignore NUMBER) IS
  BEGIN
    EXECUTE IMMEDIATE p_sql;
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE != p_ignore THEN RAISE; END IF;   -- ignore only "already exists"
  END;
BEGIN
  ddl('ALTER TABLE accounts ADD (overdraft_limit NUMBER(18,2) DEFAULT 0 NOT NULL)', -1430);  -- ORA-01430 column exists
  ddl('ALTER TABLE accounts ADD CONSTRAINT ck_accounts_overdraft CHECK (overdraft_limit >= 0)', -2264); -- ORA-02264 name used
END;
/
