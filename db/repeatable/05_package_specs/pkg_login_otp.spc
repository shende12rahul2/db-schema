CREATE OR REPLACE PACKAGE pkg_login_otp AS
  PROCEDURE generate_otp(p_customer_id NUMBER, p_purpose VARCHAR2);
  FUNCTION verify_otp(p_customer_id NUMBER, p_otp VARCHAR2) RETURN BOOLEAN;
END pkg_login_otp;
/
