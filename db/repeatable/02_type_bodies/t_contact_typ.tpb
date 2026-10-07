CREATE OR REPLACE TYPE BODY t_contact_typ AS
  MEMBER FUNCTION masked_mobile RETURN VARCHAR2 IS
  BEGIN
    RETURN RPAD('X', GREATEST(LENGTH(mobile) - 4, 0), 'X') || SUBSTR(mobile, -4);
  END masked_mobile;
END;
/
