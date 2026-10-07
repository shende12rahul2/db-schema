CREATE OR REPLACE TRIGGER trg_documents_bi
  BEFORE INSERT ON documents
  FOR EACH ROW
BEGIN
  IF :NEW.document_id IS NULL THEN
    :NEW.document_id := seq_document_id.NEXTVAL;
  END IF;
END trg_documents_bi;
/
