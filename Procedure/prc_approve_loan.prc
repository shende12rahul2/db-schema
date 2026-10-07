CREATE OR REPLACE PROCEDURE prc_approve_loan (
  p_loan_app_id NUMBER,
  p_rate NUMBER
)
IS
BEGIN
  UPDATE loan_applications
     SET status = 'APPROVED', interest_rate = p_rate
   WHERE loan_app_id = p_loan_app_id;
END prc_approve_loan;
/
