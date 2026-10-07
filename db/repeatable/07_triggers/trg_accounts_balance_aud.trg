CREATE OR REPLACE TRIGGER trg_accounts_balance_aud
  AFTER UPDATE OF balance ON accounts
  FOR EACH ROW
  WHEN (OLD.balance <> NEW.balance)
BEGIN
  INSERT INTO audit_logs (table_name, operation, record_id, details)
  VALUES ('ACCOUNTS', 'BALANCE', :OLD.account_id, 'balance ' || :OLD.balance || ' -> ' || :NEW.balance);
END trg_accounts_balance_aud;
/
