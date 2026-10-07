-- Creates the schema_version history table once (idempotent).
DECLARE
  n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM user_tables WHERE table_name = 'SCHEMA_VERSION';
  IF n = 0 THEN
    EXECUTE IMMEDIATE '
      CREATE TABLE schema_version (
        installed_rank NUMBER GENERATED ALWAYS AS IDENTITY,
        type           VARCHAR2(10)  NOT NULL,
        version        VARCHAR2(20),
        description    VARCHAR2(200) NOT NULL,
        script         VARCHAR2(300) NOT NULL,
        checksum       VARCHAR2(64),
        installed_by   VARCHAR2(60)  DEFAULT USER NOT NULL,
        installed_on   TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
        execution_ms   NUMBER,
        status         VARCHAR2(10)  NOT NULL,
        CONSTRAINT pk_schema_version PRIMARY KEY (installed_rank),
        CONSTRAINT uk_schema_version_version UNIQUE (version),
        CONSTRAINT ck_schema_version_type CHECK (type IN (''BASELINE'', ''VERSIONED'', ''REPEATABLE'')),
        CONSTRAINT ck_schema_version_status CHECK (status IN (''SUCCESS'', ''FAILED'', ''UNDONE''))
      )';
  END IF;
END;
/
