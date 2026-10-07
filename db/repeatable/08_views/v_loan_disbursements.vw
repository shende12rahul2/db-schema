CREATE OR REPLACE VIEW v_loan_disbursements AS
SELECT l.loan_app_id, l.customer_id, l.loan_type, l.requested_amt AS disbursed_amt, l.applied_at
  FROM loan_applications l
 WHERE l.status = 'DISBURSED';
