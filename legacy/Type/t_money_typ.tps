CREATE OR REPLACE TYPE t_money_typ AS OBJECT (
  amount NUMBER(18,
  2),
  currency VARCHAR2(3),
  MEMBER FUNCTION to_string RETURN VARCHAR2
);
/
