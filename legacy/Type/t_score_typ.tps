CREATE OR REPLACE TYPE t_score_typ AS OBJECT (
  customer_id NUMBER,
  score NUMBER(3),
  risk_band VARCHAR2(10)
);
/
