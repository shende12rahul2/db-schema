CREATE OR REPLACE TYPE t_contact_typ AS OBJECT (
  mobile VARCHAR2(15),
  email VARCHAR2(120),
  alt_mobile VARCHAR2(15),
  MEMBER FUNCTION masked_mobile RETURN VARCHAR2
);
/
