CREATE OR REPLACE TYPE BODY t_money_typ AS
  MEMBER FUNCTION to_string RETURN VARCHAR2 IS
  BEGIN
    RETURN currency || ' ' || TO_CHAR(amount, 'FM999,999,999,990.00');
  END to_string;
END;
/
