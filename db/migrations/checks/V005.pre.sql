-- Pre-check for V005: the index must not exist yet.
SELECT 'index idx_txn_account_date already exists' FROM user_indexes WHERE index_name = 'IDX_TXN_ACCOUNT_DATE';
