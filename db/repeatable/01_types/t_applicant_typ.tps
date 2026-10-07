CREATE OR REPLACE TYPE t_applicant_typ AS OBJECT (
  customer_id NUMBER,
  full_name VARCHAR2(130),
  date_of_birth DATE,
  pan_number VARCHAR2(10)
);
/
