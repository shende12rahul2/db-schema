CREATE OR REPLACE VIEW v_active_loans AS
SELECT l.loan_app_id, l.customer_id, l.loan_type, l.requested_amt, l.interest_rate, l.tenure_months
  FROM loan_applications l
 WHERE l.status IN ('APPROVED', 'DISBURSED');
