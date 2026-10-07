CREATE OR REPLACE VIEW v_high_risk_customers AS
SELECT cs.customer_id, cs.score, cs.risk_band, cs.scored_at
  FROM credit_scores cs
 WHERE cs.score < 500;
