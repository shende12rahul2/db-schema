CREATE OR REPLACE PROCEDURE prc_send_notification (
  p_customer_id NUMBER,
  p_channel VARCHAR2,
  p_message VARCHAR2
)
IS
BEGIN
  INSERT INTO notifications (customer_id, channel, message)
  VALUES (p_customer_id, p_channel, p_message);
END prc_send_notification;
/
