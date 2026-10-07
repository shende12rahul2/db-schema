ALTER TABLE accounts DROP CONSTRAINT ck_accounts_status;
ALTER TABLE credit_scores DROP CONSTRAINT ck_credit_scores_range;
ALTER TABLE documents DROP CONSTRAINT uk_documents_customer_type;
-- Put the archived duplicates back; the score clamp is not reversible.
INSERT INTO documents SELECT * FROM documents_dupes_v010;
COMMIT;
DROP TABLE documents_dupes_v010 PURGE;
