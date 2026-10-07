CREATE OR REPLACE PACKAGE pkg_loan_processing AS
  PROCEDURE submit(p_customer_id NUMBER, p_loan_type VARCHAR2, p_amount NUMBER, p_tenure NUMBER, p_loan_app_id OUT NUMBER);
  PROCEDURE approve(p_loan_app_id NUMBER, p_rate NUMBER);
  PROCEDURE reject(p_loan_app_id NUMBER);
END pkg_loan_processing;
/
