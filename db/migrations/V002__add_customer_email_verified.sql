-- Add an e-mail verification flag to customers.
ALTER TABLE customers ADD (email_verified CHAR(1) DEFAULT 'N' NOT NULL);
ALTER TABLE customers ADD CONSTRAINT ck_customers_email_verified CHECK (email_verified IN ('Y', 'N'));
COMMENT ON COLUMN customers.email_verified IS 'Y once the customer confirmed the e-mail address';
