-- Example 1 (data): reference table seeded with MERGE so the script is safe to re-run.
CREATE TABLE ref_loan_types (
  loan_type          VARCHAR2(20)  NOT NULL,
  description        VARCHAR2(100) NOT NULL,
  max_tenure_months  NUMBER(3)     NOT NULL,
  active             CHAR(1)       DEFAULT 'Y' NOT NULL,
  CONSTRAINT pk_ref_loan_types PRIMARY KEY (loan_type),
  CONSTRAINT ck_ref_loan_types_active CHECK (active IN ('Y', 'N'))
);

MERGE INTO ref_loan_types t
USING (SELECT 'HOME' AS loan_type, 'Home loan' AS description, 360 AS max_tenure_months FROM dual UNION ALL
       SELECT 'AUTO', 'Auto loan', 84 FROM dual UNION ALL
       SELECT 'PERSONAL', 'Personal loan', 60 FROM dual UNION ALL
       SELECT 'EDUCATION', 'Education loan', 180 FROM dual) s
   ON (t.loan_type = s.loan_type)
 WHEN MATCHED THEN UPDATE SET t.description = s.description, t.max_tenure_months = s.max_tenure_months
 WHEN NOT MATCHED THEN INSERT (loan_type, description, max_tenure_months)
                       VALUES (s.loan_type, s.description, s.max_tenure_months);
COMMIT;
