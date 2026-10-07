SET SERVEROUTPUT ON
SET LINESIZE 120
SET PAGESIZE 100

PROMPT === Object counts (expected: SEQUENCE 12, TABLE 12, TYPE 11, FUNCTION 11, PROCEDURE 11, PACKAGE 10, PACKAGE BODY 10, TRIGGER 10, VIEW 11) ===
SELECT object_type, COUNT(*) AS total FROM user_objects
 WHERE object_type IN ('SEQUENCE','TABLE','TYPE','TYPE BODY','FUNCTION','PROCEDURE','PACKAGE','PACKAGE BODY','TRIGGER','VIEW')
 GROUP BY object_type ORDER BY object_type;

PROMPT === Invalid objects (expected: no rows selected) ===
SELECT object_type, object_name FROM user_objects WHERE status = 'INVALID';

PROMPT === Compile errors (expected: no rows selected) ===
SELECT name, type, line, text FROM user_errors ORDER BY name, sequence;

PROMPT === Function smoke tests ===
SELECT fn_calc_emi(500000, 9.5, 60) AS emi, fn_mask_mobile('9876543210') AS masked, fn_format_currency(1234567.5) AS money FROM dual;

PROMPT === Insert test (rolled back) ===
INSERT INTO branches (branch_id, branch_code, branch_name) VALUES (seq_branch_id.NEXTVAL, 'B001', 'Main');
INSERT INTO customers (first_name, last_name, pan_number, mobile) VALUES ('Asha', 'Rao', 'ABCDE1234F', '9876543210');
SELECT customer_id, first_name, kyc_status FROM customers;
ROLLBACK;
