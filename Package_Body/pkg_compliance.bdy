CREATE OR REPLACE PACKAGE BODY pkg_compliance AS

  FUNCTION is_kyc_complete(p_customer_id NUMBER) RETURN BOOLEAN IS
  BEGIN
    RETURN fn_get_kyc_status(p_customer_id) = 'VERIFIED';
  END is_kyc_complete;

  PROCEDURE flag_suspicious(p_account_id NUMBER, p_reason VARCHAR2) IS
  BEGIN
    pkg_audit_service.log_event('ACCOUNTS', 'SUSPICIOUS', p_account_id, p_reason);
  END flag_suspicious;

END pkg_compliance;
/
