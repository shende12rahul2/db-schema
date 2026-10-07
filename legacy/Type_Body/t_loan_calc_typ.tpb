CREATE OR REPLACE TYPE BODY t_loan_calc_typ AS
  MEMBER FUNCTION total_payable RETURN NUMBER IS
  BEGIN
    RETURN emi * tenure_months;
  END total_payable;
END;
/
