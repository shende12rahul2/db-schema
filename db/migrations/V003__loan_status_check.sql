-- Restrict loan_applications.status to known values.
-- Order matters: fix existing rows FIRST, otherwise the constraint fails with ORA-02293.
UPDATE loan_applications
   SET status = 'REJECTED'
 WHERE status NOT IN ('SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'DISBURSED');
COMMIT;

ALTER TABLE loan_applications ADD CONSTRAINT ck_loan_app_status
  CHECK (status IN ('SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED', 'DISBURSED'));
