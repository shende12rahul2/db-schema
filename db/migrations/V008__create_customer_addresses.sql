-- Example 3 (tables): new child table with sequence, FK and index.
-- The insert trigger is a repeatable file: db/repeatable/07_triggers/trg_customer_addresses_bi.trg
CREATE SEQUENCE seq_address_id START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;

CREATE TABLE customer_addresses (
  address_id    NUMBER(10)    NOT NULL,
  customer_id   NUMBER(10)    NOT NULL,
  address_type  VARCHAR2(10)  DEFAULT 'HOME' NOT NULL,
  line1         VARCHAR2(200) NOT NULL,
  city          VARCHAR2(60)  NOT NULL,
  state         VARCHAR2(60),
  pincode       VARCHAR2(10),
  created_at    TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT pk_customer_addresses PRIMARY KEY (address_id),
  CONSTRAINT fk_cust_addr_customer FOREIGN KEY (customer_id) REFERENCES customers (customer_id),
  CONSTRAINT ck_cust_addr_type CHECK (address_type IN ('HOME', 'OFFICE', 'MAILING'))
);

-- Oracle does not index foreign keys automatically; index it to avoid table locks and slow joins.
CREATE INDEX idx_cust_addr_customer ON customer_addresses (customer_id);
