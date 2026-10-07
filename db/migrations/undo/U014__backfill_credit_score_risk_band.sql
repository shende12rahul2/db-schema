UPDATE credit_scores SET risk_band = NULL
 WHERE credit_score_id IN (SELECT credit_score_id FROM credit_scores_bak_v014);
COMMIT;
DROP TABLE credit_scores_bak_v014 PURGE;
