-- Speed up statement queries (account + date range).
CREATE INDEX idx_txn_account_date ON transactions (account_id, txn_date);
