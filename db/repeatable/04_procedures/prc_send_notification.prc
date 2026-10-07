CREATE OR REPLACE PROCEDURE prc_send_notification (
  p_customer_id NUMBER,
  p_channel VARCHAR2,
  p_message VARCHAR2,
  p_priority VARCHAR2 DEFAULT 'NORMAL'   -- new parameter LAST and with a default: existing callers keep working
)
IS
BEGIN
  INSERT INTO notifications (customer_id, channel, message, priority)
  VALUES (p_customer_id, p_channel, p_message, p_priority);
END prc_send_notification;
/
