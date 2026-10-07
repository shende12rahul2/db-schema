-- Example 1 (tables): add a column with a default, plus a constraint.
-- NOT NULL + DEFAULT lets Oracle fill existing rows instantly and keeps old code working.
ALTER TABLE accounts ADD (overdraft_limit NUMBER(18,2) DEFAULT 0 NOT NULL);
ALTER TABLE accounts ADD CONSTRAINT ck_accounts_overdraft CHECK (overdraft_limit >= 0);
