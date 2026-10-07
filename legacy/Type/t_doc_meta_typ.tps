CREATE OR REPLACE TYPE t_doc_meta_typ AS OBJECT (
  doc_type VARCHAR2(30),
  file_name VARCHAR2(255),
  uploaded_at TIMESTAMP
);
/
