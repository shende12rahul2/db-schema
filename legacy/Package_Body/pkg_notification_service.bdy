CREATE OR REPLACE PACKAGE BODY pkg_notification_service AS

  PROCEDURE notify(p_customer_id NUMBER, p_channel VARCHAR2, p_message VARCHAR2) IS
  BEGIN
    prc_send_notification(p_customer_id, p_channel, p_message);
  END notify;

END pkg_notification_service;
/
