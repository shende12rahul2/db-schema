CREATE OR REPLACE FUNCTION fn_validate_pan (
  p_pan VARCHAR2
) RETURN BOOLEAN
IS
BEGIN
  RETURN REGEXP_LIKE(p_pan, '^[A-Z]{5}[0-9]{4}[A-Z]$');
END fn_validate_pan;
/
