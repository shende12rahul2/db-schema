-- New table with sequence and backfill. The insert trigger lives in Trigger/trg_customer_prefs_bi.trg
-- and is applied by the repeatable code step that runs after the versioned migrations.
CREATE SEQUENCE seq_customer_pref_id START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;

CREATE TABLE customer_preferences (
  pref_id          NUMBER(10)   NOT NULL,
  customer_id      NUMBER(10)   NOT NULL,
  channel          VARCHAR2(10) DEFAULT 'SMS' NOT NULL,
  marketing_opt_in CHAR(1)      DEFAULT 'N'   NOT NULL,
  updated_at       TIMESTAMP    DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_customer_preferences PRIMARY KEY (pref_id),
  CONSTRAINT uk_customer_pref_customer UNIQUE (customer_id),
  CONSTRAINT fk_customer_pref_customer FOREIGN KEY (customer_id) REFERENCES customers (customer_id),
  CONSTRAINT ck_customer_pref_optin CHECK (marketing_opt_in IN ('Y', 'N'))
);

INSERT INTO customer_preferences (pref_id, customer_id)
SELECT seq_customer_pref_id.NEXTVAL, customer_id FROM customers;
COMMIT;
