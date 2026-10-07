-- Example 2 (data): backfill a column in batches so a huge table does not hold one giant transaction.
-- Remember which rows we touch, so undo can revert exactly those.
CREATE TABLE credit_scores_bak_v014 AS
SELECT credit_score_id FROM credit_scores WHERE risk_band IS NULL;

DECLARE
  v_rows PLS_INTEGER;
BEGIN
  LOOP
    UPDATE credit_scores
       SET risk_band = CASE WHEN score >= 750 THEN 'LOW' WHEN score >= 600 THEN 'MEDIUM' ELSE 'HIGH' END
     WHERE risk_band IS NULL AND ROWNUM <= 10000;
    v_rows := SQL%ROWCOUNT;
    COMMIT;
    EXIT WHEN v_rows = 0;
  END LOOP;
END;
/
