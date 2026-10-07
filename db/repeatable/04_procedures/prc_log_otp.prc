CREATE OR REPLACE PROCEDURE prc_log_otp (
  p_customer_id NUMBER,
  p_otp_hash VARCHAR2,
  p_purpose VARCHAR2,
  p_valid_minutes NUMBER DEFAULT 5
)
IS
BEGIN
  INSERT INTO otp_log (customer_id, otp_hash, purpose, expires_at)
  VALUES (p_customer_id, p_otp_hash, p_purpose, SYSTIMESTAMP + NUMTODSINTERVAL(p_valid_minutes, 'MINUTE'));
END prc_log_otp;
/
