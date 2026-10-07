CREATE OR REPLACE PACKAGE BODY pkg_loan_processing AS

  PROCEDURE submit(p_customer_id NUMBER, p_loan_type VARCHAR2, p_amount NUMBER, p_tenure NUMBER, p_loan_app_id OUT NUMBER) IS
  BEGIN
    prc_submit_loan_app(p_customer_id, p_loan_type, p_amount, p_tenure, p_loan_app_id);
  END submit;

  PROCEDURE approve(p_loan_app_id NUMBER, p_rate NUMBER) IS
  BEGIN
    prc_approve_loan(p_loan_app_id, p_rate);
  END approve;

  PROCEDURE reject(p_loan_app_id NUMBER) IS
  BEGIN
    UPDATE loan_applications SET status = 'REJECTED' WHERE loan_app_id = p_loan_app_id;
  END reject;

END pkg_loan_processing;
/
