-- Only the constraint is reverted; the data fix in V003 is not reversible.
ALTER TABLE loan_applications DROP CONSTRAINT ck_loan_app_status;
