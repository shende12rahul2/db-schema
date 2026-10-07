-- Undo of the baseline drops the whole application schema. Intentionally blocked.
BEGIN
  RAISE_APPLICATION_ERROR(-20999, 'Baseline cannot be undone. Drop and recreate the schema user instead.');
END;
/
