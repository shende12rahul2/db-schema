CREATE OR REPLACE TYPE t_audit_typ AS OBJECT (
  table_name VARCHAR2(30),
  operation VARCHAR2(10),
  record_id NUMBER,
  changed_by VARCHAR2(60)
);
/
