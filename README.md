# db-schema

Oracle PL/SQL schema for a retail banking / lending system. One object per file.

## Repository layout

| Folder | Ext | Contents | Count |
|---|---|---|---|
| `Sequence/` | `.seq` | ID sequences | 12 |
| `Table/` | `.tab` | Tables (PK / FK / unique) | 12 |
| `Type/` | `.tps` | Object type specs | 11 |
| `Type_Body/` | `.tpb` | Object type bodies | 11 |
| `Function/` | `.fnc` | Standalone functions | 11 |
| `Procedure/` | `.prc` | Standalone procedures | 11 |
| `Package/` | `.spc` | Package specs | 10 |
| `Package_Body/` | `.bdy` | Package bodies | 10 |
| `Trigger/` | `.trg` | Before-insert triggers (ID from sequence) | 10 |
| `View/` | `.vw` | Reporting views | 11 |
| `scripts/` | | `deploy.sh`, `validate.sql` | |

> `pkg_login_otp` is a placeholder: OTP generation and verification are `TODO` (verify always returns `FALSE`).
> `branches` and `credit_scores` have sequences but no insert trigger; pass `seq_branch_id.NEXTVAL` / `seq_credit_score_id.NEXTVAL` when inserting.

## Prerequisites

- Docker (Docker Desktop or Docker Engine) on your machine
- Git

The files are Oracle syntax and will not run on PostgreSQL or MySQL.

## 1. Create the database

```bash
git clone https://github.com/shende12rahul2/db-schema.git
cd db-schema

docker run -d --name oracle-free -p 1521:1521 \
  -e ORACLE_PASSWORD=Oracle123 \
  -e APP_USER=bank -e APP_USER_PASSWORD=Bank123 \
  gvenzl/oracle-free:slim

docker logs -f oracle-free      # wait for "DATABASE IS READY TO USE!", then Ctrl+C
```

This creates the schema owner `bank` / `Bank123` in the `FREEPDB1` pluggable database.

| Setting | Value |
|---|---|
| Host / Port | `localhost` / `1521` |
| Service name | `FREEPDB1` |
| User / Password | `bank` / `Bank123` |
| Admin | `sys` / `Oracle123` (as SYSDBA) |

## 2. Deploy everything in one go

```bash
./scripts/deploy.sh
```

The script:
1. Copies the repo into the container.
2. Applies every file in dependency order: Sequence, Table (parents first), Type, Type_Body, Function, Procedure, Package, Package_Body, Trigger, View.
3. Runs `scripts/validate.sql`.
4. Writes the full output to `deploy.log` and prints `DEPLOY OK`, or exits non-zero if it saw `ORA-`/`PLS-` errors or compilation warnings.

Override defaults with `CONTAINER=... CONN=... ./scripts/deploy.sh`.

## 3. Log in and run commands manually

```bash
docker exec -it oracle-free sqlplus bank/Bank123@//localhost:1521/FREEPDB1
```

To apply a single file by hand, copy the repo in and run from that folder:

```bash
docker cp . oracle-free:/tmp/db-schema
docker exec -it -w /tmp/db-schema oracle-free sqlplus bank/Bank123@//localhost:1521/FREEPDB1
```
```sql
@Sequence/seq_account_id.seq
@Table/branches.tab
SHOW ERRORS
```

Manual order: Sequence, then Table (`branches`, `customers`, `accounts`, `transactions`, `payments`, `loan_applications`, `collaterals`, `credit_scores`, `documents`, `notifications`, `otp_log`, `audit_logs`), Type, Type_Body, Function, Procedure, Package (all specs), Package_Body, Trigger, View.

## 4. Validate

`deploy.sh` already runs this; to re-run it alone:

```bash
docker exec -w /tmp/db-schema oracle-free sqlplus -s bank/Bank123@//localhost:1521/FREEPDB1 @scripts/validate.sql
```

Expected results:

| Check | Expected |
|---|---|
| Object counts | SEQUENCE 12, TABLE 12, TYPE 11, FUNCTION 11, PROCEDURE 11, PACKAGE 10, PACKAGE BODY 10, TRIGGER 10, VIEW 11 |
| Invalid objects | `no rows selected` |
| Compile errors (`user_errors`) | `no rows selected` |
| `fn_calc_emi(500000, 9.5, 60)` | an EMI of about 10,500 |
| `fn_mask_mobile('9876543210')` | `XXXXXX3210` |
| Insert test | customer row returned with `kyc_status = PENDING` (then rolled back) |

Run `SHOW ERRORS` after any file that reports "created with compilation errors".

## 5. Reset / clean up

```bash
docker rm -f oracle-free        # drops the database and all data
```

## Notes on dependencies

- Tables must be created parents first because of foreign keys.
- `pkg_compliance` calls `pkg_audit_service`, so all package specs are created before any body.
- `fn_is_eligible_for_loan` depends on `fn_get_kyc_status` and `fn_calc_risk_score`.
- `v_customer_contact_info` depends on `fn_mask_mobile`.
