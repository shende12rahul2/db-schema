CREATE OR REPLACE TYPE t_rate_typ AS OBJECT (
  rate_code VARCHAR2(10),
  annual_rate NUMBER(5,
  2),
  effective_from DATE
);
/
