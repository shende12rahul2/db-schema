CREATE OR REPLACE PACKAGE BODY pkg_login_otp AS

  PROCEDURE generate_otp(p_customer_id NUMBER, p_purpose VARCHAR2) IS
  BEGIN
    -- TODO: generate a random OTP, send it, and store only its hash
    prc_log_otp(p_customer_id, 'TODO_HASH', p_purpose);
  END generate_otp;

  FUNCTION verify_otp(p_customer_id NUMBER, p_otp VARCHAR2) RETURN BOOLEAN IS
  BEGIN
    -- TODO: compare hash of p_otp with the latest unexpired otp_log row
    RETURN FALSE;
  END verify_otp;

END pkg_login_otp;
/
