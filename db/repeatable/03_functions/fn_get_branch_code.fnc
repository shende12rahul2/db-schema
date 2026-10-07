CREATE OR REPLACE FUNCTION fn_get_branch_code (
  p_branch_id NUMBER
) RETURN VARCHAR2
IS
  v_code branches.branch_code%TYPE;
BEGIN
  SELECT branch_code INTO v_code FROM branches WHERE branch_id = p_branch_id;
  RETURN v_code;
EXCEPTION
  WHEN NO_DATA_FOUND THEN RETURN NULL;
END fn_get_branch_code;
/
