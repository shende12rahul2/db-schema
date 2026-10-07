CREATE OR REPLACE TYPE t_payment_typ AS OBJECT (
  payment_id NUMBER,
  amount NUMBER(18,
  2),
  payment_mode VARCHAR2(15),
  status VARCHAR2(10)
);
/
