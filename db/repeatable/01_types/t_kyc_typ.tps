CREATE OR REPLACE TYPE t_kyc_typ AS OBJECT (
  customer_id NUMBER,
  status VARCHAR2(15),
  verified_on DATE
);
/
