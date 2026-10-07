CREATE OR REPLACE FUNCTION fn_format_currency (
  p_amount NUMBER, p_currency VARCHAR2 DEFAULT 'INR'
) RETURN VARCHAR2
IS
BEGIN
  RETURN p_currency || ' ' || TO_CHAR(p_amount, 'FM999,999,999,990.00');
END fn_format_currency;
/
