CREATE OR REPLACE FUNCTION fn_mask_mobile (
  p_mobile VARCHAR2
) RETURN VARCHAR2
IS
BEGIN
  RETURN RPAD('X', GREATEST(LENGTH(p_mobile) - 4, 0), 'X') || SUBSTR(p_mobile, -4);
END fn_mask_mobile;
/
