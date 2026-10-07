CREATE OR REPLACE TYPE BODY t_address_typ AS
  MEMBER FUNCTION full_address RETURN VARCHAR2 IS
  BEGIN
    RETURN street || ', ' || city || ', ' || state || ' - ' || pincode;
  END full_address;
END;
/
