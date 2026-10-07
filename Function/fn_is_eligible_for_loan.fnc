CREATE OR REPLACE FUNCTION fn_is_eligible_for_loan (
  p_customer_id NUMBER, p_amount NUMBER
) RETURN BOOLEAN
IS
BEGIN
  RETURN fn_get_kyc_status(p_customer_id) = 'VERIFIED'
     AND fn_calc_risk_score(p_customer_id) >= 650;
END fn_is_eligible_for_loan;
/
