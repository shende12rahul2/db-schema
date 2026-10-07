-- Example 1 (indexes): composite index for a frequent filter, and a function-based index for case-insensitive lookup.
CREATE INDEX idx_payments_account_status ON payments (account_id, status);
CREATE INDEX idx_customers_email_upper ON customers (UPPER(email));
