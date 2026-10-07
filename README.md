# db-schema

Oracle PL/SQL schema for a retail banking / lending system, one object per file.

| Folder | Extension | Contents |
|---|---|---|
| `Sequence/` | `.seq` | ID sequences |
| `Table/` | `.tab` | Tables with PK/FK/unique constraints |
| `Type/` | `.tps` | Object type specifications |
| `Type_Body/` | `.tpb` | Object type bodies |
| `Function/` | `.fnc` | Standalone functions |
| `Procedure/` | `.prc` | Standalone procedures |
| `Package/` | `.spc` | Package specifications |
| `Package_Body/` | `.bdy` | Package bodies |
| `Trigger/` | `.trg` | Before-insert triggers (ID from sequence) |
| `View/` | `.vw` | Reporting views |

## Suggested deployment order

1. Sequence
2. Table
3. Type, Type_Body
4. Function
5. Procedure
6. Package, Package_Body
7. Trigger
8. View

Note: several functions/procedures reference tables, so deploy them after `Table/`.
`pkg_compliance` calls `pkg_audit_service`, so compile the audit package first.
`fn_is_eligible_for_loan` depends on `fn_get_kyc_status` and `fn_calc_risk_score`.
