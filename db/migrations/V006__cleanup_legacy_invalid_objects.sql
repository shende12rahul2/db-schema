-- Databases deployed with the legacy flat files (legacy/, main's scripts/deploy.sh) contain empty TYPE BODY objects
-- for types that have no methods. Oracle cannot compile an empty type body, so they are INVALID and would make
-- 'validate' fail forever. Drop them - only if they are invalid AND the type really has no methods.
-- On a database built by this tool they never existed, so this migration changes nothing there.
BEGIN
  FOR r IN (SELECT b.object_name
              FROM user_objects b
             WHERE b.object_type = 'TYPE BODY'
               AND b.status = 'INVALID'
               AND b.object_name IN ('T_APPLICANT_TYP', 'T_AUDIT_TYP', 'T_CONTACT_TYP', 'T_DOC_META_TYP',
                                     'T_KYC_TYP', 'T_PAYMENT_TYP', 'T_RATE_TYP', 'T_SCORE_TYP')
               AND NOT EXISTS (SELECT 1 FROM user_type_methods m WHERE m.type_name = b.object_name)) LOOP
    EXECUTE IMMEDIATE 'DROP TYPE BODY ' || r.object_name;
    DBMS_OUTPUT.PUT_LINE('dropped invalid empty type body ' || r.object_name);
  END LOOP;
END;
/
