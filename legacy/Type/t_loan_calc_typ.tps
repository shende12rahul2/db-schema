CREATE OR REPLACE TYPE t_loan_calc_typ AS OBJECT (
  principal NUMBER,
  annual_rate NUMBER,
  tenure_months NUMBER,
  emi NUMBER,
  MEMBER FUNCTION total_payable RETURN NUMBER
);
/
