CREATE OR REPLACE TRIGGER trg_notifications_bi
  BEFORE INSERT ON notifications
  FOR EACH ROW
BEGIN
  IF :NEW.notification_id IS NULL THEN
    :NEW.notification_id := seq_notification_id.NEXTVAL;
  END IF;
END trg_notifications_bi;
/
