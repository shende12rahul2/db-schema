-- ONE-TIME PREREQUISITE, run by a DBA (not by the migration runner).
-- Creates an isolated schema owner for ONE developer or ONE client/environment, with only the privileges migrations need.
--
--   sqlplus system@//<host>:<port>/<service> @scripts/admin/create_schema_user.sql <USER> <PASSWORD> [TABLESPACE]
--
-- Example (each developer gets their own user, so their migration history is separate automatically):
--   sqlplus system@//dbserver:1521/DEVPDB @scripts/admin/create_schema_user.sql DEV_ALICE "Alice#Pass1" USERS
--
-- What the account CAN do: create/alter/drop objects INSIDE ITS OWN SCHEMA, read/write its own history table.
-- What it CANNOT do: touch other schemas, create users, drop databases, use DBA features. Review before using in production.
SET DEFINE ON VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE
DEFINE v_user = &1
DEFINE v_pass = &2
COLUMN v_ts NEW_VALUE v_tablespace NOPRINT
SELECT NVL('&3', 'USERS') AS v_ts FROM dual;

CREATE USER &v_user IDENTIFIED BY "&v_pass" DEFAULT TABLESPACE &v_tablespace QUOTA UNLIMITED ON &v_tablespace;

GRANT CREATE SESSION   TO &v_user;
GRANT CREATE TABLE     TO &v_user;
GRANT CREATE SEQUENCE  TO &v_user;
GRANT CREATE VIEW      TO &v_user;
GRANT CREATE PROCEDURE TO &v_user;   -- functions, procedures, packages
GRANT CREATE TRIGGER   TO &v_user;
GRANT CREATE TYPE      TO &v_user;
-- Add CREATE SYNONYM / CREATE JOB / CREATE MATERIALIZED VIEW only if your migrations create them.

PROMPT User &v_user created. Put it in .env as DB_USER / DB_PASSWORD, then run: migrate.sh config
EXIT
