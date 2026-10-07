# Local setup (Oracle)

The files are Oracle PL/SQL, so they need an Oracle database (PostgreSQL/MySQL will reject them).

## 1. Start a local Oracle DB (Docker)

```bash
docker run -d --name oracle-free -p 1521:1521 \
  -e ORACLE_PASSWORD=Oracle123 \
  -e APP_USER=bank -e APP_USER_PASSWORD=Bank123 \
  gvenzl/oracle-free:slim
docker logs -f oracle-free   # wait for "DATABASE IS READY TO USE!"
```

This creates a `bank` user (the schema owner) in the `FREEPDB1` pluggable database.
Connect string: `bank/Bank123@localhost:1521/FREEPDB1` (use SQLcl, SQL*Plus, or VS Code / SQL Developer).

## 2. Apply the files one by one

Run from the repo root so `@` paths resolve. In SQLcl or SQL*Plus:

```bash
sql bank/Bank123@localhost:1521/FREEPDB1      # or: sqlplus bank/Bank123@//localhost:1521/FREEPDB1
```

```sql
-- 1. Sequences
@Sequence/seq_account_id.seq
-- ...repeat for every file in the folder...

-- 2. Tables (parents first: branches, customers, accounts, then the rest)
@Table/branches.tab
@Table/customers.tab
@Table/accounts.tab
@Table/transactions.tab
@Table/payments.tab
@Table/loan_applications.tab
@Table/collaterals.tab
@Table/credit_scores.tab
@Table/documents.tab
@Table/notifications.tab
@Table/otp_log.tab
@Table/audit_logs.tab
```

Then continue in this folder order, applying each file with `@Folder/file`:

| Step | Folder | Notes |
|---|---|---|
| 1 | `Sequence` | any order |
| 2 | `Table` | order shown above (foreign keys) |
| 3 | `Type`, then `Type_Body` | |
| 4 | `Function` | alphabetical order works (`fn_is_eligible_for_loan` last) |
| 5 | `Procedure` | needs tables + `fn_validate_pan`, `fn_calc_interest` |
| 6 | `Package` (all specs) | specs before bodies |
| 7 | `Package_Body` | `pkg_compliance` needs the `pkg_audit_service` spec |
| 8 | `Trigger` | |
| 9 | `View` | `v_customer_contact_info` needs `fn_mask_mobile` |

After each step, check for compile errors:

```sql
SELECT object_type, object_name FROM user_objects WHERE status = 'INVALID';
SHOW ERRORS
```

## 3. Or apply everything with one script (optional)

```bash
for d in Sequence Table Type Type_Body Function Procedure Package Package_Body Trigger View; do
  for f in $d/*; do echo "@$f"; done
done > /tmp/deploy.sql   # note: Table folder needs the parent-first order above
echo "EXIT" >> /tmp/deploy.sql
sql bank/Bank123@localhost:1521/FREEPDB1 @/tmp/deploy.sql
```

## 4. Quick check

```sql
SELECT fn_calc_emi(500000, 9.5, 60) FROM dual;
SELECT fn_mask_mobile('9876543210') FROM dual;
INSERT INTO branches (branch_id, branch_code, branch_name) VALUES (seq_branch_id.NEXTVAL, 'B001', 'Main');
```

Note: `branches` and `credit_scores` have sequences but no insert trigger, so pass `seq_branch_id.NEXTVAL` / `seq_credit_score_id.NEXTVAL` explicitly when inserting.
