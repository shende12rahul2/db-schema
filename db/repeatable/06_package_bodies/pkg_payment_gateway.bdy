CREATE OR REPLACE PACKAGE BODY pkg_payment_gateway AS

  PROCEDURE pay(p_account_id NUMBER, p_amount NUMBER, p_mode VARCHAR2) IS
  BEGIN
    prc_process_payment(p_account_id, p_amount, p_mode);
  END pay;

  PROCEDURE transfer(p_from_account NUMBER, p_to_account NUMBER, p_amount NUMBER) IS
  BEGIN
    prc_transfer_funds(p_from_account, p_to_account, p_amount);
  END transfer;

END pkg_payment_gateway;
/
