-- Pre-check for V004: the objects it creates must not exist yet.
SELECT 'table customer_preferences already exists' FROM user_tables WHERE table_name = 'CUSTOMER_PREFERENCES'
UNION ALL
SELECT 'sequence seq_customer_pref_id already exists' FROM user_sequences WHERE sequence_name = 'SEQ_CUSTOMER_PREF_ID';
