-- DEMO ONLY. Statement 1 succeeds (Oracle DDL auto-commits), statement 2 fails -> partial migration.
ALTER TABLE accounts ADD (overdraft_limit NUMBER(18,2) DEFAULT 0 NOT NULL);
ALTER TABLE accounts ADD CONSTRAINT ck_accounts_overdraft CHECK (overdraft_limt >= 0);  -- typo: overdraft_limt
