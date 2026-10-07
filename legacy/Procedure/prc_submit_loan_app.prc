CREATE OR REPLACE PROCEDURE prc_submit_loan_app (
  p_customer_id NUMBER,
  p_loan_type VARCHAR2,
  p_amount NUMBER,
  p_tenure NUMBER,
  p_loan_app_id OUT NUMBER
)
IS
BEGIN
  INSERT INTO loan_applications (customer_id, loan_type, requested_amt, tenure_months)
  VALUES (p_customer_id, p_loan_type, p_amount, p_tenure)
  RETURNING loan_app_id INTO p_loan_app_id;
END prc_submit_loan_app;
/
