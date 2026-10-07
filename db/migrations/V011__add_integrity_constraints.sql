-- Example 2 (constraints): clean the data first, archive what you remove, then add the constraints.

-- 1. Archive and remove duplicate documents (keep the newest per customer + doc_type).
CREATE TABLE documents_dupes_v011 AS
SELECT d.* FROM documents d
 WHERE EXISTS (SELECT 1 FROM documents n
                WHERE n.customer_id = d.customer_id AND n.doc_type = d.doc_type
                  AND (n.uploaded_at > d.uploaded_at
                       OR (n.uploaded_at = d.uploaded_at AND n.document_id > d.document_id)));
DELETE FROM documents WHERE document_id IN (SELECT document_id FROM documents_dupes_v011);

-- 2. Pull out-of-range credit scores into range.
UPDATE credit_scores SET score = LEAST(GREATEST(score, 300), 900) WHERE score NOT BETWEEN 300 AND 900;
COMMIT;

-- 3. Constraints.
ALTER TABLE documents ADD CONSTRAINT uk_documents_customer_type UNIQUE (customer_id, doc_type);
ALTER TABLE credit_scores ADD CONSTRAINT ck_credit_scores_range CHECK (score BETWEEN 300 AND 900);
-- NOVALIDATE: new/changed rows are enforced, existing rows are not scanned (useful on very large tables).
ALTER TABLE accounts ADD CONSTRAINT ck_accounts_status CHECK (status IN ('ACTIVE', 'CLOSED', 'FROZEN')) ENABLE NOVALIDATE;
