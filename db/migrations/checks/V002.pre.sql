-- Pre-check for V002: returns one message per problem. No rows = fine.
SELECT 'customers.email_verified already exists: V002 was probably applied by hand. Adopt at a higher baseline or remove the column first.'
  FROM user_tab_columns
 WHERE table_name = 'CUSTOMERS' AND column_name = 'EMAIL_VERIFIED';
