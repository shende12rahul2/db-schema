CREATE OR REPLACE TYPE t_address_typ AS OBJECT (
  street VARCHAR2(200),
  city VARCHAR2(60),
  state VARCHAR2(60),
  pincode VARCHAR2(10),
  MEMBER FUNCTION full_address RETURN VARCHAR2
);
/
