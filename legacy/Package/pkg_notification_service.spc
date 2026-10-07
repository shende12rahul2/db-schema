CREATE OR REPLACE PACKAGE pkg_notification_service AS
  PROCEDURE notify(p_customer_id NUMBER, p_channel VARCHAR2, p_message VARCHAR2);
END pkg_notification_service;
/
