-- Pre-check for V003: it would set every loan status outside the allowed list to REJECTED.
-- Listing them lets you decide (fix the data, or change the migration) BEFORE anything is modified.
SELECT 'loan_applications: ' || COUNT(*) || ' row(s) with status ''' || status
       || ''' would be set to REJECTED by V003 and then locked by a check constraint'
  FROM loan_applications
 WHERE status NOT IN ('SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'DISBURSED')
 GROUP BY status
UNION ALL
SELECT 'constraint ck_loan_app_status already exists: V003 was probably applied by hand'
  FROM user_constraints WHERE constraint_name = 'CK_LOAN_APP_STATUS';
